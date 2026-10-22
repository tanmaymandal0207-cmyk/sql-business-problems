# Case Study · Customer Profitability and the Whale Curve

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Window: 1 Oct 2025 – 30 Sep 2026.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-22 |

---

## 1. Business problem

Customers are ranked by revenue, but revenue is not profit. Some customers buy at low margins, order often in small amounts, need costly freight, take a lot of sales time and pay slowly. Management accountants show this with a **whale curve**: cumulative profit by customer, ranked from most to least profitable. The curve rises above 100 % and then falls back, because the least profitable customers give back part of what the best ones earn. The CFO wants a customer P&L that includes the **cost to serve**, not just gross margin, to guide pricing, service levels and sales coverage.

## 2. Business questions

1. After product cost, freight, order handling, sales effort and the cost of credit, which customers make money and which lose it?
2. How high does the whale curve peak, and how much profit do loss-making customers give back?
3. What makes the loss-making customers unprofitable?
4. How does profitability differ by segment?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, salesperson, status |
| `sales_order_items` | One row per product per order | Revenue |
| `products` | One row per product | Unit cost |
| `shipments` | One row per shipment | Freight and delivery date |
| `payments` | One row per payment | Payment timing for cost of credit |
| `employees`, `departments` | One row per employee / department | Salary pools for handling and sales effort |
| `customers` | One row per customer | Name and segment |

## 4. Metric definitions

| Cost line | How it is assigned to customers |
|---|---|
| Gross profit | Revenue − `quantity * unit_cost`, orders not Cancelled or Returned |
| Freight | Shipping cost on every shipment of the customer's orders, including returns |
| Order handling | Operations and Supply Chain & Logistics salaries for the window ÷ all orders placed = **₹1,639 per order**, charged on every order, including cancelled ones |
| Sales effort | Each salesperson's salary for the window ÷ the orders they booked, charged on their orders. The Head of Sales is management overhead and is not allocated. |
| Cost of credit | Rupees outstanding × days from delivery to payment (or to 30 Sep 2026 if unpaid) × 12 % a year |
| **Contribution** | Gross profit − freight − handling − sales effort − cost of credit |

Salaries are prorated for anyone who joined during the window. This is **activity-based costing**: each cost is charged in proportion to the activity that drives it (orders, shipments, rupee-days), rather than spread as a percentage of revenue.

## 5. Analytical approach

1. **Customer P&L table** (`sahyadri_b2b.customer_profitability`). One row per customer with orders in the window: revenue, every cost line, contribution, profit rank and cumulative share of profit.
2. **Company P&L** from revenue to contribution.
3. **Whale curve** by customer decile, its peak and the profit given back.
4. **Cost-to-serve profile** of profitable against loss-making customers, and the 10 largest loss-makers.
5. **Profitability by segment.**

## 6. SQL techniques used

- Activity-based cost rates computed in SQL from salary pools and activity counts, then joined back at order level
- Rupee-day financing cost from payment timing with `GREATEST(DATE_DIFF(...), 0)`
- Running `SUM … OVER (ORDER BY contribution DESC)` divided by the total to draw the whale curve
- `NTILE(10)` deciles and a `CASE GREATEST(...)` lookup to name each customer's largest cost driver

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer |
| 02 | Rows = customers with orders in the window |
| 03 | Revenue = source (₹40.36 crore, matching other 12-month case studies) |
| 04 | Gross profit = source |
| 05 | Freight = source shipping cost for these orders |
| 06 | Handling cost charged = Operations and Supply Chain salaries for the window, recomputed with a different day count |
| 07 | Sales cost charged = salaries of salespeople with orders, excluding the Head of Sales |
| 08 | Contribution = gross profit − all costs, on every row |
| 09 | Profit ranks run 1 to n, and the whale curve ends at exactly 100 % |
| 10 | No negative cost of credit, and none for customers without a delivered order |

## 8. Findings

**After cost to serve, ₹6.47 crore of gross profit becomes ₹3.03 crore of customer contribution (7.5 % of revenue).**

| Line | Amount | % of revenue |
|---|---:|---:|
| Revenue | ₹40.36 crore | 100.0 % |
| Gross profit | ₹6.47 crore | 16.0 % |
| − Sales effort | ₹1.56 crore | 3.9 % |
| − Order handling | ₹69.2 lakh | 1.7 % |
| − Cost of credit | ₹68.4 lakh | 1.7 % |
| − Freight | ₹50.3 lakh | 1.2 % |
| **Contribution** | **₹3.03 crore** | **7.5 %** |

