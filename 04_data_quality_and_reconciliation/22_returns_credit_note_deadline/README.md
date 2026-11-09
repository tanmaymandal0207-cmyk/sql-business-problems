# Case Study · Returned Goods and the GST Credit-Note Deadline: What Must Be Credited Before 30 November, What Is Already Out of Time, and What Receivables Overstate

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study takes all 75 returned orders from January 2024 to September 2026 and sets each against the GST deadline for its credit note. It lists the 29 returns that must be credited by 30 November 2026, sizes the GST already out of time, and shows how much returned orders still inflate receivables. It also lists other money held for customers on orders never delivered.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-09 |

---

## 1. Business problem

When a customer returns goods, the original tax invoice still stands. The output GST paid on it comes back only through a credit note. A credit note reduces GST only if it is declared by 30 November after the end of the financial year of the original supply. Since 1 October 2025, it also reduces GST only if the customer has reversed the input tax credit it took. The accountant has never matched returns to credit notes, and the 2025-26 deadline is three weeks away. This study is dated 9 November 2026.

## 2. Business questions

1. How many returned orders are there by financial year of supply, and how much GST is at stake against each deadline?
2. Which returns must be credited, with the customer's ITC reversal confirmed, before 30 November 2026?
3. How much do returned orders still inflate receivables?
4. What other money is held for customers on orders that were never delivered?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, customer, payment flag |
| `sales_order_items` | One row per product per order | Taxable value |
| `shipments` | One row per shipment | Invoice date, return date, status |
| `payments` | One row per receipt | Money received |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

**Rules applied** (as summarised by GST practitioners; see the sources at the end):

| Rule | Value |
|---|---|
| Section 34(1) | A credit note may be issued when the recipient returns goods |
| Section 34(2) time limit | Declared **no later than 30 November following the end of the financial year** of the supply, or the annual return date if earlier; after that the output tax cannot be reduced |
| ITC reversal condition | **From 1 October 2025**, output tax is reduced only if the registered recipient has reversed the input tax credit on the credit note |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Returned order | Order status Returned (every shipment of each such order has status Returned) |
| Invoice date / value / GST | First shipment date / order value after discount / 18 % |
| Financial year of supply | April – March of the invoice date |
| **Credit-note deadline** | 30 November of the year in which that financial year ends |
| Return date | Last delivery date of the returned shipments (the data has no separate date for goods coming back) |
| Report date | 9 November 2026 |
| Money held | Receipts on cancelled orders and on orders with no shipment |

## 5. Analytical approach

1. **Returned orders** (`sahyadri_b2b.cn_returns`) with invoice and return dates, value, GST, financial year and deadline.
2. **GST at stake** by financial year and deadline status, and how close returns come to their deadline.
3. **The list for 30 November 2026**, by customer and segment.
4. **Receivables**: open value of returned orders and its age.
5. **Money held** on cancelled and never-shipped orders.

## 6. SQL techniques used

- A statutory deadline built from the invoice date: `DATE(EXTRACT(YEAR FROM DATE_SUB(invoice_date, INTERVAL 3 MONTH)) + 1, 11, 30)`
- Deadline status relative to a fixed report date, so the result is reproducible
- Validation of the deadline by an independent route: year + 1 for April – December invoices, the same year for January – March

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Returned orders = status Returned; taxable value = source |
| 02 | GST = 18 % of taxable value |
| 03 | **Deadline = 30 November of the year the financial year ends** (recount from the invoice month) |
| 04 | Invoice date = first shipment; return date = last delivery |
| 05 | Every returned order was fully returned |
| 06 | Received = recount, and nothing was paid on any returned order |
| 07 | Financial-year totals add up |
| 08 | **Due by 30 November 2026 = invoiced April 2025 – March 2026** (independent recount) |
| 09 | Out of time = invoiced before April 2025 |
| 10 | Return date on or after the invoice date, within 30 days |

## 8. Findings

**₹4.32 lakh of GST on returns is already out of time. ₹4.06 lakh more falls due on 30 November 2026.**

| Financial year of supply | Credit-note deadline | Status on 9 November 2026 | Returned orders | Customers | Taxable value | GST |
|---|---|---|---:|---:|---:|---:|
| 2023-24 (January – March 2024) | 30 Nov 2024 | Passed | 6 | 6 | ₹3.38 lakh | ₹0.61 lakh |
| 2024-25 | 30 Nov 2025 | Passed | 26 | 22 | ₹20.63 lakh | ₹3.71 lakh |
| **2025-26** | **30 Nov 2026** | **Due in 21 days** | **29** | 26 | ₹22.53 lakh | **₹4.06 lakh** |
| 2026-27 (to September) | 30 Nov 2027 | Open | 14 | 14 | ₹15.97 lakh | ₹2.87 lakh |

- Goods come back about 4–5 days after the invoice, and every return arrived at least 237 days before its deadline. Lack of time is not the reason a credit note would be missed.
- If no credit notes were issued for 2023-24 and 2024-25, the company has paid ₹4.32 lakh of GST on goods it took back, and can no longer recover it.

