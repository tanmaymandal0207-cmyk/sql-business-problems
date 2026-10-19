# Case Study · Customer Payment Behaviour and Credit Terms

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Period: orders delivered from January 2024 to September 2026.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-19 |

---

## 1. Business problem

The company extends the same informal credit to every customer: goods go out, and the customer pays when they pay. Finance wants to replace this with **written credit terms by customer group** and to identify accounts whose payment behaviour has become a risk. Before setting terms, finance needs evidence of how each group actually pays and how much cash slow payment ties up.

## 2. Business questions

1. How quickly does each customer segment pay after delivery?
2. How much cash is tied up in receivables because of that, by segment?
3. Which customers pay much more slowly than their segment peers?
4. Is payment speed improving or getting worse year by year?
5. How much cash would formal terms release if customers paid within them?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, payment status, customer |
| `sales_order_items` | One row per product per order | Order value |
| `shipments` | One row per shipment | Final delivery date |
| `payments` | One row per receipt | Final payment date, number of instalments |
| `customers` | One row per customer | Segment and name |

**Population:** 7,856 orders that were delivered and fully paid, with a delivery date. Unpaid and part-paid balances are analysed in [Order-to-cash reconciliation](../../04_data_quality_and_reconciliation/01_order_to_cash_reconciliation/).

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Days to pay | Final payment date − final delivery date. Negative means paid before delivery (an advance). |
| Average cash tied up | Σ (order value × days to pay) ÷ days in the period: the average receivable balance these orders created |
| Customer payment tier | By the customer's median days to pay (customers with 5 or more paid orders): **Prompt** ≤ 30 · **Standard** 31–60 · **Slow** 61–90 · **Very slow** > 90 |
| Slower than peers | Customer median > 1.5 × the segment's median |
| Proposed terms (scenario) | SMB 15 · Distributor 30 · Mid-Market 45 · Enterprise 60 days |
| Cash released (scenario) | Reduction in average cash tied up if no order took longer than its segment's terms to pay |

## 5. Analytical approach

1. **Paid-order timing table** (`sahyadri_b2b.paid_order_timing`). One row per fully paid delivered order with value, final delivery date, final payment date, instalments and days to pay.
2. **Segment payment profile**, including average cash tied up.
3. **Customer tiers by segment.**
4. **Credit review list:** customers paying much more slowly than their segment.
5. **Trend** of median days to pay by delivery year.
6. **Scenario:** cash released under proposed segment terms.

## 6. SQL techniques used

- Separate order-level aggregations of line items, shipments and payments, joined one-to-one
- Medians and 90th percentiles with `PERCENTILE_CONT … OVER (PARTITION BY …)` at segment, customer and year level
- `COUNT(*) OVER (PARTITION BY …)` alongside percentiles in a `SELECT DISTINCT`
- Value-weighted days (`SUM(value * days)`) to express timing as cash
- A what-if scenario with a `CASE` terms table and `LEAST()`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order |
| 02 | Row count = the expected population, found independently with `EXISTS` (7,856) |
| 03 | Days to pay recomputed from the dates on every row |
| 04 | Final payment date matches the source on every row |
| 05 | Final delivery date matches the source on every row |
| 06 | Payment count matches the source on every row |
| 07 | No missing value, date or segment |
| 08 | Delivery year matches the delivery date |
| 09 | Segment order counts add up to the total |
| 10 | Exactly 16 paid orders have receipts that differ from their value. These are the 7 duplicate receipts and 9 short payments already found in the order-to-cash case study, so the two analyses agree. |

## 8. Findings

**Each segment already pays on a consistent, informal term, but the terms differ widely.**

| Segment | Paid orders | Median days | 90th percentile | Paid within 30 days | Paid after 60 days | Average cash tied up |
|---|---:|---:|---:|---:|---:|---:|
| SMB | 1,712 | 10 | 48 | 82.4 % | 6.1 % | ₹6.0 lakh |
| Distributor | 1,623 | 30 | 69 | 52.9 % | 14.7 % | ₹1.11 crore |
| Mid-Market | 1,950 | 42.5 | 84 | 8.2 % | 23.9 % | ₹52.4 lakh |
| Enterprise | 2,571 | 65 | 106 | **0.0 %** | **61.3 %** | **₹2.10 crore** |

- **Enterprise customers tie up more than half the cash.** No Enterprise order was paid within 30 days, and 61 % took longer than 60. They account for ₹2.10 crore of the ₹3.80 crore average balance.
- **Behaviour is consistent within each segment.** Among customers with 5 or more paid orders:
  - 94 of 95 SMB customers are Prompt payers.
  - 71 of 78 Mid-Market customers are Standard.
  - 50 of 57 Enterprise customers are Slow (61–90 days).
- **Payment speed is stable over time.** The median for each segment changed by no more than 2 days between 2024 and 2026, so these figures are a reliable basis for setting terms.
- **16 customers pay much more slowly than their peers.** The largest by value is a Mid-Market customer (1069, median 67.5 days against a segment median of 42.5). The most extreme are an SMB customer paying in 48 days against a norm of 10 (1219, 4.8×) and a Mid-Market customer at 93 days (1491). No Enterprise or Distributor customer exceeds 1.5× its segment median.
- **665 orders (8.5 %) were paid before delivery.** Advance payment already happens and could be formalised for new or high-risk accounts.

**Formal terms would release about ₹88 lakh of cash.**

| Segment | Proposed terms | Orders beyond terms | Cash released |
|---|---:|---:|---:|
| Enterprise | 60 days | 61.3 % | ₹40.0 lakh |
| Distributor | 30 days | 47.1 % | ₹33.7 lakh |
| Mid-Market | 45 days | 41.7 % | ₹11.0 lakh |
| SMB | 15 days | 33.9 % | ₹3.5 lakh |
| **Total** | | | **₹88.2 lakh** |

## 9. Business implications and recommendations

1. **Publish written credit terms by segment.** Start from the behaviour already observed: SMB 15 days, Distributor 30, Mid-Market 45, Enterprise 60. Terms close to current behaviour are easier to enforce than aspirational ones.
2. **Focus enforcement on Enterprise and Distributor accounts.** They account for ₹73.7 lakh of the ₹88.2 lakh cash release. Agree terms at contract renewal and back them with reminder schedules.
3. **Put the 16 slower-than-peer customers on credit review.** Check whether their pattern reflects disputes, delivery problems or financial stress before changing their limits.
4. **Formalise advance or part-advance payment** for new customers and for those on the review list, building on the 8.5 % of orders already paid in advance.
5. **Track days to pay monthly by segment.** It is stable today, so any rise is an early warning.

## 10. Assumptions and limitations

- **Fully paid orders only.** The analysis covers how customers pay once they do pay. Customers who never pay are not reflected here; their balances appear in the receivables ageing.
- **Measured from delivery.** Days are counted from delivery to the final payment. Invoice dates are not in the data.
- **Instalments.** For orders paid in instalments, the final payment date is used, which overstates the wait for the earlier parts.
- **Scenario.** The cash release assumes every late payer would pay on the term date, with no lost sales. It is an upper estimate of what tighter terms could achieve.
- **Average balance.** Cash tied up is averaged over the full 33-month period. It is not a month-end balance.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Paid-order timing table and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
