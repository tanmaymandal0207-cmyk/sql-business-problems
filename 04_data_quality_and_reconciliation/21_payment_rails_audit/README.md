# Case Study · Payment Rails Audit: Do the Receipts in the Ledger Fit the Rules of the Payment System They Claim to Have Used?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study tests all 10,568 receipts from January 2024 to September 2026 against the rules of the Indian payment rails they are recorded under: RTGS and UPI limits, and cheque clearing days. Because the rules are fixed, the ledger can be checked without the bank statement.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-09 |

---

## 1. Business problem

Every month the bank reconciliation leaves a list of receipts that do not match the bank statement by date or by type, and the accountant clears them by hand. The statutory auditor has asked whether the payment method and date on each receipt can be relied on. Each Indian payment rail has hard rules, so the ledger can be tested against them before anyone opens a bank statement.

## 2. Business questions

1. Do receipts recorded as RTGS or UPI respect those rails' amount limits?
2. Are cheques and demand drafts dated on days the clearing system does not run, and how many of those fall at a month-end?
3. How many receipts have no method at all?
4. How is the mix of payment methods changing, and by segment?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `payments` | One row per receipt | Date, amount, method |
| `sales_orders` | One row per order | Customer |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

**Rules applied** (as published by banks and the RBI; see the sources at the end):

| Rail | Rule |
|---|---|
| RTGS | **Minimum ₹2 lakh**, no maximum; runs 24 × 7 |
| UPI | **₹1 lakh per transaction** for ordinary payments |
| NEFT | No minimum or maximum; runs 24 × 7 |
| Cheques and drafts | Cheque Truncation System: presented **10 am – 4 pm on working days**; from 4 October 2025, cleared and credited within hours |
| Bank holidays | Every Sunday and the **second and fourth Saturday** of the month (national and state holidays not tested) |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Receipts | Every payment dated 1 January 2024 – 30 September 2026 |
| Non-clearing day | A Sunday, or the second or fourth Saturday of the month |
| **RTGS below minimum** | Recorded as RTGS, amount under ₹2 lakh |
| **Instrument on a non-clearing day** | Cheque or draft dated on a non-clearing day |
| **Month-end cut-off** | Cheque or draft dated after the last clearing day of its month: it cannot reach the bank until the next month |

## 5. Analytical approach

1. **Receipts** (`sahyadri_b2b.pr_receipts`) with each rule flag, and the **month-end cut-off list** (`pr_cutoff`) from a calendar of clearing days.
2. **Tests at a glance**, and the baseline: how often electronic receipts fall on the same days.
3. **RTGS below the minimum**: amounts, years, segments.
4. **Cheques on non-clearing days** by year, and the month-ends affected.
5. **Method mix** by year and segment.

## 6. SQL techniques used

- Rules as parameters (`rtgs_minimum`, `upi_limit`) and boolean flag columns, so each test is one `COUNTIF`
- The second and fourth Saturday from `DIV(day − 1, 7) + 1`
- A clearing calendar from `GENERATE_DATE_ARRAY` to find each month's last clearing day
- Validation with an independent calendar: days since a known Sunday, `MOD 7`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Receipts = payments in the window; amounts = source; every receipt has a customer |
| 02 | "Not recorded" exactly where the source method is missing |
| 03 | **Non-clearing days = recount from a fixed Sunday and the day of the month** |
| 04 | RTGS below minimum (recount) |
| 05 | UPI above limit (recount) |
| 06 | Cheque or draft on a non-clearing day (recount) |
| 07 | **Cut-off list = independent recount** |
| 08 | Each cut-off row is after its month's last clearing day |
| 09 | RTGS below + at or above the minimum = all RTGS |
| 10 | Six methods only; the groups add up to all receipts |

## 8. Findings

**Two of the three rules are broken, often.**

| Test | Receipts | Of | Value | Customers |
|---|---:|---:|---:|---:|
| **Recorded as RTGS, below the ₹2 lakh minimum** | **543** | 1,144 RTGS | ₹371.5 lakh | 190 |
| Recorded as UPI, above the ₹1 lakh limit | 0 | 1,758 UPI | – | – |
| **Cheque or draft dated on a non-clearing day** | **564** | 2,689 instruments | ₹316.7 lakh | 199 |
| No payment method recorded | 190 | 10,568 receipts | ₹160.8 lakh | 113 |

**Almost half the "RTGS" receipts cannot have been RTGS.**

| RTGS receipts by amount | Receipts | Value |
|---|---:|---:|
| Under ₹50,000 | 275 | ₹51.2 lakh |
| ₹50,000 – 1 lakh | 79 | ₹55.8 lakh |
| ₹1 – 2 lakh | 189 | ₹264.5 lakh |
| ₹2 lakh and above (valid) | 601 | ₹2,634.5 lakh |

| Segment | RTGS receipts | Below the minimum |
|---|---:|---:|
| SMB | 100 | **80.0 %** |
| Mid-Market | 187 | **78.6 %** |
| Enterprise | 431 | 46.4 % |
| Distributor | 426 | 27.2 % |

- The share is steady from year to year (46–49 %), so this is a standing habit, not a one-off.
- It is worst for small customers, whose payments are rarely ₹2 lakh. These are almost certainly NEFT or IMPS receipts keyed as RTGS. UPI receipts never exceed ₹1 lakh, so that field is entered correctly.

