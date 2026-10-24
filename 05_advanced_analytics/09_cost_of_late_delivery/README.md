# Case Study · Cost of a Late Delivery

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 9,125 delivered orders (1,672 late), with a within-customer comparison across 283 customers.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-25 |

---

## 1. Business problem

About one delivered order in five arrives after the promised date. Operations is asking for budget, such as more dispatch staff or a premium carrier, to fix it. The CFO wants to know **what lateness actually costs** before approving: does it slow down cash, does it lose repeat business, and is any effect caused by lateness itself or by the kind of customers who happen to get late deliveries?

## 2. Business questions

1. Do customers pay later for orders delivered late, or pay less of them?
2. Do they reorder less, or less quickly, after a late delivery?
3. Does the effect grow with days late, or when lateness repeats?
4. Do the differences hold **within the same customer**, or are they a customer-mix effect?
5. What is the cash cost per year?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order and promised dates, statuses |
| `shipments` | One row per shipment | Delivery dates |
| `payments` | One row per payment | Payment dates |
| `sales_order_items` | One row per product per order | Order value |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Measured delivery | Delivered order with a promised date and a delivery date on every shipment. Final delivery = last shipment's delivery date. |
| **Late** | Final delivery after the promised date |
| Order-to-paid days | Order date to the last payment, for orders with status Paid |
| Delivery-to-paid days | Final delivery to the last payment |
| Collection outcome | Share Paid or Unpaid, for deliveries up to 31 Mar 2026 (at least six months to pay) |
| **Reordered 30 / 90** | The customer placed another order (not Cancelled or Returned) within 30 / 90 days after the final delivery. Deliveries up to 30 Jun 2026. |
| **Within-customer difference** | For each customer with at least one late and one on-time order: average for late orders minus average for on-time orders. Averaged across customers, with a paired t-statistic. |
| Cash cost | Late-delivered revenue (last 12 months) × extra days to payment ÷ 365 × cost of capital (10 % a year, an assumption) |

The pooled comparison mixes customers. If late deliveries fall more often on customers who buy less often anyway, a pooled gap would be wrongly blamed on lateness. The within-customer comparison removes that.

## 5. Analytical approach

1. **Outcome table** (`sahyadri_b2b.delivery_outcomes`). One row per measured delivery with lateness, payment timing, collection status, next order and the previous delivery's lateness.
2. **Pooled comparison** of late against on-time, with a two-proportion z-test and a Welch t-test.
3. **Dose and repetition.** Outcomes by days late, by whether the previous delivery was also late, and the last delivery of customers who went quiet.
4. **Paired table** (`sahyadri_b2b.late_delivery_paired`). Within-customer differences for five measures, with paired t-statistics.
5. **Cash cost** for the last 12 months.

## 6. SQL techniques used

- Order-level pre-aggregation of shipments and payments before joining, to avoid fan-out
- Next-order lookup with a range join and `MIN`, instead of a correlated subquery
- Censoring cut-offs so recent deliveries are not counted as "no reorder" or "unpaid" too early
- Paired (within-customer) differences in long format, tested with `AVG ÷ (STDDEV_SAMP ÷ √n)`
- Welch t and two-proportion z statistics computed in SQL
- Validation through an accounting identity: order-to-paid = order-to-delivery + delivery-to-paid for every customer

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One outcome row per eligible delivered order |
| 02 | Late flag and days late agree with the dates |
| 03 | Lateness band agrees with days late |
| 04 | Paid date present exactly for Paid orders |
| 05 | **No valid order is skipped** between a delivery and the recorded next order (anti-join) |
| 06 | Reorder flags are consistent (30 days implies 90 days; no flag without a next order) |
| 07 | Observation flags agree with the cut-off dates |
| 08 | Paired customer counts = an independent recount |
| 09 | **Within-customer identity**: order-to-paid = order-to-delivery + delivery-to-paid |
| 10 | Order value = source revenue |

## 8. Findings

**Pooled, late deliveries look slightly worse on every measure.**

| | On time | Late | Difference | Test |
|---|---:|---:|---:|---:|
| Reordered within 30 days | 72.4 % | 69.6 % | −2.8 points | z = −2.21 |
| Reordered within 90 days | 89.9 % | 87.9 % | −2.0 points | |
| Mean order-to-delivery days | 6.8 | 17.4 | +10.6 | |
| Mean order-to-paid days | 54.4 | 57.6 | +3.2 | t = 3.30 |
| Median order-to-paid days | 53 | 54 | +1 | |
| Median delivery-to-paid days | 46 | 37 | −9 | |
| Fully paid (deliveries to Mar 2026) | 89.5 % | 89.8 % | +0.3 points | |
| Unpaid | 4.0 % | 4.1 % | +0.1 points | |

