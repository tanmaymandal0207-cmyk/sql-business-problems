# Case Study · Expected Credit Loss: A Roll-Rate Provision Matrix

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 33 month-ends of receivables ageing (January 2024 – September 2026), roll rates and loss rates by age bucket, three matrix designs back-tested on 15 month-ends against the losses that actually followed, and the provision on the 30 September 2026 book.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-29 |

---

## 1. Business problem

The auditors have asked for an expected credit loss (ECL) provision on trade receivables under the simplified approach of Ind AS 109 / IFRS 9: a provision matrix of loss rates by age, built from the company's own payment history. Today nothing is provided until a balance is written off. The [Monte Carlo collections forecast](../17_monte_carlo_collections_forecast/) showed that receivables older than 180 days are never collected; the CFO now needs a loss rate for every age bucket, a provision for the September book, and evidence that the method would have worked in the past.

## 2. Business questions

1. How fast do receivables roll from one age bucket to the next, and when is an unpaid balance effectively lost?
2. What loss rate applies to each bucket, and what is the provision on today's book?
3. Does one matrix fit all customers, or does each segment need its own?
4. Would the matrix have predicted the losses that actually happened?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Delivered orders, customer |
| `shipments` | One row per shipment | Delivery date (the invoice date) |
| `sales_order_items` | One row per product per order | Invoice value |
| `payments` | One row per receipt | Collections to each month-end |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Receivable | A delivered order (delivery date on every shipment) with more than ₹1 outstanding at a month-end |
| **Age bucket** | Calendar months since the delivery month: 0 = delivered this month, 1, 2 … 6+. Every open item moves exactly one bucket per month-end. |
| **Default** | Still unpaid at bucket 6 (the end of the sixth month after delivery, 153–184 days) |
| **Roll rate** of bucket k | Balance still open one month later ÷ balance in bucket k |
| **Loss rate** of bucket k | Roll rate of k × roll rate of k+1 × … × roll rate of 5; bucket 6+ = 100 % |
| Provision | Outstanding × loss rate |
| Matrix designs | **A** pooled, trailing 12 months of transitions; **B** one matrix per segment, all history to date; **C** pooled, all history to date |
| **Back-test** | At each month-end from January 2025 to March 2026: provision on buckets 0–5 against the balance of the same items still unpaid when they reached bucket 6 |

## 5. Analytical approach

1. **Ageing snapshots** (`sahyadri_b2b.ecl_snapshots`) and **transitions** (`sahyadri_b2b.ecl_transitions`): every open item at every month-end, and its balance one month later.
2. **Matrices** (`sahyadri_b2b.ecl_matrix`): roll and loss rates at every month-end from January 2025, for both history windows, pooled and by segment, using only transitions completed by that date.
3. **Provisions** (`sahyadri_b2b.ecl_provision`): every open item under the three designs, with the loss that actually followed.
4. **Back-test** of the three designs, and losses by delivery quarter.
5. **Today's provision**: the matrix, segment loss rates and totals at 30 September 2026.

## 6. SQL techniques used

- Month-end ageing with a calendar-month index (`year × 12 + month`), so items move one bucket per month regardless of month length
- Balance-weighted roll rates from a self-join of each snapshot to the next month
- A chain product of roll rates with `EXP(SUM(LN(x))) OVER (ORDER BY bucket DESC)`
- A point-in-time rule: each month-end's matrix uses only transitions completed by that date
- Back-testing provisions against realised losses, rebuilt independently from payments in validation

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | **Open book at 30 Sep 2026 = a rebuild from source** (1,421 items, ₹10.96 crore) |
| 02 | Bucket = calendar months since delivery (`DATE_DIFF … MONTH`), capped at 6 |
| 03 | One snapshot per item per month-end, each the last day of a month |
| 04 | Items move one bucket a month and balances never rise |
| 05 | One transition per open item in buckets 0–5, next balance between 0 and today's |
| 06 | Trailing-12-month roll rates = a recount from the snapshots |
| 07 | **Loss rate = an explicit product of the roll rates** (without the window function) |
| 08 | Loss rates lie in 0–1, rise with age, and bucket 6 = 100 % |
| 09 | Three provisions per open item and date, each = balance × loss rate |
| 10 | **The loss that followed = a rebuild from payments** on every back-test date |

