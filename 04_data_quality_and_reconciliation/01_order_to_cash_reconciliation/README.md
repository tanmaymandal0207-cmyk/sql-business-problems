# Case Study · Order-to-Cash Reconciliation

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Figures are as of 30 Sep 2026, the last transaction date in the dataset.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-15 |

---

## 1. Business problem

Finance reports receivables from the `payment_status` flag on each sales order (Paid / Partially Paid / Unpaid). The flag is updated by hand and is never checked against the payments actually received. Before finance uses it for collections and month-end reporting, it needs to know whether the flag can be trusted, where it is wrong, and how much cash is really outstanding.

## 2. Business questions

1. Does each order's `payment_status` agree with the payments recorded against it?
2. Where it does not, what type of exception is it, and how much money is involved?
3. How much cash is outstanding on delivered orders, and how old is it?
4. Which customers hold the largest balances overdue by more than 90 days?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order status, recorded payment status, customer |
| `sales_order_items` | One row per product per order | Order value |
| `payments` | One row per payment receipt | Amount received, payment date, duplicate detection |
| `shipments` | One row per shipment | Final delivery date for ageing |
| `customers` | One row per customer | Customer name and segment |

`payments`, `shipments` and `sales_order_items` are each one-to-many from `sales_orders`. Each is aggregated to order level in its own CTE before joining, so no join multiplies rows (verified by validation checks 01 and 02).

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Order value | `SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))`, rounded to 2 dp |
| Amount paid | `SUM(payments.amount)` for the order |
| Balance | Order value − amount paid |
| Derived status | Unpaid if nothing received; Paid if \|balance\| ≤ ₹0.05; Overpaid if balance < −₹0.05; otherwise Partially Paid |
| Duplicate payment | More than one payment row for the same order with the same date and amount |
| Open receivable | Balance on a **Delivered** order where balance > ₹0.05 |
| Days outstanding | As-of date − final delivery date (shipment date if delivery date is missing; order date if there is no shipment) |
| Days to settle | Final payment date − final delivery date, for fully paid delivered orders |

**Reconciliation categories** — each order gets one category, in this order of priority:

| # | Category | Rule | Action it implies |
|---|---|---|---|
| 1 | Payment on cancelled/returned order | Status Cancelled or Returned and money received | Refund or credit note |
| 2 | Duplicate payment | Same receipt recorded twice | Reverse entry or refund |
| 3 | Overpayment | Received more than order value (not a duplicate) | Credit or refund |
| 4 | Short payment marked Paid | Flag = Paid, payments fall short | Recover or approve write-off |
| 5 | Paid but status not updated | Flag ≠ Paid, payments cover the order | Correct the flag |
| 6 | Other status mismatch | Any other disagreement | Investigate |
| 0 | Matched | Flag agrees with payments | None |

## 5. Analytical approach

`analysis.sql` is a BigQuery script with seven steps:

1. **Reconciliation register.** Builds one row per order with order value, amount paid, duplicate receipts, balance, recorded vs. derived status, category, open receivable and days outstanding. It is saved as `sahyadri_b2b.order_payment_reconciliation`, so the later steps and the validation script read from one source.
2. **Exception summary.** Counts orders and the money involved in each category.
3. **Status agreement matrix.** Cross-tabulates recorded status against the status derived from payments.
4. **Settlement benchmark.** Measures how long fully paid orders took to settle, to show what "normal" looks like.
5. **Receivables ageing.** Puts open balances on delivered orders into age buckets.
6. **Overdue customers.** The top 10 customers by balance over 90 days.
7. **Exception register.** An order-level list of every non-matched order for follow-up.

## 6. SQL techniques used

- BigQuery scripting: `DECLARE` variables for the as-of date and rounding tolerance
- `CREATE OR REPLACE TABLE … AS` to keep the register as a reusable, auditable table
- CTEs that aggregate each one-to-many table to order level before joining
- `LEFT JOIN` with `IFNULL` so orders with no payment or shipment are kept
- Rule-based classification with `CASE`, ordered by financial priority
- Window functions: `PERCENTILE_CONT(...) OVER ()`, `SUM(SUM(...)) OVER ()`, `ROW_NUMBER()`
- Conditional aggregation with `COUNTIF`

## 7. Validation and reconciliation

`validation.sql` checks the register against the source tables. All 10 checks return **PASS**.

| # | Check | Result |
|---|---|---|
| 01 | One register row per order | PASS |
| 02 | Register row count = `sales_orders` row count (10,000) | PASS |
| 03 | No payment without a matching order | PASS |
| 04 | Total paid in register = total of `payments` table, to the paisa | PASS |
| 05 | Total order value = line-item total, within rounding (≤ ₹0.005 per order) | PASS |
| 06 | Order value − amount paid = balance on every row | PASS |
| 07 | Every order has a reconciliation category | PASS |
| 08 | Duplicate amount matches a second, independent recount using `ROW_NUMBER()` | PASS |
| 09 | Open receivables appear only on Delivered orders | PASS |
| 10 | Every Paid order containing a NULL-discount line was settled at the 0 % value | PASS (260 orders) |

