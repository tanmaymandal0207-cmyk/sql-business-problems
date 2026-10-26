# Case Study · Dispatch Holds

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 9,417 shipped orders, January 2024 – September 2026.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

Most orders leave the warehouse within a few days, but some wait one to three weeks before the first shipment. Sales believes finance is holding orders from customers with overdue invoices. Finance believes the warehouse is holding orders for stock. Nobody records why an order waits. The operations director wants evidence on what these holds are, whether anyone is targeting them, and what they cost in late deliveries, before changing the process.

## 2. Business questions

1. How many orders are held before dispatch, and for how long?
2. Are holds targeted (overdue customers, large or small orders, particular segments, salespeople or customers), or do they fall at random?
3. How much of the company's late-delivery problem comes from held orders?
4. Are there dispatch records that cannot be right?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order and promised dates, salesperson, status |
| `shipments` | One row per shipment | First shipment and final delivery dates |
| `sales_order_items` | One row per product per order | Order value and lines |
| `payments` | One row per payment | Amounts paid by a given date |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Dispatch days | First shipment date − order date |
| **Held order** | 7 or more dispatch days |
| Why 7 days | Dispatch days have two parts: a normal process with a peak at 2 days that falls to 673 orders at 5 days and 89 at 6, and a **flat tail of about 70 orders per day from 7 to 22 days**. A flat tail is the signature of a separate, waiting process. |
| **Overdue customer at order** | On the order date, the customer had a delivered order, delivered more than 60 days earlier, that was not fully paid by that date |
| Group z-score | Two-proportion z of a group's hold rate against all other orders; \|z\| ≥ 3 is flagged because about 55 groups are tested |
| **Over-dispersion ratio** | Observed variance of customer hold rates ÷ the variance expected if every customer had the same hold rate (customers with 20+ orders). About 1 means no customer is singled out. |
| Late | Final delivery after the promised date (Delivered orders with every delivery date and a promised date) |

## 5. Analytical approach

1. **Order table** (`sahyadri_b2b.dispatch_holds`). Every shipped order with dispatch days, held flag, overdue-at-order flag, order value, lines and lateness. The distribution of dispatch days and the size of the held group.
2. **Group table** (`sahyadri_b2b.dispatch_hold_groups`). Hold rates with z-scores by overdue status, segment, order value, lines, salesperson, month, weekday and year; and a customer-level over-dispersion test.
3. **Lateness**: late rate and share of late orders for held and normal orders, and the late rate if held orders behaved normally.
4. **Impossible records**: orders shipped before they were placed.

## 6. SQL techniques used

- Point-in-time receivable test: payments dated up to each later order's date, joined back to earlier deliveries of the same customer
- One long-format `UNION ALL` to test eight dimensions with the same z-score logic
- Over-dispersion ratio as a single test of whether any customer is targeted, instead of 135 separate tests
- Counterfactual late rate in one query

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per distinct shipped order |
| 02 | **Dispatch days = an independent recount** |
| 03 | Held flag agrees with the 7-day threshold |
| 04 | Every dimension covers all shipped orders |
| 05 | Every dimension covers all held orders |
| 06 | z-score signs agree with the rate differences |
| 07 | No customer's first order is flagged as overdue |
| 08 | Every overdue flag has an earlier delivery more than 60 days before |
| 09 | Order value = source revenue |
| 10 | Late flag agrees with the dates |

## 8. Findings

**One order in nine is held for one to three weeks.**

| Dispatch days | Orders | Orders per day value | Share |
|---|---:|---:|---:|
| Negative (shipped before ordered) | 5 | | 0.1 % |
| 0 | 196 | 196 | 2.1 % |
| 1 | 1,353 | 1,353 | 14.4 % |
| 2 | 2,521 | 2,521 | 26.8 % |
| 3 | 2,096 | 2,096 | 22.3 % |
| 4 | 1,384 | 1,384 | 14.7 % |
| 5 | 673 | 673 | 7.1 % |
| 6 | 89 | 89 | 0.9 % |
| 7–10 | 283 | 71 | 3.0 % |
| 11–14 | 284 | 71 | 3.0 % |
| 15–18 | 261 | 65 | 2.8 % |
| 19–22 | 272 | 68 | 2.9 % |

