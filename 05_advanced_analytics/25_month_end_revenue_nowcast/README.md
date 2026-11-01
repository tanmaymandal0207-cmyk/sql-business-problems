# Case Study · Nowcasting Month-End Revenue from the First Days of the Month

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Three nowcast methods and a prior are back-tested on every day 1–28 of 30 months (April 2024 – September 2026), each using only what was known on that day. The study also measures the error range for each day and tests what makes the nowcast miss: large orders and the year-end March.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-01 |

---

## 1. Business problem

Every Monday the CFO reports an expected month-end revenue figure to the promoters. Today that figure is the forecast made before the month began, and it stays unchanged until the month closes. She wants a figure that learns from the orders already booked. She needs to know which simple method to use on each day, how much to trust it, and when it is likely to go wrong.

## 2. Business questions

1. From which day do the orders booked so far say more than the forecast made before the month?
2. Which method is most accurate on each day?
3. How wide should the range around the figure be?
4. What makes the nowcast miss?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, status |
| `sales_order_items` | One row per product per order | Order value |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Revenue | Booked value of valid orders (not Cancelled or Returned) by order date, every calendar day, January 2024 – September 2026 |
| Back-test | Every month from April 2024 to September 2026 (30), on each day N = 1–28, using only data available on day N |
| **Prior** | The average of the previous 3 months, known before day 1 (the benchmark) |
| Calendar run-rate | Revenue to day N × days in month ÷ N |
| **Weekday run-rate** | Revenue to day N ÷ the share of the month's weekday weight elapsed. A weekday's weight = its average daily revenue ÷ average daily revenue, from all days before the month. |
| **Blend** | Revenue to day N + prior × share of the month's weekday weight still to come |
| Error / MAPE | Nowcast ÷ actual − 1 / the mean absolute error across months |
| 80 % error | The absolute error not exceeded in 8 of 10 months |
| Large order | ₹5 lakh or more; the back-test is repeated without them |

## 5. Analytical approach

1. **Days** (`sahyadri_b2b.nc_days`): a full calendar with revenue, for all orders and without large orders.
2. **Months and weights** (`sahyadri_b2b.nc_months`, `sahyadri_b2b.nc_weights`): actual, prior and weekday weights known before each month.
3. **Nowcasts** (`sahyadri_b2b.nc_nowcasts`): every method on every day of every back-test month, with accuracy by day.
4. **Misses**: large orders, March, and the other months on their own.

## 6. SQL techniques used

- A calendar spine from `GENERATE_DATE_ARRAY`, so that days without orders count as zero
- Point-in-time features: priors from `ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING`, and weekday weights from a join restricted to days before the month
- Running sums of revenue and of weekday weight within each month, so each day's nowcast is one row
- Error bands from `APPROX_QUANTILES` of absolute errors

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Daily revenue = source, for both series |
| 02 | One row per calendar day per series |
| 03 | Prior = average of the previous 3 months |
| 04 | **Weekday weights average 1 over the days before each month** (no look-ahead) |
| 05 | 30 back-test months × 28 days for each series |
| 06 | Revenue to date never falls and never exceeds the month |
| 07 | Revenue to day 15 = a direct recount from orders |
| 08 | Calendar run-rate = revenue to date × days in month ÷ day |
| 09 | Blend = revenue to date + prior × weight still to come |
| 10 | Weekday run-rate = revenue to date ÷ elapsed weight |

## 8. Findings

**Revenue builds evenly through the month, but weekends are quiet and single months are lumpy.**

| By day | 5 | 10 | 15 | 20 | 25 |
|---|---:|---:|---:|---:|---:|
| Average share of the month booked | 15.4 % | 33.1 % | 49.0 % | 65.2 % | 80.8 % |
| Share of the calendar elapsed | 16.4 % | 32.9 % | 49.3 % | 65.8 % | 82.2 % |
| Month-to-month standard deviation | 5.5 pts | 8.5 pts | 8.1 pts | 7.7 pts | 6.9 pts |

Relative to the average day, Tuesday books 1.41 times as much, Saturday 0.60 and Sunday 0.08. There is no month-end rush outside March.

**The blend beats the prior from day 1; the weekday run-rate takes over from day 8.**

