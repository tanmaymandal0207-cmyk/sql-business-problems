# Case Study · KPI Change-Point Detection: Which Monthly Moves Are Real?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Ten monthly KPIs over 33 months (January 2024 – September 2026), each fitted with four models (no change, linear trend, one shift, two shifts) by exhaustive search, compared by BIC, tested against 500 random reorderings, and checked against the two January price increases that are known to have happened.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-29 |

---

## 1. Business problem

Every month the management pack shows ten KPIs with red and green arrows, and every month someone is asked to explain a move: why late deliveries jumped, why cancellations fell, why order value dropped. The CEO suspects most of these explanations describe noise. She wants to know which KPIs have actually changed level in the last 33 months, when and by how much, which are growing steadily, and which have never changed at all.

## 2. Business questions

1. Does a change-point method find the two January price increases, which are known to have happened?
2. Which other KPIs shifted, which grew gradually, and which never changed?
3. Are the monthly swings in the rate KPIs larger than chance?
4. What should the monthly pack report instead of arrows?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Month, status, customer, promise date |
| `sales_order_items` | One row per product per order | Revenue, discount, invoice price |
| `products` | One row per product | Today's list price (price factor) |
| `shipments` | One row per shipment | Dispatch and delivery dates |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| KPIs | Price factor (invoice ÷ today's list), orders, active customers, net revenue, average order value, discount rate, cancellation rate, return rate, late delivery rate, dispatch lag. Revenue-based KPIs use orders not Cancelled or Returned. |
| Scale | Orders, customers, revenue and order value are analysed as natural logs (shifts and trends in percent); the others as they are |
| **Models** | **M0** one constant level; **T** linear trend; **M1** one shift (best break month); **M2** two shifts (best pair of break months). Every level lasts at least 3 months. |
| Exhaustive search | Every possible break month (and pair) is tried; segment sums of squares come from prefix sums |
| **BIC** | n ln(SSE ÷ n) + p ln(n), with p = 1, 2, 3, 5. Lower is better; a margin of 2–6 is positive evidence, 6–10 strong, over 10 very strong. |
| **Permutation test** | The share of 500 random reorderings of the months whose best single shift explains as much variance (R²) as the real order. It tests "any change in level over time", shift or trend. |
| **Dispersion test** (rates) | Chi-square of monthly counts against one constant rate, against the 95 % critical value for 32 degrees of freedom (46.2). A ratio near 1 means binomial noise only. |

## 5. Analytical approach

1. **Series** (`sahyadri_b2b.chp_series`): 33 months × 10 KPIs, with event counts for the rates.
2. **Prefix sums and segments** (`sahyadri_b2b.chp_prefix`, `sahyadri_b2b.chp_segments`): the mean and sum of squares of every run of 3+ months.
3. **Models** (`sahyadri_b2b.chp_models`): the four fits, their break months and BIC.
4. **Levels and trends** of the fitted models.
5. **Permutation test** (`sahyadri_b2b.chp_permutation_stats`) and the binomial dispersion test.

## 6. SQL techniques used

- Exhaustive one- and two-break search by joining a segment table to itself, with sums of squares from cumulative `SUM() OVER` prefix sums
- Least-squares trend fitted with plain aggregates, and model choice by BIC
- A permutation test in SQL: 500 deterministic shuffles from an integer hash (`MOD` arithmetic) ordered with `ROW_NUMBER()`
- A chi-square dispersion test with a Wilson–Hilferty critical value, so no statistical library is needed
- Validation by brute force: segment SSEs recomputed row by row, the best break re-searched without prefix sums, and a known-truth series

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | 33 consecutive months for each of the 10 KPIs |
| 02 | Orders, cancellations and returns = source recount |
| 03 | Net revenue and price factor = source recount |
| 04 | **Every segment mean and SSE = a direct row-by-row recount** |
| 05 | No-change and trend SSE = a recount from `VAR_POP` and `CORR` |
| 06 | **One-shift model = a brute-force search without prefix sums** |
| 07 | SSE falls as models add levels; every level lasts 3+ months |
| 08 | BIC recomputed; exactly one chosen model per KPI |
| 09 | 500 permutations per KPI, R² between 0 and 1 |
| 10 | **Known truth: the price factor shifts in January 2025 and January 2026 only** |

## 8. Findings

**The method finds the two price increases to the month.**

| | Jan 2024 – Dec 2024 | Jan 2025 – Dec 2025 | Jan 2026 – Sep 2026 |
|---|---:|---:|---:|
| Price factor (invoice ÷ today's list) | 0.9006 | 0.9493 (**+5.4 %**) | 1.0004 (**+5.4 %**) |

The two-shift model beats the next best (a trend) by 143 BIC points, and no random reordering comes close (p = 0.002, the smallest possible with 500 permutations). This matches the [price increase study](../../02_sales_and_profitability/12_price_increase_and_price_discipline/).

**Of the other nine KPIs, two grow steadily, two are undecided and five have never changed.**

| KPI | Chosen model | BIC margin over the next model | Permutation p-value | What the data says |
|---|---|---:|---:|---|
| Orders | Trend | 3.7 | 0.002 | **Steady growth of 17.1 % a year**, no step |
| Active customers | Trend | 3.8 | 0.002 | **Steady growth of 13.8 % a year**, no step |
| Net revenue | One shift (Dec 2025) | 1.8 | 0.004 | Growing; a step from Dec 2025 (₹2.39 → ₹3.42 crore a month) and a 19.5 % trend fit almost equally well |
| Average order value | Two shifts (Apr 2025, Jan 2026) | 1.5 | 0.070 | **No reliable change** (₹96.8k → ₹85.6k → ₹104.4k is within noise) |
| Discount rate | No change | 2.9 | 0.64 | Stable at 8.7 % |
| Cancellation rate | No change | 3.1 | 0.93 | Stable at 5.3 % |
| Return rate | No change | 3.0 | 0.86 | Stable at 0.75 % |
| Late delivery rate | No change | 3.5 | 0.73 | Stable at 18.3 % |
| Dispatch lag | No change | 3.5 | 0.95 | Stable at 4.0 days |

- **Orders and customers grow gradually.** A trend beats a one-time step by 5.1 (orders) and 6.5 (customers) BIC points; there was no single month when the business moved to a new level.
- **Revenue cannot yet be called a step or a trend.** The 2026 price increase and the richer product mix (see the [revenue driver tree](../../01_customer_and_revenue/15_revenue_driver_tree/)) may have added a step, but 10 months after the break are too few to separate it from growth.

**The monthly swings in the rate KPIs are chance.**

| Rate KPI | Overall rate | Largest month-on-month move | Chi-square (32 df) | 95 % critical value | Dispersion ratio |
|---|---:|---:|---:|---:|---:|
| Cancellation rate | 5.34 % | 4.0 points | 21.9 | 46.2 | 0.69 |
| Return rate | 0.75 % | 2.0 points | 41.6 | 46.2 | 1.30 |
| Late delivery rate | 18.32 % | **8.7 points** | 41.8 | 46.2 | 1.31 |

- With 185–438 measured deliveries a month (277 on average), a constant 18 % late rate moves by several points from month to month on its own. **An 8.7-point swing in late deliveries needed no explanation**: the 33 months together are no more variable than coin flips at a fixed rate.

**BIC alone would raise false alarms; the permutation test stops them.** On the 500 shuffled versions of each series, which have no real change by construction, BIC preferred a one-shift model over no change 8–12 % of the time. A shift should be reported only when both the BIC margin and the permutation test agree.

## 9. Business implications and recommendations

1. **Stop asking for explanations of moves in the five stable KPIs.** Discount, cancellation, return and late rates and dispatch lag have not changed in 33 months. Show them against control limits (see [statistical process control](../../03_operations_and_supply_chain/09_statistical_process_control/)) and investigate only a point outside the limits.
2. **Report orders, customers and revenue as year-on-year growth**, not month-on-month arrows. Their underlying growth is steady (14–20 % a year), and month-to-month changes include the March and December peaks.
3. **Re-run the change-point scan each quarter.** Call a shift only when the BIC margin is at least 6 and the permutation p-value is below 0.05; the price factor passes both by a wide margin, nothing else does.
4. **Do not plan on a fall or rise in order value.** Its apparent dips and recoveries are within noise; plan with its 33-month average and the mix scenarios in the driver tree.
5. **Use the price factor as the test series** whenever the scan is changed: it should always find January 2025 and January 2026.

## 10. Assumptions and limitations

- **Seasonality is not modelled.** March and December peaks add noise to orders and revenue and can pull a break towards a peak month; the revenue break falls in December 2025.
- **Mean-shift and linear-trend models only.** A trend with a step (for example growth plus a price increase) is not fitted; revenue would be the candidate.
- **33 months.** A shift in August or September 2026 cannot be detected yet (each level needs 3 months), and the permutation test treats months as exchangeable, which a growing series is not; for orders, customers and revenue a small p-value confirms change over time, not specifically a shift.
- **BIC thresholds** (2, 6, 10) are conventions, not exact error rates.
- **Rates are tested as binomial.** Orders from the same customer in a month are not independent, which would make the test slightly too willing to find extra variation; it still found none.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Series, prefix, segment, model and permutation tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
