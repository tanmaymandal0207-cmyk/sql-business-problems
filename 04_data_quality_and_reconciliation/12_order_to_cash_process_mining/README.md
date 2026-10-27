# Case Study · Order-to-Cash Process Mining

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. An event log of 40,565 events (10,000 orders, 10,031 dispatches, 9,966 deliveries, 10,568 payments) rebuilt from the transaction tables and mined for paths, timings and deviations.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-27 |

---

## 1. Business problem

Finance and operations describe order-to-cash as one simple flow: order, dispatch, delivery, payment. The ERP project team is about to configure workflow rules and approval steps on that basis. Before it hard-codes the flow, it wants evidence of how orders really move through the system: which paths exist, how common they are, where the time goes, and which departures from the flow are deliberate and which are errors.

## 2. Business questions

1. Which paths do orders actually take, and how many distinct paths (variants) are there?
2. How much of the volume follows the expected path?
3. Which paths are slow, and in which step is the time lost?
4. Which deviations follow a rule (policy) and which are errors?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order event, status |
| `shipments` | One row per shipment | Dispatch and delivery events |
| `payments` | One row per payment | Payment events |
| `sales_order_items` | One row per product per order | Order value (fully paid date) |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| **Event log** | One row per event: Order (`order_date`), Dispatch (`shipment_date`, one per shipment), Delivery (`delivery_date`, one per dated shipment), Payment (`payment_date`, one per payment) |
| Same-day order | Events on the same day are ordered Order < Dispatch < Delivery < Payment, so a same-day event never counts as a deviation |
| **Variant** | The ordered sequence of activities of an order, plus `[Cancelled]` or `[Returned]` as the end state |
| **Directly-follows relation** | An event and the next event of the same order, with the number of times it occurs and the days between |
| Fully paid date | Date of the payment that takes cumulative receipts to the order value (within ₹0.05) |
| Expected path | Order → dispatch(es) → delivery(ies) → payment(s), fully paid, with dispatch on or after the order date |
| Path group | Paid once after delivery · Paid in instalments after delivery · Advance payment (first payment before first dispatch) · Paid during delivery (first payment after dispatch, before the last delivery) · Delivered, not fully paid · In progress · Cancelled · Returned |

## 5. Analytical approach

1. **Event log** (`sahyadri_b2b.pm_events`), numbered within each order.
2. **Case table** (`sahyadri_b2b.pm_cases`). One row per order: variant, event counts, key dates, fully paid date, path group and cycle times for each step.
3. **Variant table** (`sahyadri_b2b.pm_variants`) with frequency and cumulative share, and the directly-follows relations (the process map).
4. **Path groups**: volume, value and time per step; payment paths by segment; the cost in days of paying in instalments.
5. **Conformance**: deviations from the expected flow, classified as error, policy, process or collections.

## 6. SQL techniques used

- Building an event log with `UNION ALL` from three transaction tables, and ordering ties with an activity rank
- Variants with `STRING_AGG(… ORDER BY event_no)`
- Directly-follows graph by joining each event to the next (`event_no + 1`)
- Running payment totals with `SUM() OVER (… ORDER BY …)` to date the moment an order is fully paid
- Pareto of variants with cumulative window sums
- Validation that recomputes the fully paid date with a self-join instead of a window and checks that each variant string has as many activities as the order has events

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Events = orders + shipments + dated deliveries + payments |
| 02 | Event numbers run 1..n without gaps in every order |
| 03 | One case per order, each with exactly one Order event |
| 04 | Dispatch, delivery and payment counts = source |
| 05 | **Fully paid date = a self-join recount** |
| 06 | Paid path groups have a fully paid date; the unpaid group has none |
| 07 | Variant orders add up to all orders; cumulative share ends at 1 |
| 08 | Activities in each variant = events of the order |
| 09 | Directly-follows transitions = events − orders |
| 10 | Order-to-cash = order-to-dispatch + dispatch-to-delivery + delivery-to-cash |

## 8. Findings

**There are 43 paths, but 8 cover 95 % of orders.** Only 56.8 % of orders follow the single textbook sequence.

| # | Variant | Orders | Cumulative | Average days order to cash |
|---:|---|---:|---:|---:|
| 1 | Order > Dispatch > Delivery > Payment | 5,677 | 56.8 % | 53.2 |
| 2 | Order > Dispatch > Delivery > Payment > Payment | 1,289 | 69.7 % | 78.4 |
| 3 | Order > Dispatch > Delivery (no payment yet) | 754 | 77.2 % | – |
| 4 | Order > [Cancelled] | 528 | 82.5 % | – |
| 5 | **Order > Payment > Dispatch > Delivery** | 490 | 87.4 % | **0.8** |
| 6 | Order > Dispatch > Delivery > Dispatch > Delivery > Payment | 327 | 90.6 % | 55.3 |
| 7 | Order > Dispatch > Delivery > Payment > Payment > Payment | 323 | 93.9 % | **104.7** |
| 8 | Order > Dispatch > Payment > Delivery | 131 | 95.2 % | 2.9 |

Counting split shipments and instalments as normal, **71.8 % of orders complete on the expected path**.

**Almost all the time is in waiting for payment.**

