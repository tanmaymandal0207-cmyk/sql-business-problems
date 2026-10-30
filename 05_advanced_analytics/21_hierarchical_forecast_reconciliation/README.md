# Case Study · Hierarchical Forecasting: Forecast the Total, the Categories, or Both?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Monthly revenue for 10 product categories and the company total (January 2024 – September 2026), forecast one month ahead for 21 months by bottom-up, top-down, combined and naive methods, with exponential smoothing written in SQL and every forecast adding up across the hierarchy.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-30 |

---

## 1. Business problem

From next year each category manager will own a monthly revenue forecast for their category, and finance wants the ten category forecasts to add up to the company forecast. Two approaches are on the table: each manager forecasts their category and finance adds them up (bottom-up), or finance forecasts the total and splits it by recent category shares (top-down). The planning lead wants to know which approach is more accurate at each level, how much less accurate a category forecast is than the total, and whether any category needs its own model.

## 2. Business questions

1. Which approach forecasts the company total better?
2. Which forecasts the categories better?
3. How much less accurate is a category forecast than the total?
4. Does any category deserve a model of its own?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order month, status |
| `sales_order_items` | One row per product per order | Net revenue |
| `products`, `product_categories` | One row per product / category | Category |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Series | Monthly net revenue of valid orders (not Cancelled or Returned) for each of 10 categories and the total |
| **Exponential smoothing** | F(t) = α × y(t−1) + (1 − α) × F(t−1), starting F(2) = y(1); in SQL as a weighted sum of earlier months, α(1 − α)^(t−1−u) for month u |
| Alpha choice | For each series, the α from 0.1 to 0.9 with the lowest mean absolute error on February–December 2024, then fixed |
| **Bottom-up** | Each category's own forecast; total = sum of the categories |
| **Top-down** | The total's own forecast; each category = total × its share of the previous 12 months |
| **Combined** | Average of bottom-up and top-down (still adds up) |
| Naive | Last month's actual |
| Evaluation | One-month-ahead forecasts for January 2025 – September 2026 (21 months), never using the target month |
| MAPE / WAPE | Mean of \|error\| ÷ actual (total) / Σ \|error\| ÷ Σ actual (categories) |

## 5. Analytical approach

1. **Series** (`sahyadri_b2b.hf_series`): 11 monthly series.
2. **Smoothing** (`sahyadri_b2b.hf_ses`) for every series and α, and the **chosen α** (`sahyadri_b2b.hf_alpha`).
3. **Forecasts** (`sahyadri_b2b.hf_forecasts`): bottom-up, top-down, combined and naive for every category and the total.
4. **Accuracy** at both levels, by category, month by month, and with the α chosen against the best α in hindsight.

## 6. SQL techniques used

- Exponential smoothing without recursion: a closed-form weighted sum over a self-join of each series with its earlier months
- Parameter choice by grid search with `ROW_NUMBER()` on a fitting year, kept separate from the evaluation period
- Top-down allocation with point-in-time shares from the previous 12 months
- Validation that the closed form equals the recursion and that every method's forecasts add up across the hierarchy

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | 11 series × 33 months; categories add up to the total every month |
| 02 | Total revenue = source recount |
| 03 | **Closed-form smoothing = the recursion** |
| 04 | The chosen α has the lowest 2024 error for its series |
| 05 | Category shares use the previous 12 months only and add up to 1 |
| 06 | **Coherence: category forecasts add up to the total for every method** |
| 07 | Top-down total = the total's own forecast; combined = the average |
| 08 | Bottom-up category forecast = own smoothing at the chosen α |
| 09 | Naive forecast = the previous month's actual |
| 10 | 21 evaluation months × 11 series, none in the fitting year |

## 8. Findings

**At the total, the approaches are equally good.**

| Level | Bottom-up | Top-down | Combined | Naive |
|---|---:|---:|---:|---:|
| Total (MAPE) | 18.3 % | 18.7 % | **18.0 %** | 25.3 % |
| Categories (WAPE) | 27.6 % | **25.5 %** | 26.1 % | 35.6 % |

