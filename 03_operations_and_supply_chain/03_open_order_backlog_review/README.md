# Case Study · Open Order Backlog Review

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. As-of date: 30 Sep 2026 (month-end).

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-19 |

---

## 1. Business problem

At every month-end the operations manager reviews orders that are still **open** (Pending, Processing or Shipped). The open-order list is meant to show work in progress, but nobody checks whether it is accurate. An order can sit as "Shipped" long after it was delivered, which delays invoicing and collection. A shipment can also go missing in transit without anyone noticing. Before the September close, operations wants every open order checked and the problem orders listed for action.

## 2. Business questions

1. How many orders, and how much value, are open at month-end?
2. Which open orders are healthy, and which need action: overdue for dispatch, past the promised date, stuck in transit, or actually delivered but never closed?
3. How much money has already been received against orders the customer may not have received?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, dates, customer, salesperson |
| `sales_order_items` | One row per product per order | Order value |
| `shipments` | One row per shipment | Shipment status and dates |
| `payments` | One row per receipt | Amount already paid |

Shipments, payments and line items are each aggregated to order level before joining.

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Open order | `order_status` is Pending, Processing or Shipped |
| Days open | As-of date − order date |
| Days in transit | As-of date − date of the oldest shipment still In Transit |
| Days past promise | As-of date − promised delivery date (positive = overdue) |

**Review status**: each open order gets one status, in this order of priority:

| # | Review status | Rule | Action it implies |
|---|---|---|---|
| 1 | Delivered – status not updated | Shipped, and every shipment is Delivered | Close the order and invoice it |
| 2 | Stuck in transit | A shipment In Transit for more than 30 days | Trace with the carrier and confirm receipt with the customer |
| 3 | Overdue – not yet dispatched | Pending/Processing and the promise date has passed | Expedite dispatch and inform the customer |
| 4 | Overdue – in transit | Shipped and the promise date has passed | Track and inform the customer |
| 5 | No promised date | Promised delivery date missing | Record a promise date |
| 6 | On track | None of the above | None |

The 30-day threshold is generous: 90 % of delivered shipments arrive within 8 days (see [Late delivery root cause](../01_late_delivery_root_cause/)).

## 5. Analytical approach

1. **Open order review table** (`sahyadri_b2b.open_order_review`). One row per open order with value, amount paid, shipment counts, ageing and review status.
2. **Backlog summary** by review status.
3. **Cross-check** of review status against the recorded order status.
4. **Action list** of every open order that is not on track.

## 6. SQL techniques used

- Order-level pre-aggregation of shipments (`COUNTIF` by status, oldest in-transit date with `MIN(IF(...))`) and payments
- Ageing with `DATE_DIFF` against a declared as-of date, and a declared threshold (`stuck_days`)
- A priority-ordered `CASE` that gives each order exactly one review status
- Conditional pivot with `COUNTIF(review_status LIKE ...)`
- Window share of value with `SUM(SUM(...)) OVER ()`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order |
| 02 | Row count = open orders in the source (103) |
| 03 | Order value = line-item total for open orders |
| 04 | Amount paid = payments total for open orders, to the paisa |
| 05 | Shipment count = shipments table for open orders |
| 06 | Every order has a review status |
| 07 | No "Delivered – status not updated" order has a shipment in transit |
| 08 | Every "Stuck in transit" order exceeds the 30-day threshold |
| 09 | No "On track" order is past its promised date |
| 10 | In-transit + delivered shipments = total shipments on every open order |

## 8. Findings

**103 orders worth ₹1.07 crore are open at month-end. 26 of them (₹37.3 lakh, 34.9 % of open value) need action.**

| Review status | Orders | Value | Share of open value | Already paid |
|---|---:|---:|---:|---:|
| Delivered – status not updated | 5 | ₹20.2 lakh | 18.9 % | – |
| Stuck in transit | 5 | ₹2.0 lakh | 1.9 % | ₹1.75 lakh |
| Overdue – not yet dispatched | 7 | ₹7.6 lakh | 7.1 % | ₹0.14 lakh |
| Overdue – in transit | 6 | ₹5.7 lakh | 5.4 % | – |
| No promised date | 3 | ₹1.8 lakh | 1.7 % | – |
| On track | 77 | ₹69.7 lakh | 65.1 % | ₹0.75 lakh |

- **₹20.2 lakh of "open" orders have already been delivered.** Five orders are still marked Shipped although every shipment shows as delivered. They make up nearly a fifth of the open value. Until they are closed they may not be invoiced or chased for payment, and none has been paid yet. Two of them (₹18.5 lakh) belong to the company's largest customer.
- **Five shipments have been "in transit" for between 190 and 934 days.** The oldest left the warehouse in March 2024. **Four of the five customers have already paid in full (₹1.75 lakh).** Either the goods arrived and the record was never closed, or the shipments were lost and the customers paid for goods they did not receive. Both need resolving.
- **Seven orders are overdue for dispatch.** They are still in Processing 2 to 10 days after their promised delivery date (₹7.6 lakh). One customer has already paid.
- **Six shipped orders are past their promise date while in transit**, and three open orders have no promised date at all.
- **The recorded status alone is misleading.** Of the 58 orders marked Shipped, 5 are in fact delivered and 5 are stuck. Only the shipment records reveal this.

## 9. Business implications and recommendations

1. **Close and invoice the 5 delivered orders before month-end** (₹20.2 lakh). Then add a rule to the ERP that closes an order automatically once all its shipments are delivered. The same stale-status pattern appears in the [Data quality scorecard](../../04_data_quality_and_reconciliation/02_data_quality_scorecard/) (rule K02).
2. **Investigate the 5 stuck shipments with the carrier and the customers.** Confirm delivery with each customer. Raise carrier claims for any lost goods, and refund or redeliver where a customer has paid for goods not received.
3. **Expedite the 7 overdue Processing orders** and tell the customers the new dates before they chase.
4. **Run this review at every month-end** as part of the close checklist, with the action list (Step 4) assigned to named owners.
5. **Add an alert for any shipment in transit for more than 15 days.** That is roughly twice the normal maximum transit time, so stuck shipments are caught in weeks rather than years.

## 10. Assumptions and limitations

- **Snapshot.** The review describes open orders on 30 Sep 2026 only. Orders opened or closed afterwards are not reflected.
- **Shipment status is treated as the truth.** If shipment records are themselves out of date, some "stuck" orders may simply be unrecorded deliveries.
- **Thresholds.** The 30-day stuck threshold and the priority order of the statuses are business choices.
- **Value at risk.** Order value is shown in full for each problem order. Partly delivered orders may have only part of their value at risk.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Open order review table and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
