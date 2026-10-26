# Case Study · Monetary Unit Sampling for the Receivables Audit

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 3,639 orders delivered in FY 2025-26 (₹32.57 crore); a 300-unit sample, evaluated and then re-drawn with 20 random starts.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

The statutory auditors will test whether each delivered order's payment status (Paid, Partially Paid, Unpaid) correctly reflects the cash received, because receivables are built from it. They will not test every order. They will draw a **monetary unit sample (MUS)**: every rupee of value has the same chance of selection, so large orders are more likely to be picked. Finance wants to know what that sample will look like, what conclusion it is likely to reach, and whether anything should be fixed before the auditors arrive. Unlike the auditors, finance holds all the data, so it can compare the sample's conclusion with the truth.

## 2. Business questions

1. How large will the auditors' sample be, and how is it drawn?
2. What would the sample conclude: projected misstatement, upper misstatement limit, accept or reject?
3. What is the true misstatement of the whole population, and how often does a sample reach the right conclusion?
4. What should finance correct before the audit?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Payment status, status |
| `sales_order_items` | One row per product per order | Book value |
| `shipments` | One row per shipment | Delivery date (population period) |
| `payments` | One row per payment | Cash received |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Population | Delivered orders whose final delivery fell in FY 2025-26 (1 Apr 2025 – 31 Mar 2026) |
| Book value | Order value (quantity × price × (1 − discount)) |
| **Misstatement** | \|outstanding implied by the status − actual outstanding\|. Paid implies ₹0 outstanding, Unpaid the full value; Partially Paid is taken at the actual balance (only the status is tested). Differences of ₹10 or less are rounding. |
| Tainting | Misstatement ÷ book value, capped at 1 |
| Design | 95 % confidence, no expected misstatement (reliability factor **3.0**), tolerable misstatement **1 %** of book value |
| Sample size, interval | n = ⌈book value × 3.0 ÷ tolerable⌉; interval J = book value ÷ n |
| Selection | Systematic: rupees r, r + J, r + 2J … of the cumulative book value in order-id sequence, from a random start r |
| Top stratum | Orders worth at least J: always selected; their misstatement counts in full |
| **Projected misstatement** | Σ tainting × J + top-stratum misstatement |
| **Upper misstatement limit** | J × (3.0 + Σ ranked taintings × incremental Poisson factor) + top-stratum misstatement. Incremental factors at 95 %: 1.74, 1.56, 1.45, 1.40 … |
| Conclusion | Accept if the upper limit ≤ tolerable misstatement |
| Replicates | 20 random starts from a golden-ratio sequence; replicate 1 is the audit sample |

## 5. Analytical approach

1. **Population table** (`sahyadri_b2b.mus_population`). Book value, implied and actual outstanding, misstatement, tainting and cumulative value for each order.
2. **Design table** (`sahyadri_b2b.mus_design`). Book value, tolerable misstatement, sample size, interval, and the true misstatement (known to finance, not to the auditor).
3. **Selection table** (`sahyadri_b2b.mus_selection`). Selected orders and hits for 20 random starts.
4. **Evaluation table** (`sahyadri_b2b.mus_evaluation`). Errors found, projected misstatement, upper limit and conclusion per replicate, compared with the truth.

## 6. SQL techniques used

- Probability-proportional-to-size selection in one join: an order is selected when `FLOOR((cum_after − r) / J) > FLOOR((cum_before − r) / J)`
- A Poisson factor table and `ROW_NUMBER()` ranking of taintings for the upper limit
- Many sample replicates generated with `GENERATE_ARRAY`, to measure how the method behaves
- Probability of detection computed as 1 − Π(1 − pᵢ) with `EXP(SUM(LN(…)))`
- Validation that rebuilds every selection from explicit selection points (r + m × J) with a range join

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Population = source delivered orders in the year |
| 02 | Book value = source line items |
| 03 | Cumulative values are consistent and end at total book value |
| 04 | n × J = book value, and 3 × J ≤ tolerable misstatement |
| 05 | Every replicate has exactly n hits |
| 06 | Every top-stratum order is selected in every replicate |
| 07 | **Selections = a recount from explicit selection points** |
| 08 | Misstatement = an independent status test |
| 09 | Upper limit never below basic precision; no projection without errors |
| 10 | Errors found per replicate = recount |

