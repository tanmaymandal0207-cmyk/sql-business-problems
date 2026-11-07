# Case Study · Why Do Last Month's KPIs Change After the Pack Goes Out?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study covers 18 months of delivery KPIs (January 2025 – June 2026). It rebuilds each figure as the monthly pack would have shown it 0, 5 and 15 days after month-end, compares it with the final figure, and tests a reporting method that never needs revising.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-07 |

---

## 1. Business problem

The monthly operations pack goes to the board on the 5th. Every quarter, when the figures are refreshed, last quarter's on-time delivery rate turns out lower and delivery times longer than the board was told. The operations head is accused of flattering the numbers. The financial controller wants to know whether the numbers are being massaged, or whether the method itself produces the gap, and how to report figures that stand.

## 2. Business questions

1. How much do the delivery KPIs change between the pack and the final figures, and in which direction?
2. Why: which orders are missing from the pack?
3. Does waiting longer before publishing fix it?
4. How can each KPI be reported so that it does not need revising?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, promised date, status |
| `shipments` | One row per shipment | Shipment and delivery dates |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Order | A valid order (not Cancelled or Returned) with at least one shipment |
| Delivery date | The last shipment's delivery date, only when every shipment has one |
| **As-of date** | Last day of the month + 0, 5 (the board pack) or 15 days; only events on or before it are known |
| On-time delivery (by promise month) | Orders delivered by the promised date ÷ orders promised in the month |
| **Pack method** | On-time ÷ orders **delivered by the as-of date**: what the pack reports |
| **Fixed method** | On-time ÷ **all** orders promised in the month. An order not delivered by the as-of date is already late, because its promised date has passed. |
| Delivery time (by order month) | Average days from order to delivery; pack method uses orders delivered by the as-of date |
| Dispatch wait (by order month) | Average days from order to first shipment; pack method uses orders shipped by the as-of date |
| **Revision** | Final figure (all data to 30 September 2026) − figure in the pack |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.kr_orders`) with first shipment and delivery dates.
2. **KPIs** (`sahyadri_b2b.kr_kpis`): every month × publishing lag, as the pack would have shown them and as they finally were.
3. **Revisions** by lag and month.
4. **Why**: the orders missing from the pack, and the alternative of reporting delivery time by delivery month.

## 6. SQL techniques used

- Point-in-time ("as-of") reconstruction: every event filtered to `<= as_of`, so past reports can be rebuilt exactly
- `COUNTIF` in the numerator and denominator of the same ratio to compare two definitions side by side
- A months × lags grid from `GENERATE_DATE_ARRAY` and `UNNEST`
- Identity checks in validation: the fixed method must equal the final figure exactly

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders = valid orders with at least one shipment |
| 02 | Delivery date only when every shipment is delivered, and equal to the last one |
| 03 | 18 months × 3 lags; as-of = last day of the month + lag |
| 04 | Orders promised in each month = recount, the same at every lag |
| 05 | **Fixed method = final on-time rate exactly, at every lag** |
| 06 | The pack's on-time rate is never below the final rate |
| 07 | Orders known to be delivered grow with the lag and never exceed orders promised |
| 08 | Board-pack and final delivery days = recount from orders |
| 09 | Board-pack dispatch days = recount from orders |
| 10 | Orders not delivered by the pack date = recount |

## 8. Findings

**Every month, the pack overstated on-time delivery and understated delivery time.**

| Published | Months | On-time revision | Months revised down | Largest cut | Delivery-time revision | Months revised longer | Dispatch-wait revision | Fixed-method revision |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| At month-end | 18 | −3.28 points | 18 | 5.18 points | +1.27 days | 18 | +0.69 days | **0** |
| **5 days after (board pack)** | 18 | **−1.62 points** | **18** | 2.68 points | **+1.07 days** | **18** | +0.50 days | **0** |
| 15 days after | 18 | −0.22 points | 9 | 0.71 points | +0.39 days | 18 | +0.13 days | **0** |

- The revisions always go the same way. Nobody is massaging the figures: the method leaves out exactly the orders that are going badly.
- Waiting 15 days shrinks the on-time revision to 0.22 points, but delivery time is still revised every month.

**The board pack, month by month** (5 days after month-end)

| Month | Orders promised | Not delivered by the pack date | On-time in the pack | On-time final | Fixed method | Delivery days in the pack | Final |
|---|---:|---:|---:|---:|---:|---:|---:|
| Jan 2025 | 297 | 6 | 82.8 % | 81.1 % | 81.1 % | 7.82 | 8.81 |
| Feb 2025 | 256 | 8 | 85.9 % | 83.2 % | 83.2 % | 7.25 | 8.93 |
| Mar 2025 | 371 | 7 | 82.7 % | 81.1 % | 81.1 % | 7.98 | 8.92 |
| Apr 2025 | 278 | 8 | 83.7 % | 81.3 % | 81.3 % | 7.63 | 9.04 |
| May 2025 | 261 | 3 | 80.6 % | 79.7 % | 79.7 % | 7.97 | 8.76 |
| Jun 2025 | 225 | 6 | 85.4 % | 83.1 % | 83.1 % | 7.27 | 8.14 |
| Jul 2025 | 243 | 6 | 88.2 % | 86.0 % | 86.0 % | 7.82 | 8.90 |
| Aug 2025 | 253 | 5 | 86.3 % | 84.6 % | 84.6 % | 7.07 | 8.26 |
| Sep 2025 | 287 | 4 | 80.9 % | 79.8 % | 79.8 % | 8.00 | 9.08 |
| Oct 2025 | 290 | 6 | 79.9 % | 78.3 % | 78.3 % | 7.91 | 9.08 |
| Nov 2025 | 313 | 5 | 81.2 % | 79.9 % | 79.9 % | 8.18 | 9.39 |
| Dec 2025 | 351 | 4 | 81.3 % | 80.3 % | 80.3 % | 7.82 | 8.65 |
| Jan 2026 | 369 | 7 | 82.0 % | 80.5 % | 80.5 % | 7.76 | 8.78 |
| Feb 2026 | 282 | 4 | 78.4 % | 77.3 % | 77.3 % | 7.89 | 8.77 |
| Mar 2026 | 409 | 9 | 84.3 % | 82.4 % | 82.4 % | 7.80 | 8.67 |
| Apr 2026 | 333 | 8 | 83.7 % | 81.7 % | 81.7 % | 7.65 | 8.94 |
| May 2026 | 286 | 6 | 79.3 % | 77.6 % | 77.6 % | 7.81 | 8.85 |
| Jun 2026 | 291 | 2 | 84.8 % | 84.2 % | 84.2 % | 7.73 | 8.63 |

**The orders missing from the pack are the problem orders.** Over the 18 months:

| Orders promised in the month | Orders | On time | Dispatch wait | Order to delivery | Never delivered |
|---|---:|---:|---:|---:|---:|
| Delivered by the pack date | 5,291 | 82.7 % | 3.88 days | 8.50 days | 0 |
| **Not delivered by the pack date** | **104** | **0 %** | **13.89 days** | **24.15 days** | **7** |

Only 2 % of orders are missing from the pack, but every one of them is late, and they waited more than three times as long for dispatch. Leaving them out of the denominator is what lifts the reported rate.

**Delivery time reported by delivery month needs no revision.** Every order delivered in a month is known at month-end:

| Average of the 18 months | Delivery days |
|---|---:|
| By order month, in the pack | 7.74 |
| By order month, final | 8.81 |
| **By delivery month** (never revised) | **8.80** |

The delivery-month figure matches the final order-month average across the period (8.80 against 8.81). Month by month it moves differently (correlation 0.588), because it describes orders delivered in the month rather than placed in it.

## 9. Business implications and recommendations

1. **Change the on-time formula, not the timetable.** Divide by all orders promised in the month, counting any order still undelivered at the pack date as late. It gives the final figure exactly, on the 5th, in every month tested.
2. **Report delivery time and dispatch wait by delivery and dispatch month.** Orders delivered or shipped in a month are all known at month-end, so the figure never changes. Order-month figures always come in 1.1 days too short in the pack.
3. **Add an "open past promise" count to the pack.** The 2 % of orders that miss the pack are the worst ones (24 days order to delivery). They should be visible, not silently excluded.
4. **Restate the last six packs once** with the fixed method, and tell the board the difference was the formula, not the people.
5. **Audit other KPIs for the same flaw.** Any rate whose denominator only counts finished cases (collection rate on settled invoices, return rate on completed orders) will flatter recent months the same way.

## 10. Assumptions and limitations

- **Dates are assumed entered on the day.** If delivery dates were keyed in late, the pack would miss even more, and the revisions would be larger.
- **The final figure is not quite final for the last months.** Orders still open on 30 September 2026 count as late in the final on-time rate; June 2026 had three months to mature.
- **Delivery time excludes orders never delivered** in both pack and final figures; the 7 such orders would make both longer.
- **One KPI family.** Revenue and collections have their own timing issues (cancellations and payments after month-end), not studied here; see [revenue cut-off](../04_revenue_cutoff_reconciliation/).

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order and KPI tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
