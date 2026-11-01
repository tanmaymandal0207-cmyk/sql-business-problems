# Case Study · Dispatch by Deadline: The Capacity Needed to Keep Every Promise

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Every shipped order from October 2025 to September 2026 is given a dispatch deadline: its promised date less the usual transit time to its city. The study finds the least daily capacity that meets every deadline when orders ship deadline-first, compares it with first-in-first-out dispatch, and tests a seasonal capacity plan. It also checks what the warehouse actually missed.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-01 |

---

## 1. Business problem

The [dispatch capacity](../17_dispatch_capacity_simulation/) study sized the warehouse for a first-in-first-out queue. Customers, however, are promised different dates. A pump promised in 20 days can wait; a valve promised in 5 days to a city 4 days away cannot. The [queue discipline](../15_dispatch_queue_discipline/) study found that dispatch order is effectively random and recommended a first-in-first-out pick list. The operations head wants to know whether shipping by deadline instead of by arrival would do better, what capacity it needs, and why 18 % of deliveries are late when the warehouse ships about as many orders as arrive.

## 2. Business questions

1. With deadline-first dispatch, what is the least daily capacity that meets every dispatch deadline?
2. How much more does first-in-first-out dispatch need for the same result?
3. When in the year is the requirement set, and can capacity flex by season?
4. How many deadlines are actually missed, and is it a capacity problem?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, promised delivery date |
| `shipments` | One row per shipment | First dispatch, final delivery, shipping city |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Orders | Orders placed 1 Oct 2025 – 30 Sep 2026 that have shipped and have a promised date (3,878). Day 0 = 1 Oct 2025. Shipping is possible every day, including the order date. |
| Planned transit | Median days from first shipment to final delivery for the shipping city, on orders before October 2025. City names are standardised first (case, spacing and aliases such as Bombay → Mumbai, as in the [ship-to / bill-to reconciliation](../../04_data_quality_and_reconciliation/08_ship_to_bill_to_reconciliation/)). Cities with fewer than 20 such orders use the overall median. |
| **Dispatch deadline** | Promised date − planned transit, never earlier than the order date. Slack = deadline − order date. |
| **Deadline-first (EDF) feasibility** | With c orders a day, every deadline can be met if and only if, for every window of days [s, t], the orders that arrive on or after s and are due by t number no more than c × (t − s + 1). This is Hall's condition; earliest-deadline-first dispatch then meets every deadline. The least capacity is the largest ratio, rounded up. |
| Seasonal plan check | The same test with the capacity summed over each window's days |
| **FIFO** | Oldest order first at c a day. Cumulative departures D(t) = MIN(c(t + 1), MIN over s ≤ t of A(s) + c(t − s)); order k ships on the first day D(t) ≥ k. |
| Average wait | The same for both rules at the same capacity, because both ship as many orders as they can each day; only the order of dispatch differs |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.dd_orders`) with order day, deadline, slack and actual dispatch.
2. **Windows** (`sahyadri_b2b.dd_all_windows`, `sahyadri_b2b.dd_windows`): for every start day, the orders due by each later deadline (66,961 windows), and the tightest window for each start.
3. **Least capacity**, the tightest windows, the requirement by month and a seasonal plan.
4. **FIFO** (`sahyadri_b2b.dd_fifo`) at 10–20 orders a day: missed deadlines and waits.
5. **Today**: actual misses, the link to late deliveries, and misses by slack.

## 6. SQL techniques used

- A scheduling feasibility test in pure SQL: for each start day, `ROW_NUMBER()` over deadlines counts the orders due by each date, so one pass gives every window's load
- A cumulative-capacity join that checks a capacity plan varying by season against every window
- The closed-form FIFO queue from the dispatch capacity study, with a range join that assigns each order its ship day
- City-name standardisation through an inline alias table before the transit medians are computed

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders = shipped orders of the window with a promised date; numbered 1..n |
| 02 | Deadline = promised date − planned transit, never before the order date |
| 03 | One tightest window for every day on which orders arrive |
| 04 | **Window counts = a direct recount of orders arriving after s and due by t** |
| 05 | **The least capacity fits every window; one order a day less does not** |
| 06 | FIFO: every order ships exactly once at each of 11 capacities, never before its order date |
| 07 | FIFO: no day ships more than the capacity; orders ship in arrival order |
| 08 | FIFO never idles: a day below capacity leaves nobody waiting |
| 09 | Missed flag = ship day after deadline |
| 10 | Window ratio = orders ÷ days; the tightest window per start day is kept |

A separate day-by-day simulation of deadline-first dispatch confirmed the theory: 0 missed deadlines at 12 a day, 550 at 11, and 0 under the seasonal plan.

## 8. Findings

**Orders arrive at 10.6 a day with 8.6 days of slack on average.**

| | Value |
|---|---:|
| Orders | 3,878 (10.62 a day) |
| Average promise | 12.6 days |
| Average planned transit | 4.0 days |
| Average slack to the dispatch deadline | 8.6 days |
| Orders with 3 days of slack or less | 333 (13 must ship on the order day) |

**Deadline-first dispatch needs 12 orders a day. First-in-first-out needs 17.**

| Capacity a day | FIFO missed deadlines | FIFO worst lateness | Deadline-first | Average wait (either rule) |
|---:|---:|---:|---|---:|
| 11 | 762 (19.7 %) | 15 days | Some missed | 4.44 days |
| **12** | 124 (3.2 %) | 8 days | **Every deadline met** | 1.50 days |
| 13 | 42 | 6 days | Every deadline met | 0.77 days |
| 14 | 11 | 4 days | Every deadline met | 0.46 days |
| 15 | 4 | 2 days | Every deadline met | 0.25 days |
| 16 | 2 | 1 day | Every deadline met | 0.15 days |
| **17** | **0** | 0 | Every deadline met | 0.10 days |

- At 12 a day the two rules ship the same orders each day with the same average wait. Deadline-first lets loose orders wait a little longer so that every tight one is on time; FIFO misses 124, mostly tight orders (20.4 % of those with 0–3 days of slack).
- Meeting every deadline in arrival order costs **5 more orders a day (42 % more capacity)**.

**The year-end peak sets the requirement, so capacity can flex.**

| Tightest window | Days | Orders due | Required a day |
|---|---:|---:|---:|
| **3 Mar – 4 Apr 2026** | 33 | 385 | **11.67** |
| 9 Feb – 4 Apr 2026 | 55 | 639 | 11.62 |
| 1 Dec 2025 – 4 Apr 2026 | 125 | 1,436 | 11.49 |

- Windows starting from October to March all need 12 a day because they all run into the March peak. Windows starting from April onward need 10 at most (the highest is 9.72, in August).
- **A seasonal plan of 12 a day from October to March and 10 a day from April to September meets every deadline.** It passes all 66,961 windows (the tightest at 99.5 % of capacity) and averages 11.0 a day, only 0.4 above the arrival rate.

**Today the warehouse misses 13 % of dispatch deadlines, and capacity is not the cause.**

| Actual, Oct 2025 – Sep 2026 | Value |
|---|---:|
| Missed dispatch deadlines | **510 (13.2 %)** |
| Average wait from order to dispatch | 4.03 days (1.50 would be possible at 12 a day) |
| Orders shipped per day: average / 90th percentile / most | 10.65 / 16 / 29 |
| Days shipping 12 or more | 156 |
| Late deliveries | 711 |
| … of which the dispatch deadline was missed | 453 (64 %) |
| … dispatched on time, late in transit | 258 |

| Slack | Orders | Actual wait | Actual missed | FIFO at 12 missed | Deadline-first at 12 |
|---|---:|---:|---:|---:|---:|
| 0–3 days | 333 | 3.6 days | **44.1 %** | 20.4 % | 0 % |
| 4–7 days | 1,342 | 4.3 days | 15.1 % | 4.2 % | 0 % |
| 8–11 days | 1,300 | 4.0 days | 8.8 % | 0.0 % | 0 % |
| 12+ days | 903 | 3.8 days | 5.1 % | 0.0 % | 0 % |

- **Tight and loose orders wait the same 4 days.** The warehouse does not sequence by deadline, so 44 % of the tightest orders miss.
- The warehouse ships 12 or more on 156 days and up to 29 in a day, so it has the capacity. As the dispatch capacity study found, the long waits come from holds rather than a lack of hands (see [dispatch holds](../11_dispatch_holds/)).

## 9. Business implications and recommendations

1. **Sort the pick list by dispatch deadline, not by order date.** This goes one step beyond the FIFO pick list proposed by the [queue discipline](../15_dispatch_queue_discipline/) study. Print each order's dispatch-by date (promised date less city transit) and work the list in that order. On last year's orders this alone would have met every deadline at 12 a day, where FIFO at 12 misses 124.
2. **Staff 12 a day from October to March and 10 from April to September.** This seasonal plan meets every deadline at an average of 11 a day. FIFO would need 17 a day all year.
3. **Clear holds first.** At the capacity already available, the average wait could be 1.5 days instead of 4. The [dispatch holds](../11_dispatch_holds/) study lists the causes.
4. **Flag orders with 3 days of slack or less at order entry.** There were 333 such orders last year, and 44 % missed. They need same-day or next-day dispatch or a longer promise (see [promise date standards](../05_promise_date_standards/)).
5. **Address transit separately.** 258 late deliveries were dispatched on time. Those are carrier and route problems (see [late delivery root cause](../01_late_delivery_root_cause/)).

## 10. Assumptions and limitations

- **Shipping every day.** Like the dispatch capacity study, every calendar day is a shipping day. With a six-day week the daily figures rise by about a sixth.
- **One order = one unit of work.** Large or multi-shipment orders are not weighted.
- **Planned transit is a city median.** Up to half of the orders to a city take longer in transit, so a met dispatch deadline does not guarantee on-time delivery.
- **No starting backlog.** Orders placed before October 2025 that were still waiting are not in the queue.
- **Orders without a promised date** (72) are left out. They need capacity too, about 0.2 a day.
- **Hindsight.** The capacity figures are computed with knowledge of every order. A live plan needs a margin above them for forecast error.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, window and FIFO tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
