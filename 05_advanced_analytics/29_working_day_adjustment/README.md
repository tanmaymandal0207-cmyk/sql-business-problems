# Case Study · Working-Day Adjustment: How Much of Each Month's Change Is Just the Calendar?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study covers 33 months of daily revenue (January 2024 – September 2026). Weekday weights are estimated on 2024 and tested on 2025–2026. It builds a trading-day index for every month and measures how much of the month-on-month change it explains, and in which months adjusting for it changes the story.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-05 |

---

## 1. Business problem

Every month the management pack reports revenue growth against the previous month and the same month last year. Every month, someone explains a dip with "there were more Sundays this month". Nobody knows how large the calendar effect really is, or whether the pack should report working-day-adjusted figures. The financial controller wants that settled.

## 2. Business questions

1. How much revenue does each weekday bring, and how much do months differ in trading days?
2. How much of the month-on-month change in revenue is the calendar?
3. Does adjusting for the calendar change the story in particular months?
4. Does an adjustment estimated on one year work on the next?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, status |
| `sales_order_items` | One row per product per order | Revenue |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Daily revenue | Booked revenue of valid orders (not Cancelled or Returned) by order date, every calendar day, January 2024 – September 2026 |
| **Weekday weight** | Average revenue on that weekday ÷ average daily revenue, **estimated on 2024 only** |
| **Trading-day index (TDI)** | Sum of the weights of a month's days ÷ the average of that sum over the 33 months (1 = a typical month) |
| Adjusted revenue | Revenue ÷ TDI |
| Calendar effect | ln change in TDI from one month to the next; ln change in revenue = calendar effect + ln change in adjusted revenue |
| Calendar fit | Slope (expected about 1) and R² of the revenue change on the calendar change; 2024 in sample, 2025–2026 out of sample, also without the March and April changes, which the year-end peak dominates |

## 5. Analytical approach

1. **Days** (`sahyadri_b2b.wd_days`) and **weekday weights** (`sahyadri_b2b.wd_weights`), with the same weights measured on 2025–2026 for comparison.
2. **Months** (`sahyadri_b2b.wd_months`): TDI, adjusted revenue and log changes.
3. **How much the calendar explains**, in and out of sample.
4. **Months where adjustment changes the story**, month on month and year on year.

## 6. SQL techniques used

- A full calendar spine with weekday names, so days without orders count as zero
- Weights trained on one period and applied to another (a simple out-of-sample test in SQL)
- An exact log decomposition of growth into calendar and underlying parts
- Sign-flip counts (`SIGN(raw) != SIGN(adjusted)`) to find months where the headline changes

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per calendar day; revenue = source |
| 02 | Weekday weights average 1 over the 2024 days |
| 03 | Seven weekdays, trained on the 366 days of 2024 only |
| 04 | Trading-day index averages 1 across the 33 months |
| 05 | Adjusted revenue × TDI = revenue |
| 06 | **Revenue change = calendar change + adjusted change (logs)** |
| 07 | Days, Sundays and Saturdays per month = calendar recount |
| 08 | Weighted days = the sum of the weights of the month's days |
| 09 | Weights = average weekday revenue ÷ average daily revenue in 2024 (recount) |
| 10 | 32 month-on-month changes |

## 8. Findings

**The weekday pattern is strong and stable.**

| Weekday | Weight (2024) | Weight (2025–2026) |
|---|---:|---:|
| Tue | 1.46 | 1.39 |
| Thu | 1.33 | 1.16 |
| Wed | 1.26 | 1.17 |
| Fri | 1.19 | 1.27 |
| Mon | 1.14 | 1.29 |
| Sat | 0.53 | 0.63 |
| **Sun** | **0.09** | **0.08** |

A Sunday brings less than a tenth of an average day's orders, and a Saturday about half. The ranking of weekdays shifts a little between years, but Saturday and Sunday are firmly low.

**Months differ by up to 14.5 % in trading days, but revenue swings far more.**

| | Value |
|---|---:|
| Lowest TDI | 0.920 (February 2025 and 2026) |
| Highest TDI | 1.052 (October 2024, July 2025) |
| Typical month-on-month change from the calendar (SD) | **6.7 %** |
| Typical month-on-month change in revenue (SD) | **30.8 %** |

**The calendar explains little of the month-to-month movement.**

| Month-on-month changes | Changes | Slope on calendar | R² | Slope without March / April | R² without March / April |
|---|---:|---:|---:|---:|---:|
| 2024 (weights fitted here) | 11 | 0.41 | 0.010 | 0.80 | 0.109 |
| 2025–2026 (out of sample) | 21 | 1.40 | 0.082 | **0.94** | 0.081 |

- Out of sample, outside the year-end months, a 1 % calendar change moves revenue by about 0.94 %, close to the expected 1. The calendar effect is real.
- But it explains only about **8–11 % of the variation** in month-on-month revenue. Large orders and the March peak drive the rest (see [revenue volatility](../../02_sales_and_profitability/15_revenue_volatility_drivers/)).

**Adjustment rarely changes the headline.**

| Test | Result |
|---|---|
| Month-on-month changes where adjusted growth has the opposite sign | **1 of 32** (July 2024: +2.3 % raw, −8.1 % adjusted) |
| Month-on-month changes moved by 5 points or more | 17 of 32 |
| Year-on-year comparisons with the opposite sign | **0 of 21** |
| Largest year-on-year difference | 7.3 points |

| Month | TDI | Raw month-on-month | Adjusted | Raw year-on-year | Adjusted |
|---|---:|---:|---:|---:|---:|
| Nov 2025 | 0.940 | −24.3 % | −15.9 % | +7.7 % | +11.9 % |
| Feb 2026 | 0.920 | −12.0 % | **−2.4 %** | +5.5 % | +5.5 % |
| Mar 2026 | 1.008 | +85.4 % | +69.2 % | +30.7 % | +26.8 % |
| Aug 2026 | 0.977 | +62.8 % | +73.9 % | +71.4 % | +71.7 % |
| Sep 2026 | 1.009 | −6.0 % | −8.9 % | +71.1 % | +70.4 % |

- **February is the one month where the calendar is the story.** February 2026's 12 % fall from January is almost entirely the short month (−2.4 % adjusted).
- Year-on-year comparisons are almost unaffected, because the same month in consecutive years has nearly the same calendar.

## 9. Business implications and recommendations

1. **Add a working-day-adjusted month-on-month line to the pack,** next to the raw figure. It moves the number by 5 points or more in about half the months, and it removes the February dip.
2. **Keep year-on-year growth unadjusted.** The adjustment changes it by at most 7 points and never changes its sign.
3. **Stop explaining large swings with "more Sundays".** The calendar typically moves a month by about 7 %. Swings of 20–60 % come from large orders and the year-end peak.
4. **Use the weekday weights in daily targets and nowcasts.** The [month-end nowcast](../25_month_end_revenue_nowcast/) already uses them; daily sales targets should too (a Tuesday is worth about 17 Sundays).
5. **Refresh the weights each year.** They are stable for weekends but drift a little between weekdays.

## 10. Assumptions and limitations

- **Public holidays are not modelled.** Diwali, Holi and other holidays move between months and add calendar effects of their own.
- **Booked revenue by order date.** Dispatch or invoicing calendars would give different weights.
- **Weights from one year (2024).** 52–53 days per weekday; the 2025–2026 weights show the size of the estimation noise.
- **Thirty-two monthly changes.** The calendar fit (slope and R²) is estimated on few points, and March–April dominate whenever they are included.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Day, weight and month tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
