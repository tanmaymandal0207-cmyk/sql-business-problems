# Case Study · GST Paid Before the Customer Pays: How Much Cash It Ties Up, and How Much Is Lost on Bad Debts

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study follows the GST on 7,651 invoices from April 2024 to June 2026. Each invoice's GST is paid to the government on the 20th of the following month and comes back only when the customer pays. It measures how long the company carries that GST, what it costs, and how much has been paid on invoices that will probably never be collected.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-08 |

---

## 1. Business problem

GST is due on the invoice, not on the cash. Every month the company pays the GST on last month's invoices by the 20th, but customers pay weeks later and some never pay, and there is no GST refund for bad debts. The CFO thinks the company is quietly financing its customers' tax. She wants it measured before the next round of credit-term negotiations.

## 2. Business questions

1. On average, how long does the company carry the GST before the customer's payment brings it back?
2. How much GST is outstanding at a typical month-end, and what does that cost?
3. Which customers make it worst?
4. How much GST has been paid on invoices that will probably never be collected?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, status |
| `sales_order_items` | One row per product per order | Taxable value |
| `shipments` | One row per shipment | Invoice date (first shipment) |
| `payments` | One row per receipt | When the GST comes back |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

**Rules applied** (as summarised by GST practitioners; see the sources at the end):

| Rule | Value |
|---|---|
| When GST is due | On the invoice; paid with the monthly return **GSTR-3B by the 20th of the following month** |
| Bad debts | **No GST refund**; a credit note cannot be issued just because the customer did not pay |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Invoice | A valid order (not Cancelled or Returned) with a shipment; invoice date = first shipment date; dated April 2024 – June 2026 |
| GST | **18 % of the taxable value** (assumed for every product) |
| GST due date | The 20th of the month after the invoice |
| **GST collected** | Each receipt carries GST in proportion: receipt ÷ taxable value × GST, capped at the invoice's GST. Receipts in the data carry the taxable value. |
| **Funded rupee-days** | GST collected × days from the due date to the receipt (if later), plus GST still uncollected × days from the due date to 30 September 2026 |
| Float rupee-days | GST collected × days by which the receipt came **before** the due date |
| **GST funded at a month-end** | GST due by that date − GST collected by that date |
| Cost of money | 12 % a year (as in the [early-payment discount](../21_early_payment_discount/) study) |
| Probably lost | GST on balances still open more than 180 days after the due date. The collections studies found almost nothing is collected after 180 days. |

## 5. Analytical approach

1. **Invoices** (`sahyadri_b2b.gs_invoices`), **GST in each receipt** (`gs_receipts`) and **funding per invoice** (`gs_funding`).
2. **How long and how much**: average days carried, and the balance at every month-end (`gs_month_ends`) with its cost.
3. **Segments and customers** that drive the funding.
4. **GST probably lost**: open balances by age.

## 6. SQL techniques used

- A tax due date from the invoice month: `DATE_ADD(DATE(year, month, 20), INTERVAL 1 MONTH)`
- Pro-rata allocation of each receipt to the invoice's GST, capped with a running total over earlier receipts (`ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING`)
- Rupee-days as the common unit for "how much for how long", turned into a cost with the cost of money
- A point-in-time balance at every month-end from two joins (paid by then, collected by then)

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Invoices = valid shipped orders invoiced April 2024 – June 2026; value = source |
| 02 | GST = 18 % of value, due on the 20th of the following month |
| 03 | **GST collected = MIN(receipts, value) ÷ value × GST**, per invoice |
| 04 | Uncollected GST = GST − collected, never negative |
| 05 | **Funded and float rupee-days = recount** from receipts and open balances |
| 06 | A receipt is either after the due date (funded) or before it (float), never both |
| 07 | **Month-end balance = GST due by then − GST collected by then** (December 2025 recount) |
| 08 | 27 month-ends, May 2024 – July 2026 |
| 09 | Receipts only to 30 September 2026, only on study invoices |
| 10 | GST collected per invoice never exceeds its GST; receipts add up to it |

## 8. Findings

**The company carries its customers' GST for about three weeks on average, and much longer for some.**

| | Value |
|---|---:|
| Invoices | 7,651 |
| Taxable value | ₹73.40 crore |
| GST paid to the government | **₹13.21 crore** |
| GST recovered from customers by 30 September 2026 | 93.2 % |
| Average days between paying the GST and getting it back (collected GST) | **22.3 days** |
| Average days by which customers paid **before** the GST was due | 3.9 days |
| GST on invoices paid after the due date, or still open | 87.3 % |

Few customers pay within the three to seven weeks between the invoice and the 20th of the next month. For most of the GST, the company pays first and waits.

**The GST funded at month-end has nearly quadrupled in two years, and old debt is a growing part of it.**

