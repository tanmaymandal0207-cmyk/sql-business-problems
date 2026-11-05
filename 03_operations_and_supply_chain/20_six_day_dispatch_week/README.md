# Case Study · Can the Warehouse Close on Sundays?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study uses the 3,878 orders and dispatch deadlines of the [dispatch by deadline](../18_deadline_based_dispatch/) study, with Sunday dispatch removed. It finds the least daily capacity that still meets every deadline on a six-day week (Hall's condition over 57,751 windows), compares it with the seven-day week in staff-days, and repeats the comparison for first-in-first-out dispatch.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-05 |

---

## 1. Business problem

The warehouse ships seven days a week, although customers hardly order on Sundays. The new operations head wants to close on Sundays, so staff get a weekly day off and the Sunday premium is saved. Sales fear that customer promises would slip. She wants to know what a six-day week needs in daily capacity, and whether that means more staff in total or simply the same work spread over six days.

## 2. Business questions

1. How much of today's dispatch happens on Sundays, and how much work arrives on Sundays?
2. On a six-day week, what daily capacity still meets every dispatch deadline if orders ship deadline-first?
3. Is that more or fewer staff-days than the seven-day week?
4. What happens with first-in-first-out dispatch instead?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order and promised dates |
| `shipments` | One row per shipment | Dispatch and delivery dates, city, weekday of dispatch |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Orders and deadlines | As in the dispatch-by-deadline study: orders placed 1 Oct 2025 – 30 Sep 2026 that have shipped and have a promised date. The deadline is the promised date minus the median transit time to the city, and never earlier than the order date. |
| **Six-day week** | No dispatch on Sundays. A deadline falling on a Sunday moves to the Saturday before. If an order arrives on that same Sunday with no slack, it is a forced one-day miss. |
| **Deadline-first feasibility** | For every window of days [s, t], the orders arriving on or after s and due by t must fit within c × the working days in the window. The least capacity is the largest ratio, rounded up. |
| Order slots per week | Capacity per working day × working days per week: a measure of staff-days |
| **FIFO on working days** | D(t) = c·W(t) + MIN(0, running MIN of A(s) − c·W(s)), where W(t) is the number of working days up to day t and A(s) is the number of orders arrived by day s |
| Missed | Shipped after the original (seven-day) deadline |

## 5. Analytical approach

1. **Calendar** (`sahyadri_b2b.sw_days`): days, Sundays and running working-day count.
2. **Orders** (`sahyadri_b2b.sw_orders`): seven-day and six-day deadlines; today's dispatch by weekday.
3. **Windows** (`sahyadri_b2b.sw_windows`): Hall's condition for both weeks, least capacity and order slots.
4. **FIFO** (`sahyadri_b2b.sw_fifo`) on a six-day week at 12–21 orders a day.

## 6. SQL techniques used

- A working-day calendar with a running count (`SUM(IF(Sunday, 0, 1)) OVER (ORDER BY day)`), which turns any window into its capacity days by subtraction
- Hall's condition with time-varying capacity: window load ÷ working days in the window
- The closed-form FIFO queue generalised to capacity that is zero on some days
- A day-by-day deadline-first simulation outside SQL as a cross-check (0 missed at 14 a day, 278 at 13)

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders = shipped orders of the window with a promised date (3,878) |
| 02 | Working-day count rises by one except on Sundays, which fall every seventh day |
| 03 | Six-day deadlines never fall on a Sunday and move at most one day |
| 04 | Tightest six-day window = a direct recount of orders |
| 05 | **Six-day least capacity fits every window; one order a day less does not** |
| 06 | Window capacity days = working days in the window (recount) |
| 07 | **FIFO never ships on a Sunday or above capacity** |
| 08 | FIFO ships every order once per capacity, never before it arrives |
| 09 | FIFO never idles on a working day while orders wait |
| 10 | Seven-day windows use calendar days, one start per arrival day |

