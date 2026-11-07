# Case Study · Which DSO Should the Board See? Four Formulas Against the Age of Receivables

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study computes days sales outstanding four ways at 28 month-ends (June 2024 – September 2026). It measures how much each formula moves with the sales pattern alone and compares each with the real age of the receivables.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-07 |

---

## 1. Business problem

Days sales outstanding (DSO) is the board's main collections KPI. In March 2026 it fell, and the credit team was praised. In May it jumped by 41 days, and they were blamed. The CFO suspects the formula, not the team: the pack divides receivables by a single month's sales, so a big March or a quiet May moves DSO whatever customers do. She wants to know which DSO to report, and whether any DSO shows the real state of the receivables.

## 2. Business questions

1. How much do the common DSO formulas disagree, and how much does each swing from month to month?
2. How much of each formula's movement is just the sales pattern?
3. Which formula follows how old the receivables really are?
4. What should the pack report?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status |
| `sales_order_items` | One row per product per order | Invoice amount |
| `shipments` | One row per shipment | Invoice date (last delivery date) |
| `payments` | One row per receipt | Amounts received by each month-end |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Invoice | A Delivered order with every shipment delivered; invoice date = last delivery date; amount = order value after discount |
| Receivables (AR) at a month-end | Σ MAX(0, amount − payments received by that date) over invoices dated on or before it |
| **Simple DSO** | AR ÷ the month's sales × days in the month (what the pack reports) |
| 3-month DSO | AR ÷ sales of the last 3 months × their days (as in the [receivables roll-forward](../05_receivables_rollforward/)) |
| 12-month DSO | AR ÷ sales of the last 12 months × their days (from December 2024) |
| **Countback DSO** | Walk back month by month, subtracting each month's sales from AR. DSO = days of the months fully used up + the remainder ÷ that month's sales × its days. |
| Current-invoice countback | The countback on receivables up to 90 days old only |
| **Average age** | Open-amount-weighted days since the invoice date: how old the money owed really is |
| Distortion | Correlation of each formula's monthly change with the log change in the month's sales; standard deviation of monthly changes |

## 5. Analytical approach

1. **Invoices** (`sahyadri_b2b.ds_invoices`), **monthly sales** (`ds_sales`) and the **open amount of every invoice at every month-end** (`ds_open`).
2. **DSO table** (`ds_dso`): four formulas, the current-invoice countback and the average age.
3. **Distortion and trend**: what each formula follows.
4. **March – June 2026**, the months that caused the argument.

## 6. SQL techniques used

- A point-in-time receivables ledger: every invoice × every month-end, with payments up to that date
- The countback method in one pass: cumulative sales and days over earlier months (`SUM() OVER (ORDER BY month DESC)`), then the crossing month picked with `IF(cum_sales >= ar AND cum_sales - sales < ar, ...)`
- Validation by inverting the countback: sales in the last DSO days, prorated, must equal receivables

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Invoices = Delivered orders with every shipment delivered |
| 02 | Monthly sales add up to all invoices; days = calendar days of the month |
| 03 | One open row per month-end and invoice; never negative or above the invoice amount |
| 04 | Receivables on 30 September 2026 = recount from invoices and payments |
| 05 | Simple and 3-month DSO = recount |
| 06 | **Countback inverted: sales in the last DSO days (prorated) = receivables** |
| 07 | The current-invoice countback never exceeds the full countback |
| 08 | Average age = recount |
| 09 | 28 month-ends; 12-month DSO only once 12 months of sales exist |
| 10 | Receivables up to 90 days old never exceed total receivables |

## 8. Findings

**The simple DSO in the pack mostly measures the month's sales.**

| Formula | Monthly changes | SD of monthly change | Largest move | Correlation with the sales change | Correlation with the age change |
|---|---:|---:|---:|---:|---:|
| **Simple (one month)** | 27 | **12.6 days** | **41 days** | **−0.87** | 0.56 |
| 3-month | 27 | 6.0 days | 17 days | 0.30 | −0.22 |
| 12-month | 21 | 8.6 days | 19 days | 0.81 | −0.95 |
| **Countback** | 27 | **4.8 days** | **12 days** | 0.37 | −0.31 |
| Countback, invoices up to 90 days | 27 | 3.4 days | 10 days | 0.27 | −0.41 |

- A big sales month pushes the simple DSO down and a quiet one pushes it up (correlation −0.87). The 12-month version has the opposite flaw: a big month adds to receivables before it is a large part of a year's sales (+0.81).
- The countback moves least, and least with sales, because it compares receivables with the sales they actually came from.

**The months that caused the argument**

| Month-end | Sales of the month | Simple | Countback | Current-invoice countback | Average age |
|---|---:|---:|---:|---:|---:|
| Feb 2026 | ₹3.04 crore | 88 | 88 | 49 | 211 days |
| Mar 2026 | ₹4.11 crore | **80** | 89 | 50 | 205 days |
| Apr 2026 | ₹4.56 crore | 79 | 92 | 52 | 197 days |
| May 2026 | ₹2.70 crore | **120** | **85** | 50 | 240 days |
| Jun 2026 | ₹3.18 crore | 96 | 89 | 48 | 261 days |

The "41-day jump" in May was a quiet sales month after two big ones. The countback actually fell 7 days, and customers paid current invoices exactly as before (about 50 days).

**But no DSO shows that receivables are getting older.**

| | December 2024 | September 2026 |
|---|---:|---:|
| Simple DSO | 63 days | 90 days |
| 12-month DSO | 81 days | 100 days |
| Countback DSO | 73 days | 98 days |
| **Average age of receivables** | **94 days** | **289 days** |
| **Share of receivables over 90 days old** | **29.9 %** | **52.2 %** |

- The current-invoice countback stayed between 43 and 58 days in every month: customers pay new invoices at a steady pace.
- Meanwhile the average age of the money owed tripled and over half of receivables are now more than 90 days old. That matches the [receivables roll-forward](../05_receivables_rollforward/), which traced rising DSO to old invoices. DSO, by design, compares receivables with recent sales and so dilutes the old debt in growing sales.

## 9. Business implications and recommendations

1. **Replace the simple DSO with the countback DSO** as the headline. It needs no more data, removes the March and May swings (monthly moves of at most 12 days against 41), and its movements can be explained.
2. **Report two numbers under it: current-invoice DSO and the over-90-day balance.** The first (about 50 days) measures how customers pay today, and is the credit team's KPI. The second (52 % of receivables) measures the old debt that DSO hides, and needs a collection or provisioning decision.
3. **Add the average age of receivables to the pack.** It rose from 94 to 289 days while DSO rose from 73 to 98. It is the number that would have raised the alarm.
4. **Stop judging the credit team on monthly DSO movements.** Under the pack's formula, most of the change came from the month's sales, not collections.
5. **Route the over-90-day book to the [expected credit loss](../../05_advanced_analytics/19_expected_credit_loss_provision/) review** rather than to monthly collection targets.

## 10. Assumptions and limitations

- **Invoice date = last delivery date.** If invoices are raised at dispatch, receivables start earlier and every DSO is a few days higher.
- **Open amount by invoice, payments matched by order.** Unapplied or misapplied receipts (see [cash application matching](../15_cash_application_matching/)) would shift amounts between invoices.
- **Delivered orders only.** Orders still in transit or partly delivered are not yet receivables in this study.
- **Countback assumes the oldest receivables belong to the oldest sales.** With a large old book, the countback still understates the age of what is owed, which is why the average age is reported alongside it.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Invoice, sales, open-amount and DSO tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
