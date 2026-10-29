# Case Study · Cash Application Matching: How Many Receipts Can Rules Match?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 10,568 receipts matched to open invoices using only the customer, date and amount, with every match checked against the order the payment was actually recorded on.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-29 |

---

## 1. Business problem

Two accounts executives spend most of each week applying customer receipts to open invoices by hand. A new bank-statement integration will bring in each receipt with the customer and the amount, but not the invoice it pays. Before buying the auto-matching module, finance wants to know how much of the work simple rules could take over, why the rest would fail, and what would close the gap.

## 2. Business questions

1. How do customers actually pay: one payment per order, or several?
2. If a receipt carries only the customer, date and amount, how many can be matched to the right invoice by rules?
3. Why do the rest fail, and how much money do they carry?
4. What would raise the automatic match rate: a fallback rule, or a remittance reference on part payments?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `payments` | One row per receipt | Amount, date, the true order (kept aside to score accuracy) |
| `sales_orders` | One row per order | Customer, order date, payment status |
| `sales_order_items` | One row per product per order | Invoice value |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Receipt | A payment, treated as if only the customer, date and amount were known |
| Invoice value | Net order value (quantity × unit price × (1 − discount)) |
| **Candidate invoice** | The customer's order placed on or before the receipt date with an open balance above ₹0.05 just before the receipt (receipts sequenced by date, then payment id) |
| **R1 Exact invoice** | The amount equals the full value of exactly one candidate (within ₹0.05) |
| **R2 Exact balance** | No invoice fits, and the amount equals the open balance of exactly one candidate |
| Ambiguous / No match | The amount fits two or more candidates / none |
| **Accuracy** | Share of automatic matches that pick the order the payment was recorded on |
| Round sum | An amount that is a whole multiple of ₹1,000 |
| Fallback rules (tested, not applied) | F1 oldest open invoice; F2 newest open invoice; F3 the only open invoice whose balance is at least the amount |

## 5. Analytical approach

1. **Receipts** (`sahyadri_b2b.ca_receipts`): every payment with its instalment number, the number of payments on its order and a round-sum flag.
2. **Candidates** (`sahyadri_b2b.ca_candidates`) and **matches** (`sahyadri_b2b.ca_matches`): every open invoice a receipt could pay, and the rule result.
3. **Failure analysis** by receipt type, reason and number of open invoices, and a test of three fallback rules on the unmatched receipts.

## 6. SQL techniques used

- A point-in-time open balance for every receipt × invoice pair, from a `LEFT JOIN` on earlier payments with a date-then-id tie-break
- Rule cascades with `COUNTIF` over candidates (exactly one fit, none, several)
- Scoring a blind matcher against the hidden truth (`matched_order_id = true_order_id`)
- Running totals with `SUM() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)` to classify failures and to recount balances in validation

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One receipt per payment |
| 02 | Instalments are numbered 1 to n on every order |
| 03 | Round-sum flag = an independent recount |
| 04 | Receipt customer and order value = source |
| 05 | Every candidate is the same customer's order placed by the receipt date |
| 06 | **Open balance of the true order = a running-total recount** |
| 07 | **The true order is a candidate exactly when it is open and already placed** |
| 08 | One match result per receipt, from the four categories |
| 09 | R1 and R2 counts = a recount from candidate fits |
| 10 | A matched order is set only for R1/R2 and is one of the receipt's candidates |

## 8. Findings

**How customers pay**

| Payments on the order | Receipts | Average share of the order | Round sums |
|---|---:|---:|---:|
| One | 6,769 | 96.9 % | 0.5 % |
| Two: first / second | 1,391 / 1,391 | 47.0 % / 47.5 % | **67.6 %** / 0.6 % |
| Three: first / second / third | 339 each | 49.2 % / 25.2 % / 25.6 % | **69.0 %** / **50.4 %** / 0.0 % |

- Customers pay **instalments in round sums and settle the remainder exactly.** Every non-final instalment of ₹10,000 or more is a round sum (99.5–99.7 %); below ₹10,000 none are.

**Rules match three receipts in four, and never pick the wrong invoice.**

