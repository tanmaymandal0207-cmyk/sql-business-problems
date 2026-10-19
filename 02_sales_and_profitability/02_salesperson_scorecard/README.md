# Case Study · Salesperson Performance Scorecard

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Period: orders dated 1 Jan 2024 to 30 Sep 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-19 |

---

## 1. Business problem

Sales incentives are paid on revenue alone. The sales head suspects this rewards people who win volume through deep discounts, orders that are later cancelled, or customers who pay late. Before redesigning the incentive plan, they want a **balanced scorecard**: each salesperson measured on the quality of their revenue as well as its size.

## 2. Business questions

1. How does each salesperson perform on revenue, gross margin, discount, cancellations, on-time delivery and cash collection?
2. Does a ranking on revenue alone tell the same story as a balanced ranking?
3. Who sells a lot at low margin, and who sells less but more profitably?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Salesperson, status, promised date |
| `sales_order_items` | One row per product per order | Revenue, discount |
| `products` | One row per product | Unit cost |
| `shipments` | One row per shipment | Final delivery date |
| `payments` | One row per receipt | Amount collected |
| `employees` | One row per employee | Name and designation |

Each metric is calculated in its own CTE at the right grain (line, order or shipment) and then joined at salesperson level. Shipments and payments are aggregated to order level first, so no join multiplies rows.

## 4. Metric definitions

| Metric | Definition | Better when |
|---|---|---|
| Net revenue | Revenue on orders not Cancelled or Returned (NULL discount = 0 %) | Higher |
| Gross margin % | (Net revenue − cost) ÷ net revenue, for lines with a unit cost | Higher |
| Discount % | Discount given ÷ gross value | Lower |
| Cancellation rate | Cancelled orders ÷ all orders placed | Lower |
| On-time delivery % | Delivered orders delivered on or before the promised date ÷ delivered orders with both dates | Higher |
| Overdue receivable % | Unpaid balance on Delivered orders delivered more than 90 days before 30 Sep 2026 ÷ their order value | Lower |
| Balanced rank | Rank on the sum of the six metric ranks (1 = best) | Lower |

The six metrics are weighted equally. Orders with no salesperson are reported as **Unassigned** but not ranked.

## 5. Analytical approach

1. **Scorecard table** (`sahyadri_b2b.salesperson_scorecard`). One row per salesperson with every metric, plus the underlying counts (orders placed, cancelled, delivered on time, overdue balance) so that each percentage can be audited.
2. **Balanced ranking.** Rank on each metric, the average rank, the balanced rank, and how far each person moves compared with a revenue-only ranking.
3. **Full scorecard values**, including unassigned orders.
4. **Revenue vs margin quadrant**, split at the median of the 16 ranked salespeople.

## 6. SQL techniques used

- Several metric CTEs at different grains, joined at salesperson level
- `IS NOT DISTINCT FROM` so the NULL (unassigned) group joins correctly
- `RANK() OVER (ORDER BY …)` in ascending and descending directions, then a rank of summed ranks
- `GREATEST()` to stop overpayments offsetting other orders' balances
- Medians with `PERCENTILE_CONT` and a quadrant classification
- `STRING_AGG` to list names in each quadrant

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per salesperson (including Unassigned) |
| 02 | Every salesperson on an order appears in the scorecard |
| 03 | Net revenue = in-scope line-item total |
| 04 | Orders = in-scope orders |
| 05 | Orders placed = all orders in the source (10,000) |
| 06 | Cancelled orders = cancelled orders in the source |
| 07 | On-time orders never exceed orders measured |
| 08 | Overdue balance never exceeds aged order value |
| 09 | Every percentage lies between 0 and 100 |
| 10 | No ranked salesperson is missing a metric |

## 8. Findings

**Ranking on revenue alone gives a very different picture from the balanced view.**

| Employee | Designation | Revenue rank | Balanced rank | Why |
|---|---|---:|---:|---|
| 115 | Sales Executive | 10 | **1** | Margin 12.50 %, 4th-lowest discount, 3rd-best on-time delivery |
| 109 | Senior Sales Executive | 7 | 2 | 2nd-best on-time delivery (87.3 %) and 4th-best collection |
| 106 | Key Account Manager | **1** | 3 | Highest revenue (₹12.77 crore) and best on-time delivery (89.4 %), but 13th on margin |
| 113 | Sales Executive | 15 | 7 | 2nd-highest margin (15.63 %) and 2nd-lowest discount |
| 107 | Key Account Manager | 8 | 15 | 14th on margin, 13th on collection |
| 102 | Regional Sales Manager | **2** | **16** | Lowest margin (8.29 %), 2nd-highest discount, 2nd-worst collection |

**Most high-revenue salespeople earn below-median margins.**

| Quadrant | Salespeople | Net revenue | Share of revenue |
|---|---:|---:|---:|
| High revenue, high margin | 2 | ₹13.75 crore | 15.1 % |
| High revenue, low margin | 6 | ₹53.40 crore | 58.5 % |
| Low revenue, high margin | 6 | ₹13.25 crore | 14.5 % |
| Low revenue, low margin | 2 | ₹6.90 crore | 7.6 % |

Only two people (employees 108 and 109) combine above-median revenue with above-median margin. Six of the eight biggest sellers, holding 58.5 % of revenue, sit below the median margin. A revenue-only incentive rewards exactly this pattern.

**Other measures add to the picture:**

- **Collection.** The overdue receivable share ranges from 2.36 % (employee 114) to 10.36 % (employee 103, who is 6th on revenue).
- **On-time delivery.** It ranges from 89.4 % (employee 106) to 70.7 % (employee 110). The [Late delivery root cause](../../03_operations_and_supply_chain/01_late_delivery_root_cause/) case study shows that employee 110's lateness is partly driven by promise dates that ignore distance.
- **Unassigned orders.** Orders with no salesperson total ₹3.94 crore at the highest discount (11.20 %) and one of the lowest margins (7.85 %). Nobody is accountable for them.

## 9. Business implications and recommendations

1. **Pay incentives on margin, not revenue alone.** A typical structure pays on gross margin, or on revenue with a margin gate (no incentive on orders below a margin floor).
2. **Add collection to the incentive.** Pay the final part of the incentive only once the customer has paid, or deduct balances overdue by more than 90 days. This brings employee 103's 10.4 % overdue share into scope.
3. **Use the balanced scorecard in monthly sales reviews**, and focus coaching on the high-revenue, low-margin group. That group carries 58.5 % of revenue, so a one-point margin gain there is worth more than anywhere else.
4. **Recognise the efficient sellers.** Employees 115, 109 and 113 rank far higher on the balanced view than on revenue. Their discounting and delivery-promise habits are worth sharing as practice.
5. **Assign every order to a salesperson** so that the ₹3.94 crore currently unassigned has an owner.
6. **Agree the weights with sales leadership.** Equal weights are a neutral starting point. A business focused on cash might weight collection more heavily.

## 10. Assumptions and limitations

- **Attribution.** The salesperson on the order is assumed to own its price, discount, promise date and collection follow-up.
- **Cost basis.** Gross margin uses the current unit cost per product.
- **Different portfolios.** Salespeople serve different territories, segments and customers. Some differences (for example transit time, or Enterprise payment terms) reflect the portfolio rather than individual performance, and should be discussed before being used for pay.
- **Ranks show order, not size.** A one-place difference can be a large or a tiny gap. Use the underlying values in Step 3 alongside the ranks.
- **Small numbers.** Employee 112 has 185 orders. Their rates are less stable than those of salespeople with 800 or more orders.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Scorecard table and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