## 8. Findings

**The auditors' sample: 300 monetary units, about 297 orders.**

| Design | Value |
|---|---:|
| Population | 3,639 orders, ₹32.57 crore |
| Tolerable misstatement (1 %) | ₹32.57 lakh |
| Sample size | 300 |
| Sampling interval | ₹10.86 lakh |
| Orders in the top stratum (always selected) | 6 |

**The payment status is almost always right. There are three errors, all the same kind.**

| Order | Status recorded | Book value | Paid | Misstatement |
|---|---|---:|---:|---:|
| 106794 | Unpaid | ₹2,93,218 | ₹2,93,218 | ₹2,93,218 |
| 104451 | Unpaid | ₹1,17,264 | ₹1,17,264 | ₹1,17,264 |
| 104536 | Unpaid | ₹26,396 | ₹26,396 | ₹26,396 |

- All three orders are marked Unpaid but were paid in full. Receivables are overstated by **₹4.37 lakh, 0.13 % of the population**, well below the ₹32.57 lakh tolerable misstatement.
- Two other orders differ by ₹1–2 and are treated as rounding.

**The audit sample (replicate 1) finds no error and accepts the population.**

| Items | Hits | Errors found | Projected misstatement | Upper limit | Tolerable | Conclusion |
|---:|---:|---:|---:|---:|---:|---|
| 297 | 300 | 0 | ₹0 | ₹32.57 lakh | ₹32.57 lakh | Accept |

With no errors, the upper limit is the basic precision (3.0 × J), which by design equals tolerable misstatement.

**But about one sample in three would find an error and reject.**

| Across 20 random starts | Result |
|---|---:|
| Samples that found an error | **7** (all found exactly one) |
| Samples reaching the right conclusion (accept) | 13 |
| Upper limit when one 100 %-tainted error is found | ₹51.46 lakh (above tolerable) |
| Samples whose upper limit covered the true misstatement | **20 of 20** |
| Probability that a sample contains at least one error | **36.5 %** |

| Error order | Book value | Chance of selection | Selected in replicates |
|---|---:|---:|---:|
| 106794 | ₹2.93 lakh | 27.0 % | 5 of 20 |
| 104451 | ₹1.17 lakh | 10.8 % | 2 of 20 |
| 104536 | ₹0.26 lakh | 2.4 % | 0 of 20 |

- **MUS is conservative, as intended.** Every upper limit was above the true misstatement, so the method never understated the problem.
- **The cost of that caution falls on the company.** An error with 100 % tainting adds 1.74 × J to the upper limit. One such find takes the limit to ₹51.46 lakh, above tolerable, even though the true misstatement is only ₹4.37 lakh. The auditors would then extend testing or propose an adjustment.

## 9. Business implications and recommendations

1. **Correct the three orders before the audit.** Change orders 106794, 104451 and 104536 to Paid. It removes a 36.5 % chance that the sample hits an error and triggers extended work, and it corrects ₹4.37 lakh of overstated receivables.
2. **Derive payment status from payments.** All three errors are manual statuses that were never updated after payment. A status calculated from the payments table, as the [order-to-cash reconciliation](../01_order_to_cash_reconciliation/) recommends, would remove this error type entirely.
3. **Share the population file with the auditors.** Providing the population with cumulative book values, as in `mus_population`, lets the auditors draw their sample quickly and reproducibly.
4. **Plan with an expected error if issues remain.** If errors cannot be corrected first, the auditors can design the sample with a small expected misstatement, which enlarges it but avoids a rejection driven by a single error.
5. **Re-run before each year-end.** The script parameters (year, tolerable %, confidence factor) can be changed for the next audit.

## 10. Assumptions and limitations

- **Status tested at today's data.** Payments are counted to the extraction date, not to 31 March 2026. A year-end audit would use payments up to the balance sheet date.
- **One attribute.** Only the payment status is tested. Real audit samples test several assertions (existence, valuation, cut-off) on the same items.
- **Systematic selection** in order-id sequence. If errors were patterned in the same sequence, systematic selection could under-sample them; random cell selection avoids this.
- **Poisson factors** are the standard 95 % values for up to 10 errors; beyond 10, an increment of 1.25 is used.
- **Random starts** come from a fixed quasi-random sequence so that results are reproducible.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Population, design, selection and evaluation tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