- **Category errors are about half as large again as the total's** (26–28 % against 18 %); errors in different categories partly cancel when they are added up. All three methods beat last month's actual by 7–10 points.

**Top-down's category advantage comes from one category.**

| Category | Share of revenue | Monthly CV | Chosen α | Bottom-up | Top-down | Better |
|---|---:|---:|---:|---:|---:|---|
| Industrial Safety Equipment | 11.1 % | 0.27 | 0.2 | **17.6 %** | 18.4 % | Bottom-up |
| Valves & Fittings | 11.5 % | 0.27 | 0.2 | **18.0 %** | 19.1 % | Bottom-up |
| Hydraulic Components | 6.4 % | 0.33 | 0.1 | 22.1 % | 21.9 % | Top-down |
| Bearings | 5.6 % | 0.35 | 0.2 | 22.7 % | **20.3 %** | Top-down |
| Electric Motors & Drives | 19.7 % | 0.31 | 0.1 | 28.9 % | 29.0 % | Bottom-up |
| Power Transmission | 2.9 % | 0.37 | 0.1 | 29.6 % | 29.9 % | Bottom-up |
| **Pumps** | **25.6 %** | **0.49** | **0.6** | **39.3 %** | **31.4 %** | **Top-down** |

- In nine categories the two approaches are within 2.5 points, and top-down is closer in only 47.6 % of category-months.
- **Pumps is the exception.** It is the largest and most volatile category (monthly CV 0.49), and its 2024 data chose a fast-reacting α of 0.6 that chased large one-off orders. At α 0.1, like most categories, its own forecast scores 31.6 %, the same as top-down.

**Tuning on one year over-fits lumpy categories.**

| Series | Chosen α | Error at chosen α | Best α in hindsight | Error at best |
|---|---:|---:|---:|---:|
| Pumps | 0.6 | 39.3 % | 0.1 | 31.6 % |
| Power Transmission | 0.1 | 29.6 % | 0.3 | 26.9 % |
| Bearings | 0.2 | 22.7 % | 0.1 | 20.7 % |
| Total | 0.1 | 21.0 % (WAPE) | 0.2 | 20.4 % |

## 9. Business implications and recommendations

1. **Use the combined forecast.** It is the most accurate at the total (18.0 %), close to the best at category level, never the worst, and still adds up.
2. **Plan with ±25 % on a category month and ±18 % on the total.** Category managers should not be judged against a tighter band than the data allows; review categories quarterly, where errors partly cancel.
3. **Keep category models heavily smoothed.** A low α (about 0.1–0.2) for every series is safer than tuning each one on a single year; Pumps shows the cost of tuning.
4. **Forecast Pumps' large orders separately.** Pumps carries a quarter of revenue and the largest swings; forecast its large orders from the sales pipeline (see [revenue volatility](../../02_sales_and_profitability/15_revenue_volatility_drivers/)) and smooth the rest.
5. **Add March and December effects next.** Smoothing ignores the year-end peaks that drive the biggest misses (see the [revenue forecast baseline](../04_revenue_forecast_baseline/)); add them to the total before splitting it.

## 10. Assumptions and limitations

- **One base model.** Exponential smoothing without trend or season; a richer model could change the ranking, but not the coherence logic.
- **Short fitting year.** α is chosen on 11 months of 2024; a rolling re-fit would adapt but also over-fit more often.
- **Shares from 12 months.** Top-down assumes next month's mix equals the last year's; a sudden mix change (as in 2025–2026, see the [revenue driver tree](../../01_customer_and_revenue/15_revenue_driver_tree/)) would hurt it.
- **Two levels only.** Products within categories, and segments, would add further levels.
- **Order-date revenue.** Revenue is dated by order date, not delivery.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Series, smoothing, alpha and forecast tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
