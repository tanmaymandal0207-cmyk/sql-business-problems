# Case Study 01 · Customer Revenue Risk

> **Status: Complete (version 2).** Version 2 corrects the revenue scope of the original query and adds the missing concentration view. All 8 validation checks pass. The original version 1 query is kept unchanged in [`analysis.sql`](analysis.sql) for reference.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL |
| **Files** | [`analysis_v2.sql`](analysis_v2.sql) · [`validation_v2.sql`](validation_v2.sql) · [`analysis.sql`](analysis.sql) (version 1) |
| **Last updated** | 2026-10-21 |

---

## 1. Business problem

A B2B industrial products distributor reports healthy headline revenue. Management suspects that the headline figure hides three risks in the customer base:

1. Some customers look valuable only because of one unusually large order.
2. Some customers order frequently but contribute very little revenue.
3. A small number of customers may account for a disproportionate share of company sales.

The analysis classifies each customer against these risks, so that account management and credit decisions are based on the shape of a customer's revenue, not only its total.

## 2. Business questions

1. For each customer, what share of their revenue comes from their single largest order?
2. Which customers order often but generate little revenue, and which generate high revenue from few orders?
3. How concentrated is company revenue across customers?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Revenue |
| `sales_orders` | One row per order | Customer, status |

Line items are aggregated to order level and then to customer level before any ratio is calculated.

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Net sales (order) | `SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))`, for orders not Cancelled or Returned |
| Largest order % | Largest order ÷ customer net sales |
| Company sales % | Customer net sales ÷ net sales of all in-scope customers |
| Cumulative sales % | Running share of company sales, customers ranked by net sales |

| Classification | Rule |
|---|---|
| Order concentration | Largest order ≥ 50 % → **Critical** · ≥ 30 % → **Moderate** · otherwise **Diversified** |
| Value / frequency | ≥ ₹10 lakh and ≥ 20 orders → **Strategic** · ≥ ₹10 lakh → **High Value** · ≥ 20 orders → **High Frequency** · otherwise **Standard** |
| Revenue band | The customer starts within the first 50 % of cumulative revenue → **Top 50 %**; within 80 % → **Next 30 %**; otherwise **Remaining 20 %** |
| Eligibility | Customers with at least 5 in-scope orders (299 customers) |

## 5. Analytical approach

`analysis_v2.sql`:

1. **`order_revenue`**: net sales per in-scope order.
2. **`customer_metrics`**: orders, net sales, largest order, average order value and largest-order share per customer.
3. **`customer_position`**: company share, cumulative share and sales rank, calculated across **all** in-scope customers before the 5-order filter.
4. **Classification**: concentration flag, value/frequency segment and revenue band. All thresholds sit in one `params` CTE.

## 6. SQL techniques used

- CTEs moving from line to order to customer grain
- `SAFE_DIVIDE` for every ratio
- Running total with `SUM(...) OVER (ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)` for the Pareto view
- `RANK()` window functions
- A `params` CTE `CROSS JOIN`ed into the final query, so thresholds are defined once

## 7. Validation and reconciliation

All 8 checks in `validation_v2.sql` return **PASS**.

| # | Check |
|---|---|
| 1 | Every line item has a parent order |
| 2 | Every order has at least one line item |
| 3 | One row per order at order level |
| 4 | No NULL line revenue (the version 1 defect) |
| 5 | Revenue bridge: all lines = in-scope + Cancelled/Returned |
| 6 | In-scope line revenue = order-level revenue |
| 7 | Order-level revenue = customer-level revenue |
| 8 | In-scope orders = sum of customer order counts |

**Why version 1 needed revising.** Version 1's own reconciliation passed because both sides used the same formula. It could not detect that:

- 336 lines with a missing discount were silently dropped, removing ₹1.28 crore of revenue;
- 534 Cancelled and 75 Returned orders were counted as revenue.

Check 4 and check 5 above would have caught both.

## 8. Findings

**Revenue is concentrated in a small group of customers.**

| Revenue band | Customers | Share of company revenue |
|---|---:|---:|
| Top 50 % | **23** | 50.7 % |
| Next 30 % | 63 | 29.4 % |
| Remaining 20 % | 213 | 18.5 % |

Twenty-three customers (5.4 % of the 426 with revenue) generate half of all sales.

**Single-order dependence is a small-customer problem.**

| Order concentration | Customers | Share of company revenue |
|---|---:|---:|
| Diversified | 189 | 87.5 % |
| Moderate (30–50 %) | 85 | 9.8 % |
| Critical (≥ 50 %) | 25 | 1.4 % |

All 25 critical-concentration customers sit in the bottom 20 % of revenue. The exception worth watching is **customer 1178**, ranked 5th in revenue: 47.6 % of its ₹2.51 crore comes from a single ₹1.19 crore order. That same order was identified in the [Revenue growth bridge](../03_revenue_growth_bridge/) as a one-off driver of this year's growth.

**High-frequency, low-value customers are few.** 16 customers order 20 or more times but total under ₹10 lakh (1.3 % of revenue). Their median order is ₹27,400, against ₹94,800 for Strategic customers. The 118 Strategic customers generate 85.4 % of revenue.

## 9. Business implications and recommendations

1. **Put named account management on the 23 customers who make up half of revenue**, and review their credit limits and payment behaviour quarterly (see [Customer payment behaviour](../../05_advanced_analytics/02_customer_payment_behaviour/)).
2. **Exclude one-off orders when judging an account's value.** For customer 1178, plan on the revenue without the ₹1.19 crore order.
3. **Do not chase the 25 critical-concentration customers as growth accounts.** They are small, occasional buyers whose totals are driven by a single purchase.
4. **Serve high-frequency, low-value customers at lower cost**, for example by consolidating their orders, since each small order carries freight and handling cost (see [Freight cost-to-serve](../../03_operations_and_supply_chain/02_freight_cost_to_serve/)).

## 10. Assumptions and limitations

- **Period.** All orders from January 2024 to September 2026 are treated as one period.
- **Thresholds.** ₹10 lakh, 20 orders, 30 %/50 % and the 5-order minimum are business rules. They are defined once and easy to change.
- **Revenue, not margin.** Concentration is measured on revenue.
- **Duplicate customers.** Six customer records are probable duplicates (see [Customer master de-duplication](../../04_data_quality_and_reconciliation/03_customer_master_deduplication/)). Merging them would raise some customers' totals slightly, for example Navkar Agencies from 6th to 5th.

---

## Version history

| Version | Date | Change |
|---|---|---|
| 1 | 2026-10-11 | Original query (`analysis.sql`). Findings held back because of known issues. |
| 2 | 2026-10-21 | Corrected revenue scope (NULL discounts, Cancelled/Returned orders), added the Pareto view, and independent validation (`analysis_v2.sql`, `validation_v2.sql`). Findings published. |

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis_v2.sql` | Current analysis query |
| `validation_v2.sql` | 8 pass/fail checks |
| `analysis.sql` | Original version 1 query, kept for reference |
