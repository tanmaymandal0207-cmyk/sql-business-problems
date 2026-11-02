# Case Study · Honest Forecast Ranges: Conformal Intervals for Product Demand

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The back-test covers 186 products over 15 months (July 2025 – September 2026), 2,790 product-months in all. Each month's demand is forecast with a 6-month average and given three 80 % ranges: the planners' normal ± 1.28 SD range, a conformal range from the product's own recent errors, and a pooled, scaled conformal range. The study compares coverage, where the misses fall, and the stock each range implies.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-02 |

---

## 1. Business problem

The planning team forecasts each product's monthly units and covers "the forecast plus a normal safety margin". In practice that is an 80 % range of forecast ± 1.28 standard deviations, whose top is meant to be exceeded only one month in ten. Stock-outs and excess stock both keep happening. The supply chain head wants to know whether the ranges are honest, and whether a method that makes no assumption about the shape of the errors would do better.

## 2. Business questions

1. Do the 80 % ranges contain next month's demand 80 % of the time, and are the misses balanced?
2. Is a conformal range, built from each product's own recent forecast errors, more honest?
3. Does pooling errors across products help the slower movers?
4. What does each method cost in stock held above the forecast?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order month, status |
| `sales_order_items` | One row per product per order | Units |
| `products` | One row per product | Unit cost |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Demand | Units per product per month on valid orders (not Cancelled or Returned), January 2024 – September 2026, zero months included |
| **Forecast (MA6)** | Average of the previous 6 months |
| Calibration errors | The 12 forecast errors (actual − MA6) of the 12 months before the forecast month |
| **Normal range** | MA6 ± 1.2816 × SD of the calibration errors (floored at 0) |
| **Conformal range (own errors)** | MA6 + [smallest, largest] calibration error. With 12 errors this is split conformal for 80 %: expected coverage at least 11 ÷ 13 = 84.6 % if errors are exchangeable. |
| **Conformal range (pooled, scaled)** | MA6 + (MA6 + 1) × [10th, 90th percentile] of all products' scaled errors error ÷ (MA6 + 1) in the same 12 months |
| Back-test | Forecast months July 2025 – September 2026, products with some demand in the previous 12 months |
| Coverage / above range | Share of product-months whose actual units fall inside the range / above its top (a stock-out at that stock level) |
| Demand type | Months with demand in the previous 12: regular 9+, intermittent 4–8, sparse 1–3 |
| Stock above forecast | (top of range − MA6) × unit cost, summed over products, per month |

## 5. Analytical approach

1. **Demand and forecast** (`sahyadri_b2b.cf_demand`): every product-month with MA6, error and scaled error.
2. **Ranges** (`sahyadri_b2b.cf_intervals`): the three ranges for every back-test product-month.
3. **Scores** (`sahyadri_b2b.cf_scores`): coverage, misses, width and stock, overall, by demand type and month by month.
4. **Error shape**: why the normal range misses on one side.

## 6. SQL techniques used

- A complete product × month grid with zeros, and moving windows (`ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING`) for a point-in-time forecast
- Rolling calibration statistics with a named `WINDOW` (`STDDEV_SAMP`, `MIN`, `MAX`, `COUNTIF` over the previous 12 months)
- Split conformal prediction in SQL: interval ends from the order statistics of past errors
- Pooled quantiles per test month from a range join on the previous 12 months, with `APPROX_QUANTILES`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per product per month; units = source |
| 02 | **MA6 = average of the previous six months (self-join recount)** |
| 03 | Error = units − MA6 from month 7; none before |
| 04 | Back-test rows: test months only, 12 calibration errors each |
| 05 | **Conformal range = MA6 + smallest and largest of the 12 errors (recount)** |
| 06 | Normal range = MA6 ± 1.2816 SD of the 12 errors (recount) |
| 07 | Pooled ranges use every scaled error of the previous 12 months |
| 08 | Every range has 0 ≤ low ≤ high |
| 09 | Three methods for every back-test product-month |
| 10 | Conformal coverage = a recount from the interval table |

## 8. Findings