| Quarter-end | GST paid but not yet collected | Of which over 180 days past due |
|---|---:|---:|
| Jun 2024 | ₹35.6 lakh | – |
| Sep 2024 | ₹50.7 lakh | – |
| Dec 2024 | ₹53.8 lakh | ₹7.9 lakh |
| Mar 2025 | ₹78.5 lakh | ₹16.5 lakh |
| Jun 2025 | ₹69.5 lakh | ₹24.2 lakh |
| Sep 2025 | ₹77.6 lakh | ₹32.9 lakh |
| Dec 2025 | ₹95.2 lakh | ₹39.3 lakh |
| Mar 2026 | ₹113.3 lakh | ₹48.6 lakh |
| Jun 2026 | ₹129.6 lakh | ₹59.3 lakh |

| | Value |
|---|---:|
| Average month-end balance (May 2024 – July 2026) | ₹80.3 lakh |
| Peak | **₹134.3 lakh** (May 2026) |
| **Cost at 12 % a year, latest 12 months** | **₹12.82 lakh a year** |

**Enterprise customers cause more than half of the funding.** Over April 2024 – September 2026:

| Segment | Invoices | GST | Days carried per rupee of GST | Funding cost | Share |
|---|---:|---:|---:|---:|---:|
| **Enterprise** | 2,617 | ₹548.3 lakh | **68.1** | ₹12.28 lakh | **56.1 %** |
| Mid-Market | 1,879 | ₹183.0 lakh | 42.0 | ₹2.53 lakh | 11.6 % |
| SMB | 1,604 | ₹72.6 lakh | 36.7 | ₹0.88 lakh | 4.0 % |
| Distributor | 1,551 | ₹517.2 lakh | 36.5 | ₹6.20 lakh | 28.3 % |

| Customer | Segment | GST | Days carried per rupee | Funding cost | GST still uncollected |
|---|---|---:|---:|---:|---:|
| Hindustan Joshi Agencies | Distributor | ₹8.58 lakh | **566** | ₹1.60 lakh | ₹5.63 lakh |
| Krishna Castings Ltd | Enterprise | ₹77.03 lakh | 58 | ₹1.47 lakh | ₹4.56 lakh |
| Mahavir Pillai Spinning Mills Pvt Ltd | Enterprise | ₹48.30 lakh | 63 | ₹1.00 lakh | ₹3.80 lakh |
| Sudarshan Autoparts Pvt Ltd | Enterprise | ₹31.87 lakh | 78 | ₹0.82 lakh | ₹1.85 lakh |
| Saraswati Mehta Flexipack Pvt Ltd | Enterprise | ₹20.87 lakh | 112 | ₹0.77 lakh | ₹3.16 lakh |

**₹70.8 lakh of GST has been paid on invoices that will probably never be collected.** Status on 30 September 2026:

| Status | Invoices | GST uncollected | Taxable value uncollected |
|---|---:|---:|---:|
| Fully collected | 6,851 | – | – |
| Open, up to 90 days past the GST due date | 42 | ₹4.32 lakh | ₹23.98 lakh |
| Open, 91–180 days | 107 | ₹14.88 lakh | ₹82.65 lakh |
| **Open, over 180 days (probably lost)** | **651** | **₹70.84 lakh** | **₹393.58 lakh** |

A bad debt costs the company the invoice plus 18 % on top: the GST on the ₹3.94 crore that is probably lost was paid in full and cannot be reclaimed.

## 9. Business implications and recommendations

1. **Price the GST into credit terms.** For customers paying 60+ days after invoice, the company funds 18 % of the invoice for one to two months. An early-payment incentive or a shorter credit period for Enterprise accounts is worth up to about ₹13 lakh a year at today's balances.
2. **Treat bad-debt risk as 118 % of the invoice.** Credit limits and provisioning should count the GST already paid, since it is lost along with the receivable.
3. **Chase the 651 invoices more than 180 days past due.** Their GST alone is ₹70.8 lakh. For any that will not be paid, check with the tax adviser whether a credit note or other route is available before writing them off.
4. **Watch Hindustan Joshi Agencies.** The company has carried its GST for an average of 566 days per rupee: most of its invoices are long overdue.
5. **Report "GST funded" in the monthly cash pack.** It grew from ₹36 lakh to ₹128 lakh in two years and is invisible in DSO.

## 10. Assumptions and limitations

- **Not tax advice.** The rules are as summarised by GST practitioners; check credit-note and other options with the tax adviser.
- **18 % GST on every product.** Products taxed at 5 % or 12 % reduce the amounts in proportion.
- **Gross output GST.** Input tax credit reduces the cash paid to the government each month, but it does not change the timing gap: the company still parts with the GST, in cash or credit, before the customer pays.
- **Invoice date = first shipment date**; GST on later shipments of split orders may fall due a month later.
- **Receipts assumed to carry GST pro rata.** A customer that pays the GST portion first, or withholds it, changes the timing.

**Sources for the rules:** [CA Rajput: challenges MSMEs face due to accrual-based GST](https://carajput.com/blog/?p=29448) · [TaxGuru: GSTR-3B FAQs](https://taxguru.in/?p=621817)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Invoice, receipt, funding and month-end tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
