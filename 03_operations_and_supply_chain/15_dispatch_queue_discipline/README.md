# Case Study · Dispatch Queue Discipline: Is It First Come, First Served?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 9,412 dispatched orders and 638,635 pairs of orders placed one to seven days apart, compared with what random dispatch timing would produce, plus a first-in-first-out (FIFO) simulation at the same daily capacity.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-29 |

---

## 1. Business problem

Customers complain that an order placed on Monday sometimes ships after one placed on Wednesday. The warehouse manager says orders are picked in the order they arrive, except for urgent key-account orders. The [dispatch holds](../11_dispatch_holds/) study found one order in nine waiting one to three weeks in a separate queue. The operations head now wants to know whether the normal queue is first come, first served, and what a strict FIFO rule would change, before rewriting the picking procedure.

## 2. Business questions

1. How often is an earlier order dispatched after a later one?
2. Is that more than random dispatch timing would produce?
3. Do key-account (Enterprise) orders jump the queue?
4. What would strict FIFO dispatch change for waiting times and on-time delivery?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order and promise dates, status |
| `shipments` | One row per shipment | Dispatch and delivery dates |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Dispatch date | First shipment date of the order |
| Wait (lag) | Dispatch date − order date (5 orders shipped before they were placed are excluded) |
| Pair | Two orders placed 1–7 days apart |
| **Overtaken** | The earlier order was dispatched on a later date than the later order |
| Same day | Both dispatched on the same date |
| **Expected if random** | If waits do not depend on order sequence, P(overtaken \| gap g) = P(L₁ − L₂ > g) for two independent waits drawn from the observed wait distribution |
| **FIFO simulation** | Keep the actual number of dispatches on each day, but give the k-th earliest order the k-th earliest dispatch slot (never before its own order date). Delivery = simulated dispatch + the order's actual transit time. |

## 5. Analytical approach

1. **Order table** (`sahyadri_b2b.fq_orders`): dispatch date and wait for each order.
2. **Pairs** (`sahyadri_b2b.fq_pairs`) and the **random-timing expectation** (`sahyadri_b2b.fq_expected`): overtaking by gap, by the later order's segment, and with long holds removed.
3. **FIFO simulation** (`sahyadri_b2b.fq_fifo`): waiting-time distribution and on-time delivery under strict FIFO.

## 6. SQL techniques used

- A pairwise self-join on a date window to measure order sequence violations (a discordant-pair count, as in Kendall's tau)
- The distribution of a difference of two independent variables, built with a `CROSS JOIN` of the empirical distribution with itself
- A FIFO re-sequencing that matches two `ROW_NUMBER()` sequences (orders and dispatch slots)
- Validation that the simulation preserves daily capacity and total waiting time, and has no overtaking

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order dispatched on or after its order date |
| 02 | Wait = dispatch date − order date, never negative |
| 03 | **Pairs = a recount from daily order counts** |
| 04 | Overtaken exactly when earlier wait − later wait > gap |
| 05 | Expected probabilities lie in 0–1 and fall as the gap grows |
| 06 | **FIFO keeps the number of dispatches on every day** |
| 07 | Under FIFO no earlier order leaves after a later one |
| 08 | FIFO never dispatches before the order date |
| 09 | FIFO delivery = FIFO dispatch + actual transit |
| 10 | Total waiting days are the same under both policies |

## 8. Findings

**The dispatch sequence ignores the order sequence completely.**

| Days between the two orders | Pairs | Earlier order overtaken | Expected if dispatch were random | Same-day dispatch | Expected |
|---:|---:|---:|---:|---:|---:|
| 1 | 95,769 | **27.0 %** | 26.9 % | 14.5 % | 14.6 % |
| 2 | 85,454 | 17.1 % | 17.3 % | 9.5 % | 9.6 % |
| 3 | 85,638 | 12.5 % | 12.4 % | 5.1 % | 4.9 % |
| 4 | 85,097 | 10.7 % | 10.4 % | 2.0 % | 2.0 % |
| 7 | 106,568 | 8.1 % | 8.1 % | 0.8 % | 0.7 % |

- An order placed a day earlier is dispatched later in 27 % of cases, exactly what random timing produces. **There is no queue discipline at all**: not even a weak tendency to ship older orders first.
- Even an order placed a full week earlier is overtaken 8 % of the time.

**Nobody jumps the queue on purpose.** The earlier order is overtaken 19.3 % of the time when the later order is a Distributor's, 19.4 % for Enterprise, 18.9 % Mid-Market and 19.1 % SMB (gaps of 1–3 days).

**The normal queue is also disordered, not just the long holds.** With both orders dispatched within six days, an order placed a day earlier is still overtaken 20.6 % of the time and 8.5 % at two days.

**Strict FIFO at the same capacity would remove long waits and cut late deliveries by 17 %.**

| Policy | Average wait | Median | 90th percentile | 99th percentile | Longest | Waited 7+ days |
|---|---:|---:|---:|---:|---:|---:|
| Actual | 4.03 days | 3 | **9** | **21** | **22** | **11.7 %** |
| Strict FIFO, same daily dispatches | 4.03 days | 4 | **5** | **6** | **7** | **0.1 %** |

| Delivered orders with a promise date | Actual | Strict FIFO |
|---|---:|---:|
| On time | 81.7 % | **84.9 %** |
| Late | 1,672 | **1,381** (−291) |

- **The average wait does not change** (4.03 days): FIFO does not need more capacity, it shares the same waiting more evenly. The median rises from 3 to 4 days, but no order waits more than a week.
- The on-time gain is smaller than removing holds entirely (see [dispatch holds](../11_dispatch_holds/)), because under FIFO the orders that used to ship in 1–2 days wait about 4.

## 9. Business implications and recommendations

1. **Introduce a FIFO pick list.** Print or display the dispatch queue sorted by order date (then order number), with an exception code for any order picked out of sequence. On this data it ends waits of a week or more without adding capacity.
2. **Make priority explicit if it is wanted.** Key accounts get no priority today. If they should, define the rule (for example, Enterprise orders enter the queue one day ahead) and measure it with the overtaking table.
3. **Combine FIFO with shorter promises where it helps.** With waits capped at about a week, promise dates can be set from the [city promise standards](../05_promise_date_standards/) with more confidence.
4. **Monitor overtaking monthly.** The share of pairs one day apart that ship in reverse order should fall from 27 % towards the small number of documented exceptions.
5. **Investigate how dispatch is actually sequenced.** A dispatch order indistinguishable from random suggests picking by location, by product availability or by whoever asks; the [weekend postings test](../../04_data_quality_and_reconciliation/14_weekend_holiday_postings/) also suggests dispatch dates may be recorded rather than observed.

## 10. Assumptions and limitations

- **Daily capacity held fixed.** The simulation keeps the actual number of dispatches per day; real capacity might differ under a new rule.
- **Transit time unchanged.** Each order keeps its actual transit time; consolidating loads differently could change it.
- **Orders, not shipments.** Split orders are timed by their first shipment.
- **Stock availability** is not recorded. Some out-of-sequence dispatches may wait for stock; FIFO assumes stock is available when the order reaches the front of the queue.
- **Dates, not times.** Orders placed on the same day are not compared with each other.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, pair, expectation and FIFO tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
