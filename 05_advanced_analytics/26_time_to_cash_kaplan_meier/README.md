# Case Study · Time to Cash with Kaplan–Meier: Counting the Orders Not Yet Paid

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Days from delivery to settlement for 9,279 delivered orders (January 2024 – September 2026). The 1,419 orders not yet settled are counted as censored rather than dropped. The study compares Kaplan–Meier curves by segment and delivery half-year with paid-only figures, and re-tests the proposed payment terms.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-01 |

---

## 1. Business problem

The [payment behaviour](../02_customer_payment_behaviour/) study measured days to pay on fully paid orders only, and proposed payment terms from those figures. The credit controller points out that the slowest payers are exactly the ones missing: an order still unpaid today never enters a "days to pay" figure. Before the terms go into new contracts, she wants the same measures with unpaid orders counted for the time they have been waiting.

## 2. Business questions

1. How long does cash really take to arrive once unpaid orders are counted?
2. How much do paid-only figures understate it, by segment and for recent deliveries?
3. What share of orders is still not settled 30, 60, 90 and 180 days after delivery?
4. Are the proposed terms realistic?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, customer |
| `sales_order_items` | One row per product per order | Order value |
| `shipments` | One row per shipment | Final delivery date |
| `payments` | One row per payment | Payment dates and amounts |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Orders | Valid orders (not Cancelled or Returned) with every shipment delivered, final delivery 1 Jan 2024 – 30 Sep 2026 |
| Clock | Starts at final delivery |
| **Settled** | The first day cumulative payments reach 99 % of the order value (short payments under 1 % count as settled). Paid before delivery = day 0. |
| **Censored** | Not settled by 30 Sep 2026; observed for the days since delivery |
| **Kaplan–Meier S(t)** | Share of orders still not settled after t days = the product over each day u ≤ t of (1 − settled on day u ÷ still waiting at the start of day u). It uses every order for as long as it has been observed. |
| KM median | The first day with S(t) ≤ 50 % |
| Restricted mean | Area under S(t) over the first 365 days: average days to cash within the first year, where an order never paid counts 365 |
| Greenwood interval | 95 % confidence interval for S(t) |
| **Paid-only** | The same orders, fully settled ones only (the payment behaviour study's method) |
| Follow-up limit | A curve is not read beyond the longest time any of its orders has been followed |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.tc_orders`): delivery, settlement and days to cash or days waiting.
2. **Curves** (`sahyadri_b2b.tc_curves`): Kaplan–Meier step by step for the company, each segment and each delivery half-year.
3. **Summary** (`sahyadri_b2b.tc_summary`): KM medians, restricted means and S at 30, 60, 90 and 180 days, set against paid-only figures.
4. **Terms**: the share of each segment beyond the proposed term, paid-only against KM.

## 6. SQL techniques used

- A survival estimator in pure SQL: at-risk counts from a reverse running sum, and the product limit as `EXP(SUM(LN(1 − d/n)))`
- Greenwood standard errors from a second running sum
- Step-function reads ("S at day 90") with `ROW_NUMBER()` over steps on or before the day
- A restricted mean as the area under the step curve, and a day-by-day recount in validation

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per valid, fully delivered order of the period |
| 02 | **Settled on the first day payments reach 99 %, and never otherwise** |
| 03 | Days = settlement − delivery (0 if paid before), else as-of − delivery |
| 04 | At risk on the first day = group size; leavers add up to it |
| 05 | At risk falls by the previous day's leavers |
| 06 | Survival never rises and stays between 0 and 1 |
| 07 | **Kaplan–Meier lies between the "censored = paid at once" and "censored = never paid" bounds** |
| 08 | Segment and half-year groups add up to the company |
| 09 | Median = first day with S ≤ 0.5 |
| 10 | Restricted mean = sum of daily S(t) over the first 365 days |

The company curve was also recomputed independently outside SQL, with the same median (51 days), S(90) (18.71 %) and restricted mean (80.5 days).

## 8. Findings

**Counting unpaid orders adds 6 days to the median and 34 days to the average.**

| Company | Paid-only | Kaplan–Meier |
|---|---:|---:|
| Orders used | 7,860 | 9,279 (1,419 censored) |
| Median days to cash | 45 | **51** |
| Average days to cash | 46.9 | **80.5** (within the first year) |
| Still not settled after 30 days | | 73.3 % |
| … after 60 days | | 38.6 % |
| … after 90 days | | 18.7 % (± 0.8) |
| … after 180 days | | **10.3 %** |

- The median moves little because most orders do get paid. The average moves a lot because about **one order in ten is still unsettled after 180 days**: 776 orders have been open for longer than that. Receivables that old are rarely collected (see [collections forecast](../17_monte_carlo_collections_forecast/)).

**Every segment has the same unpaid tail.**

| Segment | Orders | Censored | Paid-only median | KM median | Not settled at 30 / 60 / 90 days | At 180 days | KM average (1st year) |
|---|---:|---:|---:|---:|---|---:|---:|
| SMB | 1,924 | 212 | 10 | 12 | 25.8 / 15.2 / 10.4 % | 9.4 % | 49.3 |
| Distributor | 1,868 | 244 | 30 | 31 | 52.8 / 23.0 / 12.6 % | 9.0 % | 65.7 |
| Mid-Market | 2,319 | 367 | 42 | 45 | 92.8 / 32.5 / 17.1 % | 10.2 % | 83.0 |
| Enterprise | 3,168 | 596 | 65 | 69 | **100.0** / 66.5 / 28.5 % | **11.6 %** | **105.9** |

- Segments differ in how fast they pay, but not in how often an order is never settled (9–12 % at 180 days). SMB customers pay in 12 days at the median, yet 9.4 % of their orders are still open at 180 days. Their paid-only average of 16 days triples to 49 once those orders are counted.
- No Enterprise order is settled within 30 days.

**Paid-only figures make the latest deliveries look 17 days faster.**

| Delivered | Orders | Censored | Longest follow-up | Paid-only median | KM median |
|---|---:|---:|---:|---:|---:|
| 2024 H1 | 1,324 | 140 | 999 days | 45 | 50 |
| 2024 H2 | 1,496 | 168 | 820 | 46 | 51 |
| 2025 H1 | 1,724 | 167 | 637 | 44 | 49 |
| 2025 H2 | 1,783 | 193 | 454 | 48 | 53 |
| 2026 H1 | 1,987 | 207 | 272 | 45 | 50 |
| **2026 Jul–Sep** | 965 | **544** | 90 | **32** | **49** |

- On the Kaplan–Meier view payment speed has not changed: the median sits at 49–53 days in every half-year.
- The paid-only median for July–September 2026 deliveries is 32 days. This is not because customers sped up: 544 of the 965 orders are not settled yet, and the slow ones are the ones missing. A paid-only DSO report would show a false improvement every month.

**Each proposed term is missed more often than the paid-only figures suggest.**

| Segment | Proposed term | Beyond term: paid-only | Beyond term: Kaplan–Meier |
|---|---:|---:|---:|
| Enterprise | 60 days | 61.3 % | **66.5 %** |
| Distributor | 30 days | 47.2 % | 52.8 % |
| Mid-Market | 45 days | 41.8 % | 48.5 % |
| SMB | 15 days | 33.9 % | 40.7 % |

## 9. Business implications and recommendations

1. **Report time to cash with Kaplan–Meier, not paid-only averages.** Use the KM median and the share unsettled at 30, 60 and 90 days. Paid-only figures flatter every recent month.
2. **Plan cash on 51 days at the median and 81 days on average,** not 45 and 47. The difference is the unpaid tail, which ties up cash for the whole year.
3. **Treat the 10 % tail as a credit problem in every segment.** Even SMB, the fastest payer, leaves 9 % of orders unsettled at 180 days. Credit holds (see [customer credit limits](../../01_customer_and_revenue/17_customer_credit_limits/)) and early follow-up in the first 90 days matter more than faster terms.
4. **Set terms knowing how many will miss.** Under the proposed terms, two-thirds of Enterprise orders and about half of Distributor and Mid-Market orders would breach on today's behaviour. Pair the terms with reminders at the term date and an escalation at 30 days past it.
5. **Fix the payment-status flag.** Four orders flagged Unpaid are fully paid in the payments table.

## 10. Assumptions and limitations

- **Settlement at 99 %.** Short payments under 1 % count as settled; a part-paid order counts as not settled, however much has been paid.
- **Order counts, not rupees.** Each order counts once. A value-weighted view would give more weight to large Enterprise orders.
- **Censoring is assumed to be uninformative** within each group: an open order is assumed to pay like other orders that have waited as long. Very old open orders are probably worse than that, so the tail is if anything understated.
- **Clock from final delivery.** Orders paid before delivery count as day 0.
- **The latest half-year is short** (July–September 2026, at most 90 days of follow-up); its 180-day figure is not read.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, curve and summary tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
