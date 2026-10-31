# Case Study · Dispatch Capacity: How Many Orders a Day Must the Warehouse Ship?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. A first-in-first-out dispatch queue simulated exactly in SQL for eight daily capacities, on the last 12 months of orders (3,993) and on a 2027 scenario with 18.7 % more orders (4,713), compared with what the warehouse actually ships.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-31 |

---

## 1. Business problem

The [Little's Law](../16_littles_law_backlog_planning/) study showed that the dispatch queue must fall from 4.0 to about 3.4 days in 2027 to stop the backlog growing with an 18.7 % rise in orders. The warehouse manager needs that turned into a staffing number: how many orders a day must the team be able to pick, pack and ship? Before hiring she also wants to know whether today's waiting is caused by too little capacity at all.

## 2. Business questions

1. With strict first-in-first-out dispatch, what waiting time does each daily capacity give?
2. Is capacity what keeps orders waiting today?
3. What capacity does 2027 need, and how much extra in the peak months?
4. Can the 2027 target be met without extra capacity?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, status |
| `shipments` | One row per shipment | First dispatch date |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Arrivals | Orders that entered the dispatch queue (shipped, or Pending / Processing), by order date, Oct 2025 – Sep 2026 |
| 2027 scenario | The same arrivals plus a copy of a random 18.7 % of them (the last 12 months' order growth), chosen by integer hash |
| **FIFO queue with capacity c** | Up to c orders ship each day, every day, oldest first; an order can ship on its order date |
| **Cumulative departures** | D(t) = MIN over s ≤ t of [A(s) + c × (t − s)], with A(s) the orders arrived by day s and A(0) = 0. Order k (in arrival order) ships on the first day with D(t) ≥ k. |
| Utilisation | Orders per day ÷ c |
| Held order | An actual order dispatched 7 or more days after it was placed (see [dispatch holds](../11_dispatch_holds/)) |

## 5. Analytical approach

1. **Arrivals** (`sahyadri_b2b.cs_arrivals`) for today and 2027.
2. **Daily departures** (`sahyadri_b2b.cs_days`) for capacities of 11–20 orders a day, by the closed-form queue formula.
3. **Simulated waits** (`sahyadri_b2b.cs_waits`) for every order and capacity; waiting-time distribution.
4. **Today's reality**: actual waits, holds and what the warehouse ships per day.
5. **2027 by month**: where the queue builds.

## 6. SQL techniques used

- An exact queue simulation without loops: cumulative arrivals with `SUM() OVER`, and cumulative departures with a running `MIN() OVER` of A(s) − c·s
- A range join that assigns each order to the day the departures pass its number
- A growth scenario built by duplicating a hash-selected share of real orders, keeping the real calendar pattern
- Validation that the closed form equals the day-by-day recursion, that no day ships more than c, and that the queue is first in, first out

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Today = every queue order of the 12 months; 2027 = today plus copies |
| 02 | Arrival numbers run 1..n in date order |
| 03 | Arrivals by the last day = all arrivals |
| 04 | **Departures follow D(t) = MIN(A(t), D(t−1) + c)** (the recursion the closed form replaces) |
| 05 | Every arrival ships exactly once at every capacity |
| 06 | **First in, first out, and never before the order date** |
| 07 | No day ships more than the capacity |
| 08 | Orders shipped each day = D(t) − D(t−1) |
| 09 | Actual waits = first shipment − order date |
| 10 | 2027 copies = the growth share of today's orders |

## 8. Findings

**Capacity is not what keeps orders waiting today.**

| Today (Oct 2025 – Sep 2026) | Value |
|---|---:|
| Orders arriving per day | 10.94 (busiest day 30) |
| Orders actually shipped per day: average / median | 10.82 / 11 |
| Orders shipped on the busiest 5 % of days | 17 or more |
| Busiest dispatch day | **29** |
| Actual average wait | 4.05 days |
| Held orders (7+ days) | 12.0 %, waiting 14.3 days on average |
| Average wait of orders not held | **2.65 days** |

| Capacity a day (today's orders) | Utilisation | Average wait | 90th percentile | 99th percentile | Longest | Shipped within a day |
|---:|---:|---:|---:|---:|---:|---:|
| 11 | 99.5 % | 5.88 days | 13 | 16 | 18 | 18.5 % |
| 12 | 91.2 % | 1.70 | 4 | 8 | 9 | 58.7 % |
| 13 | 84.2 % | **0.86** | 2 | 6 | 7 | 82.2 % |
| 14 | 78.1 % | 0.50 | 2 | 4 | 5 | 89.1 % |
| 16 | 68.4 % | 0.16 | 1 | 1 | 2 | 99.2 % |

- The warehouse has shipped up to 29 orders in a day, and 17 or more on one day in twenty. With that capacity every day and first-in-first-out, the average order would wait well under a day.
- **Orders that are not held still wait 2.65 days**, three times what a 13-a-day FIFO queue would produce. The normal wait is handling time and the order in which work is picked up (the [FIFO study](../15_dispatch_queue_discipline/) found the sequence is random), not a queue for scarce capacity.

**2027: below 15 orders a day the queue starts to bite.**

| Capacity a day (2027 orders, 12.91 a day) | Utilisation | Average wait | 99th percentile | Longest |
|---:|---:|---:|---:|---:|
| 13 | 99.3 % | 5.53 days | 16 | 17 |
| 14 | 92.2 % | **1.91** | 9 | 10 |
| 15 | 86.1 % | 1.08 | 6 | 8 |
| 16 | 80.7 % | **0.68** | 4 | 6 |
| 18 | 71.7 % | 0.26 | 2 | 3 |

| 2027 month | Orders | Average wait at 13 a day | at 14 | at 15 |
|---|---:|---:|---:|---:|
| April | 337 | 13.61 days | **5.15** | 2.16 |
| March | 529 | 11.15 | **5.07** | 3.87 |
| January | 378 | 6.33 | 2.68 | 0.52 |
| December | 485 | 3.64 | 2.30 | 1.15 |

- The March financial-year-end peak builds a queue that a 14-a-day team is still clearing in April.

**The 2027 target can be met by ending long holds.** Holds beyond six days add 0.99 days to today's average wait. Releasing held orders within six days would bring the average from 4.05 to about 3.06 days, below the 3.4-day target, with no extra capacity.

## 9. Business implications and recommendations

1. **Do not hire for 2027 on the strength of the average wait.** The waiting today comes from holds and handling, not from too few hands.
2. **Plan a standing capacity of 16 orders a day for 2027**, close to what the team already achieves on its busiest 5 % of days; at that level queueing adds under a day even at peak.
3. **Add temporary capacity for March and April.** Even at 15 a day, March orders would wait 3.9 days on average; the year-end surge needs a short-term team or overtime on top of the standing capacity.
4. **End holds of more than six days.** This alone brings the average wait below the 2027 target (see [dispatch holds](../11_dispatch_holds/) for who holds orders and why).
5. **Attack handling time with a FIFO pick list.** A non-held order waits 2.65 days where the queue alone would cost under one; a daily pick list sorted by order date with a same-day/next-day standard targets that gap.

## 10. Assumptions and limitations

- **Capacity in orders, not lines or weight.** Large orders take longer to pick; a capacity in lines would refine the staffing number.
- **Seven-day working.** Dispatch dates fall on every day of the week in the data (see the [weekend postings test](../../04_data_quality_and_reconciliation/14_weekend_holiday_postings/)); a six-day week needs about a sixth more daily capacity.
- **Same calendar for 2027.** The growth scenario keeps 2025–26's daily pattern; a different peak shape would move the monthly figures.
- **No holds or stock shortages in the simulation.** It measures queueing alone; real waits add handling time and holds on top.
- **Queue starts empty** on 1 October 2025; the effect on a 12-month average is negligible.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Arrival, daily departure and wait tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
