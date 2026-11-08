# Case Study · TDS on Purchase of Goods: What Our Customers Should Deduct, and What to Reconcile

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study applies the TDS rule on purchases of goods to every invoice from April 2024 to September 2026. It finds the customers who cross ₹50 lakh in each financial year and builds the quarterly schedule of TDS credits that should appear in our tax statement. It then checks whether customers' receipts show the deduction and sizes the old TCS exposure for 2024-25.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-08 |

---

## 1. Business problem

A large buyer must deduct TDS of 0.1 % on its purchases from a supplier above ₹50 lakh in a financial year. This was section 194Q, and is section 393(1) of the Income-tax Act 2025 from 1 April 2026. The tax deducted is our money: it appears as a credit in our tax statement (Form 26AS / AIS) once the buyer files its TDS return, and we set it against our own tax. Until March 2025, the seller also had to collect TCS from such buyers (section 206C(1H)) unless they deducted TDS. The accountant has never reconciled any of it and wants to know what should be there.

## 2. Business questions

1. Which customers cross ₹50 lakh in each financial year, and when?
2. How much TDS should each deduct, by quarter, so the credits in our tax statement can be checked?
3. Do customers' receipts show the deduction, or do they pay in full?
4. What TCS exposure did the old rule leave for 2024-25?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, status |
| `sales_order_items` | One row per product per order | Taxable value |
| `shipments` | One row per shipment | Invoice date (first shipment) |
| `payments` | One row per receipt | Receipts per invoice and per year |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

**Rules applied** (as summarised by tax practitioners; see the sources at the end):

| Rule | Value |
|---|---|
| TDS on purchase of goods | The buyer deducts **0.1 %** of the amount by which its purchases from one seller in a financial year exceed **₹50 lakh**, when the purchase is booked or paid, whichever is earlier |
| Value | **Excluding GST** where GST is shown separately (CBDT Circular 13/2021) |
| Who must deduct | Buyers with turnover above ₹10 crore in the previous year |
| TCS on sale of goods (206C(1H)) | 0.1 % of receipts from a buyer above ₹50 lakh in a year, not needed where the buyer deducted TDS. **Not collected on sales from 1 April 2025** (Finance Act 2025). |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Invoice | A valid order (not Cancelled or Returned) with a shipment; invoice date = first shipment date (the GST invoice travels with the goods); taxable value = order value after discount |
| Financial year | April – March; 2024-25, 2025-26 and 2026-27 to September 2026 |
| **Running total** | The customer's purchases in the financial year up to and including the invoice |
| **Amount above ₹50 lakh** | MAX(0, running total − ₹50 lakh) − MAX(0, running total before the invoice − ₹50 lakh) |
| **Expected TDS** | 0.1 % × amount above ₹50 lakh |
| Deducting customers | Every customer crossing ₹50 lakh; customers' turnover is not in the data. A sensitivity keeps only Enterprise and Distributor customers. |
| Receipt pattern | Settled net of TDS (within ₹1 of value − TDS), paid in full, part paid, or nothing received |

## 5. Analytical approach

1. **Invoices** (`sahyadri_b2b.td_invoices`) with the running total per customer and financial year, the amount above ₹50 lakh and the expected TDS.
2. **Customer-years** (`sahyadri_b2b.td_customers`): who crosses, when, and how much TDS; the quarterly schedule.
3. **Receipts**: whether payments show the deduction.
4. **TCS 2024-25** (`sahyadri_b2b.td_tcs`): receipts above ₹50 lakh per customer.

## 6. SQL techniques used

- A statutory threshold applied invoice by invoice with a running `SUM() OVER (PARTITION BY customer, financial year ORDER BY date)`
- The portion of each invoice above the threshold: `GREATEST(0, cum − limit) − GREATEST(0, cum − value − limit)`
- A financial-year key from `DATE_SUB(date, INTERVAL 3 MONTH)`
- Validation of the running total by self-join, and of the crossing date from both sides

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Invoices = valid shipped orders in the window; value = source |
| 02 | Financial year runs April – March |
| 03 | **Running total = recount of earlier invoices** in the same customer-year |
| 04 | Amount above ₹50 lakh per customer-year = MAX(0, purchases − ₹50 lakh) |
| 05 | TDS = 0.1 % of the amount above, invoice by invoice and in total |
| 06 | Customers over ₹50 lakh have a crossing date, and only they do |
| 07 | **Crossing date: running total at or below ₹50 lakh before it, above it by the end of that day** |
| 08 | Customer-year purchases add up to all invoices |
| 09 | The quarterly schedule adds up to the total expected TDS |
| 10 | TCS base 2024-25 = receipts above ₹50 lakh per customer (recount) |

## 8. Findings

**In a full year, 13 to 16 customers cross ₹50 lakh, and they carry about 40 % of sales.**

| Financial year | Customers buying | Over ₹50 lakh | Their share of sales | Purchases above ₹50 lakh | Expected TDS | Invoices carrying TDS | If only Enterprise and Distributor deduct |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2024-25 | 323 | 13 | 42.4 % | ₹6.50 crore | **₹65,017** | 389 | ₹65,017 |
| 2025-26 | 350 | 16 | 41.3 % | ₹5.39 crore | **₹53,888** | 382 | ₹52,962 |
| 2026-27 (to September) | 320 | 6 | 32.5 % | ₹3.80 crore | ₹37,951 | 144 | ₹37,951 |

