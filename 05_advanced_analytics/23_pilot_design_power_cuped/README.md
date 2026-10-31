# Case Study · Designing a Sales Pilot: How Many Customers, How Long, Which Metric?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Power analysis for a customer-level pilot on the 350–360 active customers, comparing 3- and 6-month windows, three outcome metrics and CUPED variance reduction, checked with 500 A/A random splits of real history per design.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-31 |

---

## 1. Business problem

Sales wants to test a reorder-call programme before rolling it out: half of the active customers get a monthly call, the other half do not, and revenue is compared after three months. The commercial head expects about a 10 % uplift. Before the pilot starts, the analytics lead must say whether a pilot of this size could detect that at all, which metric and duration to use, and whether the planned test would give false alarms when nothing works.

## 2. Business questions

1. With the customers available, what is the smallest uplift a 3- or 6-month pilot could detect?
2. How much do adjusting for past revenue (CUPED) and capping extreme customers help?
3. How many customers would be needed to detect 10 %?
4. Does the test raise false alarms at the stated 5 % when nothing is done?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Revenue |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Eligible customers | A valid order (not Cancelled or Returned) in the 12 months before the window |
| Windows (on history) | 3 months: Jul–Sep 2026 (pre-period Jul 2025 – Jun 2026); 6 months: Apr–Sep 2026 (pre-period Apr 2025 – Mar 2026) |
| Metrics | Revenue in the window (0 if no order); revenue capped at the 99th percentile; number of orders |
| **CUPED** | Outcome − θ × (pre-period value − its mean), θ = cov ÷ var; the variance falls by (1 − ρ²), ρ = correlation with the pre-period |
| **Minimum detectable effect (MDE)** | (1.96 + 0.84) × SD × √(2 ÷ n per arm) ÷ mean: the uplift a two-arm test detects 80 % of the time at a 5 % significance level |
| Customers needed | Per arm, for a 10 % uplift: 2 × (2.80 × SD ÷ (0.10 × mean))² |
| **A/A test** | 500 random 50/50 splits of the real customers on the historical window with no treatment; a sound test flags about 5 % of them |

## 5. Analytical approach

1. **Customers** (`sahyadri_b2b.pd_customers`): window and pre-period values for each design.
2. **Designs** (`sahyadri_b2b.pd_designs`): SD, correlation, CUPED SD, MDE and customers needed for 12 combinations of window, metric and adjustment.
3. **A/A tests** (`sahyadri_b2b.pd_aa_tests`): false-alarm rate and spread of differences for each design.
4. **Concentration**: how much of the noise comes from the largest customers.

## 6. SQL techniques used

- Power and sample-size formulas computed in SQL from observed variances
- CUPED variance reduction with `COVAR_POP`, `VAR_POP` and `CORR`
- Capping at a percentile with `PERCENTILE_CONT` as a window function
- An A/A simulation: random half-splits of real customers by integer hash, with a two-sample z test per split

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer active in the pre-period |
| 02 | Window and pre-period revenue = source totals |
| 03 | Capped values never exceed the raw value |
| 04 | No orders in the window exactly when no revenue |
| 05 | θ and correlation recomputed |
| 06 | **CUPED SD = plain SD × √(1 − ρ²)**, never above plain |
| 07 | MDE and customers needed recomputed from the formula |
| 08 | 500 A/A splits for each of 12 designs |
| 09 | A/A z-scores finite and centred near zero |
| 10 | **A/A spread of differences within 10 % of the formula** |

## 8. Findings

**A 3-month revenue pilot on the available customers cannot detect 10 %. It cannot detect 100 %.**

| Window | Metric | Adjustment | Correlation with pre-period | MDE | Customers per arm needed for 10 % | × available |
|---|---|---|---:|---:|---:|---:|
| 3 months (360 customers) | Revenue | Plain | 0.67 | **115.5 %** | 24,020 | 133 |
| | Revenue | CUPED | 0.67 | 86.0 % | 13,321 | 74 |
| | Revenue, capped | CUPED | 0.82 | 34.7 % | 2,170 | 12 |
| | Orders | Plain | 0.92 | 49.6 % | 4,435 | 25 |
| | Orders | CUPED | 0.92 | 19.5 % | 688 | 3.8 |
| 6 months (350 customers) | Revenue | Plain | 0.81 | 90.2 % | 14,232 | 81 |
| | Revenue | CUPED | 0.81 | 52.3 % | 4,791 | 27 |
| | Revenue, capped | CUPED | 0.89 | 28.1 % | 1,383 | 7.9 |
| | **Orders** | **CUPED** | **0.94** | **16.9 %** | **499** | **2.9** |

- **The noise comes from a few large customers.** In the 3-month window the 10 largest customers carry 42.0 % of revenue and 92.0 % of its variance, and 32.2 % of customers place no order at all. Which half the big accounts land in decides the result.
- **CUPED and capping together cut the revenue MDE by about 70 %**, and CUPED cuts the orders MDE by about 60 %, because past ordering predicts future ordering very well (correlation 0.92–0.94).
- **Even the best design needs about 500 customers per arm** for a 10 % uplift: three times the 175 available.

**The test itself is sound: the A/A splits behave as designed.**

| Window | Metric | Adjustment | Flagged at 5 % | SD of difference: observed / formula |
|---|---|---|---:|---|
| 3 months | Revenue | Plain | 1.8 % | 115,585 / 114,755 |
| 3 months | Revenue, capped | CUPED | 7.4 % | 29,249 / 28,119 |
| 3 months | Orders | CUPED | 3.6 % | 0.2 / 0.2 orders |
| 6 months | Revenue | Plain | 4.2 % | 175,482 / 174,596 |
| 6 months | Revenue, capped | CUPED | 6.2 % | 48,894 / 47,022 |
| 6 months | Orders | CUPED | 6.2 % | 0.3 / 0.3 orders |

- The formula's spread matches the real splits to within about 5 % in every design, so the MDEs above can be trusted.
- Raw revenue is conservative (1.8 % flagged at a stated 5 %): with a few huge customers the z test rarely fires, which is another way of saying it rarely detects anything.
- **By chance alone, the two halves of a 3-month raw-revenue pilot can differ by up to 101 % of average revenue**; for orders with CUPED, by up to 19.5 %.

## 9. Business implications and recommendations

1. **Do not run the pilot as planned.** A 3-month revenue comparison of 180 against 180 customers would show a "result" driven by where a handful of large accounts fall.
2. **Measure orders, adjusted for each customer's past orders, over six months.** The programme aims at ordering frequency anyway; this design detects a 17 % change.
3. **For a 10 % answer, include every active customer in a staggered roll-out.** Call half the customers from month one and the other half from month four, then compare the first three months; or run the pilot in two consecutive waves and pool them.
4. **Handle the largest customers separately.** Pair the top 20 customers by size and randomise within pairs, or exclude them from the pilot; they carry most of the variance.
5. **Agree the metric, window and test before the pilot starts**, and publish the A/A result alongside the final one so a chance difference is not mistaken for success.

## 10. Assumptions and limitations

- **History as a stand-in.** Variances come from Jul–Sep 2026 and Apr–Sep 2026; a different season (March peak) would change them.
- **Customer-level randomisation.** If one salesperson calls customers in both arms, effects can spill over; randomise by salesperson portfolio if that is a risk.
- **Normal approximation.** With heavily skewed revenue, z tests are approximate; the A/A results show where they are conservative or slightly liberal (up to 7.4 % against 5 %).
- **CUPED θ estimated on all customers**, as it would be before the pilot.
- **Only eligible customers.** New or lapsed customers are outside the pilot population.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer, design and A/A tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