## 8. Findings

**A balance still unpaid five months after delivery is lost.**

| Bucket | Balance-months | Roll rate: all | Distributor | Enterprise | Mid-Market | SMB |
|---|---:|---:|---:|---:|---:|---:|
| 0 Delivered this month | ₹78.8 crore | 58.1 % | 24.9 % | **90.6 %** | 48.2 % | 37.7 % |
| 1 | ₹44.4 crore | 38.4 % | 54.3 % | 34.5 % | 36.0 % | 64.7 % |
| 2 | ₹16.5 crore | 50.9 % | 61.4 % | 46.3 % | 50.2 % | 70.0 % |
| 3 | ₹8.1 crore | 73.0 % | 90.9 % | 62.1 % | 73.6 % | **98.5 %** |
| 4 | ₹5.7 crore | 92.0 % | 98.7 % | 84.4 % | 98.6 % | 99.7 % |
| 5 | ₹5.1 crore | **99.3 %** | 100 % | 98.8 % | 99.0 % | 100 % |

- 778 invoices (₹507.8 lakh) have reached bucket 6. **Not one rupee was collected on any of them afterwards**, which makes bucket 6 a clean default point.
- **Collection happens in months 1–3.** The loss rate rises from 13 % in bucket 1 to 34 % in bucket 2 and 67 % in bucket 3.

**The provision on the 30 September 2026 book is ₹6.22 crore, 56.7 % of gross receivables.**

| Bucket | Roll rate | Loss rate | Open items | Outstanding | Provision |
|---|---:|---:|---:|---:|---:|
| 0 Delivered this month | 58.1 % | **7.57 %** | 309 | ₹338.8 lakh | ₹25.6 lakh |
| 1 | 38.4 % | 13.03 % | 158 | ₹131.6 lakh | ₹17.2 lakh |
| 2 | 50.9 % | 33.96 % | 72 | ₹53.4 lakh | ₹18.1 lakh |
| 3 | 73.0 % | 66.69 % | 44 | ₹27.6 lakh | ₹18.4 lakh |
| 4 | 92.0 % | 91.42 % | 32 | ₹22.7 lakh | ₹20.7 lakh |
| 5 | 99.3 % | 99.35 % | 28 | ₹14.2 lakh | ₹14.1 lakh |
| 6+ In default | – | 100 % | 778 | **₹507.8 lakh** | **₹507.8 lakh** |
| **Total** | | | 1,421 | ₹10.96 crore | **₹6.22 crore** |

- **₹5.08 crore is already in default** and needs a full provision or a write-off.
- The expected loss on balances not yet in default adds **₹1.14 crore**: 19.4 % of the ₹5.88 crore in buckets 0–5.

**Segments lose money in different ways, but one matrix gives almost the same total.**

| Loss rate | Bucket 0 | 1 | 2 | 3 | 4 |
|---|---:|---:|---:|---:|---:|
| All | 7.6 % | 13.0 % | 34.0 % | 66.7 % | 91.4 % |
| Distributor | 7.5 % | **29.9 %** | 55.0 % | 89.7 % | 98.7 % |
| Enterprise | 7.5 % | **8.3 %** | 24.0 % | 51.8 % | 83.4 % |
| Mid-Market | 6.3 % | 13.0 % | 36.1 % | 71.8 % | 97.6 % |
| SMB | **16.8 %** | 44.5 % | 68.8 % | 98.2 % | 99.7 % |

- **Enterprise customers pay late but pay**: 90.6 % of their delivery-month balance is still open a month later, yet a one-month-old Enterprise invoice has only an 8.3 % loss rate.
- **Distributors pay at once or not at all**: an invoice still open a month after delivery has a 29.9 % loss rate.
- **SMB loses one rupee in six** of new invoices (16.8 %), more than twice the other segments.
- On today's book the segment matrices give ₹109.9 lakh against ₹114.2 lakh pooled on buckets 0–5 (−₹4.3 lakh). They move provision from Enterprise (−₹12.2 lakh) to Distributors (+₹7.1 lakh) and SMB (+₹1.5 lakh).

**Back-test: a trailing 12-month window lags the cycle; all history to date tracks it.**