| Day | Prior | Calendar run-rate | Weekday run-rate | Blend | 80 % error (weekday run-rate) |
|---:|---:|---:|---:|---:|---:|
| 1 | 21.1 % | 51.0 % | 55.8 % | **20.9 %** | 79.3 % |
| 3 | 21.1 % | 40.9 % | 30.3 % | **19.8 %** | 46.6 % |
| 5 | 21.1 % | 27.1 % | 22.5 % | **18.6 %** | 33.8 % |
| 7 | 21.1 % | 20.2 % | 20.2 % | **19.2 %** | 40.8 % |
| 10 | 21.1 % | **16.7 %** | 17.1 % | 17.3 % | 21.7 % |
| 15 | 21.1 % | 12.8 % | **12.3 %** | 13.8 % | 19.1 % |
| 20 | 21.1 % | **8.1 %** | 8.3 % | 9.4 % | 14.4 % |
| 25 | 21.1 % | **4.6 %** | 5.0 % | 6.2 % | 6.9 % |

*Mean absolute error, 30 months.*

- The blend is better than the prior on all 28 days. Both run-rates beat the prior from day 7. The weekday run-rate is better than the blend from day 8.
- The weekday weighting matters early: on day 3 it cuts the run-rate error from 41 % to 30 %, because the first days may or may not include a weekend. From day 10 on, the two run-rates are within half a point of each other.
- From day 10 the run-rate is unbiased (within ±1.3 %).

**Large orders cause about half of the error.**

| Day | Weekday run-rate, all orders | Without orders ≥ ₹5 lakh | Prior, without large orders |
|---:|---:|---:|---:|
| 5 | 22.5 % | 16.8 % | 15.0 % |
| 10 | 17.1 % | **10.1 %** | 15.0 % |
| 15 | 12.3 % | **6.2 %** | 15.0 % |
| 20 | 8.3 % | 6.0 % | 15.0 % |

171 orders of ₹5 lakh or more made up 21.2 % of revenue in the back-test months. Without them, the run-rate is twice as accurate by mid-month.

**March is back-loaded, and every method under-calls it.**

| March | Actual | Prior error | Weekday run-rate error on day 10 / 15 / 20 / 25 |
|---|---:|---:|---|
| 2025 | ₹414.5 lakh | −29.8 % | −9.0 % / +16.0 % / +2.4 % / −1.6 % |
| 2026 | ₹541.7 lakh | −38.5 % | −21.7 % / −25.4 % / −21.0 % / **−21.7 %** |

- March books 29.3 % of its revenue from day 26 onward (19.4 % of its days), against 18.2 % in other months. In 2026 the run-rate was still 22 % short on day 25.
- Without the two Marches, the weekday run-rate error is 17.3 % on day 10 and 11.7 % on day 15.

## 9. Business implications and recommendations

1. **Replace the static figure with a rolling nowcast.** In the first week report the blend (booked so far + prior for the days left). From day 8 report the weekday run-rate.
2. **Always show a range.** Use about ±22 % on day 10, ±19 % on day 15 and ±14 % on day 20 (8 months in 10 fall within it). Never quote a single figure in the first week.
3. **Nowcast base revenue and large deals separately.** Run-rate the orders under ₹5 lakh (±10 % by day 10). Add large deals from the sales pipeline, deal by deal, as in the [March peak](../../01_customer_and_revenue/19_march_peak_drivers/) study.
4. **Add a March uplift for the last week.** Budget-flush orders arrive after the 25th. Until a third March confirms the pattern, show March as a range up to about 30 % above the run-rate (in 2026 the final figure was 28 % above the day-25 run-rate).
5. **Use the [revenue forecast baseline](../04_revenue_forecast_baseline/) as the prior** instead of a 3-month average once it beats the average in back-tests; a better prior improves the blend in the first week.

## 10. Assumptions and limitations

- **Booked revenue, by order date.** Cancellations later in the month can reduce booked orders; invoiced or delivered revenue would build differently.
- **Days 1–28 only.** Days 29–31 are left out so that every month has the same days; by then the nowcast is within a few per cent.
- **30 months, two Marches.** The March pattern rests on 2025 and 2026.
- **Weekday weights are company-wide.** Public holidays are not modelled; a holiday early in a month lowers that month's run-rate.
- **Simple methods only.** No regression or machine-learning model is fitted; the point is a figure finance can explain line by line.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Day, month, weight and nowcast tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
