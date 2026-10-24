# Case Study · Salesperson Ramp-Up

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Four salespeople hired November 2024 – June 2025, followed for 15–22 months against 4 established peers.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-25 |

---

## 1. Business problem

Four salespeople joined between November 2024 and June 2025, and two more joined in September 2026. The sales head has to set first-year targets for the September joiners and decide how much support they need, but has no evidence of how long a new salesperson takes to become productive, or what "productive" is built on. The usual assumption is a six-to-twelve-month learning curve.

## 2. Business questions

1. How long does a new salesperson take to win a first order, and to reach the level of an established colleague?
2. What does the ramp-up curve look like over the first 18 months?
3. Is a new joiner's revenue built on customers handed over to them, or on customers they win?
4. When a new joiner lags, is it fewer orders or smaller orders?
5. What revenue should be planned for the September 2026 joiners in their first six months?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `employees` | One row per employee | Hire date, designation |
| `departments` | One row per department | Sales department filter |
| `sales_orders` | One row per order | Salesperson, customer, order date, status |
| `sales_order_items` | One row per product per order | Revenue |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Revenue | Quantity × unit price × (1 − discount %), orders not Cancelled or Returned; NULL discount = 0 % |
| New joiner | Sales department, hired on or after 1 Jan 2024, so the whole ramp-up is in the data |
| **Benchmark** | Average monthly revenue (and orders) of the 4 established Sales Executives and Senior Sales Executives, hired before 2024, **in the same calendar month**. Managers and key account managers are excluded because they hold the largest accounts. |
| Tenure month | 1 = first full calendar month after the hire month |
| **Revenue index** | Joiner's revenue ÷ benchmark revenue for the same month. 1.00 = level with an established peer. |
| 3-month index | Sum of the last 3 months' revenue ÷ sum of the last 3 months' benchmark |
| **Productive** | 3-month index of 0.80 or more. Month 3 is the earliest month this can be measured. |
| Handed-over customer | A customer who had ordered from the company before their first order with the joiner |
| Order value index | Revenue index ÷ orders index |

Comparing with the same calendar month removes seasonality and year-end peaks from the ramp-up curve.

## 5. Analytical approach

1. **Monthly table** (`sahyadri_b2b.rep_monthly`). Revenue, orders and customers for every salesperson and every month after hire, with zero-filled months.
2. **Ramp table** (`sahyadri_b2b.rep_ramp`). Each joiner's month against the benchmark month, with 1-month and 3-month indices.
3. **Time to first order and to productivity**, and year-1 revenue and order indices for each joiner. Context: average monthly revenue by salesperson group in the last 12 months.
4. **Ramp-up curve** by quarter of tenure, split into orders and order value.
5. **Customer source**: handed-over against self-won revenue, and the joiners' share of new customers won.
6. **Plan** for the September 2026 joiners' first six months.

## 6. SQL techniques used

- Zero-filled salesperson × month grid with `GENERATE_DATE_ARRAY` and a `CROSS JOIN`, so silent months count as zero instead of disappearing
- Named `WINDOW` clause for 3-month rolling ratios (sum ÷ sum, not an average of ratios)
- Benchmarking against peers in the same calendar month to remove seasonality
- Validation that recomputes the benchmark from source orders and the rolling index with a self-join

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per salesperson and month |
| 02 | Monthly revenue = source revenue on orders with a salesperson |
| 03 | Monthly orders = source orders with a salesperson |
| 04 | No order dated in or before the salesperson's hire month |
| 05 | Row count = months after hire for every salesperson (zero-fill complete) |
| 06 | Every benchmark month has 4 peers |
| 07 | **Benchmark revenue = an independent recount from source orders** |
| 08 | **3-month index = a self-join recount** |
| 09 | Tenure months run consecutively from 1 |
| 10 | Joiners' revenue in the ramp table = source |

## 8. Findings

**There is no learning curve: every joiner was productive by month 3, the first month it can be measured.**

| Joiner | Role | Hired | Days to first order | Index months 1–3 | Months 4–6 | Months 10–12 | Year 1 revenue index | Year 1 orders index |
|---|---|---|---:|---:|---:|---:|---:|---:|
| Harish Tiwari | Sales Executive | 18 Nov 2024 | 30 | 1.68 | 0.82 | 1.00 | 0.99 | 0.91 |
| Ritu Mishra | Senior Sales Executive | 20 Jan 2025 | 30 | 3.22 | 2.64 | 4.13 | **2.96** | 1.83 |
| Vikram Gupta | Sales Executive | 7 Apr 2025 | 31 | 1.01 | 0.83 | 0.64 | 0.98 | 1.44 |
| Rahul Kapoor | Senior Sales Executive | 27 Jun 2025 | 32 | 1.52 | 2.09 | 2.10 | 1.80 | 1.49 |

