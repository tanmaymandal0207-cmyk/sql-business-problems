# Case Study · Will We Hit the Full-Year Target? A Monte Carlo of the Rest of the Financial Year

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. With April – September 2026 booked, the study simulates October 2026 – March 2027 order by order, 1,000 times. The result is the chance of reaching each candidate target for FY 2026-27. The same method is back-tested from the end of every month of FY 2025-26.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-06 |

---

## 1. Business problem

Half of FY 2026-27 is booked: ₹19.56 crore in April – September 2026, 51 % more than a year earlier. The board will set the year's revenue target at its next meeting. The CFO wants to tell it how likely each candidate target is, rather than give a single forecast. She also wants to know whether the method would have told the truth a year ago.

## 2. Business questions

1. What does the rest of the year (October 2026 – March 2027) look like as a range, given the first half?
2. How likely is each candidate target: ₹40, 45, 50 or 55 crore?
3. Would the same method have been right through FY 2025-26?
4. Should growth in order size be projected, or only growth in the number of orders?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, status |
| `sales_order_items` | One row per product per order | Order value |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| FY | April – March; revenue of valid orders (not Cancelled or Returned) by order date |
| Cut-off | The end of a month; everything up to it is known |
| **Count growth** | FY-to-date orders ÷ orders in the same months a year earlier |
| **Size growth** | FY-to-date average order value ÷ the same a year earlier |
| Simulated month | Orders N ~ Poisson(same month last year's orders × count growth), normal approximation. Each order is a random order from the same month last year. |
| **Rule A** | Count growth only: drawn orders keep last year's value |
| **Rule B** | Count and size growth: drawn orders are scaled by size growth |
| Pooled | Rules A and B combined with equal weight |
| FY total | FY-to-date actual + simulated rest of year; 1,000 simulations from an integer hash, so every run gives the same result |
| Back-test | Cut-offs at the end of April 2025 to February 2026, each predicting FY 2025-26; scored by where the actual falls in the simulated range |

## 5. Analytical approach

1. **Orders, draw pool and months** (`sahyadri_b2b.ft_orders`, `ft_pool`, `ft_months`); **cut-offs and growth** (`ft_cutoffs`, `ft_growth`); **remaining months** (`ft_plan`).
2. **Simulation**: monthly order counts (`ft_counts`), then every simulated order drawn from last year's same month (`ft_sims`).
3. **Back-test** (`ft_backtest`) for both rules, and a harder test on April – September 2026.
4. **FY 2026-27**: range and the chance of each target.

## 6. SQL techniques used

- A compound-Poisson simulation in SQL: a count per simulated month, then `CROSS JOIN UNNEST(GENERATE_ARRAY(1, n))` to create that many orders
- Normal draws by the Box–Muller transform on integer-hash uniforms (`MOD(x * x + 12345, 2147483647)`)
- Bootstrap draws by a hashed row number joined to a pool numbered with `ROW_NUMBER`
- Probability-integral-transform scoring (`COUNTIF(sim <= actual) / COUNT(*)`) for the back-test

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders and revenue = source |
| 02 | Draw pool numbered 1 to n within each month, n = the month's orders |
| 03 | Monthly orders and revenue = recount |
| 04 | Twelve cut-offs, FY from April; FY-to-date revenue = recount (September 2025 and September 2026) |
| 05 | **Count growth = recount** |
| 06 | Plan covers every remaining month; base = same month last year × count growth |
| 07 | 1,000 counts per plan month, never negative; normal draws with mean ≈ 0 and SD ≈ 1 |
| 08 | **Every simulated order was drawn**: orders per simulation = sum of its monthly counts |
| 09 | FY total = FY-to-date + rest (rule A), + rest × size growth (rule B) |
| 10 | Back-test actual = FY 2025-26 revenue (₹33.70 crore); percentiles = recount |

## 8. Findings

**In FY 2025-26, projecting order counts alone was accurate; projecting order size was not.**

| Data to the end of | Months simulated | Count growth | Size growth | Rule A median | Rule A 10–90 % | Rule B median | Actual |
|---|---:|---:|---:|---:|---|---:|---:|
| April 2025 | 11 | 1.261 | 0.913 | ₹37.57 crore | ₹35.92 – 39.33 crore | ₹34.47 crore | ₹33.70 crore |
| May 2025 | 10 | 1.207 | 0.942 | ₹35.86 crore | ₹34.37 – 37.65 crore | ₹34.03 crore | ₹33.70 crore |
| June 2025 | 9 | 1.159 | 0.928 | ₹34.14 crore | ₹32.68 – 35.82 crore | ₹32.14 crore | ₹33.70 crore |
| September 2025 | 6 | 1.171 | 0.888 | ₹33.45 crore | ₹32.22 – 34.82 crore | ₹31.14 crore | ₹33.70 crore |
| December 2025 | 3 | 1.185 | 0.914 | ₹33.41 crore | ₹32.53 – 34.42 crore | ₹32.42 crore | ₹33.70 crore |
| February 2026 | 1 | 1.172 | 0.934 | ₹33.07 crore | ₹32.42 – 33.91 crore | ₹32.76 crore | ₹33.70 crore |

| Rule | Cut-offs | Actual inside 10–90 % | Actual above 90 % | Actual below 10 % | Mean absolute error of the median | Mean error |
|---|---:|---:|---:|---:|---:|---:|
| **A. Count growth only** | 11 | **9** | 0 | 2 | **2.4 %** | +1.2 % |
| B. Count and size growth | 11 | 3 | 8 | 0 | 4.3 % | −3.7 % |

- Rule A missed only in April and May 2025, when one or two months of count growth (+21 to +26 %) overstated the year. From June on, its median was within 2 % of the actual.
- In FY 2025-26, average order size ran 6–11 % below the year before in the first half, then partly recovered. Projecting that fall made rule B too low at 8 of 11 cut-offs.

**But in April – September 2026, rule A would have missed badly.** From March 2026, using FY 2025-26 growth (count 1.167, size 0.963):

| | Value |
|---|---:|
| Rule A expected, April – September 2026 | ₹15.06 crore |
| Rule B expected | ₹14.51 crore |
| **Actual** | **₹19.56 crore** |
| Rule A error | **−23.0 %** |

Order counts grew a little faster than assumed (1.209 against 1.167), and order size jumped 25 %. Neither rule saw that coming.

**For FY 2026-27, the target the board can count on depends on whether bigger orders last.** First half: ₹19.56 crore; count growth 1.209; size growth 1.254.

| Scenario | P10 | Median | P90 | ₹40 crore | ₹45 crore | ₹50 crore | ₹55 crore |
|---|---:|---:|---:|---:|---:|---:|---:|
| A. Size growth fades (count growth only) | ₹42.73 crore | ₹44.45 crore | ₹46.83 crore | 100 % | 38.8 % | 0.1 % | 0 % |
| B. Size growth holds | ₹48.62 crore | ₹50.78 crore | ₹53.76 crore | 100 % | 100 % | 66.9 % | 3.9 % |
| **Pooled A and B** | ₹43.33 crore | **₹47.93 crore** | ₹52.77 crore | **100 %** | **69.4 %** | **33.5 %** | 2.0 % |

- **₹40 crore is safe** in every scenario: it needs only ₹20.44 crore in the second half, against ₹20.80 crore booked in the same months of FY 2025-26.
- **₹45 crore is likely but not safe** (69 % pooled). Without bigger orders it is less likely than not.
- **₹50 crore needs the bigger orders to last.**
- The spread within one scenario (P10 to P90, about ₹4–5 crore) is smaller than the gap between the scenarios (₹6.3 crore between medians). Thousands of orders average out. The real uncertainty is the growth assumption, not chance.

**The second half under rule A, month by month**

| Month | Orders a year earlier | Expected orders | Revenue a year earlier | Expected, rule A | Expected, rule B |
|---|---:|---:|---:|---:|---:|
| October 2026 | 332 | 401 | ₹3.06 crore | ₹3.70 crore | ₹4.64 crore |
| November 2026 | 275 | 332 | ₹2.32 crore | ₹2.80 crore | ₹3.51 crore |
| December 2026 | 409 | 494 | ₹3.76 crore | ₹4.54 crore | ₹5.70 crore |
| January 2027 | 317 | 383 | ₹3.32 crore | ₹4.02 crore | ₹5.04 crore |
| February 2027 | 321 | 388 | ₹2.92 crore | ₹3.53 crore | ₹4.43 crore |
| March 2027 | 446 | 539 | ₹5.42 crore | ₹6.55 crore | ₹8.21 crore |

## 9. Business implications and recommendations

1. **Set the target at ₹45 crore, and call ₹50 crore a stretch.** ₹45 crore is reached in about seven of ten pooled simulations. ₹50 crore needs the April – September jump in order size to last all year.
2. **Present the target as scenarios, not one number.** The ±5 % simulation range understates the risk. The open question is order size, and it should be named as such.
3. **Track two numbers monthly: order count against rule A's plan, and average order value against last year.** If October and November order values stay about 25 % up, move to scenario B. If they fall back, plan on scenario A. The month-by-month table above is the yardstick.
4. **Re-run the simulation at every month-end.** In the back-test, the median came within 2 % of the actual from three months into the year, as long as growth held steady.
5. **Look for the cause of bigger orders.** The [large-order study](../../01_customer_and_revenue/22_large_order_pull_forward/) shows big orders do not steal later demand. If the jump comes from a few large accounts, scenario B rests on them, and the [concentration trend](../../01_customer_and_revenue/08_revenue_concentration_trend/) should be checked.

## 10. Assumptions and limitations

- **One FY of back-test.** The 11 cut-offs all predict the same year, so they are not independent tests. The harder test on April – September 2026 shows the method fails when growth changes pace.
- **Poisson counts.** Real ordering is lumpier than Poisson (customers order in clusters, March peaks), so the 10–90 % ranges are narrower than they should be.
- **Same-month-last-year draws.** A month's simulated orders can only look like last year's orders in that month, scaled. A new customer's very large order is not in the pool.
- **Booked revenue by order date**, including orders later cancelled after the cut-off; invoiced or collected revenue would differ.
- **Targets are candidates for illustration.** The board's actual target and the plan behind it are not in the data.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, pool, month, cut-off, growth, plan, count, simulation and back-test tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
