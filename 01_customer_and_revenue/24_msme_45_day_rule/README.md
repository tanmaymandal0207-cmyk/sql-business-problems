# Case Study · The MSME 45-Day Rule: How Much of Our Receivables Breach It, What Interest the Law Allows, and Which Customers It Pressures

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study applies the MSME payment rules to every fully delivered invoice accepted from April 2024 to June 2026, with receipts to September 2026. It measures how much is paid after 45 days and the interest the law would allow. It also lists the customers that owed money past 45 days at their year-end, which costs them their tax deduction.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-08 |

---

## 1. Business problem

Indian law protects micro and small manufacturers. A buyer must pay within the agreed period, at most 45 days from accepting the goods (15 days if nothing is agreed in writing). Late payments carry compound interest at three times the RBI bank rate. Since 2024, a buyer that has not paid by its year-end cannot deduct the purchase for tax (section 43B(h)). The company is considering registering as a small enterprise (Udyam) to use these rules with its slow payers. The CFO wants to know what is at stake before deciding.

## 2. Business questions

1. How much of what customers pay arrives after 45 days, and how late?
2. How much interest would the law have allowed us to claim?
3. Which customers owed us money past 45 days at their year-end, and so would lose their tax deduction?
4. How should the rules be used?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, status |
| `sales_order_items` | One row per product per order | Invoice amount |
| `shipments` | One row per shipment | Acceptance date (last delivery) |
| `payments` | One row per receipt | Settlement dates |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

**Rules applied** (as summarised by tax practitioners; see the sources at the end):

