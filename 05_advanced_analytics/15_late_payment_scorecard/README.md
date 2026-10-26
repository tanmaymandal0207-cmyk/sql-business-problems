# Case Study · Late Payment Scorecard

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 8,611 delivered orders: 5,340 to build the scorecard (deliveries before October 2025) and 3,271 to test it (October 2025 – July 2026).

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

About four delivered orders in ten are still not fully paid 60 days after delivery. The credit controller has two people to chase overdue accounts. She wants to know, at the moment of delivery, which orders are likely to be paid late, so that reminders and calls start early on the right ones. She asks for a simple points scorecard of the kind banks use, built and tested on the company's own history, and she wants to know whether it beats the simplest possible rule.

## 2. Business questions

1. Which order and customer characteristics predict late payment, and how strongly?
2. How well does a points scorecard rank orders on a later period it has not seen?
3. Is it better than ranking by customer segment alone?
4. Where should the collection effort go?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, dates, status |
| `sales_order_items` | One row per product per order | Order value, discount |
| `shipments` | One row per shipment | Delivery date |
| `payments` | One row per payment | Amounts and dates |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Population | Delivered orders with final delivery on or before 31 Jul 2026, so that 60 days after delivery can be observed |
| **Late** | Not fully paid within 60 days of final delivery (payments dated up to delivery + 60 days) |
| Characteristics | Segment; customer's **prior late rate** (orders whose 60-day window had closed before this order was placed); order value; average discount; delivered late or on time. All are known at delivery. |
| Train / test | Train: deliveries before 1 Oct 2025. Test: 1 Oct 2025 – 31 Jul 2026. A time-based split, as the scorecard would be used. |
| **Weight of evidence (WoE)** | ln(share of on-time payers in the bin ÷ share of late payers in the bin), with 0.5 added to counts |
| **Information value (IV)** | Σ (share on-time − share late) × WoE. Below 0.02 not useful, 0.02–0.10 weak, 0.10–0.30 medium, above 0.30 strong. |
| Points | ROUND(28.85 × WoE) per bin: 20 points double the odds of paying on time. Score = 600 + points. Higher = safer. |
| **AUC / Gini** | AUC: probability that an on-time order scores higher than a late one. Gini = 2 × AUC − 1. |

## 5. Analytical approach

1. **Modelling table** (`sahyadri_b2b.lps_orders`). One row per order: late flag, sample and the bin for each characteristic.
2. **WoE table** (`sahyadri_b2b.lps_woe`). Counts, late rate, WoE, IV contribution and points per bin, built on the train sample only. A combined segment × history characteristic is added to test for overlap.
3. **Scores** (`sahyadri_b2b.lps_scores`) for every order, for three models: full scorecard, segment only, and segment × history.
4. **AUC table** (`sahyadri_b2b.lps_auc`) for train and test; late rate by score band; late rate by segment on the test period.

## 6. SQL techniques used

- Point-in-time customer history: only orders whose 60-day outcome was known before the new order was placed
- Weight of evidence and information value in SQL, with smoothing for empty bins
- A points scorecard assembled by joining each order to its bins
- Time-based hold-out and AUC (Mann–Whitney, average ranks)
- Validation that recomputes test AUC by brute force over every on-time × late pair

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per eligible delivered order |
| 02 | Order value = source |
| 03 | **Late flag = an independent recount** of payments within 60 days |
| 04 | Every customer's first order has no payment history (no look-ahead) |
| 05 | Train / test split agrees with the delivery date |
| 06 | Bins cover every train order for each characteristic |
| 07 | Late orders by bin add up to the train late count |
| 08 | Points = ROUND(28.85 × WoE) |
| 09 | **Test AUC of the scorecard = a brute-force pair count** |
| 10 | Test AUC of the segment rule = a brute-force pair count |

## 8. Findings

**Late payment is common and stable: 38.4 % of orders in the train period, 39.4 % in the test period.**

**Segment is by far the strongest characteristic.**

