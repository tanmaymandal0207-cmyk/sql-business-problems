# Case Study · Intermittent Demand Forecasting (Croston and SBA)

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 186 products × 144 weeks; 16,554 back-test forecasts per method of 4-week lead-time demand.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

The [safety stock](../../03_operations_and_supply_chain/08_safety_stock_reorder_points/) study found that most products sell in irregular lumps: several weeks with nothing, then a large order. Moving averages and exponential smoothing handle that pattern badly. The supply chain team is considering a planning tool that uses methods designed for intermittent demand, **Croston's method** and its bias-corrected version, the **Syntetos–Boylan approximation (SBA)**. Before buying, they want evidence from their own data that these methods forecast lead-time demand better.

## 2. Business questions

1. How intermittent is weekly demand, product by product?
2. Which method forecasts 4-week lead-time demand best in a back-test?
3. Does the answer differ by demand pattern?
4. Which methods are biased?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Units |
| `sales_orders` | One row per order | Order date, status |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Weekly demand | Units per product per ISO week, zero-filled (orders not Cancelled or Returned) |
| **ADI** | Average demand interval: weeks ÷ weeks with demand |
| **CV²** | Squared coefficient of variation of non-zero weekly demand |
| Pattern | Smooth (ADI < 1.32, CV² < 0.49) · Erratic (ADI < 1.32) · Intermittent (CV² < 0.49) · Lumpy (both high) — the Syntetos–Boylan classification |
| Naive | Next week = last week |
| MA13 | Mean of the last 13 weeks |
| SES | Simple exponential smoothing on every week, α = 0.1 |
| **Croston** | Smooths the size of non-zero demands (z) and the interval between them (p) separately, updating only in weeks with demand; forecast per week = z ÷ p |
| **SBA** | (1 − α/2) × Croston, which corrects Croston's known upward bias |
| Lead-time demand | Units in the 4 weeks after the forecast origin; forecast = 4 × weekly forecast |
| Back-test | Every origin from week 52 to the last week with 4 weeks of actuals (89 origins × 186 products) |
| WAPE | Σ \|forecast − actual\| ÷ Σ actual |
| Bias | Σ (forecast − actual) ÷ Σ actual; negative = under-forecast |
| RMSE | Root mean squared error, in units |

Exponential smoothing is recursive, but SQL has no loop over rows. The script uses the closed form, for example sₜ = (1 − α)ᵗ⁻¹ y₁ + α Σ (1 − α)ᵗ⁻ⁱ yᵢ, computed with running window sums. Validation check 04 confirms it equals the recursion at every week.

## 5. Analytical approach

1. **Weekly grid** (`sahyadri_b2b.idf_weekly`) and **demand pattern** per product (`sahyadri_b2b.idf_pattern`).
2. **States table** (`sahyadri_b2b.idf_states`). The per-week forecast of every method at every week.
3. **Back-test table** (`sahyadri_b2b.idf_backtest`). Forecast and actual 4-week demand at every origin, for every method.
4. **Results** overall, by pattern, and the best method per product.

## 6. SQL techniques used

- Recursive smoothing written in closed form with `POW` and running `SUM() OVER` windows
- Croston's two-state update on demand occurrences only, carried forward with `LAST_VALUE(… IGNORE NULLS)`
- Look-ahead sums with `ROWS BETWEEN 1 FOLLOWING AND 4 FOLLOWING` for lead-time actuals
- Rolling-origin back-test of five methods in one long table
- Validation that checks the closed form against the recursion, and window results against self-join recounts

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Weekly grid = products × weeks, one row each |
| 02 | Weekly units = source units |
| 03 | Pattern agrees with ADI and CV² |
| 04 | **SES closed form = the recursion α·y + (1 − α)·previous at every week** |
| 05 | Croston forecast is unchanged in weeks without demand |
| 06 | Croston at the first demand = first size ÷ first interval |
| 07 | MA13 = a self-join recount |
| 08 | Lead-time demand = a self-join recount |
| 09 | Forecasts = 5 methods × origins × products |
| 10 | SBA = (1 − α/2) × Croston on every forecast |

## 8. Findings

**Weekly demand is mostly lumpy.**