**Cheques are dated on bank holidays as often as electronic payments are.**

| Method | Receipts | Dated on a non-clearing day | On a Sunday |
|---|---:|---:|---:|
| NEFT | 4,787 | 19.5 % | 13.1 % |
| UPI | 1,758 | 21.0 % | 14.1 % |
| RTGS | 1,144 | 20.1 % | 13.9 % |
| **Cheque** | 2,281 | **21.4 %** | **14.9 %** |
| **Demand draft** | 408 | **18.9 %** | 12.7 % |

| Year | Cheques and drafts | On a Sunday | On a 2nd or 4th Saturday | Share | Value |
|---|---:|---:|---:|---:|---:|
| 2024 | 712 | 98 | 42 | 19.7 % | ₹80.6 lakh |
| 2025 | 1,047 | 151 | 60 | 20.2 % | ₹110.5 lakh |
| 2026 (to September) | 930 | 143 | 70 | 22.9 % | ₹125.6 lakh |

- About one day in five is a Sunday or a second or fourth Saturday, and cheques are dated on those days at exactly that rate. The date on a cheque receipt is therefore the day it was booked or received, not the day the bank credited it. That one fact explains most of the date breaks in the bank reconciliation.
- At month-ends the effect is small. 14 cheques and drafts (₹5.8 lakh) were dated after the last clearing day of their month, at 4 of 33 month-ends. The largest was May 2026: 7 instruments, ₹2.91 lakh, dated Sunday 31 May. They count as receipts in May but reach the bank in June.

**The method mix has not changed in three years.**

| Year | Receipts | Electronic (NEFT, RTGS, UPI) | Cheque or draft | Not recorded | Cheque or draft, by value |
|---|---:|---:|---:|---:|---:|
| 2024 | 2,873 | 73.3 % | 24.8 % | 1.9 % | 17.3 % |
| 2025 | 4,084 | 72.5 % | 25.6 % | 1.9 % | 19.7 % |
| 2026 | 3,611 | 72.7 % | 25.8 % | 1.6 % | 18.4 % |

| Segment | Receipts | NEFT | RTGS | UPI | Cheque | Draft | Not recorded |
|---|---:|---:|---:|---:|---:|---:|---:|
| Enterprise | 3,569 | 45.7 % | 12.1 % | 15.5 % | 21.3 % | 3.7 % | 1.8 % |
| Mid-Market | 2,681 | 46.3 % | 7.0 % | 20.1 % | 21.1 % | 4.1 % | 1.4 % |
| SMB | 2,165 | 46.6 % | 4.6 % | 19.5 % | 23.1 % | 4.1 % | 2.1 % |
| Distributor | 2,153 | 42.0 % | 19.8 % | 11.4 % | 21.2 % | 3.6 % | 2.1 % |

A quarter of receipts still come by cheque or draft in every segment, even though cheques now clear within hours.

## 9. Business implications and recommendations

1. **Tell the auditor the method field is not reliable for RTGS.** 543 of 1,144 RTGS receipts (₹3.7 crore) are below the RTGS minimum. Re-label them from the bank statement, where the transaction reference (UTR) shows which rail carried each payment.
2. **Make the method a validated drop-down with amount rules.** Block RTGS under ₹2 lakh and UPI over ₹1 lakh at entry, and make the method mandatory: 190 receipts (₹1.6 crore) have none.
3. **Record two dates on cheque receipts: received and credited.** The ledger records when a cheque was booked, not when it cleared, so one cheque in five is dated on a bank holiday. Reconcile on the credit date to remove most date breaks.
4. **Hold month-end cheques received after the last clearing day as "cheques in hand".** At the four affected month-ends this was ₹5.8 lakh. It is small, but it is a reconciling item the auditor will expect to see named.
5. **Ask cheque-paying customers to move to NEFT.** A quarter of receipts are still cheques or drafts. Each one needs a deposit, can bounce, and creates a date break. NEFT costs little and arrives with a reference.

## 10. Assumptions and limitations

- **National and state bank holidays are not tested.** Only Sundays and the second and fourth Saturdays are; the counts of cheques on non-clearing days are a lower bound.
- **The payment date's meaning is not documented.** The study infers it is the booking date because cheques fall on holidays at the same rate as electronic payments.
- **Bank-specific limits.** Some banks set lower UPI or higher RTGS minimums for particular accounts; the tests use the standard limits.
- **IMPS is not a recorded method.** Small instant transfers keyed as RTGS may have been IMPS rather than NEFT.

**Sources for the rules:** [Axis Bank: RTGS limit](https://www.axis.bank.in/blogs/payments/rtgs-limit) · [Juris Hour: bank transaction limits 2026](https://www.jurishour.in/columns/bank-transaction-limits-2026-cash-upi-gold-rtgs-neft/) · [Bandhan Bank: continuous clearing in the Cheque Truncation System](https://www.bandhan.bank.in/sites/default/files/2025-09/Introduction-of-Continuous-Clearing-and-Settlement-on-Realisation-in-the-Cheque-Truncation-System.pdf)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Receipt and cut-off tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
