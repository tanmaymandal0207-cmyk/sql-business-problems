# Case Study · Little's Law: Backlog, Throughput and Lead Time for 2027

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Daily counts of orders waiting for dispatch and in transit over 1,004 days (January 2024 – September 2026), checked against Little's Law year by year, and used to size the 2027 backlog at today's speed and the speed needed to hold it at today's level.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-30 |

---

## 1. Business problem

Orders are growing by close to a fifth a year. For the 2027 plan the operations head must decide how much staging space the warehouse needs for orders waiting to be dispatched, how many consignments will be on the road at once, and how much faster dispatch must become to stop the backlog growing. The team plans today from month-end open-order counts. She wants a method that links backlog, order volume and lead time, a check that it holds on this data, and a 2027 estimate.

## 2. Business questions

1. On average, how many orders are waiting for dispatch and in transit, and does Little's Law hold?
2. Do month-end snapshots give a fair picture of the backlog?
3. How high do the peaks go?
4. What will 2027 look like at today's speed, and what speed keeps the backlog at today's level?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, status |
| `shipments` | One row per shipment | First dispatch and final delivery dates |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| **Awaiting dispatch** | From order date to first shipment date. Pending and Processing orders stay in the stage until 30 Sep 2026. |
| **In transit** | From first shipment to final delivery. Shipments not delivered by 30 Sep 2026 stay in the stage. |
| Excluded | Cancelled orders never shipped (the date they left the backlog is not recorded), 5 orders shipped before they were placed and 4 delivered orders without a shipment |
| Daily count N(d) | Orders that entered the stage on or before day d and had not left by the end of day d |
| **Little's Law** | L = λ × W: average number in a stage = entries per day × average days in the stage. The daily counts add up to the total days spent in the stage, so the law holds exactly apart from orders that cross the period's start or end. |
| **Stale record** | A shipment never delivered and more than 30 days on the road |
| Delivered orders only | The in-transit stage for shipments that were delivered (used for planning) |
| 2027 at today's speed | λ grows by the last 12 months' order growth (18.7 %); W stays at its 2026 level |
| Speed to hold today's level | W × λ(2026) ÷ λ(2027) |

## 5. Analytical approach

1. **Order table** (`sahyadri_b2b.ll_orders`): stage start and end dates for every order.
2. **Daily table** (`sahyadri_b2b.ll_daily`): entries, exits and the number in each stage on every day, including delivered-only and stale counts.
3. **Yearly table** (`sahyadri_b2b.ll_yearly`): λ, W, λ × W and the observed average L by year and stage.
4. **Snapshots and peaks**: month-end counts against daily averages, the 95th-percentile day and the busiest months; the stale records.
5. **2027**: the backlog at today's speed and the speed that holds it.

## 6. SQL techniques used

