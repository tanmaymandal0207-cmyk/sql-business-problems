# Case Study 01 · Customer Revenue Risk

> **Status: Version 1 — query added, revision planned.** The original analysis query is committed as written. Known gaps in revenue scope (discounts and order returns/cancellations) are documented in [section 10](#10-assumptions-and-limitations) and will be addressed in the next version. Findings will be published only after that revision is validated.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL |
| **Query** | [`analysis.sql`](analysis.sql) |
| **Last updated** | 2026-10-11 |

---

## 1. Business problem

A B2B industrial products distributor reports healthy headline revenue. Management suspects that this headline figure hides three risks in the customer base:

1. Some customers look valuable only because of one unusually large order.
2. Some customers order frequently but contribute very little revenue.
3. A small number of customers may account for a disproportionate share of company sales.

The analysis classifies each customer against these risks so that account management and credit decisions can be based on the shape of a customer's revenue, not only its total.

## 2. Business questions

1. For each customer, what share of their total revenue comes from their single largest order?
2. Which customers order often but generate low revenue, and which generate high revenue from few orders?
3. What share of company revenue does each customer contribute, and how do customers rank by sales and by single-order dependence?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Quantity, unit price and discount — the revenue basis |
| `sales_orders` | One row per order | Links each order to its customer |

Join path: `sales_order_items.order_id = sales_orders.order_id` (many-to-one). Line items are aggregated to order level before any customer-level metric is calculated, so no row multiplication occurs.

Full schema: [`datasets_and_documentation/schema.md`](../../datasets_and_documentation/schema.md)

## 4. Metric definitions

Definitions as implemented in version 1 of the query.

| Metric | Definition | Grain |
|---|---|---|
| Net sales (order) | `SUM(quantity * unit_price * (1 - discount_percent / 100))` | Order |
| Total orders | Count of orders per customer | Customer |
| Net sales (customer) | Sum of order net sales | Customer |
| Customer AOV | Customer net sales ÷ total orders | Customer |
| Largest order | Maximum order net sales | Customer |
| Largest order contribution % | Largest order ÷ customer net sales × 100 | Customer |
| Company sales contribution % | Customer net sales ÷ company net sales × 100 | Customer |

**Classification rules**

| Field | Rule |
|---|---|
| `Risk_Flag` | ≥ 50 % → Critical Concentration · 30–50 % → Moderate Concentration · < 30 % → Diversified |
| `Customer_Segment` | Net sales ≥ ₹10,00,000 and ≥ 20 orders → Strategic · ≥ ₹10,00,000 and < 20 orders → High Value · < ₹10,00,000 and ≥ 20 orders → High Frequency · otherwise Standard |
| Eligibility | Customers with at least 5 orders (single-order dependence is not meaningful below this) |

## 5. Analytical approach

The query is built as a sequence of CTEs:

1. **`Order_Level_Revenue`** — calculates net sales per order from its line items.
2. **`Customer_Revenue_Metrics`** — aggregates orders to customer level: order count, total net sales, largest order, AOV and largest-order share.
3. **`Company_Revenue`** — calculates total company net sales from all line items.
4. **`Customer_Revenue_Analysis`** — attaches the company total to every customer row.
5. **Final select** — calculates company share, ranks customers by sales and by concentration, assigns the concentration flag and value/frequency segment, and keeps customers with 5 or more orders.

## 6. SQL techniques used

- Common table expressions (CTEs) for step-by-step aggregation
- Two-level aggregation (line → order → customer) to control grain
- `CROSS JOIN` to attach a single company-level total to every row
- Window functions: `DENSE_RANK() OVER (ORDER BY …)`
- `CASE` expressions for rule-based classification

## 7. Validation and reconciliation

| Check | Method | Result |
|---|---|---|
| Customer revenue reconciles to company revenue | Sum of unfiltered customer net sales vs. `Company_Revenue` (validation block at the end of `analysis.sql`) | Match — ₹95,18,90,079.55 on both sides |
| Reproducibility | Query re-run independently on the CSV export of `sahyadri_b2b` | 305 customers returned; rank 1 is customer 1042 with net sales of ₹7,04,11,352.22 |

**Limitation of this check:** both sides of the reconciliation use the same line-item formula, so the check confirms that no orders are lost between levels, but it cannot detect issues in the revenue formula itself (see section 10). A broader set of checks — revenue bridge by order status, NULL detection, grain and order-count reconciliation — is planned for version 2.

## 8. Findings

_Pending._ Findings will be written after the version 2 query (section 10) has been run and validated, so that reported figures reflect the corrected revenue scope.

## 9. Business implications and recommendations

_Pending — each recommendation will reference the finding it is based on._

## 10. Assumptions and limitations

**Assumptions in version 1**

- All orders are included regardless of `order_status`.
- Revenue is measured from order line items, not from payments received.
- Thresholds (₹10,00,000 net sales, 20 orders, 30 % and 50 % concentration, 5-order minimum) are fixed business rules, not statistically derived.
- The analysis covers the full dataset period (orders dated 2024-01-01 to 2026-09-30) with no time segmentation.

**Known issues — planned for version 2**

| Issue | Effect on version 1 | Planned change |
|---|---|---|
| Missing discounts | 336 line items have a NULL `discount_percent`. The revenue expression returns NULL for these lines and `SUM()` ignores them, so their revenue is excluded. | Treat a NULL discount explicitly (e.g. as 0 %) and report the number of lines affected |
| Cancelled and returned orders | 534 cancelled and 75 returned orders are included in revenue and order counts, which can overstate a customer's value or frequency and affect the largest-order test. | Exclude non-revenue statuses and show a revenue bridge by status |
| Concentration across the customer base | Each customer's share of company sales is reported, but not the cumulative share, so risk 3 is only partly answered. | Add cumulative revenue share and a Pareto band |
| Table name casing | The query references `Sales_Orders`; BigQuery table names are case-sensitive. | Align the reference with the table name as created |

---

## Files

| File | Purpose | Status |
|---|---|---|
| `README.md` | Case study documentation (this file) | Version 1 |
| `analysis.sql` | Primary analysis query, including its reconciliation check | Version 1 — original |

Additional files (for example, a separate validation script) will be listed here when they are added.