| Rule | Value |
|---|---|
| Payment period (MSMED Act, section 15) | As agreed in writing, **at most 45 days from acceptance**; 15 days without a written agreement |
| Interest on late payment | **Compound, with monthly rests, at three times the RBI bank rate** |
| Section 43B(h) | A buyer's purchase from a micro or small enterprise is deductible only when paid, if paid after the time limit; from 2024-25; covers manufacturers and service providers, not traders |
| RBI bank rate | **5.50 %** (since December 2025), so 16.5 % a year; 6.75 % (the 2024 rate) gives 20.25 % |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Invoice | A Delivered order with every shipment delivered; accepted April 2024 – June 2026 |
| Acceptance / due date | Last delivery date; due = acceptance + 45 days (a written 45-day agreement is assumed) |
| Amount | Order value after discount, which is what receipts carry (GST would add 18 %) |
| Item | Each receipt, capped at what was still owed, plus the balance open on 30 September 2026 |
| **Days late** | MAX(0, settlement date − due date); open balances are measured to 30 September 2026 |
| **Interest** | Amount × ((1 + 3 × bank rate ÷ 12)^(days late × 12 ÷ 365) − 1) |
| **43B(h) exposure** | Amounts owed on 31 March 2025 and 2026 (customers' year-end assumed) that were then more than 45 days past acceptance |

## 5. Analytical approach

1. **Invoices** (`sahyadri_b2b.ms_invoices`), **receipts and open balances** (`ms_items`) and **interest per item** (`ms_interest`).
2. **How late**: share paid after 45 days and the distribution of days from acceptance.
3. **Interest** by segment and customer, at two bank rates.
4. **Year-end exposure** (`ms_year_end`) for section 43B(h).

## 6. SQL techniques used

- Receipts allocated to invoices with a running cap (`LEAST(amount, invoice − earlier receipts)`), so overpayments never count
- Paid and open items in one table with `UNION ALL`, so every rupee of every invoice is measured once
- Statutory compound interest with monthly rests in one expression: `POW(1 + 3 × r ÷ 12, months) − 1`
- Point-in-time balances at two year-ends from a payments join filtered to `<= year_end`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Invoices = fully delivered orders accepted in the window; amount = source |
| 02 | Due date = acceptance + 45 days |
| 03 | **Receipts settled + balance open = invoice amount, for every invoice** |
| 04 | Receipts never settle more than the invoice |
| 05 | Days late and days from acceptance = recount |
| 06 | **Interest = the statutory formula**; zero when on time |
| 07 | Open balances dated 30 September 2026; receipts never after it |
| 08 | **Owed at 31 March 2026 = amount − payments by then** (recount) |
| 09 | "Past 45 days" = more than 45 days between acceptance and the year-end |
| 10 | Interest is never negative, and higher at the 2024 bank rate |

## 8. Findings

**More than half of what customers pay arrives after 45 days.**

| | Items | Amount | Beyond 45 days | Beyond 15 days | Average days from acceptance | Average days late, when late |
|---|---:|---:|---:|---:|---:|---:|
| **Paid** | 9,189 | ₹68.42 crore | **51.9 %** | 92.7 % | 48.5 | 23.9 |
| Open on 30 September 2026 | 801 | ₹5.00 crore | 100 % | 100 % | 468.3 | 423.3 |

| Paid after acceptance | Receipts | Amount | Share |
|---|---:|---:|---:|
| Within 15 days | 1,314 | ₹5.01 crore | 7.3 % |
| 16–45 days | 3,154 | ₹27.87 crore | 40.7 % |
| **46–90 days** | 3,883 | ₹30.85 crore | **45.1 %** |
| 91–180 days | 835 | ₹4.67 crore | 6.8 % |
| Over 180 days | 3 | ₹0.01 crore | 0.0 % |

Most late payment is moderately late: 45 % of receipts arrive between day 46 and day 90. Without a written agreement, the limit would be 15 days, and 93 % of receipts would breach it.

**The law would allow ₹38.5 lakh of interest on receipts already paid late, and ₹108.7 lakh on balances still open.**

| | At 16.5 % (bank rate 5.50 %) | At 20.25 % (bank rate 6.75 %) | As % of the amount |
|---|---:|---:|---:|
| On receipts paid late | **₹38.50 lakh** | ₹47.27 lakh | 0.56 % |
| On balances open on 30 September 2026 | ₹108.69 lakh | ₹137.44 lakh | 21.72 % |
| **Total** | **₹147.19 lakh** | ₹184.71 lakh | 2.00 % |

The interest on open balances is real in law but mostly sits on invoices that are a year old or more and may never be paid. The interest on late receipts is the part a customer could realistically be asked for.

| Segment | Amount | Beyond 45 days | Interest on late receipts | Interest on open balances |
|---|---:|---:|---:|---:|
| **Enterprise** | ₹30.64 crore | **94.4 %** | **₹29.16 lakh** | ₹48.71 lakh |
| Distributor | ₹28.71 crore | 24.4 % | ₹5.23 lakh | ₹41.73 lakh |
| Mid-Market | ₹10.06 crore | 39.9 % | ₹3.74 lakh | ₹11.79 lakh |
| SMB | ₹4.01 crore | 14.8 % | ₹0.37 lakh | ₹6.47 lakh |

Enterprise customers pay almost everything after 45 days and account for three-quarters of the interest on late receipts.

| Customer | Segment | Late receipts | Average days late | Interest on paid receipts |
|---|---|---:|---:|---:|
| Krishna Castings Ltd | Enterprise | 333 | 24 | ₹3.86 lakh |
| Sudarshan Autoparts Pvt Ltd | Enterprise | 91 | 32 | ₹2.40 lakh |
| Mahavir Pillai Spinning Mills Pvt Ltd | Enterprise | 235 | 22 | ₹2.37 lakh |
| Precision Petrochem India Ltd | Enterprise | 217 | 24 | ₹1.83 lakh |
| Saraswati Mehta Flexipack Pvt Ltd | Enterprise | 107 | 28 | ₹1.25 lakh |

**At 31 March 2026, 201 customers owed us ₹4.88 crore past the 45-day limit.** For a customer with a March year-end, that purchase is not deductible for tax that year.

| Year-end | Customers owing | Owing past 45 days | Owed | Owed past 45 days | Share |
|---|---:|---:|---:|---:|---:|
| 31 Mar 2025 | 193 | 143 | ₹7.67 crore | ₹2.93 crore | 38.2 % |
| **31 Mar 2026** | 245 | **201** | ₹9.83 crore | **₹4.88 crore** | **49.6 %** |

| Largest balances past 45 days at 31 March 2026 | Segment | Invoices | Owed |
|---|---|---:|---:|
| Mahavir Pillai Spinning Mills Pvt Ltd | Enterprise | 32 | ₹31.3 lakh |
| Hindustan Joshi Agencies | Distributor | 2 | ₹31.3 lakh |
| Krishna Castings Ltd | Enterprise | 36 | ₹26.9 lakh |
| Saraswati Mehta Flexipack Pvt Ltd | Enterprise | 16 | ₹22.2 lakh |
| Siddhivinayak Mishra Trading Co. | Distributor | 17 | ₹19.4 lakh |

## 9. Business implications and recommendations

1. **Register as a small enterprise (Udyam) if the company qualifies as a manufacturer**, and put a written 45-day payment clause on every invoice and contract. Without a written period, the legal limit is 15 days, which nearly every customer breaches and few would accept.
2. **Write to the Enterprise accounts before 31 March each year.** About ₹4.9 crore was owed past 45 days at the last year-end. A reminder that unpaid balances cost the customer its tax deduction is the strongest lever the company has, and it costs nothing.
3. **Use the interest as a negotiating figure, not a bill.** ₹38.5 lakh of interest accrued on receipts paid late in two and a half years. Waiving it in exchange for 45-day payment going forward is a credible offer.
4. **Take the oldest open balances to the MSME Samadhaan facilitation process** where negotiation fails. That includes ₹31 lakh owed by Hindustan Joshi Agencies on two invoices.
5. **Check the trader question first.** If the company is classed as a trader for some lines, those sales are outside section 43B(h).

## 10. Assumptions and limitations

- **Not legal or tax advice.** Eligibility (Udyam registration, manufacturer status, micro/small size) and the treatment under the Income-tax Act 2025 must be confirmed with an adviser.
- **One bank rate for the whole period.** The RBI bank rate fell from 6.75 % in 2024 to 5.50 %; the two rates bracket the true figure.
- **A 45-day written agreement is assumed for every customer.** With 15 days the share late and the interest would be far higher.
- **Customers' year-end assumed to be 31 March**, the usual Indian financial year.
- **Amounts exclude GST.** Interest and 43B(h) apply to the full invoice, so the figures are about 18 % higher with GST.
- **Acceptance = delivery date.** A customer that formally accepts goods later (after inspection) starts the clock later.

**Sources for the rules:** [ClearTax: section 43B(h)](https://cleartax.in/s/section-43bh-of-income-tax-act) · [TaxGuru: MSME 45/15-day payment, section 43B(h) explained](https://taxguru.in/income-tax/payment-msme-45-15-days-section-43b-h-explained.html) · [C4S: RBI monetary policy, August 2026 (bank rate 5.50 %)](https://c4scourses.in/banking-finance/rbi-monetary-policy-august-2026/)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Invoice, item, interest and year-end tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