- **Every joiner took 30–32 days to place a first order.** This is consistent enough to be the onboarding period, not individual skill.
- From then on, all four sold at or above the benchmark straight away. Pooled across joiners, the index was 1.94 in the first quarter of tenure, 1.53 in the second, 1.48 in the third and 1.83 in the fourth. **Performance did not improve with tenure.**

**The reason: 85–99 % of each joiner's revenue comes from customers handed over to them.**

| Joiner | Handed-over customers | Revenue from them | Customers won | Revenue from them |
|---|---:|---:|---:|---:|
| Harish Tiwari | 47 | ₹2.93 crore (98.6 %) | 6 | ₹4.0 lakh (1.4 %) |
| Ritu Mishra | 54 | ₹4.94 crore (84.9 %) | 16 | ₹87.7 lakh (15.1 %) |
| Vikram Gupta | 44 | ₹1.50 crore (97.4 %) | 4 | ₹3.9 lakh (2.6 %) |
| Rahul Kapoor | 29 | ₹2.58 crore (98.9 %) | 4 | ₹2.8 lakh (1.1 %) |

- A joiner's early results mostly measure **the accounts they were given**, not their selling. Ritu Mishra is the exception: she has won 16 customers worth ₹87.7 lakh, more than the other three joiners combined.
- Since December 2024 joiners handled 19.5 % of orders and won 24.4 % of new customers (29 of 119). Acquisition by joiners is in line with their share of activity, not a strength.

**Where joiners differ, the cause is order size as well as order count.**

| Last 12 months | Avg monthly revenue | Avg monthly orders | Avg order value |
|---|---:|---:|---:|
| Ritu Mishra | ₹33.5 lakh | 27.0 | ₹1.24 lakh |
| Managers and key account managers (8) | ₹25.5 lakh | 23.2 | ₹1.10 lakh |
| Rahul Kapoor | ₹19.2 lakh | 21.4 | ₹89,400 |
| Harish Tiwari | ₹18.4 lakh | 11.8 | ₹1.57 lakh |
| Benchmark peers (4) | ₹10.3 lakh | 13.6 | ₹75,500 |
| Vikram Gupta | ₹9.7 lakh | 18.6 | **₹52,300** |

- **Vikram Gupta places more orders than the benchmark but at about 70 % of its order value.** His revenue index has fallen from 1.01 in months 1–3 to 0.64 in months 10–12. Coaching should focus on order size: bundling, cross-sell and quantity breaks.
- **Harish Tiwari places fewer orders, but large ones.** His revenue depends on a few big orders: one month (tenure month 16) was 5.2 times the benchmark, while he was at or above 80 % of the benchmark in only 11 of 22 months.

**Plan for the September 2026 joiners.**

| | Per joiner, first 6 months |
|---|---:|
| Benchmark monthly revenue (last 12 months) | ₹10.3 lakh |
| Pooled index of the four joiners, months 1–6 | 1.72 |
| **Planned revenue** | **₹1.06 crore** |
| Low case (weakest joiner's index) | ₹56.5 lakh |
| High case (strongest joiner's index) | ₹1.82 crore |

The range is wide because it depends on which accounts are handed over. The plan should be built account by account from the handover list, with this figure as a sense check.

## 9. Business implications and recommendations

1. **Set joiner targets in two parts:** retain the handed-over book (measured against its prior revenue) and win new customers (a count and a value). A single revenue target rewards the joiner who was given the best accounts.
2. **Plan the first 30 days as onboarding.** No joiner placed an order in their first 30 days. Use it for product training and joint visits on the handed-over accounts.
3. **Make acquisition the year-1 development goal.** Three of four joiners won 4–6 customers in 15–22 months. Pair the September joiners with Ritu Mishra, the only joiner with a meaningful new-customer record.
4. **Coach Vikram Gupta on order size** and review Harish Tiwari's dependence on a few large orders, using the [market basket affinity](../08_market_basket_affinity/) and [cross-sell white space](../04_cross_sell_white_space/) lists for their accounts.
5. **Allocate handovers deliberately.** Since the handover list largely decides early results, balance it by value and growth potential, and track what happens to handed-over accounts using the [salesperson relationship risk](../../01_customer_and_revenue/04_salesperson_relationship_risk/) analysis.

## 10. Assumptions and limitations

- **Four joiners.** The curve rests on four people, two Sales Executives and two Senior Sales Executives. Individual results, not the average, should guide decisions.
- **Small benchmark.** Four established peers set the benchmark; one of them sells far less than the others. A wider peer group would lower every index: established managers and key account managers average ₹25.5 lakh a month, against ₹10.3 lakh for the benchmark peers.
- **Order attribution.** Revenue is credited to the salesperson recorded on the order. Customers are often served by several salespeople, so "handed-over" means the customer had ordered from the company before, not that it was formally reassigned.
- **No targets or territories** are recorded, so the analysis cannot judge joiners against the potential of their territory.
- 352 orders with no salesperson are excluded.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Monthly and ramp tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