| From → to | Transitions | Average days | Median days |
|---|---:|---:|---:|
| Order → Dispatch | 8,894 | 4.0 | 3 |
| Dispatch → Delivery | 9,705 | 4.0 | 4 |
| **Delivery → Payment** | 7,816 | **44.7** | **42** |
| Payment → Payment (next instalment) | 2,062 | 24.8 | 25 |
| Delivery → Dispatch (back-order) | 488 | 6.2 | 6 |
| Order → Payment (advance) | 530 | 1.2 | 1 |

Physical fulfilment takes about 8–9 days; the cash step takes 45 days on average, and each extra instalment adds about 25.

| Path group | Orders | Share | Order value | Order → dispatch | Dispatch → delivery | Delivery → cash | Order → cash (median) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Paid once after delivery | 5,652 | 56.5 % | ₹56.77 crore | 4.0 | 4.7 | 44.6 | 51 |
| Paid in instalments after delivery | 1,539 | 15.4 % | ₹15.69 crore | 4.2 | 4.7 | **75.5** | **81** |
| Delivered, not fully paid | 1,425 | 14.3 % | ₹13.97 crore | 3.9 | 4.8 | – | – |
| Cancelled | 534 | 5.3 % | ₹4.61 crore | – | – | – | – |
| Advance payment | 516 | 5.2 % | ₹2.96 crore | 4.7 | 4.2 | −8.1 | **1** |
| Paid during delivery | 156 | 1.6 % | ₹0.78 crore | 2.1 | 6.3 | −2.9 | 2 |
| In progress | 103 | 1.0 % | ₹1.07 crore | | | | |
| Returned | 75 | 0.8 % | ₹0.63 crore | | | | |

**Instalments are the slowest path, and they are not small orders.**

| Payments per order | Fully paid orders | Average order value | Delivery → cash (days) |
|---:|---:|---:|---:|
| 1 | 5,652 | ₹1,00,441 | 44.6 |
| 2 | 1,203 | ₹1,04,109 | 69.8 |
| 3 | 336 | ₹94,132 | **96.1** |

**Paying before or during delivery is a segment rule, not random.**

| Segment | Completed orders | Advance payment | Paid during delivery | Paid once after | Instalments | Not fully paid |
|---|---:|---:|---:|---:|---:|---:|
| SMB | 1,928 | **20.0 %** | **6.4 %** | 50.4 % | 12.1 % | 11.0 % |
| Distributor | 1,867 | 7.0 % | 1.7 % | 61.3 % | 17.0 % | 13.0 % |
| Enterprise | 3,172 | **0.0 %** | **0.0 %** | 63.5 % | 17.6 % | 18.9 % |
| Mid-Market | 2,321 | **0.0 %** | **0.0 %** | 65.7 % | 18.4 % | 15.9 % |

Not one Enterprise or Mid-Market order in 33 months was paid before delivery. Advance payment is clearly applied only to SMB and some Distributor customers.

**Deviations from the expected flow**

| Deviation | Kind | Orders |
|---|---|---:|
| Dispatched before the order date | Error | 5 |
| Delivered status, no shipment record | Error | 4 |
| Delivered status, a shipment without a delivery date | Error | 10 |
| Shipped status, every shipment already delivered | Error (status not updated) | 5 |
| Cancelled, but payments received | Follow-up (refund or re-use) | 6 |
| Payment before dispatch | Policy | 518 |
| Payment while goods in transit | Policy or timing | 161 |
| Second dispatch after the first delivery | Process (back-order) | 488 |
| Delivered over 90 days ago, not fully paid | Collections | 885 |

- **True errors are rare: 24 orders (0.24 %)**, plus 6 cancelled orders with receipts to settle. Several match items already in the [data quality scorecard](../02_data_quality_scorecard/); the event log shows where in the flow each one sits.
- **Back-orders are a normal path**: 488 orders received a second dispatch after the first delivery, about 6 days later.

## 9. Business implications and recommendations

1. **Configure the ERP for eight paths, not one.** Split shipments, back-orders, instalments and advance payment together cover more than a quarter of orders and must be supported as normal flows, not exceptions requiring approval.
2. **Write the advance-payment rule down.** The data shows a consistent rule (SMB and some Distributors only). Making it an explicit customer-master setting lets the ERP enforce it and lets credit control see who is on advance terms.
3. **Target the cash step, not fulfilment.** Fulfilment takes 8–9 days; payment takes 45. A 10 % improvement in delivery-to-cash saves more days than a 50 % improvement in dispatch.
4. **Limit instalments.** Orders paid in three instalments take 96 days to cash, twice the single-payment path, with no difference in order size. Require approval for instalment plans and agree the schedule up front.
5. **Block the four status errors at source.** Dispatch dated before the order, Delivered status without shipment or delivery dates, and Shipped status after full delivery can each be prevented with a single validation rule in the ERP.
6. **Process the 6 cancelled orders with receipts** as refunds or credits on the customer account.

## 10. Assumptions and limitations

- **Dates, not timestamps.** Events on the same day are put in the logical order, so same-day deviations are not detected.
- **Cancellation and return have no date** in the data; they appear only as end states of a variant.
- **Invoicing is not recorded.** In a real ERP the invoice is a separate step between delivery and payment; here delivery is used as its proxy.
- **Fully paid** uses the line-item order value with NULL discounts treated as 0 %, consistent with the [order-to-cash reconciliation](../01_order_to_cash_reconciliation/).
- **Open orders are censored.** "Delivered, not fully paid" includes recent deliveries that are not yet due.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Event log, case and variant tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
