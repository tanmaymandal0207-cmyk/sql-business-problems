# Case Study · Would Trade Credit Insurance Have Paid Our Bad Debts? Testing the Policy Conditions Against Two Years of Losses

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study takes every fully delivered invoice that reached 180 days past due by 30 September 2026: 6,836 invoices, ₹64.1 crore, invoiced January 2024 – February 2026. It applies the two main conditions of a trade credit insurance policy to the ₹4.63 crore of losses and works out what the policy would have paid and the premium that would have broken even.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-08 |

---

## 1. Business problem

Bad debts have reached about 7 % of sales (see the [expected credit loss](../19_expected_credit_loss_provision/) study). A broker proposes trade credit insurance: the insurer pays 90 % of a buyer's unpaid debt for a premium on insured turnover. His illustration applies 90 % to every past loss, which makes almost any premium look cheap. The CFO wants to know what the policy would really have paid, given its conditions, before asking for quotes.

## 2. Business questions

1. How much has been lost, and on which customers?
2. Which of those losses would the policy's conditions have covered?
3. What premium rate would break even on history, with and without the conditions?
4. If insurance is not the answer, what is?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, status |
| `sales_order_items` | One row per product per order | Invoice amount |
| `shipments` | One row per shipment | Invoice date (last delivery) |
| `payments` | One row per receipt | What was paid, and when |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

