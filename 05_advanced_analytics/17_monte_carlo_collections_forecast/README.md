# Case Study · Monte Carlo Forecast of Collections from Open Receivables

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 28 month-end snapshots of open receivables (26,481 item-snapshots); 15 back-test forecasts (five quarter-ends × 30, 60 and 90 days) and a live forecast at 30 Sep 2026, each from 500 simulations.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-27 |

---

## 1. Business problem

Every month the finance manager tells the bank and the directors how much cash will come in from the receivables on the books. Today she applies standard percentages to each age bucket and gives one number. The directors now want a range ("how bad could it be?"), and the auditors want to know how much of the book will ever be collected. She asks for a method that gives a range, can be tested against what actually happened, and runs in the warehouse each month.

## 2. Business questions

1. How does the chance of collection fall as a receivable ages?
2. How much of today's open book will be collected in 30, 60 and 90 days, as a range?
3. Would the method have worked in the past, and is the range honest?
4. How much of the book is unlikely ever to be collected?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Delivered orders |
| `shipments` | One row per shipment | Final delivery date (age) |
| `sales_order_items` | One row per product per order | Order value |
| `payments` | One row per payment | Amounts and dates |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Receivable | A delivered order (delivery date on every shipment) with more than ₹1 outstanding |
| Outstanding | Order value − payments up to the date |
| Age band | Days since final delivery: 0–30, 31–60, 61–90, 91–180, 181–365, 365+ |
| Snapshot | Every month-end from 30 Jun 2024 to 30 Sep 2026: each open item with the share of its outstanding balance collected in the next 30, 60 and 90 days (capped at 100 %) |
| History window | For a forecast at date A and horizon h: snapshots from A − 365 days whose outcome is known by A (snapshot + h ≤ A) |
| **Monte Carlo (two-level bootstrap)** | 500 replicates. In each: (1) draw one historical month-end, because collection conditions vary from month to month; (2) for every open item, draw one item of the same age band from that month-end and apply its collected share. Replicate total = Σ outstanding × drawn share. |
| **P10 / P50 / P90** | 10th, 50th and 90th percentiles of the 500 totals. A P10–P90 range should contain the actual outcome 80 % of the time. |
| Item-independent model (comparison) | Mean = Σ outstanding × average share of the age band; variance = Σ outstanding² × variance of the share; P10 / P90 = mean ∓ 1.2816 standard deviations |
| Random draws | A portable integer hash (`MOD` arithmetic), so the result is identical in any SQL engine |

## 5. Analytical approach

1. **Snapshot table** (`sahyadri_b2b.mc_snapshot_items`). Every open item at every month-end, with its age band and what was collected in the next 30, 60 and 90 days; the collection curve by age.
2. **Settings and history pools** (`sahyadri_b2b.mc_settings`, `sahyadri_b2b.mc_pool`). Six forecast dates × three horizons, and the numbered history items each may draw from.
3. **Simulation** (`sahyadri_b2b.mc_replicates`). 500 replicate totals per forecast date and horizon.
4. **Results** (`sahyadri_b2b.mc_results`). Monte Carlo range, the item-independent range, actual collections and the back-test; the live forecast.
5. **Uncollectable book**: today's receivables by age band.

## 6. SQL techniques used

- Month-end snapshots generated with `GENERATE_DATE_ARRAY`, and look-ahead payment windows with conditional sums
- A point-in-time rule for every forecast: only outcomes known at the forecast date enter its history pool
- Monte Carlo simulation in SQL: replicates from `GENERATE_ARRAY`, a two-level bootstrap (month, then item), and draws from a deterministic integer hash
- Percentile ranges with `APPROX_QUANTILES`, and an analytic variance model for comparison
- Back-testing forecast ranges for coverage, not just point error
- Validation that rebuilds the latest open book and every back-test outcome directly from payments

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | **Latest open book = a rebuild from source** (items and rupees) |
| 02 | Collected shares lie between 0 and 1 and never fall as the horizon grows |
| 03 | Age band agrees with age in days |
| 04 | 28 snapshots, each the last day of a month |
| 05 | **History pools only use outcomes known at the forecast date** |
| 06 | Pool members are numbered 1..n in every month and age band |
| 07 | 500 replicates per forecast date and horizon |
| 08 | Each replicate draws at most one history item per open item |
| 09 | **Actual collections = a recount from payments** |
| 10 | P10 ≤ P50 ≤ P90, and the mean lies inside the range |

## 8. Findings

**After 180 days, receivables are not collected at all.**

| Age at month-end | Item-snapshots | Collected in 30 days | Collected in 90 days | Nothing paid in 90 days |
|---|---:|---:|---:|---:|
| 0–30 days | 6,246 | 40.4 % | **89.3 %** | 8.2 % |
| 31–60 days | 3,886 | 62.3 % | 86.6 % | 12.7 % |
| 61–90 days | 1,819 | 49.4 % | 67.1 % | 34.0 % |
| 91–180 days | 2,538 | 15.4 % | **18.4 %** | 82.9 % |
| 181–365 days | 3,568 | 0.0 % | **0.0 %** | 100 % |
| 365+ days | 4,336 | 0.0 % | **0.0 %** | 100 % |

