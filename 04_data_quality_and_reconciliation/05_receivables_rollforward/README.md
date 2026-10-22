# Case Study · Receivables Roll-forward Reconciliation

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Month-ends January 2024 – September 2026.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Depends on** | `order_payment_reconciliation` table from [Order-to-cash reconciliation](../01_order_to_cash_reconciliation/) (for the tie-out in Step 5 and checks 07–08 only) |
| **Last updated** | 2026-10-22 |

---

## 1. Business problem

At every month-end, finance must show that the trade receivables balance moves only for the right reasons:

**opening balance + invoices raised − cash received = closing balance**

Auditors ask for this roll-forward, and for the closing balance to agree with the open-item ageing. Customer credit balances (cash with no invoice, or more cash than the invoice) must be shown as a liability, not netted silently against receivables. Before the half-year close, finance wants the roll-forward rebuilt from source data for every month since January 2024.

## 2. Business questions

1. Does the receivables account roll forward every month, and what are the month-end balances and days sales outstanding (DSO)?
2. How large are customer credit balances, and what causes them?
3. Does the 30 Sep 2026 closing balance agree with the open-item ageing?
4. Why is DSO rising?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status and customer |
| `sales_order_items` | One row per product per order | Invoice amount |
| `shipments` | One row per shipment | Invoice date (final delivery) |
| `payments` | One row per payment | Receipts |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Invoice | One per Delivered order, for its order value rounded to the paisa |
| Invoice date | Final delivery date, the recognition point used in [Revenue cut-off reconciliation](../04_revenue_cutoff_reconciliation/). Fallbacks: latest shipment date, then order date. |
| Receipt | Each payment row, on its payment date |
| Order balance | Invoices − receipts on the order up to the month-end |
| Gross receivables | Sum of positive order balances (above 5 paise) |
| Credit balances | Sum of negative order balances, shown as a positive amount |
| Net balance | Gross receivables − credit balances |
| DSO | Gross receivables ÷ invoices in the last 3 months × 91 days |

## 5. Analytical approach

1. **Sub-ledger** (`sahyadri_b2b.receivables_ledger`). One row per invoice or receipt, built from source tables.
2. **Month-end balances** (`sahyadri_b2b.receivables_month_end`). Each order's balance at each of the 33 month-ends, classed as receivable, credit balance or settled.
3. **Monthly roll-forward** with gross receivables, credit balances and DSO.
4. **Credit balance analysis** at the as-of date, by cause.
5. **Tie-out** of the closing balance to the order-to-cash ageing, and a list of invoices dated on a fallback basis.

## 6. SQL techniques used

- A transaction-level sub-ledger built with `UNION ALL` of invoices (+) and receipts (−)
- A month-end spine (`GENERATE_DATE_ARRAY` + `LAST_DAY`) joined to the ledger with `txn_date <= month_end` to get point-in-time balances
- `LAG` for opening balances and a rolling 3-month window for DSO
- Gross-versus-net presentation, with credit balances kept separate
- A cross-case tie-out against another case study's output table

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Exactly one invoice per Delivered order |
| 02 | Invoice total = delivered order value |
| 03 | Receipt total = source payments |
| 04 | Receipt rows = source payment rows |
| 05 | At every month-end, the sum of order balances = the cumulative ledger total |
| 06 | **Roll-forward:** in every month, opening + invoices − receipts = closing |
| 07 | **Tie-out:** gross receivables at 30 Sep 2026 = the order-to-cash open-item ageing (₹10,96,76,399.97) |
| 08 | Receivable order count = the ageing (1,425 orders) |
| 09 | No invoice or receivable on an order that is not Delivered |
| 10 | No invoice dated before its order or after the as-of date |

## 8. Findings

**The receivables account rolls forward without difference in all 33 months, and the closing balance agrees with the ageing to the paisa.**

