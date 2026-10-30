# Case Study · Revenue Volatility: How Much of a Monthly Miss Is Predictable?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 33 months of revenue (January 2024 – September 2026, 9,391 valid orders) split into number of orders and order value, separated into trend, the March and December peaks and the remaining swing, and compared with a 300-draw bootstrap of what chance alone produces.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-30 |

---

## 1. Business problem

The best monthly revenue forecast misses a typical month by about 17 % (see the [revenue forecast baseline](../../05_advanced_analytics/04_revenue_forecast_baseline/)). Each month the board asks the sales director to explain the miss, and it now wants the forecast within ±5 %. Before anyone promises that, the FP&A lead wants to know where the volatility comes from, how much of it can be planned, and how much would remain even with a perfect plan.

## 2. Business questions

1. Does monthly volatility come from the number of orders or from their size?
2. How much is trend and the March and December peaks, which can be planned?
3. How much is chance: what would remain with a perfect forecast of demand?
4. How much do a few very large orders contribute?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, status |
| `sales_order_items` | One row per product per order | Order value |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Valid order | Not Cancelled or Returned |
| **Revenue identity** | Monthly revenue R = orders N × average order value S, so ln R = ln N + ln S |
| **Planned pattern** | A least-squares trend in ln y, plus a March effect and a December effect (the average trend residual in those months), fitted on all 33 months |
| **Unexplained swing** | ln y − planned pattern; shown as a percentage of the planned level. Because every step is linear, the swings add up: u(R) = u(N) + u(S). |
| Variance share | var(u(N)) ÷ var(u(R)), var(u(S)) ÷ var(u(R)) and 2 cov ÷ var(u(R)), which add to 100 % |
| **Random arrival noise** | If orders arrive at random at the planned rate, ln N varies by about 1 ÷ √N |
| **Random draw noise** | 300 times, each month's N orders are redrawn at random from all orders of the same calendar year; the SD of ln(average order value) across draws |
| Irreducible swing | √(random arrival² + random draw²): what a perfect plan of demand would still miss by |
| Large order | Net value of ₹5 lakh or more |

## 5. Analytical approach

1. **Orders and months** (`sahyadri_b2b.rv_orders`, `sahyadri_b2b.rv_months`).
2. **Components** (`sahyadri_b2b.rv_components`): trend, peaks and unexplained swing for revenue, orders, average order value and revenue without large orders; the variance split.
3. **Bootstrap** (`sahyadri_b2b.rv_bootstrap`): the swing chance alone produces.
4. **Large orders**: the biggest misses and how much of them large orders explain.

## 6. SQL techniques used

- A multiplicative identity turned additive with logs, so variance splits exactly into count, size and covariance
- Least-squares trend from plain aggregates, and seasonal effects as group means of residuals
- A bootstrap in SQL: each month's orders redrawn from a numbered annual pool with an integer hash
- Validation of the identities (ln R = ln N + ln S before and after the plan; the variance split adds up) and of the bootstrap structure

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per valid order in range; order value = source |
| 02 | 33 months; totals = order recount; large + other = revenue |
| 03 | **ln revenue = ln orders + ln order value, before and after the plan** |
| 04 | Trend slope = `COVAR_POP(t, y) ÷ VAR_POP(t)` |
| 05 | Trend residuals average zero for every measure |
| 06 | March and December effects = average residual; the swing averages zero there |
| 07 | 300 bootstrap draws per month, each with the real number of orders |
| 08 | Bootstrap averages lie within the same year's order values |
| 09 | Large-order flag = order value of ₹5 lakh or more |
| 10 | **Swing variance = orders + order value + 2 × covariance** |

## 8. Findings

**Order values are extremely uneven.** The median order is ₹46.6k and the mean ₹97.2k (coefficient of variation 2.63). 190 orders of ₹5 lakh or more (2.0 % of orders) carry **21.9 % of revenue**; the largest is ₹119.3 lakh.

**Seven-tenths of the monthly variation is planned pattern.**