| Pattern | Products | Average ADI | Average CV² | Share of units |
|---|---:|---:|---:|---:|
| Lumpy | 134 | 2.64 | 1.41 | 46.7 % |
| Erratic | 24 | 1.16 | 1.07 | 34.9 % |
| Intermittent | 24 | 3.52 | 0.38 | 1.3 % |
| Smooth | 4 | 1.00 | 0.30 | 17.1 % |

- 158 of 186 products (85 %) have demand in fewer than three weeks out of four (lumpy or intermittent). Only 4 products sell smoothly, but they carry 17.1 % of units.

**Croston and SBA forecast best overall.**

| Method | WAPE | Bias | RMSE (units) |
|---|---:|---:|---:|
| Naive | 95.2 % | −0.7 % | 208.5 |
| MA13 | 59.4 % | −0.9 % | 108.7 |
| SES | 56.9 % | −1.9 % | 104.8 |
| Croston | 54.6 % | −2.9 % | 101.7 |
| **SBA** | **53.7 %** | −7.8 % | **101.6** |

- Croston and SBA cut the 4-week error by about 5–6 points of WAPE against a 13-week moving average, and by 2–3 points against exponential smoothing.
- **Naive forecasting (next week like last week) is almost twice as bad** as any smoothing method.
- **Even the best method misses by about half of the actual demand.** Lumpy demand cannot be forecast precisely week by week; stock policy has to absorb the remaining uncertainty.

**By pattern, Croston-type methods win where demand is intermittent or lumpy; SES ties for smooth products.**

| Pattern | Best method | WAPE | Next best |
|---|---|---:|---|
| Lumpy (134) | SBA | 72.9 % | Croston 74.1 %, SES 78.4 % |
| Erratic (24) | SBA | 43.1 % | Croston 43.9 %, SES 44.2 % |
| Intermittent (24) | Croston and SBA (equal RMSE) | 75.6 % and 75.0 % | SES 81.3 % |
| Smooth (4) | SES | 21.1 % | Croston 21.1 %, MA13 22.0 % |

| Pattern | Best method by product (lowest RMSE) |
|---|---|
| Lumpy (134) | SBA 72, Croston 53, MA13 5, SES 4 |
| Erratic (24) | SBA 16, Croston 6, MA13 1, SES 1 |
| Intermittent (24) | Croston 14, SBA 9, SES 1 |
| Smooth (4) | SES 3, Croston 1 |

- **Croston or SBA is the best method for 171 of 186 products.**

**SBA under-forecasts by 7.8 %.** SBA is designed to remove Croston's upward bias, but demand grew during the period, so every smoothing method lags and is already slightly low. SBA's correction pushes it further down. Croston's bias (−2.9 %) is smaller.

## 9. Business implications and recommendations

1. **Use Croston-type forecasting for intermittent and lumpy products.** On this data it is the best method for 171 of 186 products. A planning tool offering Croston or SBA is justified on accuracy grounds.
2. **Prefer Croston to SBA while demand is growing**, or add a trend adjustment. SBA's lower error comes with a −7.8 % bias, which would mean systematic under-ordering.
3. **Keep SES for the 4 smooth products**; they carry 17 % of units and simple smoothing is as good as any method.
4. **Do not rely on the forecast alone.** With errors of about half the lead-time demand, [safety stock](../../03_operations_and_supply_chain/08_safety_stock_reorder_points/) sized from the forecast error, not from demand variance alone, is what protects service.
5. **Stop using the last period's sales as the forecast** wherever it is still used informally; it is about twice as wrong as any smoothing method.

## 10. Assumptions and limitations

- **α = 0.1 for all methods and products.** Optimising α per product would improve all smoothing methods somewhat; the ranking between methods is usually stable.
- **No trend or seasonality term.** Demand grew during the period; trend-adjusted methods (for example Holt or TSB) could reduce the negative bias.
- **Lead time of 4 weeks** for every product. Products with longer lead times would be evaluated on longer horizons.
- **Back-test from week 52.** Earlier weeks are used only to initialise the methods.
- **Weekly demand from order dates.** Cancelled and returned orders are excluded.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Weekly, pattern, states and back-test tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