- The segment assumption barely matters: almost every customer that crosses ₹50 lakh is an Enterprise or Distributor account.
- Customers cross all through the year. In 2024-25, 5 of the 13 crossed in March, with the year-end peak.

**The reconciliation schedule: TDS credits that should appear in our tax statement**

| Quarter | Deducting customers | Invoices | Expected TDS |
|---|---:|---:|---:|
| Apr – Jun 2024 | 2 | 25 | ₹5,048 |
| Jul – Sep 2024 | 4 | 60 | ₹11,333 |
| Oct – Dec 2024 | 8 | 129 | ₹18,172 |
| Jan – Mar 2025 | 13 | 175 | ₹30,463 |
| Jul – Sep 2025 | 2 | 20 | ₹3,401 |
| Oct – Dec 2025 | 9 | 116 | ₹16,834 |
| Jan – Mar 2026 | 16 | 246 | ₹33,653 |
| Apr – Jun 2026 | 3 | 39 | ₹10,437 |
| Jul – Sep 2026 | 6 | 105 | ₹27,515 |

No customer crossed ₹50 lakh in April – June 2025, so that quarter should show no credits. The credits are back-loaded: January – March carries 47 % of the 2024-25 TDS and 62 % of the 2025-26 TDS.

| Largest expected deductors, 2025-26 | Segment | Purchases | Crossed on | Expected TDS | Invoices |
|---|---|---:|---|---:|---:|
| Siddhivinayak Mishra Trading Co. | Distributor | ₹170.4 lakh | 30 Jul 2025 | ₹12,036 | 74 |
| Krishna Castings Ltd | Enterprise | ₹140.4 lakh | 27 Aug 2025 | ₹9,040 | 84 |
| Maa Joshi Industrial Suppliers | Distributor | ₹117.9 lakh | 3 Oct 2025 | ₹6,793 | 43 |
| Mahavir Pillai Spinning Mills Pvt Ltd | Enterprise | ₹112.1 lakh | 6 Dec 2025 | ₹6,210 | 39 |
| Sudarshan Autoparts Pvt Ltd | Enterprise | ₹85.0 lakh | 23 Oct 2025 | ₹3,501 | 17 |

**No receipt shows the deduction.**

| Invoices with TDS due | Invoices | Expected TDS |
|---|---:|---:|
| Settled net of TDS | **0** | – |
| Paid in full (no deduction visible) | 735 | ₹1,34,307 |
| Part paid | 69 | ₹7,460 |
| Nothing received yet | 111 | ₹15,089 |

Every settled invoice that should carry TDS was paid in full. Either customers are not deducting, or receipts are booked gross with the TDS posted somewhere else. Either way, the ₹1.57 lakh of expected credits has never been matched.

**The old TCS rule left an exposure for 2024-25.** Seven customers paid us more than ₹50 lakh in 2024-25, ₹4.92 crore above the limit. If they did not deduct TDS, we should have collected **₹49,184** of TCS.

## 9. Business implications and recommendations

1. **Reconcile Form 26AS / AIS against this schedule, quarter by quarter.** Expect about ₹65,000 for 2024-25 and ₹54,000 for 2025-26 from 13–16 customers. Any credit missing after the buyer's quarterly return is due should be chased with that customer.
2. **Ask the 16 customers for their TDS certificates (Form 16A).** Their invoices were all paid in full, so either they did not deduct (their default) or our receipt entries need a TDS line.
3. **Settle the 2024-25 TCS question.** For the seven customers whose receipts passed ₹50 lakh, confirm whether each deducted TDS. Where none did, ₹49,184 of TCS was due from us, with interest.
4. **Book receipts net of TDS from now on.** Record "amount received + TDS deducted = invoice value", so the receivables ledger and the tax credit agree. Otherwise every TDS invoice looks short-paid by 0.1 % or leaves a tiny open balance.
5. **Flag customers as they approach ₹50 lakh in the year**, so the TDS clause and the PAN check (5 % if no PAN) are in place before the invoice that crosses.

## 10. Assumptions and limitations

- **Not tax advice.** The rules are as summarised by tax practitioners; confirm the position under the Income-tax Act 2025 and any notifications with the tax adviser.
- **Customers' turnover is unknown.** A customer buying over ₹50 lakh from us may still be below ₹10 crore turnover and not need to deduct; the expected TDS is an upper bound.
- **Invoice date = first shipment date**, and value excludes GST. Customers booking the purchase on receipt of goods would push some crossings a few days later.
- **The 2026-27 figure is half a year.** Crossings in October 2026 – March 2027 will add to it.
- **TCS uses receipts by payment date** and treats every receipt from 1 April 2024 to 31 March 2025 as from that year's sales.

**Sources for the rules:** [TDSMAN: TDS on purchase of goods, section 393(1) (section 194Q)](https://blog.tdsman.com/2026/07/tds-on-purchase-of-goods-section-3931-section-194q/) · [Income Tax Department: TDS on purchase of goods](https://www.incometaxindia.gov.in/w/tds-on-purchase-of-goods) · [CalcGuru: section 194Q vs 206C(1H) after TCS on goods was scrapped](https://calcguru.in/?p=8271)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Invoice, customer-year and TCS tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
