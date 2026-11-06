# Case Study · How Big Can One Order Get? Extreme Value Analysis for Order Approval Limits

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study covers 9,391 valid orders from January 2024 to September 2026. It fits a generalised Pareto distribution to the 190 orders of ₹5 lakh or more and sets the size exceeded about once a month, quarter, year and five years. It then back-tests a fit made on 2024–2025 against 2026.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-06 |

---

## 1. Business problem

In March 2026 a single distributor order of ₹1.19 crore went through on the salesperson's approval alone. The CFO wants an approval ladder for large orders: a credit check, director sign-off and MD sign-off. Each step should be set by how often orders of that size actually occur. An average-and-spread view of order sizes is useless for this, because a handful of orders dominate the tail.

## 2. Business questions

1. How heavy is the tail of order sizes?
2. How often should we expect orders above ₹10 lakh, ₹20 lakh, ₹50 lakh and ₹1 crore?
3. What order size is exceeded about once a month, quarter, year and five years?
4. Would a model fitted on 2024–2025 have predicted 2026?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Order value |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Order value | Sum of line value after discount, valid orders (not Cancelled or Returned) |
| Exceedance | y = order value − u, for orders above the threshold u (₹5 lakh; ₹3 and ₹8 lakh to check stability) |
| **Generalised Pareto (GPD)** | P(Y > y) = (1 + ξ y ÷ σ)^(−1/ξ). The shape ξ measures tail weight: 0 is an exponential tail, above 0 a power-law tail, above 0.5 a tail so heavy that its variance is infinite. |
| **Probability-weighted moments** | With exceedances sorted ascending, a0 = mean, a1 = (1/n) Σ (n − i)/(n − 1) y(i); k = a0/(a0 − 2a1) − 2, σ = 2a0a1/(a0 − 2a1), ξ = −k (Hosking and Wallis) |
| Rate | λ = exceedances per year; orders a year above x = λ × P(Y > x − u) |
| **Return level** | The size exceeded about once every T years: x(T) = u + σ/ξ × ((λT)^ξ − 1) |
| Bootstrap | 500 resamples of the exceedances (integer hash), each refitted; 5–95 % range |
| Back-test | Fit on 2024–2025, predict January – September 2026; compared with a naive count rate from 2024–2025 |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.ev_orders`) and the shape of the distribution.
2. **Fits** (`sahyadri_b2b.ev_fits`) at three thresholds and on the training years; **bootstrap** (`ev_bootstrap`).
3. **Fit check**: fitted against actual counts above each size.
4. **Rates and return levels**, with bootstrap ranges.
5. **Back-test** on 2026.
6. **Approval ladder** from the return levels, and the orders that would have hit each step.

## 6. SQL techniques used

- Peaks-over-threshold extreme value analysis entirely in SQL, with no statistics library
- Probability-weighted moments from `ROW_NUMBER` ranks and a weighted `SUM`
- A bootstrap by hashed row numbers, refitted in one pass with `PARTITION BY` resample
- Closed-form return levels and rates with `POW`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders and revenue = source |
| 02 | Exceedances per fit = recount of orders above the threshold in the window |
| 03 | **Probability-weighted moments = recount**, with ranks from a self-join instead of `ROW_NUMBER` |
| 04 | **Fitted GPD mean σ/(1 − ξ) = mean exceedance** for every fit (a property of the method) |
| 05 | Rate = exceedances ÷ years (2.75 years full, 2 years train) |
| 06 | Return levels: expected exceedances at the level × T = 1 |
| 07 | 500 bootstrap refits, all with a finite shape between −0.5 and 1.5 |
| 08 | Fitted tail: all exceedances at the threshold, fewer at every higher size |
| 09 | The training fit uses only 2024–2025 orders |
| 10 | Bootstrap shapes centre on the full-sample shape |

## 8. Findings

**A few orders are far larger than the rest.**

| | Value |
|---|---:|
| Orders | 9,391 |
| Median order | ₹0.47 lakh |
| 90th percentile | ₹2.21 lakh |
| 99th percentile | ₹6.83 lakh |
| **Largest order** | **₹119.32 lakh** (₹1.19 crore) |
| Revenue from orders of ₹5 lakh or more | 21.9 % |
| Revenue in the 10 largest orders | 6.4 % |

**The tail is very heavy, and the shape is stable across thresholds.**

| Fit | Threshold | Exceedances | Per year | Shape ξ | Scale σ |
|---|---:|---:|---:|---:|---:|
| Full period | ₹3 lakh | 502 | 182.6 | 0.549 | ₹1.50 lakh |
| **Full period** | **₹5 lakh** | **190** | **69.1** | **0.625** | **₹2.07 lakh** |
| Full period | ₹8 lakh | 69 | 25.1 | 0.666 | ₹3.44 lakh |
| Training (2024–2025) | ₹5 lakh | 117 | 58.5 | 0.541 | ₹2.37 lakh |

- The bootstrap range of ξ is **0.464–0.704** (median 0.610); 90 % of resamples are above 0.5. In a tail this heavy, a single order can move a month's revenue, and averages of large orders are unstable.

**The fit matches the orders seen, except at the very top.**

| Order size above | Actual orders | Fitted |
|---:|---:|---:|
| ₹7.5 lakh | 79 | 77.4 |
| ₹10 lakh | 38 | 43.7 |
| ₹15 lakh | 19 | 20.6 |
| ₹20 lakh | 12 | 12.4 |
| ₹30 lakh | 10 | 6.2 |
| ₹50 lakh | 3 | 2.6 |
| ₹1 crore | **2** | **0.8** |

**How often, and how big** (full-period fit, with the 5–95 % bootstrap range)

| Order size above | Expected a year | Range | About one every |
|---:|---:|---|---:|
| ₹10 lakh | 15.89 | 13.03 – 18.72 | 0.8 months |
| ₹20 lakh | 4.49 | 2.94 – 5.70 | 2.7 months |
| ₹50 lakh | 0.95 | 0.42 – 1.37 | 12.6 months |
| ₹1 crore | 0.31 | 0.09 – 0.49 | 39.3 months |
| ₹2 crore | 0.10 | 0.02 – 0.18 | 120.6 months |

| Exceeded about | Order size | Range |
|---|---:|---|
| Once a month | **₹11.6 lakh** | ₹10.4 – 12.9 lakh |
| Once a quarter | **₹21.4 lakh** | ₹17.3 – 24.9 lakh |
| Once a year | **₹48.5 lakh** | ₹33.4 – 61.4 lakh |
| Once in 5 years | ₹129.8 lakh | ₹70.9 – 183.4 lakh |
| Once in 10 years | ₹199.3 lakh | ₹97.4 – 293.2 lakh |

**2026 brought more large orders, and bigger ones, than 2024–2025 predicted.** Fit on 2024–2025, January – September 2026:

| Order size above | GPD expected | GPD, scaled to 2026's count of ₹5 lakh+ orders | Naive rate from 2024–2025 | Actual |
|---:|---:|---:|---:|---:|
| ₹5 lakh | 43.7 | 73.0 | 43.7 | **73** |
| ₹10 lakh | 10.7 | 17.9 | 9.7 | 12 |
| ₹20 lakh | 2.8 | 4.7 | 3.4 | 3 |
| ₹50 lakh | 0.5 | 0.8 | 0.4 | **2** |
| ₹1 crore | 0.1 | 0.2 | 0.0 | **2** |

- Orders of ₹5 lakh or more came 67 % more often than in 2024–2025 (73 in nine months against 43.7 expected).
- Up to ₹20 lakh, the 2024–2025 fit predicted 2026 well (10.7 against 12 above ₹10 lakh, 2.8 against 3 above ₹20 lakh). At the very top it did not: two orders above ₹1 crore arrived where the fit expected 0.1. The naive count rate, which had never seen a ₹1 crore order, would have expected none.
- Either the tail has grown heavier in 2026, or two rare orders fell in the same year. Both point to planning for bigger orders, as the [FY target simulation](../30_fy_target_monte_carlo/) also found.

**The approval ladder, set from the return levels**

| Step | From | Orders since January 2024 | Customers | Value |
|---|---:|---:|---:|---:|
| Credit check (about once a month) | ₹11.6 lakh | 30 | 19 | ₹9.02 crore |
| Director sign-off (about once a quarter) | ₹21.4 lakh | 12 | 9 | ₹6.34 crore |
| MD sign-off (about once a year) | ₹48.5 lakh | 4 | 4 | ₹3.61 crore |

## 9. Business implications and recommendations

1. **Set the approval ladder at round numbers near the return levels:** a credit check above ₹10 lakh (about 16 orders a year), director sign-off above ₹20 lakh (about 4–5 a year) and MD sign-off above ₹50 lakh (about one a year). Each step then adds work at a known, manageable rate.
2. **Tie the credit check to the [credit-limit review](../../01_customer_and_revenue/17_customer_credit_limits/).** An order above ₹10 lakh should be checked against the customer's open balance before it is accepted, not after dispatch.
3. **Plan for a ₹1 crore order roughly every three years, and expect it sooner.** The full-period fit says once in about 39 months, but 2026 has already had two. Dispatch and working-capital plans should be able to absorb one at short notice.
4. **Report large orders separately in forecasts.** With ξ above 0.5, the average large order is not a stable quantity. Forecasts should treat them as a count with a size distribution, as in the FY target simulation, not as a fixed share of revenue.
5. **Refit the tail every quarter.** If the 2026 pattern continues, the once-a-year level will rise, and so should the MD threshold.

## 10. Assumptions and limitations

- **Orders, not customers, are the unit.** A customer may split a large need into several orders below a threshold (see the [order splitting test](../../04_data_quality_and_reconciliation/11_order_splitting_test/)); an approval ladder can encourage that.
- **Stationarity.** The fit assumes the tail is the same across the period. The 2026 back-test suggests it is not, so the levels should be read as a floor.
- **Few points in the far tail.** Return levels beyond five years rest on extrapolation; the bootstrap range (₹71 lakh – ₹1.83 crore for once in five years) shows how uncertain they are.
- **Probability-weighted moments, not maximum likelihood.** They are stable for small samples and simple in SQL, and they gave ξ = 0.625, against 0.657 by maximum likelihood on the same data, checked outside SQL during the analysis.
- **Bootstrap holds the rate fixed.** It resamples sizes, not the number of large orders a year, so the ranges understate total uncertainty.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, fit and bootstrap tables, and 6 analysis steps |
| `validation.sql` | 10 pass/fail checks |
