# Case Study · Dispatch Workload and Capacity Planning

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Period: 2 January 2024 to 30 September 2026 (1,003 days).

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-20 |

---

## 1. Business problem

The warehouse plans staff and vehicles on a flat daily average. Supervisors say some days and months are much busier than others. The [Late delivery root cause](../01_late_delivery_root_cause/) study also found that slow dispatch causes most late orders. Before renewing the staffing plan and the transport contract, operations wants to know **when** the work arrives, **how much capacity** a busy day needs, and whether **heavy days actually slow dispatch down**.

## 2. Business questions

1. How does dispatch volume vary by day of the week and by month?
2. How much daily capacity covers a normal day, a busy day and a peak day?
3. Does a heavy order intake make dispatch slower?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `shipments` | One row per shipment | Shipments per day |
| `sales_orders` | One row per order | Orders received per day; dispatch days |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Calendar | Every day from 2 Jan 2024 (first shipment) to 30 Sep 2026, generated with `GENERATE_DATE_ARRAY`. Days with no activity count as zero. |
| Shipments per day | Shipment records with that shipment date |
| Orders received per day | Orders with that order date |
| Seasonality index | Average shipments per day in the month ÷ average across the whole period × 100 |
| Capacity levels | **Normal:** median day · **Busy:** 90th percentile · **Peak:** 95th percentile |
| Dispatch days | First shipment date − order date |
| Intake band | Number of orders received on the order's own date: Light ≤ 8 · Normal 9–12 · Busy 13–16 · Heavy ≥ 17 |

## 5. Analytical approach

1. **Daily workload table** (`sahyadri_b2b.daily_dispatch_workload`). One row per calendar day with weekday, month, shipments and orders received.
2. **Weekday profile.** Orders in vs shipments out.
3. **Monthly seasonality index.**
4. **Capacity sizing** at the normal, busy and peak levels, with the number of days above each.
5. **Load vs speed.** Dispatch time for orders received on light, normal, busy and heavy days.

## 6. SQL techniques used

- A date spine with `UNNEST(GENERATE_DATE_ARRAY(...))` and `LEFT JOIN`, so quiet days are counted as zero
- Date parts with `EXTRACT(DAYOFWEEK …)`, `EXTRACT(MONTH …)` and `FORMAT_DATE`
- Percentiles with `PERCENTILE_CONT … OVER ()` for capacity levels
- A subquery in the `SELECT` for the seasonality index
- Banding and conditional rates with `CASE` and `COUNTIF`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per day |
| 02 | The calendar covers every day in the period (1,003) |
| 03 | Shipments = shipments table for the period |
| 04 | No shipment is dated outside the period |
| 05 | Orders received = orders dated within the period |
| 06 | The 9 orders outside the period are all on 1 Jan 2024, the day before the first shipment |
| 07 | Weekday names and numbers match one-to-one |
| 08 | All 12 months are present |
| 09 | No negative counts |
| 10 | Weekday totals add up to total shipments |

## 8. Findings

**Orders arrive on weekdays, but dispatch peaks at the weekend.**

| Day | Avg orders received | Avg shipments | Share of shipments |
|---|---:|---:|---:|
| Monday | 12.4 | 9.3 | 13.2 % |
| Tuesday | 12.9 | **7.7** | 11.0 % |
| Wednesday | 12.2 | 9.2 | 13.2 % |
| Thursday | 12.5 | 10.4 | 14.8 % |
| Friday | 12.1 | 11.1 | 15.8 % |
| Saturday | 6.7 | **11.7** | **16.6 %** |
| Sunday | 0.9 | 10.8 | 15.4 % |

Almost no orders arrive on Sunday, yet Sunday dispatches more than any day from Monday to Wednesday. The warehouse is clearing the week's backlog at the weekend, and Tuesday is the quietest dispatch day.

**March and December are peak months.**

| Month | Avg shipments per day | Index |
|---|---:|---:|
| March | 13.2 | **131** |
| December | 12.2 | **122** |
| September | 10.5 | 105 |
| April–August | 8.7–9.3 | 87–93 |

March is the Indian financial year-end, when customers spend remaining budgets. December is calendar year-end. April to August is the quiet season, about 10 % below average.

**Sizing capacity at the average leaves many days short.**

| Level | Shipments per day | Days above it in 1,003 |
|---|---:|---:|
| Average / median | 10 | 424 |
| Busy (90th percentile) | 15 | 92 |
| Peak (95th percentile) | 17 | 40 |
| Highest day | 30 | – |

Capacity planned for 10 shipments a day is exceeded on 42 % of days. Capacity for 15 covers 9 days in 10.

**Heavy intake does not slow dispatch.** Orders received on light, normal, busy and heavy days are all dispatched in about 4 days on average. Between 64 % and 66 % leave within 3 days, and 9–12 % take more than 8 days. Warehouse workload does not explain the slow-dispatch tail found in the late delivery study. That points to stock availability or order processing as the cause.

## 9. Business implications and recommendations

1. **Plan base capacity for a busy day, about 15 shipments, rather than the average of 10.** That covers 90 % of days and avoids building a backlog on 42 % of them.
2. **Add seasonal capacity for March and December** (index 131 and 122), for example temporary staff or extra vehicles agreed in the transport contract. Use April–August, about 10 % below average, for leave, training and stock counts.
3. **Move dispatch from the weekend into the week.** Orders arrive Monday to Friday, but Saturday and Sunday carry 32 % of shipments, often at weekend labour and transport rates. Same-day or next-day dispatch during the week, especially on quiet Tuesdays, reduces weekend work and shortens delivery times.
4. **Do not expect extra warehouse staff to fix late deliveries.** Dispatch speed is the same on heavy and light days. Investigate stock availability and order release for the slow orders instead (see the late delivery and open order backlog case studies).
5. **Refresh this view every quarter**, and track the share of days above the 15-shipment level as a capacity KPI.

## 10. Assumptions and limitations

- **Shipments, not effort.** Every shipment counts as one unit of work. A shipment of one motor and a shipment of 50 product lines are not distinguished.
- **No staffing or cost data.** The analysis sizes workload, not headcount or cost. Converting shipments into staff hours needs warehouse productivity data.
- **Weekend dispatch.** The data does not show whether weekend dispatches are a policy (for example a weekend shift) or backlog clearing. The interpretation should be confirmed with the warehouse.
- **Partial final year.** 2026 covers January–September only, so October–December averages come from 2024 and 2025 alone.
- **Excluded from the load-vs-speed test.** Orders dated 1 Jan 2024 (before the calendar starts) and 5 orders shipped before their order date.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Daily workload table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