**The 2025-26 list: 29 returns from 26 customers, all needing the customer's ITC reversal.**

| Largest, by GST | Segment | Returned orders | Invoiced | Taxable value | GST |
|---|---|---:|---|---:|---:|
| Siddhivinayak Mishra Trading Co. | Distributor | 2 | Jul – Aug 2025 | ₹5.95 lakh | ₹1,07,097 |
| Galaxy Garg Industrial Suppliers | Distributor | 1 | Jan 2026 | ₹2.08 lakh | ₹37,512 |
| Mittal Traders | Distributor | 1 | Mar 2026 | ₹1.91 lakh | ₹34,468 |
| Mahavir Pillai Spinning Mills Pvt Ltd | Enterprise | 2 | Apr – Nov 2025 | ₹1.86 lakh | ₹33,412 |
| Trimurti Traders | Distributor | 1 | Sep 2025 | ₹1.59 lakh | ₹28,575 |

| Segment | Due by 30 Nov 2026 | GST due | Already out of time | GST out of time |
|---|---:|---:|---:|---:|
| Distributor | 8 | ₹2.64 lakh | 5 | ₹1.67 lakh |
| Mid-Market | 8 | ₹0.72 lakh | 4 | ₹0.54 lakh |
| Enterprise | 8 | ₹0.61 lakh | 14 | ₹1.91 lakh |
| SMB | 5 | ₹0.08 lakh | 9 | ₹0.21 lakh |

Distributors account for 65 % of the GST due. Credit notes issued now fall under the ITC reversal rule, so each customer must confirm the reversal in its own return before the company's GST is reduced.

**Returned orders still sit in receivables as ₹73.8 lakh owed.**

| | Value |
|---|---:|
| Returned orders | 75, all flagged Unpaid, none with any receipt |
| Open taxable value | ₹62.52 lakh |
| **Open invoice value including GST** | **₹73.77 lakh** |
| Average age on 9 November 2026 | 525 days |
| Older than 180 days | 63 |

Unless credit notes were posted, these 75 invoices appear in the receivables ledger as unpaid and mostly very old. They inflate receivables, DSO and the over-180-day balance by money nobody owes.

**₹3.2 lakh is held for customers on orders that were never delivered.**

| Situation | Orders | Received | Oldest receipt | Average days held |
|---|---:|---:|---|---:|
| Cancelled order | 6 | ₹0.72 lakh | 30 Jun 2024 | 597 |
| No shipment, but status Delivered | 4 | ₹2.16 lakh | 15 Apr 2024 | 695 |
| No shipment, status Pending | 1 | ₹0.15 lakh | 30 Sep 2026 | 40 |
| No shipment, status Processing | 1 | ₹0.14 lakh | 16 Sep 2026 | 54 |

The cancelled-order refunds were first flagged in the [cancellation and return leakage](../../03_operations_and_supply_chain/06_cancellation_return_leakage/) study and are still unresolved. The four "Delivered" orders with no shipment are a data error: either the shipment record is missing or the money belongs to the customer.

## 9. Business implications and recommendations

1. **Issue the 29 credit notes for 2025-26 returns this week**, and declare them in the November GSTR-1. That recovers ₹4.06 lakh of GST. Ask each of the 26 customers to confirm the ITC reversal before the return is filed.
2. **Check whether credit notes exist for the 32 earlier returns.** If not, ₹4.32 lakh of GST is lost. Issue commercial credit notes anyway, so the customers' ledgers are cleared, but without a GST reduction.
3. **Clear the ₹73.8 lakh of returned invoices out of receivables.** Post the credit notes against them, then re-run the receivables reports. The [DSO](../19_dso_formula_comparison/) and [expected credit loss](../../05_advanced_analytics/19_expected_credit_loss_provision/) studies used Delivered orders only, but the ledger the auditor sees may not.
4. **Make a credit note part of receiving a return.** Goods come back within about five days, so the credit note can be raised the day the return is received, months before any deadline.
5. **Refund or apply the ₹3.2 lakh held**, and fix the four "Delivered" orders that have no shipment.

## 10. Assumptions and limitations

- **Not tax advice.** The rules are as summarised by GST practitioners; confirm the position, including any annual-return date earlier than 30 November, with the tax adviser.
- **Credit notes are not in the data.** The study lists what should have been credited; some may already have been issued.
- **GST at 18 % on every product**, on the full order value. Every returned order was returned in full.
- **Return date is the delivery date of the returned shipment**, the closest proxy in the data.
- **All customers are treated as GST-registered businesses.** For an unregistered buyer the ITC test is replaced by a test that the tax was not passed on.

**Source for the rules:** [TaxGarden: GST debit and credit notes under section 34 (2026)](https://taxgarden.in/blog/gst-debit-note-credit-note-section-34-rules-india-2026)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Returned-order table and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