- A daily calendar with `GENERATE_DATE_ARRAY` and running counts from entry and exit events (`SUM() OVER` of entries − exits)
- Little's Law checked as an identity: the sum of daily counts equals total order-days
- Separating stale open records from the real flow with a delayed entry event (shipment date + 31 days)
- Validation by direct recounts of the daily count on chosen dates and of the total order-days

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order that entered the dispatch queue |
| 02 | Stage dates in order; open stages end at the as-of date |
| 03 | One row per stage and calendar day |
| 04 | Daily counts never negative; entries = orders entering each stage |
| 05 | **Daily counts on four dates = a direct recount from order dates** |
| 06 | **Sum of daily counts = total order-days in each stage** (the identity behind Little's Law) |
| 07 | Delivered-only plus stale counts never exceed the recorded in-transit count |
| 08 | Yearly entries add up to all entries |
| 09 | Yearly λ and L = a recount from the daily table |
| 10 | Three years for each of the three flow stages |

## 8. Findings

**Little's Law holds for dispatch, and for transit only once stale records are removed.**

| Stage | Year | Orders a day (λ) | Days in stage (W) | λ × W | Observed average (L) | Difference |
|---|---|---:|---:|---:|---:|---:|
| Awaiting dispatch | 2024 | 8.05 | 3.97 | 32.0 | 31.6 | −1.2 % |
| Awaiting dispatch | 2025 | 9.70 | 4.12 | 40.0 | 39.8 | −0.4 % |
| Awaiting dispatch | 2026 | 10.87 | 4.00 | 43.5 | **44.4** | +2.0 % |
| In transit (all records) | 2024 | 7.93 | 6.64 | 52.7 | 40.2 | **−23.8 %** |
| In transit (all records) | 2025 | 9.66 | 5.11 | 49.4 | 53.5 | +8.3 % |
| In transit (all records) | 2026 | 10.93 | 4.89 | 53.5 | 65.0 | **+21.6 %** |
| In transit (delivered orders) | 2024 | 7.92 | 4.64 | 36.7 | 36.4 | −1.0 % |
| In transit (delivered orders) | 2025 | 9.65 | 4.70 | 45.3 | 45.4 | +0.2 % |
| In transit (delivered orders) | 2026 | 10.74 | 4.71 | 50.6 | **51.0** | +0.8 % |

- **Dispatch is a stable flow.** About 4 days in the queue in every year; the backlog has grown only because orders have grown (from 32 to 44 orders on an average day).
- **The transit mismatch is a data problem, and Little's Law found it.** 63 shipments are still recorded as in transit on 30 September 2026; 15 have been on the road for more than 30 days, the oldest for 997 days. These 63 records hold 15.6 % of all recorded transit days. They inflate the average days of the year they were shipped (2024: 6.64 days against 4.64 for delivered orders) and the counts of every later year.

| Month-end | Recorded in transit | Stale records (30+ days) | Excluding stale |
|---|---:|---:|---:|
| Mar 2024 | 52 | 1 | 51 |
| Mar 2025 | 62 | 7 | 55 |
| Mar 2026 | 71 | **13** | 58 |
| Sep 2026 | 63 | **15** | 48 |

**Month-end snapshots are unbiased but noisy.** For the dispatch backlog the average month-end count was +3.0 %, +1.2 % and −6.9 % against the daily average in 2024, 2025 and 2026; for transit +11.2 %, −0.2 % and −4.9 %. A single month-end can be well off a typical day.

**Plan space for the peaks, not the average.** In 2026, the dispatch backlog averaged 44 orders, reached 62 on the busiest 5 % of days and 79 on the busiest day. March is the heaviest month (50.4 orders a day on average, peak 79), followed by December (45.6, peak 67).

**2027: the backlog grows with volume unless dispatch gets faster.**

| Stage | Orders a day 2026 → 2027 | Days in stage 2026 | Average number 2026 → 2027 at today's speed | Busiest 5 % of days, 2027 | Days in stage to stay at the 2026 level |
|---|---:|---:|---:|---:|---:|
| Awaiting dispatch | 10.87 → 12.90 | 4.00 | 44.4 → **51.6** | about 74 | **3.37** |
| In transit (delivered orders) | 10.74 → 12.74 | 4.71 | 51.0 → **60.0** | about 84 | **3.97** |

## 9. Business implications and recommendations

1. **Size 2027 staging space for about 75 waiting orders**, the 95th-percentile day at today's speed, with March as the design month.
2. **Or cut the dispatch queue from 4.0 to 3.4 days** to keep the backlog at 2026 levels. That needs more daily dispatch capacity at the peaks: the [FIFO study](../15_dispatch_queue_discipline/) showed that re-sequencing alone removes the long waits but leaves the average wait unchanged.
3. **Close the stale in-transit records.** Trace the 15 shipments on the road for more than 30 days, record the delivery or the loss, and add an exception report for any shipment in transit for more than 15 days (see the [open order backlog review](../03_open_order_backlog_review/)).
4. **Plan from daily averages, not month-end counts.** Report the daily average and the 95th-percentile day each month; a single month-end count can be 7–11 % off.
5. **Use λ × W as a monthly control.** When the observed backlog drifts from λ × W, either the lead time has changed or records are going stale; either needs action.

## 10. Assumptions and limitations

- **Cancelled orders are missing from the queue.** Their cancellation date is not recorded; if they waited before being cancelled, the true dispatch backlog was somewhat higher.
- **Calendar days.** Days in stage include Sundays and holidays; the [weekend postings test](../../04_data_quality_and_reconciliation/14_weekend_holiday_postings/) shows dispatch dates follow calendar days.
- **2027 growth** uses the last 12 months' order growth (18.7 %); a different growth rate scales the 2027 figures in proportion.
- **Peaks scaled with volume.** The 2027 95th-percentile day assumes peaks grow in proportion to the average.
- **End of period.** Shipments made just before 30 Sep 2026 are not yet delivered, so the delivered-only transit count falls near the end of the data; the yearly comparison is barely affected.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, daily and yearly tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
