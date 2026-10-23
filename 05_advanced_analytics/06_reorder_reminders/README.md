# Case Study · Replenishment Reorder Reminders

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. As of 30 Sep 2026, with a backtest at 31 Mar 2026.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-23 |

---

## 1. Business problem

Many customers rebuy the same products on a rough cycle. If a customer's usual reorder date passes without an order, they may have bought from a competitor. The inside-sales team wants a weekly **reminder list**: "these customers usually buy this product about now". The [churn early warning](../../01_customer_and_revenue/02_customer_churn_early_warning/) works at customer level. This works at **product level**, so it can catch a customer who is still active but has stopped buying one line. Before building it, the sales head wants proof that it would work.

## 2. Business questions

1. How many customer-product pairs buy on a regular cycle?
2. Which pairs are due or overdue today, and what are they worth?
3. Would the reminders have worked? Of the pairs the method called due, how many actually reordered, compared with pairs that were not due?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, date, status |
| `sales_order_items` | One row per product per order | Product, quantity, value |
| `customers`, `products` | One row per customer / product | Names for the reminder lists |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Purchase event | A customer buying a product on an order date (orders not Cancelled or Returned) |
| Gap | Days between consecutive events for the same customer and product |
| Median gap | The pair's usual reorder interval |
| CV | Standard deviation ÷ mean of the gaps |
| Regularity | Pairs with 4+ events: **Regular** (CV < 0.5), **Semi-regular** (0.5–1.0), **Irregular** (≥ 1.0). Fewer events: Insufficient history. |
| Reorder status | Days since last purchase ÷ median gap: Not yet due (< 0.8), **Due now** (0.8–1.5), **Overdue** (1.5–3), Lapsed (> 3) |
| Typical value | Median value of the pair's purchase events: what one reorder is worth |
| Backtest | Statistics from purchases up to 31 Mar 2026 only. A pair is predicted due if its expected next date (last purchase + median gap) is on or before 29 Jun 2026 and it is not already lapsed. |
| Lift | Reorder rate of predicted-due pairs ÷ reorder rate of other pairs |

## 5. Analytical approach

1. **Purchase events** (`sahyadri_b2b.customer_product_purchases`). One row per customer, product and date, with the gap since the previous purchase.
2. **Reorder status** (`sahyadri_b2b.reorder_status`). One row per pair with cycle statistics, regularity and status at 30 Sep 2026.
3. **Backtest** (`sahyadri_b2b.reorder_backtest`). Predictions from data up to 31 Mar 2026, compared with actual purchases in the following 90 days.
4. **Reminder lists:** overdue pairs by value, and customers with the most overdue products.

## 6. SQL techniques used

- `LAG(...) OVER (PARTITION BY customer, product ORDER BY date)` for inter-purchase gaps
- `PERCENTILE_CONT` medians and `STDDEV_SAMP / AVG` for the coefficient of variation
- A **point-in-time backtest**: statistics rebuilt from events up to a cut-off date, then scored against later actuals
- Lift and capture rate computed with conditional `COUNTIF`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One event per customer, product and date |
| 02 | Event value = source revenue |
| 03 | Status pairs = distinct customer-product pairs in the source |
| 04 | Events per pair add up to event rows |
| 05 | **Gaps recomputed** with a self-join instead of `LAG` |
| 06 | Every pair's median gap passes the median property |
| 07 | Regularity matches events and CV |
| 08 | Reorder status matches days since last purchase ÷ median gap |
| 09 | **No look-ahead:** no backtest pair uses a purchase after 31 Mar 2026 |
| 10 | Backtest reorder flags match an independent check on source orders |

## 8. Findings

**Few customer-product pairs buy on a regular cycle.**

| Regularity | Pairs | Share | Average usual gap |
|---|---:|---:|---:|
| Regular | 144 | 1.1 % | 175 days |
| Semi-regular | 819 | 6.1 % | 125 days |
| Irregular | 376 | 2.8 % | 69 days |
| Insufficient history (fewer than 4 purchases) | 12,187 | 90.1 % | – |

Most pairs are bought only once or twice in 33 months. Cycles exist mainly for large repeat buyers.

**The backtest shows the reminders have real but modest predictive value.**

| Regularity (at 31 Mar 2026) | Predicted due | Reordered within 90 days if due | If not due | Lift | Share of all reorders anticipated |
|---|---:|---:|---:|---:|---:|
| Regular | 68 | 33.8 % | 23.4 % | 1.45 | 67.6 % |
| Semi-regular | 394 | 45.4 % | 35.7 % | 1.27 | 70.5 % |
| Irregular | 199 | 49.2 % | 32.1 % | 1.53 | 78.4 % |
| **All pairs with 4+ purchases** | **661** | **45.4 %** | **33.1 %** | **1.37** | **72.6 %** |

- **A "due" pair is about 1.4 times as likely to reorder** as a pair that is not due, and the method anticipated 73 % of the reorders that happened.
- **Regularity did not improve the prediction.** Irregular pairs had the highest lift. The CV filter would not make the list more accurate, so it can be dropped.
- Fewer than half of due pairs reorder within 90 days. A reminder is a prompt for a call, not a forecast.

**At 30 Sep 2026, 182 regular or semi-regular pairs are overdue across 71 customers.** One reorder of each is worth about ₹52.0 lakh. Another 200 pairs (₹67.4 lakh) are due now.

| Customer | Overdue products | One reorder each |
|---|---:|---:|
| Navkar Agencies | 4 | ₹7.80 lakh (mostly a ₹7.2 lakh fire-fighting pump, 284 days since last) |
| Maa Joshi Industrial Suppliers | 17 | ₹6.65 lakh |
| Siddhivinayak Mishra Trading | 17 | ₹6.24 lakh |
| Mahavir Pillai Spinning Mills | 12 | ₹3.15 lakh |
| Krishna Castings | 10 | ₹2.29 lakh |

These customers are still active and among the largest. The overdue lines may be bought elsewhere, which customer-level churn signals would not show.

## 9. Business implications and recommendations

1. **Launch the reminder list as a weekly call prompt for inside sales**, limited to overdue pairs worth ₹25,000 or more per reorder. It anticipated 73 % of real reorders, and a call costs little.
2. **Start with the five customers above.** They have 60 overdue product lines between them while still buying other products, which suggests lost share of wallet rather than lost customers.
3. **Drop the regularity filter.** Any pair with 4 or more purchases is worth monitoring.
4. **Measure the uplift.** Call half the overdue pairs and hold back the other half for a quarter, then compare reorder rates. This tests whether reminders *cause* reorders, which the backtest cannot show.
5. **Test category-level cycles next.** Customers may rotate between similar products, which product-level cycles miss.

## 10. Assumptions and limitations

- **Short history.** 33 months gives most pairs too few purchases for a cycle. The method will cover more pairs as history grows.
- **Single backtest date.** One evaluation date (31 Mar 2026) and one 90-day horizon. Rolling backtests would give a more stable estimate.
- **Correlation, not effect.** The backtest shows the method identifies likely buyers. It cannot show that a reminder call increases sales.
- **Project purchases.** Some repeated purchases are project-driven, not consumption, and will not recur on a cycle.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Purchase event, status and backtest tables, and 2 analysis steps |
| `validation.sql` | 10 pass/fail checks |