**Policy terms applied** (as summarised in insurers' policy documents; see the sources at the end):

| Term | Value |
|---|---|
| Indemnity | The insured percentage of the unpaid debt, typically 85–90 %; **90 %** used here |
| Premium | A percentage of insured turnover |
| **Deliveries to an overdue buyer** | Not covered. No further deliveries while the oldest invoice is outstanding beyond the maximum period; **60 days past due assumed** (each policy schedule sets its own) |
| What is claimable | The buyer's insolvency or protracted default; disputed debts are not paid until the dispute is settled |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Invoice | A Delivered order with every shipment delivered; invoice date = last delivery; amount after discount, GST not added |
| Due date / default date | Invoice + 45 days / due date + 180 days. Only invoices with a default date on or before 30 September 2026 are judged. |
| **Loss** | Amount unpaid on 30 September 2026 |
| **Delivered while overdue** | On the invoice date, the same customer had an earlier invoice more than 60 days past due with more than ₹1 unpaid |
| **Customer kept paying** | The customer made any payment after the defaulted invoice's default date: it was solvent and trading |
| **Insurable loss** | A loss not delivered while overdue, from a customer that made no payment after its default date |
| **Break-even premium rate** | 90 % × insurable losses ÷ insurable turnover (turnover not delivered while overdue) |

## 5. Analytical approach

1. **Invoices** (`sahyadri_b2b.ti_invoices`) with losses, and the **policy tests** for each invoice (`ti_tests`).
2. **Losses** by segment, nothing-paid or part-paid, and whether anything is collected after the default date.
3. **Coverage**: each loss classed as not covered, not buyer default, or insurable; the two tests cross-tabulated.
4. **Break-even premium rates**, the broker's way and with the conditions.
5. **Where the losses come from**: customers still trading, and those who stopped paying.

## 6. SQL techniques used

- A point-in-time test on a self-join: earlier invoices of the same customer past the extension period, with payments up to the later invoice's date
- Customer-level payment activity joined back to each invoice (`payment_date > default_date`) to separate disputes from buyer default
- `GROUP BY ROLLUP` for segment rows and a total in one query
- Validation by an independent route: the date each invoice was cleared (running payment total), and the customer's last payment date

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Invoices = fully delivered orders with a default date by 30 September 2026; amount = source |
| 02 | Due date = invoice + 45 days; default date = due date + 180 days |
| 03 | **Loss = MAX(0, amount − payments to 30 September 2026)** (recount) |
| 04 | Paid by the default date never exceeds paid by 30 September 2026 |
| 05 | **Delivered while overdue = recount from the date each earlier invoice was cleared** |
| 06 | Customer kept paying = the customer's last payment is after the default date |
| 07 | Every invoice has one class; classes add up to the total loss |
| 08 | Insurable = lost, not delivered while overdue, no customer payment after the default date |
| 09 | **Claims = 90 % of losses recounted from the two independent tests** |
| 10 | Turnover delivered while overdue + insurable turnover = all turnover |

## 8. Findings

**₹4.63 crore, 7.2 % of what was invoiced, was never paid. Nothing is collected after 180 days past due.**

| Segment | Invoices | Invoiced | Invoices with a loss | Loss | Loss rate | Collected after the default date |
|---|---:|---:|---:|---:|---:|---:|
| Enterprise | 2,349 | ₹26.78 crore | 279 | ₹207.6 lakh | 7.75 % | – |
| Distributor | 1,387 | ₹24.96 crore | 118 | ₹166.0 lakh | 6.65 % | – |
| Mid-Market | 1,679 | ₹8.63 crore | 183 | ₹60.0 lakh | 6.95 % | – |
| SMB | 1,421 | ₹3.73 crore | 146 | ₹29.0 lakh | 7.78 % | – |
| **All** | **6,836** | **₹64.09 crore** | **726** | **₹462.6 lakh** | **7.22 %** | **–** |

- 279 invoices were not paid at all (₹288.7 lakh). 447 were part paid, leaving 46.8 % of their value unpaid (₹173.8 lakh).
- 206 of 384 customers have at least one loss. The losses are spread across the book, not confined to a few failed customers.

**The policy would have paid ₹10 lakh of the ₹463 lakh: about 2 %.**

| Loss class (tests applied in order) | Invoices | Customers | Loss | Share | Claim at 90 % |
|---|---:|---:|---:|---:|---:|
| Not covered: delivered while the customer was overdue | 428 | 119 | ₹257.3 lakh | 55.6 % | – |
| Not buyer default: the customer kept paying | 280 | 191 | ₹194.1 lakh | 42.0 % | – |
| **Insurable: the customer stopped paying** | **18** | 17 | **₹11.2 lakh** | **2.4 %** | **₹10.05 lakh** |

The two tests overlap, and either alone rules out most of the loss:

| Delivered while overdue | Customer kept paying | Invoices with a loss | Loss | Share |
|---|---|---:|---:|---:|
| No | No | 18 | ₹11.2 lakh | 2.4 % |
| No | **Yes** | 280 | ₹194.1 lakh | 42.0 % |
| Yes | No | 11 | ₹5.1 lakh | 1.1 % |
| Yes | **Yes** | 417 | ₹252.2 lakh | 54.5 % |

- **96.5 % of the loss is on customers who kept paying other invoices** after the unpaid one was 180 days past due. They were solvent and trading. The unpaid invoices look like disputes, deductions or invoices nobody chased, and an insurer would not pay those as buyer default.
- One insurable loss, Tirupati Infrastructure (₹8.9 lakh), is 80 % of the claimable total.
- Changing the assumed extension period to 30 or 90 days (`max_extension_days`) leaves the insurable share at 0.5–2.4 % of the loss.

**The policy's delivery condition would have stopped 59 % of sales.**

| Delivered while the customer had an invoice over 60 days past due | Invoices | Invoiced | Share of sales | Loss rate |
|---|---:|---:|---:|---:|
| No | 2,982 | ₹26.49 crore | 41.3 % | 7.75 % |
| **Yes** | 3,854 | ₹37.61 crore | **58.7 %** | 6.84 % |

Most customers, including the largest, routinely have an old invoice outstanding while they keep ordering. Under the policy, those deliveries would need the insurer's approval or would be uninsured.

**The broker's break-even premium is 6.5 %. With the conditions it is 0.38 %.**

| Segment | Turnover | Break-even rate, all losses (broker's view) | Insurable turnover | Claims | Break-even rate with the conditions |
|---|---:|---:|---:|---:|---:|
| Distributor | ₹24.96 crore | 5.98 % | ₹12.29 crore | ₹1.02 lakh | 0.083 % |
| Enterprise | ₹26.78 crore | 6.98 % | ₹8.03 crore | – | **0.000 %** |
| Mid-Market | ₹8.63 crore | 6.26 % | ₹3.86 crore | ₹8.30 lakh | 2.149 % |
| SMB | ₹3.73 crore | 7.00 % | ₹2.31 crore | ₹0.74 lakh | 0.322 % |
| **All** | ₹64.09 crore | **6.50 %** | ₹26.49 crore | ₹10.05 lakh | **0.380 %** |

- A premium quoted at, say, 0.5 % looks like a bargain against 6.5 %. Against what the policy would actually pay, it loses money.
- Enterprise customers cause the largest losses, ₹207.6 lakh, but on history the policy would have paid nothing on them.
- The Mid-Market rate is high only because of Tirupati Infrastructure.

**The losses sit with customers who are still buying and paying.**

| Customer | Segment | Unpaid invoices | Unpaid | Of which part paid | Paid since on other invoices |
|---|---|---:|---:|---:|---:|
| Hindustan Joshi Agencies | Distributor | 2 | ₹31.30 lakh | 1 | ₹18.1 lakh |
| Krishna Castings Ltd | Enterprise | 32 | ₹26.68 lakh | 20 | ₹312.3 lakh |
| Siddhivinayak Mishra Trading Co. | Distributor | 19 | ₹23.23 lakh | 12 | ₹509.5 lakh |
| Navkar Agencies Pvt Ltd | Distributor | 12 | ₹20.79 lakh | 7 | ₹154.9 lakh |
| Saraswati Mehta Flexipack Pvt Ltd | Enterprise | 12 | ₹18.05 lakh | 7 | ₹92.9 lakh |
| Mahavir Pillai Spinning Mills Pvt Ltd | Enterprise | 28 | ₹16.26 lakh | 20 | ₹235.4 lakh |

Krishna Castings Ltd has paid ₹312 lakh on other invoices since its oldest unpaid invoice defaulted, and still owes ₹26.7 lakh on 32 old ones, 20 of them part paid. That is a reconciliation or dispute problem, not a credit risk.

## 9. Business implications and recommendations

1. **Do not buy trade credit insurance to solve the bad-debt problem.** On history it would have paid about ₹10 lakh of ₹463 lakh of losses. At any premium above about 0.4 % of insured turnover it would have cost more than it paid, and it would have required stopping 59 % of deliveries.
2. **Treat the losses as disputes and unapplied cash first.** 96.5 % of the loss is on customers who kept paying. Reconcile their statements invoice by invoice, starting with the six customers above. Check for unapplied or misapplied receipts (see [cash application matching](../../04_data_quality_and_reconciliation/15_cash_application_matching/)) and for deductions taken without a credit note.
3. **Stop shipping new orders against very old unpaid invoices.** The insurer's own condition is a good rule for the company too. Hold new orders while a customer has an invoice more than 60 days past due, unless the old invoice is in dispute and being worked.
4. **If insurance is still wanted, buy it for named buyers only.** Insure the few customers whose failure would hurt, where the company could live with the delivery condition, rather than the whole turnover. Ask for a quote against the 0.38 % break-even, not the broker's 6.5 %.
5. **Re-test in a year.** If losses from customers who stop paying altogether start to rise, the case for insurance changes.

## 10. Assumptions and limitations

- **Not insurance advice.** Policy terms (insured percentage, extension period, discretionary limits, waiting periods) vary by insurer and are negotiated; the conditions here are the standard ones in published wordings.
- **"Kept paying" is a proxy for a dispute.** Some of those invoices may be lost through a slow decline before insolvency, which a policy could cover. The test is a strong signal, not proof.
- **Short observation for recent defaults.** An invoice defaulting in September 2026 has little time to show later payments, so recent losses are more likely to be classed as insurable. The insurable figure is an upper bound.
- **Credit limits per buyer are not modelled.** An insurer's limit on each buyer would cap claims further.
- **Amounts exclude GST.** A policy insures the gross invoice, so turnover and losses would both be about 18 % higher; the break-even rates are unchanged.
- **Payment terms of 45 days are assumed for every customer.**

**Sources for the policy terms:** [IFFCO Tokio: trade credit insurance policy wording](https://www.iffcotokio.co.in/content/dam/iffcotokio/policy-wordings/business/trade-credit-insurance-policy.pdf) · [Universal Sompo: trade credit policy prospectus](https://www.universalsompo.com/assets/file/trade-credit-policy/trade-credit-policy-prospectus.pdf) · [Bandhan Bank: trade credit insurance](https://bandhan.bank.in/sites/default/files/2026-05/Trade-Credit-Insurance.pdf)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Invoice and policy-test tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
