# Case Study · Customer Momentum

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. A revenue trend fitted for 367 customers (current 12 months) and 340 customers (back-test year), with the back-test judged on the following 12 months.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-25 |

---

## 1. Business problem

Every quarter, account managers are asked which of their customers are "growing" and which are "declining", and they answer from memory. The sales head wants a statistical answer for every customer, fitted the same way for all, and wants to know **whether it can be trusted** before using it to direct sales effort. The test of trust is simple: did customers flagged a year ago actually go on growing or declining?

## 2. Business questions

1. For each customer, is monthly revenue trending up or down over the last 12 months, and is the trend distinguishable from noise?
2. Which customers are growing or declining significantly now?
3. Back-test: did last year's growing and declining customers continue in the following 12 months?
4. Which signal predicts next year best: the trend, its significance, or recent revenue level?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Revenue |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Revenue | Quantity × unit price × (1 − discount %), orders not Cancelled or Returned; NULL discount = 0 % |
| Monthly series | Revenue per customer per month, **zero-filled**, x = month 1 to 12 of the window |
| **Slope** | Least-squares slope b = `COVAR_POP(x, y) / VAR_POP(x)`, in ₹ per month |
| **Trend %** | b × 12 ÷ mean monthly revenue: the change in monthly revenue over a year, as a share of the customer's average month |
| **t-statistic** | r × √(n − 2) ÷ √(1 − r²), with r = `CORR(x, y)` and n = 12. \|t\| ≥ 2 is treated as significant. |
| Momentum class | Too few active months (fewer than 3 months with revenue) · Growing (t ≥ 2) · Declining (t ≤ −2) · No significant trend |
| Trend quartile | Customers with 3+ active months ranked by trend % into four equal groups |
| Windows | **Current** Oct 2025 – Sep 2026 · **Back-test** Oct 2024 – Sep 2025, judged on revenue in the current window |
| Spearman ρ | Correlation of ranks, computed as `CORR` of `RANK()` values |

## 5. Analytical approach

1. **Monthly table** (`sahyadri_b2b.customer_monthly_revenue`). Every customer × every month from January 2024, zero-filled.
2. **Momentum table** (`sahyadri_b2b.customer_momentum`). For both windows: slope, trend %, correlation, t-statistic, halves, class and quartile.
3. **Current classes** and the distribution of t-statistics.
4. **Current lists** of significant growers and decliners.
5. **Back-test** by class and by trend quartile: revenue change, share of customers down, share lost.
6. **Signal comparison** with Spearman correlations against next-year outcomes.

## 6. SQL techniques used

- Per-customer linear regression with aggregate functions: `COVAR_POP`, `VAR_POP` and `CORR` in one `GROUP BY`
- Slope significance from the correlation coefficient, with `SAFE_DIVIDE` for perfect fits
- Zero-filled time series with `GENERATE_DATE_ARRAY` and `CROSS JOIN`, so silent months count
- Out-of-sample back-test: a classification fitted on one year, judged on the next
- Validation that recomputes the slope from sums of squares and the t-statistic from **residuals**, a different route from `CORR`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Monthly grid has one row per customer and month, 33 months each |
| 02 | Grid revenue = source revenue |
| 03 | One momentum row per customer with revenue in each window |
| 04 | Window revenue = source revenue for each window |
| 05 | **Slope = Σ(x − x̄)(y − ȳ) ÷ Σ(x − x̄)²** recomputed from the grid |
| 06 | **t-statistic = slope ÷ standard error from residuals** |
| 07 | Every window has 12 months, and the two halves add up to the window |
| 08 | Classes agree with the thresholds |
| 09 | Trend quartiles are balanced and do not overlap |
| 10 | Active months = recount of months with revenue |

## 8. Findings

**For almost every customer, monthly revenue is too lumpy to show a significant trend.**

| Current class (Oct 2025 – Sep 2026) | Customers | Revenue | Share of revenue | Median trend |
|---|---:|---:|---:|---:|
| Too few active months | 116 | ₹1.07 crore | 2.6 % | |
| Growing | 8 | ₹82.2 lakh | 2.0 % | +361 % |
| No significant trend | 238 | ₹37.58 crore | **93.1 %** | +0 % |
| Declining | 5 | ₹89.1 lakh | 2.2 % | −220 % |

| t-statistic (251 customers with 3+ active months) | Customers | Share |
|---|---:|---:|
| t ≤ −2 | 5 | 2.0 % |
| −2 < t < −1 | 32 | 12.7 % |
| −1 ≤ t ≤ 1 | 172 | 68.5 % |
| 1 < t < 2 | 34 | 13.5 % |
| t ≥ 2 | 8 | 3.2 % |

- **13 significant trends among 251 customers is no more than chance would produce.** With 10 degrees of freedom, |t| ≥ 2 occurs about 7.3 % of the time without any real trend, about 18 customers. A list of "trending" customers from 12 monthly points is mostly noise.
- Revenue from customers with a significant trend is 4.2 % of the total. Momentum is not where the money is.