## 8. Findings

**Sunday is a full dispatch day, but almost no work arrives on Sundays.**

| Weekday | Shipments | Share |
|---|---:|---:|
| Mon | 562 | 13.2 % |
| Tue | 479 | 11.3 % |
| Wed | 567 | 13.3 % |
| Thu | 633 | 14.9 % |
| Fri | 660 | 15.5 % |
| Sat | 704 | 16.6 % |
| **Sun** | **645** | **15.2 %** |

- Only 55 of the 3,878 orders arrived on a Sunday. Sunday dispatch clears work that arrived earlier in the week.
- 550 orders have a deadline on a Sunday; with a six-day week they must ship by Saturday. No order would be forced late: none arrives on a Sunday with a same-day deadline.

**A six-day week needs 14 orders a day, the same 84 order slots a week as today's 12 × 7.**

| Week | Windows checked | Required per day (tightest window) | Least capacity | Order slots per week |
|---|---:|---:|---:|---:|
| Seven-day | 66,961 | 11.67 | 12 | **84** |
| **Six-day** | 57,751 | 13.66 | **14** | **84** |

- The tightest window is the same in both cases: 3 March – 4 April 2026, the year-end peak. On a six-day week it holds 396 orders due in 29 working days.
- At 14 a day on six days, deadline-first dispatch misses no deadline. At 13 a day it misses 278.
- **Closing on Sundays needs no extra staff-days.** The Sunday shift is moved into the other six days, about 17 % more capacity per open day.

**With first-in-first-out dispatch, the six-day week needs 18 a day.**

| Six-day capacity | Order slots a week | FIFO missed | Worst lateness | Average wait |
|---:|---:|---:|---:|---:|
| 13 | 78 | 453 (11.7 %) | 13 days | 3.14 days |
| **14** | 84 | 95 (2.5 %) | 9 days | 1.23 days |
| 15 | 90 | 36 | 6 days | 0.62 days |
| 16 | 96 | 11 | 4 days | 0.37 days |
| 17 | 102 | 4 | 2 days | 0.20 days |
| **18** | **108** | **0** | 0 | 0.10 days |

On a seven-day week FIFO needed 17 a day (119 slots). So in FIFO terms the six-day week also needs fewer slots, because shipping in arrival order already carries spare capacity.

## 9. Business implications and recommendations

1. **Close on Sundays, with deadline-sorted dispatch.** With 14 orders a day from Monday to Saturday, every dispatch deadline of the last year would have been met. That is the same 84 order slots a week as seven days at 12.
2. **Move the Sunday staff into the week, mainly Saturday and Monday.** Saturday absorbs the 550 Sunday deadlines, and Monday clears the Sunday arrivals.
3. **Do not close on Sundays while dispatch is first-in-first-out without adding capacity.** At 14 a day, FIFO would have missed 95 deadlines (2.5 %). Sort the pick list by deadline first (see [dispatch by deadline](../18_deadline_based_dispatch/)).
4. **Staff the year-end peak.** March sets the requirement in both weeks. On the seven-day week a seasonal plan saved capacity outside October–March; a six-day seasonal plan is probably possible too, but must pass the same window test before it is staffed.
5. **Clear holds as well.** The long waits seen today come from holds, not capacity (see [dispatch holds](../11_dispatch_holds/)); a six-day week will not fix those.

## 10. Assumptions and limitations

- **Same deadlines and orders as the dispatch-by-deadline study.** Transit is assumed not to depend on the weekday of dispatch, which holds in today's data.
- **One unit of work per order.** Large or multi-shipment orders are not weighted.
- **Customers' Sunday deliveries** (carriers delivering on Sundays) are unchanged; only dispatch stops.
- **No starting backlog,** and hindsight: the capacity is computed knowing every order. A live plan needs a margin.
- **The seasonal six-day plan in recommendation 4 is not tested here.**

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Calendar, order, window and FIFO tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
