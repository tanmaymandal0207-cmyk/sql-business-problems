# Case Study · Do Large Orders Steal Next Quarter's Demand?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study covers the 190 orders of ₹5 lakh or more placed from January 2024 to September 2026. It compares each customer's regular ordering before and after a large order, adjusts for the market over the same days, and tests the result against 400 sets of random dates for the same customers.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-06 |

---

## 1. Business problem

Orders of ₹5 lakh or more bring in about a fifth of revenue. Each time one lands, someone warns the sales director: "they have just stocked up, the next quarter will be quiet." If that is true, the plan should net a large order against the customer's next few months. If it is not, large orders are extra business and the plan should keep them on top. The FP&A lead wants the question settled before the next budget.

## 2. Business questions

1. After a large order, does the customer's regular ordering drop?
2. Is any drop larger than random dates for the same customers would show?
3. Does the answer depend on the window, or on how often the customer places large orders?
4. How should the plan treat a large order?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Order value |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Large order | A valid order (not Cancelled or Returned) worth ₹5 lakh or more, as in the [revenue volatility](../../02_sales_and_profitability/15_revenue_volatility_drivers/) and [nowcast](../../05_advanced_analytics/25_month_end_revenue_nowcast/) studies |
| Base revenue | Revenue from orders below ₹5 lakh |
| Event | A large order with a full window of W days before and after it inside the data (W = 30, 60, 90, 180) |
| Customer change | The customer's base revenue in the W days after ÷ the W days before (the order date itself left out) |
| Market change | The same ratio for all other customers over the same calendar days. It removes trend and season. |
| **Relative change** | Customer change ÷ market change, pooled over events (sum after ÷ sum before) |
| **Placebo test** | 400 sets of random dates for the same customers (one per event, from an integer hash), scored the same way. p-value = share of placebo sets at or below the actual relative change. The placebo median is the "no event" level. |
| Base lost | Base revenue after the events × (placebo median ÷ relative change − 1) |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.po_orders`) and a **daily cumulative base-revenue index** (`sahyadri_b2b.po_days`) for the market windows.
2. **Scores** (`sahyadri_b2b.po_scores`): every event and its 400 placebo dates, with own and market base revenue before and after, for each window. **Sets** (`sahyadri_b2b.po_sets`): one relative change per window and set.
3. **The test** by window, and again on one common set of events.
4. **Value and segments**: base revenue lost as a share of the large orders, and habitual against occasional large-order customers.

## 6. SQL techniques used

- An event study in SQL: before/after windows around each event, joined on a day index
- A cumulative-sum table for the market windows (one lookup per window edge instead of a join to every order)
- A placebo (randomisation) test with 400 pseudo-random dates per event from an integer hash, `GENERATE_ARRAY` and `MOD`
- One-sided p-values as `COUNTIF(placebo <= actual) / COUNT(*)`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders and revenue = source |
| 02 | One row per day; cumulative base = all orders below ₹5 lakh |
| 03 | Events = large orders with a full window on both sides, by window |
| 04 | Every event has 400 placebo dates, all inside the valid range |
| 05 | Placebo dates belong to the event's customer |
| 06 | **Own base revenue before and after = recount from orders** (actual events and 5 placebo sets) |
| 07 | Base + large = every order in the window, with the date itself left out |
| 08 | **Market base before and after = recount of the other customers' orders** (90-day window) |
| 09 | Relative change per set = recount from the event scores; 4 windows × 401 sets |
| 10 | Placebo dates spread over the range (average within 3 % of the midpoint) |

## 8. Findings

**Large orders are a fifth of revenue and come from 76 customers.**

| | Value |
|---|---:|
| Orders of ₹5 lakh or more | 190 |
| Customers placing them | 76 |
| Revenue | ₹20.01 crore (21.9 % of the total) |
| Average large order | ₹10.53 lakh |

**After a large order, the customer's regular ordering dips a little, but not by more than chance would explain.**

| Window | Events | Customer change | Market change | Relative change | Placebo median | Placebo 5–95 % | p-value | Dip against placebo |
|---|---:|---:|---:|---:|---:|---|---:|---:|
| 30 days | 172 | 0.914 | 1.003 | 0.911 | 0.995 | 0.872–1.131 | 0.128 | −8.4 % |
| 60 days | 157 | 0.884 | 1.005 | 0.879 | 0.980 | 0.897–1.077 | **0.025** | −10.3 % |
| 90 days | 149 | 0.945 | 1.012 | 0.934 | 0.958 | 0.884–1.066 | 0.330 | −2.5 % |
| 180 days | 117 | 1.052 | 1.098 | 0.958 | 0.974 | 0.902–1.038 | 0.393 | −1.6 % |

- In the first one to two months, the customer's regular orders run about 8–10 % below the no-event level. Only the 60-day window reaches p < 0.05, and four windows were tested.
- Over 90 and 180 days the dip shrinks to 2–3 % and is well inside the placebo range.

**On one common set of events, even the 60-day dip is not significant.** The windows above use different events, because longer windows drop events near the ends of the data. Using the 117 events with a full 180-day window for every window:

| Window | Relative change | Placebo median | p-value |
|---|---:|---:|---:|
| 30 days | 0.971 | 1.001 | 0.393 |
| 60 days | 0.922 | 0.984 | 0.185 |
| 90 days | 0.972 | 0.964 | 0.568 |
| 180 days | 0.958 | 0.974 | 0.393 |

**Even the largest estimate is a small fraction of the large order.**

| Window | Large orders in the test | Base revenue lost against placebo | Share of the large orders |
|---|---:|---:|---:|
| 30 days | ₹18.65 crore | ₹0.62 crore | 3.3 % |
| 60 days | ₹16.24 crore | ₹1.28 crore | **7.9 %** |
| 90 days | ₹14.87 crore | ₹0.44 crore | 2.9 % |
| 180 days | ₹11.51 crore | ₹0.45 crore | 3.9 % |

At most about 8 % of a large order's value comes out of the customer's next two months. More than 90 % of it is extra revenue.

**Habitual and occasional large-order customers behave alike** (90-day window).

| Customers | Events | Customers | Relative change | Placebo median | p-value |
|---|---:|---:|---:|---:|---:|
| Habitual (3+ large orders) | 102 | 22 | 0.925 | 0.951 | 0.333 |
| Occasional (1–2 large orders) | 47 | 41 | 0.998 | 1.052 | 0.385 |

Neither group shows a significant dip.

## 9. Business implications and recommendations

1. **Plan large orders as extra revenue, not as demand borrowed from next quarter.** Over 90–180 days, the customer's regular ordering after a large order is within 3 % of normal and not significantly different from it.
2. **If any netting is wanted, keep it small and short:** at most about 8 % of the large order's value, spread over the next two months. Do not reduce the customer's quarterly target by the full order.
3. **Keep large orders as a separate line in forecasts.** The [volatility study](../../02_sales_and_profitability/15_revenue_volatility_drivers/) showed they drive most of the month-to-month swing. This study shows they do not need a matching negative line afterwards.
4. **Stop the "quiet quarter" warning in sales reviews.** A dip after a large order should be followed up like any other dip, not explained away.
5. **Re-run the test yearly.** With this many events, only a dip of about 7–12 % (the gap between the placebo median and its 5th percentile) would stand out from chance; a smaller pull-forward cannot be ruled out.

## 10. Assumptions and limitations

- **Booked order value by order date.** If customers stock up through dispatch timing rather than ordering, this study would not see it.
- **Regular ordering only.** The test measures base revenue (orders below ₹5 lakh); it does not ask whether one large order delays the customer's next large order.
- **Placebo dates are random days for the same customer.** They control for the customer's own level and the market, but a customer's large orders may fall in its busier periods, which would hide a small pull-forward.
- **Several windows were tested.** The one p-value below 0.05 (60 days, full event set) does not survive on the common event set and should not be read as proof of a dip.
- **₹5 lakh threshold.** The same as in earlier studies; a different cut-off changes which orders are events.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, day, score and set tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