- **Customers pay to a clock that starts at the order, not at delivery.** A late order arrives 10.6 days later but is paid only 3.2 days later on average, so the time from delivery to payment shrinks.
- **Lateness does not affect whether an order is paid.** Paid and unpaid shares are the same.

**Within the same customer, the reorder gap disappears, but the payment delay is real.**

| Within-customer difference (late − on time) | Customers | Mean | Standard error | Paired t |
|---|---:|---:|---:|---:|
| Reorder within 30 days | 281 | −0.1 points | 1.7 | −0.07 |
| Reorder within 90 days | 281 | +0.5 points | 2.0 | 0.23 |
| Order to delivery | 283 | +10.4 days | 0.3 | 40.4 |
| **Order to paid** | 283 | **+6.4 days** | 1.1 | **5.83** |
| Delivery to paid | 283 | −3.9 days | 1.1 | −3.73 |

- **The pooled 2.8-point reorder gap is a customer-mix effect.** Compared with their own on-time orders, customers reorder after a late delivery just as often. Late deliveries fall more on customers who reorder less anyway.
- **The payment delay is larger within customers than pooled: 6.4 days.** About 60 % of the 10.4 extra days of delivery passes through to cash; customers absorb the rest by paying sooner after delivery.

**The payment delay grows with lateness. Reorder hardly moves.**

| Days late | Deliveries (reorder) | Reordered 30 days | Reordered 90 days | Paid orders | Mean order-to-delivery | Mean order-to-paid |
|---|---:|---:|---:|---:|---:|---:|
| On time | 6,686 | 72.4 % | 89.9 % | 6,304 | 6.8 | 54.4 |
| 1–3 | 546 | 71.4 % | 89.0 % | 508 | 12.1 | **52.4** |
| 4–7 | 403 | 69.5 % | 85.9 % | 383 | 17.1 | 56.0 |
| 8+ | 550 | 67.8 % | 88.4 % | 536 | 22.6 | **63.6** |

- Slightly late orders (1–3 days) are paid no later than on-time ones. **Orders 8 or more days late are paid about 9 days later.**
- Repeated lateness does not compound: after two late deliveries in a row, 72.2 % reordered within 30 days, against 71.6 % after a late delivery that followed an on-time one.
- Customers who have gone quiet were not driven out by a late last delivery: 19.8 % of the 106 lapsed customers had a late last delivery, against 17.6 % of the 319 active ones (z = 0.5, not significant).

**The cash cost is small.**

| Last 12 months | Value |
|---|---:|
| Late deliveries | 741 |
| Late-delivered revenue | ₹7.83 crore |
| Extra days to payment (within-customer) | 6.4 |
| Extra receivables carried on average | ₹13.8 lakh |
| **Financing cost at 10 % a year** | **₹1.38 lakh** |

## 9. Business implications and recommendations

1. **Do not justify the delivery budget on cash or retention.** In this data lateness costs about ₹1.4 lakh a year in financing and no measurable repeat business. A dispatch investment must be justified by customer commitments (contract penalties, service levels), competitive position, or the operational fixes being cheap, not by lost revenue.
2. **Focus on the long tail of lateness.** Deliveries 8+ days late carry most of the payment delay and the weakest reorder rate. A target of "no order more than 7 days late" addresses the cost that exists, at lower expense than improving every order. The [split shipment](../../03_operations_and_supply_chain/10_split_shipment_drivers/) study shows that a quarter of late orders come from second shipments that follow 3–15 days after the first.
3. **Use within-customer comparisons before attributing outcomes to service failures.** The pooled 2.8-point reorder gap would have been a misleading headline. Apply the same paired method to future questions such as discounts or salesperson changes.
4. **Keep payment terms anchored to the invoice or order date.** Customers' payment behaviour already follows the order date; that protects cash when delivery slips.
5. **Revisit with complaint data.** The measures here are behavioural. Complaints, penalties or lost tenders tied to lateness would add costs this analysis cannot see.

## 10. Assumptions and limitations

- **Observational.** Within-customer comparison removes stable customer differences, but not changes over time within a customer (for example a customer whose orders become larger and slower to deliver).
- **Customers with only late or only on-time orders** are excluded from the paired comparison (283 of the customers with paid orders are included). A customer who left after a single late first order would not be in it; the lapsed-customer check shows no sign of that pattern.
- **Cost of capital** is an assumption (10 % a year). The cost scales linearly with it.
- **Payment status at extraction.** Partially paid and unpaid orders are excluded from timing; collection share is compared separately.
- Returned and cancelled orders are excluded, so the effect of lateness on returns is not measured here.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Outcome and paired tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