| Result | Receipts | Share | Value | Value share | Wrong matches |
|---|---:|---:|---:|---:|---:|
| R1 Exact invoice amount | 6,332 | 59.9 % | ₹60.60 crore | 76.4 % | 0 |
| R2 Exact open balance | 1,540 | 14.6 % | ₹7.38 crore | 9.3 % | 0 |
| Ambiguous | 0 | 0.0 % | – | – | – |
| No match | 2,696 | 25.5 % | ₹11.34 crore | 14.3 % | – |

- **74.5 % of receipts and 85.7 % of the money match automatically with 100 % accuracy.** No receipt amount fits two open invoices of the same customer, so the exact rules are never ambiguous.
- The match rate barely depends on how many invoices are open: 78.2 % with 0–1 open, 73.7 % with 11 or more.

**Every failure is a part payment, a short payment or a duplicate.**

| Receipt type | Receipts | Auto-matched |
|---|---:|---:|
| Single payment of the full invoice | 6,325 | **100 %** |
| Single payment, order not fully paid | 444 | 0 % |
| Instalment, not the last | 2,069 | 0.3 % |
| Last instalment | 1,730 | 89.0 % |

| Why the 2,696 unmatched receipts fail | Receipts | Value | Round sums |
|---|---:|---:|---:|
| Instalment, more payments followed | 2,062 | ₹868.7 lakh | 65.3 % |
| Part payment, order still open (₹259.2 lakh left unpaid) | 609 | ₹244.1 lakh | 7.2 % |
| Short payment of ₹500 or less (₹4,086 short in total) | 18 | ₹12.8 lakh | 0 % |
| Duplicate: order already fully paid | 7 | ₹8.0 lakh | 0 % |

- **The 7 duplicates are a control, not a failure.** They are the same ₹8,00,255.77 of receipts recorded twice found by the [order-to-cash reconciliation](../01_order_to_cash_reconciliation/); a matcher that only applies money to open balances refuses them automatically.

**Guessing does not work; one narrow fallback does.**

| Fallback rule on unmatched receipts | Receipts matched | Correct | Wrong |
|---|---:|---:|---:|
| F1 Oldest open invoice | 2,696 | 405 | **2,291** |
| F2 Newest open invoice | 2,696 | 565 | **2,131** |
| F3 Only one open invoice large enough | 390 | **390** | **0** |

- Applying a part payment to the oldest invoice (the usual "FIFO" default) is wrong 85 % of the time: customers pay the invoice they choose, not the oldest one.
- F3 is safe on this data: it would take the automatic rate to **78.2 %** (8,262 receipts) with no errors.
- **If part payments carried an invoice reference, 98.2 % of receipts would match automatically.** The remaining 190 are the final recorded payment on orders still open (183) and the 7 duplicates.

## 9. Business implications and recommendations

1. **Buy the module and switch on the two exact rules.** R1 and R2 take over three receipts in four and 86 % of the value, with no wrong matches on 7,872 receipts.
2. **Ask customers for an invoice number on every part payment.** It is the only change that moves the rate to about 98 %. Put the request on the invoice and on payment reminders.
3. **Add F3 as a third rule, with review.** "Only one open invoice is large enough" matched 390 receipts correctly; keep it on a review queue for the first months before applying it unattended.
4. **Never default part payments to the oldest invoice.** It would misapply 2,291 of the 2,696 unmatched receipts and distort the [receivables roll-forward](../05_receivables_rollforward/) and ageing.
5. **Route round sums to an "on account" queue.** 96.8 % of round-sum receipts (1,346 of 1,390) are instalments with more to follow; holding it as unapplied cash against the customer, until the reference or the final payment arrives, is safer than guessing an invoice.
6. **Set a write-off tolerance for short payments.** 18 receipts were short by ₹500 or less (₹4,086 in total); a small-balance write-off rule would close those invoices without manual work.

## 10. Assumptions and limitations

- **The bank feed is simulated.** Each recorded payment is treated as one bank receipt; in practice one bank credit can pay several invoices, which these rules do not cover.
- **Payment allocation is taken as recorded.** Accuracy is measured against the order each payment was booked to; if bookings are themselves wrong, accuracy is overstated.
- **Exact amounts.** The ₹0.05 tolerance covers rounding only; bank charges or tax deducted at source would need a wider tolerance and would create ambiguous matches.
- **Credit notes and returns** are not in the payments data and are not matched.
- **Rule accuracy is in-sample.** F3 was tested on the same receipts it is reported for; monitor it before relying on it.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Receipt, candidate and match tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
