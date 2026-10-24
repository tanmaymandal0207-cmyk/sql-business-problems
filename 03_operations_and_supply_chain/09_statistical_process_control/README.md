# Case Study · Statistical Process Control for Delivery and Cancellations

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Weekly data January 2024 – September 2026; baseline to June 2025, monitoring from July 2025.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-24 |

---

## 1. Business problem

Every Monday, the operations review discusses last week's late-delivery and cancellation rates. Managers react to every rise: a bad week triggers an investigation, a good week is praised. Most of those movements are normal week-to-week noise. **Statistical process control (SPC)** separates noise ("common cause") from real change ("special cause"), so the team investigates only the weeks that are genuinely unusual, and can tell when a process has really improved or worsened.

## 2. Business questions

1. What range of weekly late-delivery and cancellation rates is normal?
2. Which weeks were genuinely out of control, and on which rule?
3. Has either process shifted since the baseline period?
4. How many weekly alarms would a simple target-based rule raise that SPC shows to be noise?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order week, status, promised date |
| `shipments` | One row per shipment | Final delivery date |

## 4. Method and metric definitions

**p-chart for each week t**, with n(t) orders and x(t) events (late, or cancelled):

| Term | Definition |
|---|---|
| p(t) | x(t) ÷ n(t) |
| Centre line p̄ | Total events ÷ total orders in the **baseline** (weeks to 30 Jun 2025) |
| σ(t) | √(p̄ (1 − p̄) ÷ n(t)). Limits are wider in weeks with fewer orders. |
| Control limits | p̄ ± 3σ(t), with the lower limit floored at 0 |
| **R1** | One point beyond 3σ |
| **R2** | 2 of 3 consecutive points beyond 2σ on the same side |
| **R4** | 8 consecutive points on the same side of the centre line (a sustained shift) |
| Naive alarm | A week more than 3 percentage points above the long-run average, a typical "management by exception" rule |

| Process | Orders counted |
|---|---|
| Late delivery | Delivered orders with a promised and a final delivery date, by order week, to 31 Aug 2026 (later weeks still have undelivered orders) |
| Cancellation | Closed orders (Delivered, Cancelled, Returned), by order week |

The baseline period sets the limits (Phase I). Later weeks are judged against them (Phase II), so a change in the process shows up as signals.

## 5. Analytical approach

1. **Weekly counts** (`sahyadri_b2b.spc_weekly`) for both processes, tagged Baseline or Monitoring.
2. **Control chart table** (`sahyadri_b2b.spc_chart`). Centre line, σ, limits, z-score and naive alarm for every week.
3. **Signals table** (`sahyadri_b2b.spc_signals`). Weeks that break rules R1, R2 or R4, and a summary against naive alarms.
4. **Signal list.**
5. **Shift test:** monitoring against baseline rate (two-proportion z-test).

## 6. SQL techniques used

- Control limits that vary with each week's sample size
- Western Electric run rules written as window counts (`COUNTIF(z > 2) OVER (… ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)`, and an 8-week window for runs)
- Phase I / Phase II separation: limits from a baseline, applied to later data
- Validation that recounts runs with a self-join over date ranges instead of window functions

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per process and week |
| 02 | Cancellation counts = source closed orders |
| 03 | No missing weeks (every gap is 7 days) |
| 04 | Centre line = baseline event rate |
| 05 | Limits sit exactly 3σ from the centre, and the lower limit is between 0 and the centre |
| 06 | R1 signals = weeks outside the control limits |
| 07 | **R4 signals = an independent self-join recount** |
| 08 | Phase matches the baseline end date |
| 09 | No late-delivery week after the cut-off |
| 10 | No week with more events than orders, or with no orders |

## 8. Findings

**Both processes are stable. Every weekly rise in 2.7 years was within normal variation.**

| Process | Centre line | Normal range for a typical week | R1 or R2 signals | Naive alarms |
|---|---:|---|---:|---:|
| Late delivery | 18.0 % | 2.5 – 33.6 % (55 orders) | **0** | 34 |
| Cancellation | 5.4 % | 0 – 14.2 % (59 orders) | **0** | 27 |

- **The simple rule raised 61 alarms; SPC found none on the bad side.** Each would have triggered an investigation into what was ordinary noise.
- The worst weeks were close to, but inside, the limits: late delivery 32.8 % in the week of 24 Nov 2025 (z = 2.92), and cancellations 13.3 % in the week of 26 May 2025 (z = 2.74).
- **Weekly rates swing widely because weekly samples are small.** With about 60 orders a week, a late-delivery rate anywhere between about 3 % and 33 % is consistent with an unchanged process.

**The only signal is a genuine improvement.** Late delivery stayed below the centre line for 10 consecutive weeks, from the week of 18 May to the week of 20 Jul 2026, at about 15 %. Rule R4 flags the 8th to 10th weeks. Something improved in that period, and the rate later returned to normal.

**No overall shift since the baseline.**

| Process | Baseline rate | Monitoring rate | z-score |
|---|---:|---:|---:|
| Late delivery | 18.02 % | 18.96 % | 1.14 |
| Cancellation | 5.37 % | 5.33 % | −0.09 |

The processes are stable, but stable at a level that is not good enough: about 1 order in 5 is late and 1 in 19 is cancelled. Improvement needs a change to the process, such as the promise standards or dispatch capacity, not a reaction to individual weeks.

## 9. Business implications and recommendations

1. **Replace the weekly "red/amber/green" against target with a p-chart** in the Monday review. Investigate only R1, R2 or R4 signals. This removes about 60 false alarms over the period.
2. **Find out what happened in May–July 2026.** Ten weeks of better-than-normal delivery is the one real signal. If a change in carriers, staffing or promise rules explains it, make it permanent.
3. **Move the process, not the week.** Both processes are stable at an unsatisfactory level. Use the [promise standards](../05_promise_date_standards/) and [late delivery root cause](../01_late_delivery_root_cause/) findings to change the system, then reset the baseline and confirm the shift with R4.
4. **Review monthly where weekly samples are too small.** For smaller segments, such as a single region, weekly charts will be too noisy to be useful.

## 10. Assumptions and limitations

- **Independence.** p-charts assume orders are independent. Orders from the same customer or the same carrier may be correlated, so the true limits are slightly wider.
- **Order week, not delivery week.** Lateness is charted by the week the order was placed, which is when the promise was made.
- **Recent weeks are incomplete.** Late delivery is charted only to the end of August 2026.
- **Rules chosen.** R1, R2 and R4 are standard Western Electric rules. Adding more rules raises the false-alarm rate.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Weekly, chart and signal tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