**The whale curve peaks at 106.5 %.**

| Customers, ranked by contribution | Cumulative share of contribution |
|---|---:|
| Top 10 % (38 customers) | 76.2 % |
| Top 20 % | 93.0 % |
| Top 30 % | 100.9 % |
| Peak (223 profitable customers) | **106.5 %** |
| All 373 customers | 100.0 % |

- **109 customers (29 %) earn all of the company's contribution.** The 223 profitable customers earn ₹3.23 crore. The other 150 give back **₹19.6 lakh**.
- **The three most profitable customers are distributors** and earn 26.4 % of all contribution: Siddhivinayak Mishra Trading (₹41.5 lakh), Banerjee Sales Corporation (₹20.1 lakh) and Maa Joshi Industrial Suppliers (₹18.6 lakh).

**Loss-making customers earn the same gross margin. They lose money on cost to serve.**

| Per ₹100 of revenue | Profitable (223) | Loss-making (144) |
|---|---:|---:|
| Revenue per order | ₹1,11,711 | ₹29,922 |
| Gross margin | 16.0 | 16.0 |
| Sales effort | 3.2 | **13.8** |
| Order handling | 1.5 | **5.5** |
| Freight | 1.2 | 2.7 |
| Cost of credit | 1.7 | 1.8 |
| **Contribution** | **8.5** | **−7.8** |

A further 6 customers placed orders that were all cancelled or returned. They carry handling and freight costs with no revenue.

- **Small orders drive the losses.** Loss-makers' orders are about a quarter the size, so sales time and handling, which cost much the same per order, weigh about four times as much per rupee of revenue. Pricing is not the cause, and payment speed barely differs.
- **Sales effort is the largest cost for 9 of the 10 biggest loss-makers.** For example, Om Electricals placed 30 orders worth ₹6.8 lakh in total and lost ₹1.2 lakh after cost to serve.

**SMB is the only segment that loses money, despite the highest gross margin:**

| Segment | Customers | Loss-making | Revenue per order | Gross margin | Cost to serve | Contribution margin | Share of contribution |
|---|---:|---:|---:|---:|---:|---:|---:|
| Distributor | 68 | 6 | ₹1,97,217 | 14.6 % | 3.4 % + credit | **9.9 %** | 53.2 % |
| Enterprise | 64 | 12 | ₹1,09,366 | 15.5 % | 6.5 % + credit | 6.8 % | 35.5 % |
| Mid-Market | 104 | 27 | ₹56,304 | 19.5 % | 10.9 % + credit | 6.9 % | 14.0 % |
| SMB | 137 | **99** | ₹23,204 | **21.6 %** | 25.1 % + credit | **−4.3 %** | −2.8 % |

Cost to serve here is sales effort + handling + freight as a share of revenue.

## 9. Business implications and recommendations

1. **Serve small customers through a lower-cost channel.** SMB accounts take sales time costing 14.9 % of their revenue. Move them to inside sales, a phone and WhatsApp desk or a distributor, and keep field salespeople on accounts where the visit pays back.
2. **Set a minimum order value or a small-order charge.** Loss-making customers average under ₹30,000 per order, and fixed costs per order are what sink them. The [freight cost-to-serve study](../../03_operations_and_supply_chain/02_freight_cost_to_serve/) tested a ₹10,000 MOV. This analysis supports it and suggests reviewing the level.
3. **Protect the top 38 customers.** They earn 76 % of contribution. Several are also high-dependency accounts in [Salesperson relationship risk](../../01_customer_and_revenue/04_salesperson_relationship_risk/).
4. **Do not drop loss-making customers automatically.** Many are small and could become profitable with fewer, larger orders. Use the customer P&L in account reviews and change how they are served before deciding whether to keep them.
5. **Refresh the customer P&L each quarter** and report contribution, not just revenue, in the sales scorecard.

## 10. Assumptions and limitations

- **Allocation choices drive results.** Handling is spread equally per order and sales effort per salesperson's order. Real effort varies by order, and a time study would refine both. The rates are computed in the script and can be changed.
- **Not full cost.** Finance, HR, IT, marketing, production and the Head of Sales are overhead and are not allocated. Contribution is a customer-level margin, not net profit.
- **Cost of capital.** 12 % a year is an assumption for the cost of working capital. It is declared at the top of the script. Credit cost is similar across groups, so the ranking is not sensitive to it.
- **Missing data.** Lines with no unit cost and shipments with no freight cost are treated as zero, which slightly flatters those customers.
- **One year.** A customer that is loss-making in one year may be in a ramp-up or slow year.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer P&L table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