**All three ranges cover about 80 %, but the normal range misses on the wrong side.**

| Method (80 % range) | Coverage | Demand above the top | Demand below the bottom | Average width | Stock above forecast, a month |
|---|---:|---:|---:|---:|---:|
| Normal (± 1.28 SD) | 82.2 % | **13.3 %** | 4.5 % | 138 units | ₹2.34 crore |
| Conformal, own errors | 83.1 % | 7.6 % | 9.3 % | 196 units | ₹4.06 crore |
| Conformal, pooled and scaled | 80.9 % | **10.1 %** | 9.0 % | 186 units | ₹3.77 crore |

- **The normal range under-protects.** Its top is meant to be exceeded one month in ten (10 %), but demand exceeds it 13.3 % of the time: an 86.7 % service level instead of 90 %. Its bottom is too low, so the misses are lopsided.
- **The pooled conformal range hits the target on both sides** (10.1 % above, 9.0 % below).
- The own-errors conformal range is the most cautious (7.6 % above). With only 12 calibration errors, the largest error is a conservative top, as the 84.6 % guarantee implies.

**Errors are skewed, which is why ± SD fails.**

| Forecast errors, July 2024 – September 2026 | Value |
|---|---:|
| Errors above zero | 39.6 % |
| Scaled error, 5th / 50th / 95th percentile | −0.93 / −0.08 / **+2.27** |
| Months with zero demand | 17.3 % |

Most months come in a little below the moving average, and a few come in far above it (a large order). A symmetric ± SD range puts too little room on top and too much underneath. Conformal ranges take the shape from the errors themselves.

**Pooling fails the intermittent products.**

| Demand type | Product-months | Normal: coverage / above top | Own errors: coverage / above top | Pooled: coverage / above top |
|---|---:|---|---|---|
| Regular (9+ of 12 months) | 2,479 | 82.0 % / 13.0 % | 83.1 % / 7.3 % | 82.6 % / 9.0 % |
| Intermittent (4–8) | 309 | 83.2 % / 15.9 % | 83.2 % / 9.7 % | **67.3 % / 19.1 %** |

The pooled scale (MA6 + 1) suits regular products. For intermittent ones, a single large order is a far bigger multiple of the average, so pooled ranges are too narrow, and one month in five exceeds the top. Only 2 product-months were sparse.

**Coverage holds month by month.** The worst months for all methods were March and April 2026, the year-end peak (normal 73.7 % and 75.3 %).

## 9. Business implications and recommendations

1. **Stop using ± 1.28 SD for safety stock.** It promises a 90 % service level and delivers 86.7 %, because big orders make errors lopsided.
2. **Use the pooled conformal top for regular products** (91 % service on regular products at about the same width as the own-errors range, and on target across the range), and **the own-errors conformal top for intermittent products** (90.3 % service where pooling fails).
3. **Budget the stock honestly.** Moving from the normal top to the conformal tops raises stock above forecast from ₹2.3 crore to about ₹3.8–4.1 crore a month of cover. If that is too much, choose a lower service level openly rather than keep a range that claims 90 % and gives 87 %.
4. **Handle large orders separately.** The upper tail is mostly single large orders. Committed large orders from the sales pipeline should be added to the forecast rather than covered with safety stock (see [intermittent demand forecasting](../14_intermittent_demand_forecasting/)).
5. **Plan March separately.** All methods under-cover the year-end peak; add the March uplift from the [March peak](../../01_customer_and_revenue/19_march_peak_drivers/) study to March forecasts.

## 10. Assumptions and limitations

- **A simple forecast.** Ranges are built around a 6-month average; a better forecast would give narrower ranges, but the conformal method works the same way around any forecast.
- **Stock above forecast is a monthly cover figure,** summed across products at unit cost; it is not a stock count, and lead times are not modelled.
- **Exchangeability.** The conformal guarantee assumes the next error behaves like the last 12. Trends and the March peak break that a little, as the monthly table shows.
- **15 back-test months.** Each method's coverage figure rests on 2,790 product-months, but only 15 distinct months.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Demand, interval and score tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