| Characteristic | Information value | Strength |
|---|---:|---|
| Segment | **0.807** | Strong |
| Payment history | 0.422 | Strong |
| Discount | 0.121 | Medium |
| Order value | 0.044 | Weak |
| Delivery (late or on time) | 0.006 | Not useful |

| Segment | Late (train) | Points |
|---|---:|---:|
| Enterprise | **66.4 %** | −33 |
| Mid-Market | 31.5 % | +9 |
| Distributor | 23.6 % | +20 |
| SMB | 16.1 % | +34 |

- **Whether a delivery was late does not affect whether it is paid late** (IV 0.006), consistent with the [cost of a late delivery](../09_cost_of_late_delivery/) study.

**But payment history adds nothing once segment is known.**

| Segment (train) | No history | Rarely late before | Sometimes late before | Mostly late before |
|---|---:|---:|---:|---:|
| Distributor | 22.7 % | 25.8 % | 21.5 % | 25.5 % |
| Enterprise | 65.0 % | 72.2 % | 58.8 % | 67.1 % |
| Mid-Market | 32.2 % | 29.3 % | 29.5 % | 38.2 % |
| SMB | 13.8 % | 16.0 % | 22.9 % | 15.6 % |

- Within each segment, a customer's own record barely changes the late rate and has no consistent direction. The history characteristic looked strong only because Enterprise customers are both mostly late before **and** mostly late now.
- **Late payment is a segment habit, not a customer trait.** Enterprise customers pay late about two-thirds of the time whatever their record.

**So the simple rule performs as well as the full scorecard, and slightly better.**

| Model | Train AUC | Test AUC | Test Gini |
|---|---:|---:|---:|
| Full scorecard (5 characteristics) | 0.726 | 0.730 | 0.460 |
| Segment × history (combined bins) | 0.739 | 0.742 | 0.484 |
| **Segment only** | 0.732 | **0.743** | **0.485** |

- Adding characteristics made the scorecard **worse** on new data: segment, history and discount carry the same information, and adding their points counts it more than once.

**Where the late money is (test period, segment rule).**

| Segment | Orders | Late | Share of late orders | Late order value |
|---|---:|---:|---:|---:|
| Enterprise | 1,141 | **67.0 %** | **59.3 %** | ₹9.41 crore |
| Mid-Market | 819 | 34.7 % | 22.0 % | ₹1.71 crore |
| Distributor | 645 | 22.2 % | 11.1 % | ₹2.69 crore |
| SMB | 666 | 14.6 % | 7.5 % | ₹0.19 crore |

## 9. Business implications and recommendations

1. **Do not build a multi-factor scorecard yet.** On this data, segment alone ranks late payers as well as any combination, and is easier to explain and maintain.
2. **Put collection effort on Enterprise accounts.** They are 35 % of the test-period orders but 59 % of late orders and ₹9.41 crore of late value. Start reminders before the due date for every Enterprise delivery.
3. **Treat Enterprise lateness as a terms problem, not a behaviour problem.** If Enterprise customers routinely pay at 60–90 days, they are probably working to their own payment cycles. Agree written terms (as the [customer payment behaviour](../02_customer_payment_behaviour/) study recommends) and measure lateness against those terms.
4. **Use customer history for exceptions within a segment only after terms are fixed.** Once the segment norm is set by contract, individual deviations from it may become predictive; re-test then.
5. **Ignore delivery performance in credit decisions.** It has no link to payment timing.

## 10. Assumptions and limitations

- **60-day definition** of late. There are no formal terms in the data; a 30- or 90-day definition would change the late rates but the segment pattern is strong.
- **Naive additive scorecard.** Points are added as if characteristics were independent. A logistic regression would down-weight overlapping characteristics; it would not beat the segment rule by much given the table above.
- **Time-based test** over 10 months. Behaviour could change if terms or collection practice change.
- **Payments to the extraction date.** Orders delivered after 31 July 2026 are excluded because their 60-day window is not complete.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Modelling, WoE, scores and AUC tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