Check 10 is the evidence behind treating a missing discount as 0 %: all 260 orders marked Paid that contain a NULL-discount line were paid exactly at the 0 % value.

## 8. Findings

**The payment flag is accurate on 99.74 % of orders, but the 26 exceptions involve real money.**

| Category | Orders | Amount at issue |
|---|---:|---:|
| Duplicate payment | 7 | ₹8,00,255.77 received twice |
| Payment on cancelled order | 6 | ₹72,325.69 held against cancelled orders |
| Short payment marked Paid | 9 | ₹817.00 not received |
| Paid but status not updated | 4 | ₹8,17,221.76 shown as unpaid but already received |
| **Total exceptions** | **26** | |

- **Duplicate receipts.** One order alone (order 106585) carries a duplicate receipt of ₹5,78,508.58. Every duplicate pair has the same order, date and amount. One pair (order 103477) has the payment method missing on the second row, which points to a manual re-entry.
- **Short payments.** Five of the nine are ₹2 or less, which is consistent with rounding to the nearest rupee. The other four range from ₹5 to ₹499.
- **Stale flags.** Four orders worth ₹8.17 lakh are flagged Unpaid even though they have been paid in full. Collections would be chasing customers who have already paid.

**Over half of open receivables are more than 90 days old.**

Fully paid delivered orders settle a median of **45 days** after delivery. 90 % settle within 87 days and 99 % within 133 days.

| Age since delivery | Orders | Open receivable | Share |
|---|---:|---:|---:|
| 0–30 days | 321 | ₹3,42,87,316.31 | 31.3 % |
| 31–60 days | 147 | ₹1,27,78,908.64 | 11.7 % |
| 61–90 days | 72 | ₹53,38,606.53 | 4.9 % |
| 91–180 days | 99 | ₹63,52,451.57 | 5.8 % |
| 181–365 days | 215 | ₹1,46,00,049.77 | 13.3 % |
| Over 365 days | 571 | ₹3,63,19,067.15 | 33.1 % |
| **Total** | **1,425** | **₹10,96,76,399.97** | **100 %** |

- **₹5.73 crore (52.2 %)** is more than 90 days past delivery, spread across 885 orders and 229 customers.
- **₹3.63 crore (33.1 %)** is more than a year old. That is far beyond the 133 days within which 99 % of paid orders settle.
- The **top 10 customers** hold ₹2.09 crore, 36.5 % of the balance over 90 days. The largest single balance is ₹31.30 lakh across 2 orders (customer 1212), the oldest being 900 days.
- All 10 of these customers placed orders in August or September 2026, and 9 of them made a payment in September 2026. They are active accounts that are still buying and paying while older invoices stay open.

## 9. Business implications and recommendations

1. **Recover the duplicate receipts and refund the cancelled-order payments** (findings: duplicates ₹8.00 lakh; cancelled ₹72,325.69). Reverse or refund the 7 duplicate receipts and issue credit notes for the 6 cancelled orders before month-end close, so that customer ledgers are not overstated.
2. **Correct the 4 stale flags before the next collections run.** This avoids chasing ₹8.17 lakh that has already been received.
3. **Adopt a written round-off policy**, for example writing off differences of up to ₹2. That clears 5 of the 9 short payments automatically; the remaining 4 are reviewed individually.
4. **Review receivables over 365 days for provisioning** (₹3.63 crore). Settlement behaviour shows that balances this old are unlikely to be timing differences. Each one should be confirmed with the customer, collected or provided for.
5. **Prioritise collections on the top 10 overdue customers.** They hold 36.5 % of the balance over 90 days. Because they are still ordering and paying, unapplied or misallocated receipts should be ruled out before escalating.
6. **Stop maintaining `payment_status` by hand.** Derive it from the payments table using the same rule as this analysis. The flag then cannot drift from actual receipts.

## 10. Assumptions and limitations

- **Revenue basis.** Order value comes from line items. No tax, freight or other charges are recorded, so payments are expected to equal line-item value. This is supported by 7,861 of the 7,877 orders flagged Paid matching line-item value within ₹0.05.
- **NULL discounts** are treated as 0 % (evidence in validation check 10).
- **Receivables** include Delivered orders only. Shipped, Processing and Pending orders with balances are treated as not yet invoiced.
- **No payment terms or due dates** are in the data. Ageing is measured from delivery, not from a due date, so "overdue" here means "older than the stated age band".
- **Payment allocation.** Payments are recorded against specific orders. Receipts that a customer intended for a different order cannot be detected from this data.
- **Data gap.** 4 Delivered orders have no shipment record. Their balances are aged from the order date.
- **Tolerance.** Amounts within ₹0.05 are treated as equal. A different tolerance would move very small differences between "Matched" and "Short payment".
- **As-of date.** 30 Sep 2026, the last transaction date in the dataset. Results will change as new payments are recorded.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Reconciliation register and analysis (7 steps) |
| `validation.sql` | 10 pass/fail checks against the source tables |