Of 10,554 payments ever received, only 3 arrived more than 180 days after delivery (the latest after 195 days).

**Today's book: ₹10.96 crore, of which about ₹4.5 crore is expected in 90 days.**

| Horizon | Open items | P10 | P50 | P90 | P50 as share of book |
|---|---:|---:|---:|---:|---:|
| 30 days | 1,421 | ₹2.22 crore | ₹2.48 crore | ₹2.74 crore | 22.6 % |
| 60 days | 1,421 | ₹3.79 crore | ₹4.01 crore | ₹4.25 crore | 36.6 % |
| 90 days | 1,421 | ₹4.34 crore | ₹4.54 crore | ₹4.70 crore | 41.4 % |

**46 % of the book is older than 180 days and, on all past evidence, will not be collected.**

| Age | Open items | Outstanding | Share of book |
|---|---:|---:|---:|
| 0–30 days | 321 | ₹3.43 crore | 31.3 % |
| 31–60 days | 146 | ₹1.28 crore | 11.6 % |
| 61–90 days | 72 | ₹0.53 crore | 4.9 % |
| 91–180 days | 99 | ₹0.64 crore | 5.8 % |
| **181–365 days** | 214 | **₹1.46 crore** | 13.3 % |
| **365+ days** | 569 | **₹3.63 crore** | 33.1 % |

**The method forecasts within about 5 %, and its range holds 11 times out of 15.**

| Forecast at | Horizon | Open book | P10 | P90 | Actual | Error of mean | Inside range |
|---|---:|---:|---:|---:|---:|---:|---|
| 30 Jun 2025 | 30 | ₹614.0 lakh | 149.9 | 182.4 | **197.9** | −16.0 % | No |
| 30 Jun 2025 | 90 | 614.0 | 272.4 | 299.5 | **304.3** | −6.0 % | No |
| 30 Sep 2025 | 90 | 658.9 | 282.6 | 306.8 | 285.4 | +3.3 % | Yes |
| 31 Dec 2025 | 90 | 865.1 | 401.0 | 434.1 | 425.6 | −1.7 % | Yes |
| 31 Mar 2026 | 90 | 1,054.7 | 507.7 | 547.4 | 511.4 | +3.3 % | Yes |
| 30 Jun 2026 | 90 | 1,012.4 | 391.6 | 433.5 | **440.2** | −6.0 % | No |

(P10, P90 and actual in ₹ lakh. The full 15-row table is Step 4 of the script.)

| Across 15 back-tests | Result |
|---|---:|
| Mean absolute error of the mean forecast | **5.3 %** |
| Actual inside the Monte Carlo P10–P90 range | 11 of 15 (73 %, against 80 % intended) |
| Actual inside the item-independent range | 11 of 15 |
| Average width of the Monte Carlo range | 13.9 % of the forecast |
| Average width of the item-independent range | 12.1 % |

- **All four misses are under-forecasts**: collections came in faster than the previous year's history suggested, most clearly at 30 June 2025, when the history window still held the slower months of 2024.
- **Monte Carlo and the simpler analytic model agree here.** The month-level draw widens the range by about 15 % but changes no back-test result. The value of the simulation is that it extends to things the analytic model cannot easily handle (per-customer correlation, scenario shocks).

## 9. Business implications and recommendations

1. **Report the 90-day collection forecast as a range**: ₹4.34–4.70 crore, central ₹4.54 crore, from a book of ₹10.96 crore. Re-run the script at each month-end.
2. **Treat receivables over 180 days as doubtful.** ₹5.09 crore (46 % of the book) is older than 180 days; in every month-end snapshot since June 2024, no such item received a payment within the next 90 days. Provide for it, and review the 569 items over a year old for write-off.
3. **Escalate at 90 days, not later.** Collection probability falls from 67 % (61–90 days) to 18 % (91–180 days). Chasing has to happen before an item reaches 90 days; the [late payment scorecard](../15_late_payment_scorecard/) shows which orders to start on at delivery.
4. **Quote the range slightly wider than P10–P90 to directors.** In the back-test the range held 73 % of the time, and every miss was on the cautious side; a P5–P95 range or a 10 % margin brings coverage close to the intended level.
5. **Clean the book before using DSO.** With 46 % of balances uncollectable, any DSO or receivables KPI is dominated by dead items (see [receivables roll-forward](../../04_data_quality_and_reconciliation/05_receivables_rollforward/)).

## 10. Assumptions and limitations

- **History repeats.** The forecast assumes the next 90 days behave like the past 12 months. The under-forecasts show that improving collection behaviour is picked up with a lag.
- **Age band only.** Segment and customer history are not used; the [late payment scorecard](../15_late_payment_scorecard/) shows segment matters, so adding it could sharpen the forecast.
- **Open book only.** Collections from invoices raised after the forecast date are not included; a full cash forecast adds them from the sales forecast.
- **Missing age bands.** If a drawn month-end has no history item in an age band (for example 365+ days in 2024), items of that band contribute nothing in that replicate; those bands collect nothing anyway.
- **`APPROX_QUANTILES`** is approximate in BigQuery; with 500 replicates the percentiles may differ by a fraction of a lakh.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Snapshot, settings, pool, replicate and result tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