**Current lists.** Growing: Rajdhani Switchgear (₹22.9 lakh, all in Apr–Sep 2026, t = 4.47), Sunrise Steel (₹21.7 lakh, t = 2.40), Garg Autoparts, Apex Foods & Beverages, Bharat Autoparts, Jai Motor Parts, Mishra Agro Processors and Balaji Fabrics. Declining: Saraswati Mehta Flexipack (₹47.8 lakh in Oct–Mar, ₹7.4 lakh in Apr–Sep, t = −2.17), Universal Alloys, Kaveri Polymers, Saraswati Parikh Engineering Works and Trimurti Pillai Industries.

- **Five of the eight growers had little or no revenue in the first half.** They are new or returning customers ramping up, not established accounts accelerating.

**Back-test: upward momentum persisted, downward momentum reversed.**

| Back-test class (Oct 2024 – Sep 2025) | Customers | Revenue that year | Revenue next 12 months | Change | Customers down | Customers lost |
|---|---:|---:|---:|---:|---:|---:|
| Too few active months | 109 | ₹92.9 lakh | ₹1.29 crore | +39.0 % | 61.5 % | 37.6 % |
| **Growing** | 13 | ₹97.4 lakh | ₹3.77 crore | **+286.7 %** | **0.0 %** | 0.0 % |
| No significant trend | 207 | ₹27.65 crore | ₹32.16 crore | +16.3 % | 49.3 % | 1.0 % |
| **Declining** | 11 | ₹90.3 lakh | ₹1.35 crore | **+49.5 %** | **36.4 %** | 0.0 % |

| Back-test trend quartile | Customers | Change next 12 months | Customers down |
|---|---:|---:|---:|
| Q1 (steepest decline) | 58 | +25.7 % | 53.4 % |
| Q2 | 58 | +17.8 % | 46.6 % |
| Q3 | 58 | +11.3 % | 51.7 % |
| Q4 (steepest growth) | 57 | **+85.6 %** | **31.6 %** |

- **All 13 growing customers grew again**, almost quadrupling their revenue. A significant upward trend usually means a customer still ramping up, and ramp-ups continue.
- **Declining customers recovered.** Only 4 of 11 bought less the next year, and as a group they bought 49.5 % more. A falling trend in B2B usually reflects a large order early in the window, not a customer leaving.
- The weakest predictor of trouble is the trend; the strongest predictor of loss is **activity**: 37.6 % of customers with fewer than 3 active months bought nothing the next year.

**Recent revenue level predicts next year far better than any trend.**

| Signal → target (231 customers, back-test) | Spearman ρ |
|---|---:|
| Second-half revenue → next-year revenue | **0.767** |
| Trend % → next-year growth | 0.124 |
| Trend t-statistic → next-year growth | 0.119 |
| Second-half share → next-year growth | 0.055 |

## 9. Business implications and recommendations

1. **Use the growing list for account expansion, not the declining list for churn.** Significant upward trends persisted in every back-tested case; give those customers credit-limit reviews, stock planning and a key-account contact early.
2. **Do not run "declining customer" campaigns on trend alone.** Decliners usually recovered. Use recency and order-cycle rules from the [churn early warning](../../01_customer_and_revenue/02_customer_churn_early_warning/) and [time-to-reorder](../07_time_to_reorder_survival/) studies to find customers who are actually leaving.
3. **Forecast customers from recent level, not trend.** Second-half revenue explains next year's ranking far better (ρ = 0.77) than trend (ρ = 0.12). This supports the run-rate approach in the [revenue forecast baseline](../04_revenue_forecast_baseline/).
4. **Report momentum with its significance.** Showing trend % without the t-statistic would flag dozens of customers whose movement is noise. Keep |t| ≥ 2 as the minimum, and expect about 7 % of customers to cross it by chance.
5. **Re-run quarterly and re-check the back-test.** One back-test year is limited evidence. If decliners stop recovering in future back-tests, the declining list becomes useful.

## 10. Assumptions and limitations

- **Linear trend on lumpy data.** Monthly B2B revenue is dominated by a few large orders, and zero months are common. The t-test assumes roughly normal, independent residuals, which these series do not fully have. Treat t as a screening score.
- **Twelve points.** A longer window would give more power, but the data starts in January 2024, so two non-overlapping 12-month windows are the most a back-test allows.
- **One back-test year.** Results for the small classes (13 growing, 11 declining) rest on few customers.
- **Rank correlation with ties.** `RANK()` gives tied values the same rank, a close approximation to Spearman's average-rank method.
- New customers in the window have zero months before their first order, which makes their trend look strongly positive. They are kept, because "ramping up" is the useful signal, but they are named in the findings.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Monthly and momentum tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