| Measure | Trend a year | March vs trend | December vs trend | Variance explained by the pattern | Unexplained swing (SD) |
|---|---:|---:|---:|---:|---:|
| Revenue | +19.5 % | **+63.1 %** | +29.4 % | **72.3 %** | **13.7 %** |
| Orders | +17.0 % | +38.9 % | +27.5 % | 82.8 % | 8.0 % |
| Average order value | +2.1 % | +17.4 % | +1.5 % | 21.0 % | 10.4 % |
| Revenue excluding large orders | +20.9 % | +37.8 % | +28.2 % | 72.9 % | 11.8 % |

- **The March financial year-end is the biggest planned event**: more orders (+39 %) and bigger ones (+17 %). December brings more orders, not bigger ones.

**What is left is mostly order size, and it is no larger than chance.**

| Unexplained swing | Orders | Average order value | Revenue |
|---|---:|---:|---:|
| Observed (SD) | 8.0 % | 10.4 % | 13.7 % |
| Chance alone (random arrival / random draw) | 6.0 % | 14.2 % | **15.4 %** |
| Share of revenue swing variance | 34.1 % | **56.9 %** | (covariance 9.0 %) |

- **A perfect demand plan would still miss a typical month by about 15 %.** With orders this uneven, which few large orders land in a given month is luck; 285 orders a month are not enough to average it out.
- The observed swing (13.7 %) is already at that floor. The baseline forecast's 17.5 % error is close to it; the gap came from under-forecasting 2026 growth, not from missing a pattern.
- Order count and order value move independently (correlation 0.10): busy months do not bring bigger orders.

**Large orders explain about half of the big misses.**

| Month | Revenue | Large orders | Their revenue | vs pattern | Without large orders |
|---|---:|---:|---:|---:|---:|
| Jun 2025 | ₹198.6 lakh | 4 | ₹26.3 lakh | **−26.6 %** | −19.4 % |
| Jul 2026 | ₹244.8 lakh | 3 | ₹20.8 lakh | −25.4 % | −14.6 % |
| Apr 2025 | ₹202.7 lakh | 2 | ₹28.0 lakh | −22.9 % | −15.6 % |
| Sep 2025 | ₹219.0 lakh | 4 | ₹31.6 lakh | −22.6 % | −16.4 % |
| Nov 2025 | ₹231.7 lakh | 4 | ₹23.3 lakh | −20.5 % | −9.9 % |

- Large orders made up between 7.4 % and 40.0 % of a month's revenue; the month's miss rises with that share (correlation 0.54).
- **11 months missed the pattern by more than 15 %; 6 of them fall within 15 % once large orders are removed.**

## 9. Business implications and recommendations

1. **Do not promise a ±5 % monthly forecast.** Chance alone moves a month by about 15 %; a tighter target can only be met by managing the timing of orders, not by forecasting better.
2. **Forecast two streams.** Plan regular orders with trend and the March and December peaks (11.8 % swing), and forecast orders of ₹5 lakh or more one by one from the sales pipeline.
3. **Report the forecast as a range.** A ±15 % band around the planned pattern held 22 of 33 months; explain only months outside it.
4. **Plan quarters, not months, for targets.** The swing carries little from one month to the next (correlation 0.18), so it partly cancels over a quarter, and a quarterly target is a fairer measure of the sales team.
5. **Use the March and December effects in capacity and cash planning**: +63 % and +29 % on trend are known in advance (see [dispatch workload planning](../../03_operations_and_supply_chain/04_dispatch_workload_planning/)).

## 10. Assumptions and limitations

- **The pattern is fitted in hindsight** on all 33 months; a forecast made in advance would do somewhat worse.
- **Three seasonal parameters only.** Other months are assumed to sit on trend; with two or three years per month, a full seasonal profile would over-fit.
- **The random-draw pool is the calendar year**, so mix and price changes within a year count as chance.
- **Orders, not invoices.** Revenue is dated by order date; the [revenue cut-off](../../04_data_quality_and_reconciliation/04_revenue_cutoff_reconciliation/) study shows how delivery-date revenue differs.
- **₹5 lakh threshold** is a judgement (the top 2 % of orders); a different threshold changes the large-order figures.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, month, component and bootstrap tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
