# Case Study · Baseline Revenue Forecast with Backtesting

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. History January 2024 – September 2026; backtest January – September 2026; forecast October – December 2026.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-21 |

---

## 1. Business problem

Finance needs a revenue forecast for **October–December 2026** to plan purchasing, working capital and the year-end. There is no forecasting tool, and today's method is "last month plus a bit". The CFO does not want a black box. They want a **simple baseline that anyone can re-run in SQL**, evidence of how accurate it would have been, and a **range** rather than a single number.

## 2. Business questions

1. Which simple forecasting method would have been most accurate, tested on months it had not seen?
2. Does the best method tend to over- or under-forecast?
3. What is the Q4 2026 forecast, and what range should finance plan around?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order month and status |
| `sales_order_items` | One row per product per order | Revenue |

## 4. Metric definitions

| Method | Forecast for month *t* |
|---|---|
| Last month | Revenue in *t* − 1 |
| 3-month average | Average of *t* − 3 to *t* − 1 |
| 12-month average | Average of *t* − 12 to *t* − 1 |
| Seasonal × growth | Revenue in *t* − 12 × (last 12 months ÷ the 12 months before that) |
| Blend | Average of the 12-month average and seasonal × growth |

| Accuracy measure | Definition |
|---|---|
| MAPE | Mean absolute % error across the test months (lower is better) |
| Bias | Mean % error; negative = under-forecast |
| Nine-month total error | Forecast total ÷ actual total − 1 for Jan–Sep 2026 |

Revenue is order intake (orders not Cancelled or Returned, by order month), the basis used in management reports. For a delivery-basis view, see [Revenue cut-off reconciliation](../../04_data_quality_and_reconciliation/04_revenue_cutoff_reconciliation/).

## 5. Analytical approach

1. **Monthly revenue table** (`monthly_revenue`). A month spine from January 2024 to December 2026, with actuals to September 2026 and blanks for the future.
2. **Forecast table** (`monthly_forecasts`). Every method's forecast for each month, built with window functions that look only **backwards**, so no forecast uses data from its own month or later.
3. **Backtest accuracy** for January–September 2026.
4. **Month-by-month backtest** of the blend.
5. **Q4 2026 forecast** with a range of ± the backtest MAPE, plus a bias-adjusted version.

## 6. SQL techniques used

- A month spine with `GENERATE_DATE_ARRAY`, so missing months cannot silently shift the window functions
- Rolling windows: `AVG/SUM … OVER (ORDER BY month ROWS BETWEEN n PRECEDING AND 1 PRECEDING)` and `LAG(…, 12)` for year-on-year values
- `UNION ALL` to reshape five methods into long format for one accuracy query
- Scenario ranges from backtest error, and a bias correction

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per month |
| 02 | The spine covers 36 months (Jan 2024 – Dec 2026) |
| 03 | Actual revenue = in-scope line-item total |
| 04 | No future month has an actual value |
| 05 | Every historical month has an actual value |
| 06 | **No look-ahead:** the Jan 2026 12-month average equals the 2025 average, recomputed directly |
| 07 | The Jan 2026 seasonal × growth forecast recomputed by hand |
| 08 | Every backtest month has a forecast from every method |
| 09 | All three Q4 months are forecast |
| 10 | The blend equals the average of its two inputs on every row |

## 8. Findings

**The blend is the most accurate method, but every trailing method under-forecast 2026.**

| Method | MAPE | Bias | Worst month | Nine-month total |
|---|---:|---:|---:|---:|
| **Blend** | **17.5 %** | −13.8 % | 32.5 % | −16.4 % |
| 12-month average | 18.0 % | −12.4 % | 50.1 % | −16.4 % |
| Seasonal × growth | 18.2 % | −15.1 % | 28.9 % | −16.4 % |
| 3-month average | 21.5 % | +1.9 % | 38.5 % | −2.9 % |
| Last month | 25.8 % | +5.6 % | 71.6 % | 0.0 % |

- **Monthly revenue is volatile.** Even the best method misses a typical month by about 17 %. Large one-off orders, such as the ₹1.19 crore order in March 2026, move single months sharply.
- **The longer-memory methods under-forecast by 12–15 % in 2026** because growth accelerated to 38.7 % year on year (see [Revenue growth bridge](../../01_customer_and_revenue/03_revenue_growth_bridge/)). A method based on the past assumes the past growth rate.
- **"Last month" gets the nine-month total right but individual months badly wrong** (MAPE 25.8 %, one month off by 71.6 %). It is useless for monthly planning.
- **The biggest miss was March 2026.** Actual revenue was ₹5.42 crore against a blend forecast of ₹3.65 crore (−32.5 %), driven by the financial year-end push.

**Q4 2026 forecast (blend):**

| Month | Blend forecast | Range (± 17.5 %) | Bias-adjusted |
|---|---:|---:|---:|
| October 2026 | ₹3.71 crore | ₹3.06 – ₹4.36 crore | ₹4.30 crore |
| November 2026 | ₹3.22 crore | ₹2.65 – ₹3.78 crore | ₹3.73 crore |
| December 2026 | ₹4.17 crore | ₹3.44 – ₹4.90 crore | ₹4.84 crore |
| **Q4 total** | **₹11.10 crore** | **₹9.15 – ₹13.04 crore** | **₹12.87 crore** |

Q4 2025 actual revenue was ₹9.13 crore, so the blend implies 21.5 % growth and the bias-adjusted forecast 41 %. December is forecast highest, consistent with the year-end peak found in [Dispatch workload planning](../../03_operations_and_supply_chain/04_dispatch_workload_planning/).

## 9. Business implications and recommendations

1. **Plan Q4 on ₹11.1 crore as the base case and ₹12.9 crore as the upside.** The blend is the most accurate method, but it under-forecast every quarter of 2026. The bias-adjusted figure reflects the current growth rate.
2. **Plan stock and cash for the range, not the point.** Monthly error of about 17 % means purchasing and working capital need headroom. Use the low end for committed spend and the high end for stock availability on A-class products (see [ABC-XYZ classification](../01_abc_xyz_product_classification/)).
3. **Stop using "last month plus a bit" for monthly planning.** Its typical monthly error is 26 %, and one month in the backtest was off by 72 %.
4. **Add known large orders on top of the baseline.** A statistical baseline cannot see one-off project orders. Sales should list confirmed large orders separately, and finance should add them explicitly.
5. **Re-run the backtest each month** as a new actual arrives, and switch methods if another one becomes consistently more accurate.

## 10. Assumptions and limitations

- **Short history.** Only 33 months of data, with 24 needed before the seasonal method can start, leaves a 9-month backtest. Accuracy figures will become more reliable as history grows.
- **Simple methods by design.** More advanced models (for example exponential smoothing or ARIMA) may be more accurate. The aim here is a transparent baseline that can be re-run in SQL and explained to non-specialists.
- **Order intake basis.** The forecast is for orders booked, not delivered or invoiced revenue.
- **Bias adjustment.** The adjustment assumes 2026's under-forecast continues. If growth slows, the bias-adjusted figure will overstate Q4.
- **No external drivers.** Price changes, large contracts and economic conditions are not modelled.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Monthly revenue, forecast table and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
