# Case Study · Revenue Growth Bridge

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Like-for-like comparison: January–September 2026 vs January–September 2025.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-19 |

---

## 1. Business problem

Year-to-date revenue is well ahead of last year. Before the board meeting, the managing director wants to know **where the growth came from**, because the answer changes next year's plan. Growth from winning new customers calls for more sales hunting. Growth from existing accounts calls for protecting them. Growth from a handful of large one-off orders may not repeat.

## 2. Business questions

1. How much did revenue grow, like for like, over January–September?
2. Did growth come from new customers or from existing customers buying more? How much did lost and declining customers take away?
3. Was it driven by more orders or by bigger orders?
4. Which product categories and customer segments contributed the growth?
5. How concentrated is the growth in a few accounts?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Revenue |
| `sales_orders` | One row per order | Order date, status, customer |
| `customers` | One row per customer | Segment and name |
| `products`, `product_categories` | One row per product / category | Category |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)` on orders not Cancelled or Returned |
| PY / CY | Prior year: 1 Jan–30 Sep 2025 · Current year: 1 Jan–30 Sep 2026. The data ends on 30 Sep 2026, so only the same nine months are compared. |
| Average order value (AOV) | Revenue ÷ distinct orders |
| Customer bridge | **New:** revenue in CY only · **Grew:** CY > PY · **Declined:** 0 < CY < PY · **Lost:** revenue in PY only |
| Order count vs size split | Change from more orders = (orders CY − orders PY) × AOV PY. Change from bigger orders = (AOV CY − AOV PY) × orders CY. The two parts add up exactly to the total change. |
| Contribution to growth | A group's revenue change ÷ total revenue change |

## 5. Analytical approach

1. **Period table** (`sahyadri_b2b.ytd_revenue_lines`). One row per in-scope order line in either period, labelled PY or CY.
2. **Headline.** Revenue, orders, customers and AOV in both periods.
3. **Customer bridge** from PY revenue to CY revenue.
4. **Order count vs order size** decomposition.
5. **Contribution to growth by category.**
6. **Contribution to growth by segment.**
7. **Top 10 customers** by revenue added.

## 6. SQL techniques used

- Period labelling with `CASE … BETWEEN`, and declared period boundaries so the comparison can be rolled forward
- Pivoting periods into columns with `SUM(IF(period = 'CY', …))` and `MAX(IF(…))`
- A `CROSS JOIN` of one-row summaries for side-by-side PY/CY metrics
- Customer bridge classification with `CASE`
- Exact two-factor decomposition (count × average)
- Contribution shares with `SUM(SUM(...)) OVER ()`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Row count = in-scope source lines in both periods |
| 02 | Revenue = source total, to the paisa |
| 03 | Every PY and CY label matches the order date |
| 04 | Sum of customer changes = total change |
| 05 | Every customer falls in exactly one bridge group |
| 06 | Order-count part + order-size part = total change, to the paisa |
| 07 | Sum of category changes = total change |
| 08 | Sum of segment changes = total change |
| 09 | No NULL or negative revenue lines |
| 10 | Every line has a category and segment |

## 8. Findings

**Revenue grew 38.7 %, from ₹22.52 crore to ₹31.22 crore (+₹8.71 crore).** Orders rose from 2,504 to 2,948 and active customers from 322 to 353.

**Growth came from existing customers, not new ones.**

| Bridge group | Customers | Revenue change |
|---|---:|---:|
| Revenue Jan–Sep 2025 | | **₹22.52 crore** |
| + New customers | 69 | +₹1.54 crore |
| + Existing customers who grew | 165 | +₹11.22 crore |
| − Existing customers who declined | 119 | −₹3.67 crore |
| − Lost customers | 38 | −₹0.38 crore |
| **Revenue Jan–Sep 2026** | | **₹31.22 crore** |

Existing customers contributed a net +₹7.55 crore, which is 87 % of total growth. New customers added only ₹1.54 crore. At the same time, 119 existing customers bought less, taking away ₹3.67 crore.

**More orders and bigger orders contributed almost equally.** More orders (+17.7 %) added ₹3.99 crore. Bigger orders (AOV up 17.8 %, from ₹89,922 to ₹1,05,914) added ₹4.71 crore.

**Two categories delivered nearly two-thirds of the growth.**

| Category | Growth | Share of total growth |
|---|---:|---:|
| Pumps | +77.1 % | 45.5 % |
| Electric Motors & Drives | +35.9 % | 17.9 % |
| Industrial Safety Equipment | +27.2 % | 8.0 % |
| Valves & Fittings | +23.1 % | 7.7 % |
| *Slowest:* Bearings | +10.5 % | 1.7 % |

**By segment**, Distributors (44.1 % of growth) and Enterprise accounts (32.7 %) led. Mid-Market grew fastest (+57.2 %). SMB grew only 16.2 % and contributed 2.4 % of growth.

**Growth is highly concentrated.** The **top 10 customers account for 67.3 % of net growth**, and the top two alone for 28.9 %. The second-largest contributor, customer 1178, grew from ₹31.2 lakh to ₹1.54 crore. **77 % of that came from a single ₹1.19 crore order** on 30 Mar 2026, so it is unlikely to repeat. This is the single-order dependence risk examined in [Customer revenue risk](../01_customer_revenue_risk/).

## 9. Business implications and recommendations

1. **Present the growth as account expansion, not new-customer acquisition.** 87 % came from existing customers. Next year's plan should protect and deepen these accounts before it expands the sales team for new business.
2. **Separate one-off orders from the growth base when setting next year's targets.** Customer 1178's ₹1.19 crore order should be excluded from the run-rate used for targets, or next year will start with a built-in shortfall.
3. **Treat the 119 declining customers as an early churn signal.** They took away ₹3.67 crore. Cross-check them against the overdue accounts in [Customer churn early warning](../02_customer_churn_early_warning/) and assign account reviews.
4. **Check that Pumps and Electric Motors can keep up with demand.** They delivered 63 % of the growth. Confirm supplier capacity and stocking policy (see [ABC-XYZ classification](../../05_advanced_analytics/01_abc_xyz_product_classification/)). Also note that Electric Motors has the lowest gross margin (see [Discount and margin erosion](../../02_sales_and_profitability/01_discount_margin_erosion/)), so its growth adds less profit than its revenue suggests.
5. **Reduce dependence on the top 10 accounts.** With two-thirds of growth in 10 customers, losing one or two of them would erase much of the year's gain. Mid-Market, the fastest-growing segment, is the natural place to broaden the base.

## 10. Assumptions and limitations

- **Revenue, not profit.** This bridge explains revenue. Margin by category differs, so profit growth will not match these shares.
- **Order-based timing.** Revenue is counted on the order date, not the invoice or delivery date.
- **Price vs volume.** Bigger orders could mean more units or higher prices. The order-size split does not separate the two.
- **Seasonality.** Comparing the same nine months removes seasonal effects within the year, but not differences in timing of large projects between years.
- **New customers.** "New" means no orders in January–September 2025. Some may have ordered in late 2025 or before 2025.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Period table and 6 analysis steps |
| `validation.sql` | 10 pass/fail checks |