| | 30 Sep 2024 | 30 Sep 2025 | 31 Mar 2026 | 30 Sep 2026 |
|---|---:|---:|---:|---:|
| Gross receivables | ₹5.12 crore | ₹6.59 crore | ₹10.56 crore | **₹10.97 crore** |
| Credit balances | ₹6.0 lakh | ₹5.8 lakh | ₹16.0 lakh | ₹11.4 lakh |
| Net balance | ₹5.06 crore | ₹6.54 crore | ₹10.40 crore | ₹10.85 crore |
| DSO | 71 days | 92 days | 90 days | **97 days** |

From January 2024 to September 2026, ₹90.17 crore was invoiced and ₹79.31 crore received.

**Receivables are growing twice as fast as sales, and the whole gap is old, uncollected invoices.**

| | 30 Sep 2025 | 30 Sep 2026 | Change |
|---|---:|---:|---:|
| Invoices in the quarter (Jul–Sep) | ₹6.52 crore | ₹10.28 crore | +57.7 % |
| Gross receivables | ₹6.59 crore | ₹10.97 crore | +66.3 % |
| – up to 90 days old | ₹3.49 crore | ₹5.24 crore | +50.0 % |
| – over 90 days old | ₹3.10 crore | ₹5.73 crore | **+84.8 %** |
| – of which over 365 days | ₹1.73 crore | ₹3.63 crore | +110.2 % |

- **Current collection is stable.** Measured on invoices up to 90 days old, DSO was about 49 days in September 2025 and 46 days in September 2026. Customers pay new invoices on time.
- **The headline DSO is rising because old invoices are not being collected.** Items over 90 days old account for 51 of the 97 days of DSO in September 2026. This matches the ageing in the [order-to-cash reconciliation](../01_order_to_cash_reconciliation/), where 52 % of open receivables are over 90 days old.

**₹11.36 lakh of credit balances at 30 Sep 2026 is a liability, not a reduction of receivables:**

| Cause | Orders | Amount |
|---|---:|---:|
| Duplicate receipt on a delivered order | 7 | ₹8,00,255.77 |
| Advance on an order not yet delivered | 9 | ₹2,63,429.81 |
| Cash on a cancelled order (refund due) | 6 | ₹72,325.69 |
| **Total** | **22** | **₹11,36,011.27** |

- Credit balances peaked at **₹21.5 lakh in June 2026**, mostly customer advances on orders delivered later.
- 13 invoices (₹5.4 lakh) are dated on a fallback basis because the delivered order has no delivery date: 9 use the shipment date and 4 the order date.

## 9. Business implications and recommendations

1. **Use this roll-forward as the month-end receivables control.** It rebuilds from source in one script and proves the closing balance against the ageing. Any future difference points to a posting or data error.
2. **Report receivables gross, with credit balances as a liability.** Netting ₹11.4 lakh of credit balances hides the duplicate receipts and the refunds owed.
3. **Run a collection drive on invoices over 90 days, not a general credit tightening.** New invoices are paid in about 46–49 days. The DSO problem is ₹5.73 crore of old items, ₹3.63 crore of them more than a year old.
4. **Assess the over-365-day items for a bad-debt provision** at the half-year close. Items this old in a business where 99 % of invoices settle within 133 days may not be collectable.
5. **Clear the duplicate receipts and cancelled-order cash** with credit notes or refunds, and allocate the advances when the orders are delivered.

## 10. Assumptions and limitations

- **Opening balance is zero.** The data starts in January 2024, so invoices raised before then are missing. Early 2024 balances and DSO are understated, which is why the comparison uses September 2025 and September 2026.
- **Delivery-based invoicing.** Invoices are dated at delivery, consistent with the revenue cut-off study. If invoices are actually raised at dispatch, balances would be slightly higher in each month.
- **Order-level matching.** Each payment is matched to the order it was recorded against. Customers who pay on account without an order reference would need a customer-level roll-forward.
- **Returned orders** are treated as never invoiced. In the books they would appear as an invoice followed by a credit note, with no effect on the closing balance.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Sub-ledger and month-end tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