- **1,100 orders (11.7 %, ₹11.22 crore) were held**, for a median of 14 days, against a median of 3 days for the rest.
- The tail is flat from 7 to 22 days and stops abruptly. Held orders are not slow versions of normal orders; they wait in a separate queue.

**Holds are not targeted at anyone.**

| Dimension | Groups | Hold rate range | Largest \|z\| | Groups with \|z\| ≥ 3 |
|---|---:|---|---:|---:|
| Order month | 12 | 10.4 – 14.4 % | 2.01 | 0 |
| Order value | 4 | 10.2 – 12.5 % | 1.74 | 0 |
| Order weekday | 7 | 6.9 – 12.8 % | 1.61 | 0 |
| Segment | 4 | 11.3 – 12.6 % | 1.41 | 0 |
| Order lines | 6 | 10.3 – 12.6 % | 1.36 | 0 |
| Salesperson | 17 | 9.6 – 14.1 % | 1.35 | 0 |
| **Customer overdue at order** | 2 | 11.2 – 11.9 % | **0.98** | 0 |
| Order year | 3 | 11.3 – 11.9 % | 0.73 | 0 |

- **The credit-hold theory does not hold.** Orders from customers with an invoice overdue by more than 60 days were held 11.9 % of the time, against 11.2 % for other customers (z = 0.98).
- Large orders are not held more (₹3 lakh+: 10.2 %), and neither are complex ones (6+ lines: within 10.3–12.6 %).
- **No customer is singled out.** Across 135 customers with 20 or more orders, the over-dispersion ratio is 1.1, almost exactly what equal hold rates would produce. One customer crosses \|z\| = 3, about what chance alone gives across 135 customers.

**Held orders cause half of all late deliveries.**

| Dispatch | Orders measured | Late | Late orders | Share of late orders | Avg days to delivery | Avg days promised |
|---|---:|---:|---:|---:|---:|---:|
| Within 6 days | 8,060 | 10.0 % | 808 | 48.3 % | 7.3 | 12.7 |
| **Held 7+ days** | 1,060 | **81.5 %** | 864 | **51.7 %** | 19.2 | 12.5 |
| All, actual | 9,120 | 18.3 % | 1,672 | | | |
| **All, if held orders were late at the normal rate** | 9,120 | **10.0 %** | 914 | | | |

- Held orders are promised the same 12.5 days as other orders but take 19.2 days to arrive. The promise does not know about the hold.
- **Releasing held orders within the normal process would cut the late rate from 18.3 % to 10.0 %**, removing about 758 late orders over the period. That is a larger effect than fixing split shipments (18.2 % → 14.7 % in that study).

**Five orders were shipped before they were placed** (by 1–3 days), including order 109011 (₹1.04 lakh). Either the order date was entered late or the shipment date is wrong.

## 9. Business implications and recommendations

1. **Find the hold queue.** Holds are random with respect to customer, order and credit, which points to a process queue (for example orders waiting for a picking slot, a missed hand-off between order entry and the warehouse, or a batch that is released periodically) rather than a policy. Trace a sample of held orders through the order-entry and warehouse systems.
2. **Make holds visible.** Add a hold reason and a hold date to the order record, and report any order not dispatched within 6 days every morning.
3. **Promise to the dispatch date.** While holds exist, the promise date should move when an order is held, so the customer is told in advance.
4. **Do not introduce credit holds as a fix.** The data shows credit status plays no part in holds today. If finance wants credit holds, they should be a deliberate, recorded rule, not part of an unexplained queue.
5. **Correct the five impossible records** and add a system check that a shipment date cannot be earlier than its order date.

## 10. Assumptions and limitations

- **The 7-day threshold** is read from the shape of the distribution. Using 6 days would add 89 orders, part of which belong to the normal process.
- **No hold reason is recorded**, so the cause can only be narrowed down, not identified. The tests rule out causes linked to customer, credit, order size, salesperson and timing.
- **Overdue definition.** "Not fully paid 60 days after delivery" is an assumption; there are no formal credit terms in the data. A 30- or 90-day definition could be tested by changing `overdue_days`.
- **Stock availability** cannot be tested: there is no stock data. Holds for stock would normally fall more on larger and multi-line orders, which is not what the data shows. Holds by product were not tested, because an order can contain several products.
- Split shipments are also a major source of lateness ([split shipment drivers](../10_split_shipment_drivers/)). The two effects are measured separately and their shares of late orders should not be added together.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order and group tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