| Month-end | Buckets 0–5 | Actual loss | A: pooled, 12 months | B: by segment, all history | C: pooled, all history |
|---|---:|---:|---:|---:|---:|
| Jan 2025 | ₹529.4 lakh | ₹89.2 lakh | +19.5 % | +20.5 % | +19.5 % |
| Apr 2025 | ₹611.4 lakh | ₹95.4 lakh | +81.3 % | +74.0 % | +81.7 % |
| Jun 2025 | ₹387.8 lakh | ₹75.7 lakh | +8.8 % | +15.0 % | +18.1 % |
| Sep 2025 | ₹390.8 lakh | ₹94.6 lakh | **−25.7 %** | −16.3 % | −15.8 % |
| Dec 2025 | ₹563.2 lakh | ₹123.6 lakh | −12.6 % | −8.9 % | −2.7 % |
| Mar 2026 | ₹692.0 lakh | ₹145.0 lakh | −18.6 % | −8.5 % | −7.8 % |

| Design (15 month-ends) | Mean absolute error | Jan–Jun 2025 | Jul 2025 – Mar 2026 | Months under-provided | Worst under / over |
|---|---:|---:|---:|---:|---:|
| A Pooled, trailing 12 months | 22.6 % | 36.5 % | 13.4 % | 9 | −25.7 % / +81.3 % |
| B By segment, all history | **18.0 %** | 34.3 % | 7.2 % | 7 | −16.3 % / +74.0 % |
| C Pooled, all history | 19.1 % | 38.6 % | **6.1 %** | 7 | −15.8 % / +81.7 % |

**The errors come from the loss cycle, which no age matrix can see in advance.**

| Delivered in | Q1 2024 | Q2 2024 | Q3 2024 | Q4 2024 | Q1 2025 | Q2 2025 | Q3 2025 | Q4 2025 | Q1 2026 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Share of value lost | **11.2 %** | 9.5 % | 5.6 % | 7.2 % | **4.4 %** | 5.0 % | **9.3 %** | 7.3 % | 7.7 % |

- In the first half of 2025 every design over-provided by up to 82 %: it had learned from the poor 2024 invoices, while early-2025 invoices were the best ever paid.
- From mid-2025 losses rose again. The 12-month window had by then forgotten 2024 and under-provided in 9 of 15 months; all history to date stayed within about ±16 % from July 2025.

## 9. Business implications and recommendations

1. **Recognise ₹6.22 crore at 30 September 2026.** Fully provide or write off the ₹5.08 crore in default, and book ₹1.14 crore of ECL on the ₹5.88 crore not yet in default.
2. **Use the pooled matrix on all history to date (design C), refreshed every month-end.** It had the smallest error once history covered a full cycle. Keep at least two years of transitions in the window rather than switching to a short rolling window.
3. **Keep one matrix for the provision; use the segment rates for credit decisions.** Segment matrices change the total by ₹4 lakh, but SMB's 16.8 % loss on new invoices and Distributors' 29.9 % at one month are useful signals for credit limits and advance payment terms.
4. **Add a documented overlay when the loss cycle turns.** The share of a quarter's deliveries that reaches default swung from 4.4 % to 9.3 % within two quarters, and it is only known six months later. Review the early roll rates (buckets 0–2, known within three months) every month-end, and record any overlay with its reason.
5. **Put collection effort into months 1–3.** That is where the loss rate rises from 13 % to 67 %; after month 5 nothing comes back. The [late payment scorecard](../15_late_payment_scorecard/) flags at delivery which orders are likely to be paid late.

## 10. Assumptions and limitations

- **Default point chosen from the data.** Nothing has ever been collected after bucket 6; with more history a later recovery could appear.
- **No forward-looking adjustment.** Ind AS 109 / IFRS 9 also requires current and forecast conditions; the overlay in recommendation 4 is where these would go. This study is analysis, not accounting advice.
- **Delivery date is the invoice date.** Credit terms are not recorded, so ageing is from delivery, not from the due date.
- **Debit balances only.** Credit balances (duplicate receipts, advances, refunds due, see the [receivables roll-forward](../../04_data_quality_and_reconciliation/05_receivables_rollforward/)) are not netted against the book.
- **Short history.** 33 months of snapshots give 15 back-test month-ends, and the first six share almost the same training data.
- **Delivered orders with a missing delivery date** (13 invoices in the roll-forward) are excluded.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Snapshot, transition, matrix and provision tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
