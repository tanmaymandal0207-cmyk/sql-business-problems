# Case Study · Weekend and Holiday Postings Test

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 40,565 dated events (orders, dispatches, deliveries and payments) tested against the weekly calendar and three fixed national holidays, January 2024 – September 2026.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-28 |

---

## 1. Business problem

The internal auditor is planning the year-end review. A standard test in any audit of transaction data is to look for activity dated on days the business does not work. The company sells Monday to Saturday (Saturday is a half day), the warehouse is said to follow the same calendar, and cheques and demand drafts can only be cleared on bank working days. The auditor wants to know which dates in the system follow the real calendar, and which do not, before relying on them for cut-off, lead-time and collection tests.

## 2. Business questions

1. On which days of the week are orders, dispatches, deliveries and payments dated?
2. Which of them follow the business calendar, and which do not?
3. How many cheque and demand-draft receipts are dated on Sundays or national holidays, and how much money is involved?
4. What do the results say about how each date is captured?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date |
| `shipments` | One row per shipment | Dispatch and delivery dates |
| `payments` | One row per payment | Payment date, method, amount |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Events | Order placed (`order_date`), dispatched (`shipment_date`), delivered (`delivery_date`), payment (`payment_date`, by method) |
| Weekday | `MOD(DATE_DIFF(date, DATE '1900-01-07', DAY), 7)`: 0 = Sunday … 6 = Saturday (7 Jan 1900 was a Sunday). Works the same in any engine. |
| National holidays | Fixed-date holidays: Republic Day (26 Jan), Independence Day (15 Aug), Gandhi Jayanti (2 Oct). Festival holidays move each year and are not included. |
| **Calendar-blind expectation** | Events × (days of that type ÷ all days), over each event type's first-to-last date: what dates would look like if they ignored the calendar |
| **Uniformity test** | Chi-square across the seven weekdays (6 degrees of freedom); critical value 22.46 at 0.1 % |
| **Dispatch model** | If dispatch dates are "order date + N calendar days" with N unrelated to the weekday, the dispatch weekdays can be predicted by combining the mix of order weekdays with the mix of lags. A close fit (chi-square well below 22.46) means weekends play no part in dispatch dating. |
| Bank working day | Cheques and demand drafts need one to clear; NEFT, RTGS and UPI settle every day |

## 5. Analytical approach

1. **Calendar** (`sahyadri_b2b.cal_days`) and **event table** (`sahyadri_b2b.cal_events`).
2. **Weekday profile** (`sahyadri_b2b.cal_weekday`): observed events against the calendar-blind expectation, events per day of each weekday, and the uniformity test. **Dispatch model** (`sahyadri_b2b.cal_dispatch_model`) and dispatch lag by order weekday.
3. **Payments** on Sundays and national holidays, by method and value.
4. **National holidays**: events against expectation, and a holiday-by-holiday table.

## 6. SQL techniques used

- A date spine with `GENERATE_DATE_ARRAY` and a portable weekday calculation
- Chi-square goodness-of-fit against a calendar-based expectation
- A convolution in SQL: combining two independent distributions with a `CROSS JOIN` to predict a third, then testing the prediction
- Validation with a second, independent weekday anchor and a known-date check

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Calendar has one row per day of the range |
| 02 | 1 January 2024 is a Monday |
| 03 | Three national holidays a year |
| 04 | Every source event is in the event table |
| 05 | Weekday table: events add up to each event type |
| 06 | Expected counts add up to observed counts |
| 07 | Days in period = each event type's first-to-last span |
| 08 | Dispatch model: predicted shipments = observed shipments |
| 09 | **Weekday = a recount from a different anchor date** |
| 10 | Sunday cheque and DD receipts = an independent recount |

## 8. Findings

**Order dates follow the business calendar. Dispatch, delivery and payment dates do not.**

| Event | Events | On Sundays | Share on Sundays | Per Sunday | Per weekday (Mon–Fri) | Per Saturday | Chi-square | Weekly pattern |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Order placed | 10,000 | 124 | **1.2 %** | 0.87 | 12.42 | 6.71 | 1,779.1 | **Business calendar** |
| Dispatched | 10,031 | 1,540 | **15.4 %** | **10.77** | 9.51 | 11.68 | 163.2 | Yes, but not a business one |
| Delivered | 9,966 | 1,390 | 13.9 % | 9.72 | 10.01 | 9.87 | 23.9 | Barely |
| Payment | 10,568 | 1,449 | 13.7 % | 10.13 | 10.68 | 10.24 | 7.5 | **None** |

- Orders behave like a real six-day business: almost none on Sundays, about half a day's volume on Saturdays.
- **More shipments are dated on Sundays than on an average weekday** (10.77 against 9.51), and Saturday is the busiest dispatch day.

**Dispatch dates are "order date + N calendar days".**

| Dispatch weekday | Recorded | Predicted if the lag ignores weekends |
|---|---:|---:|
| Sun | 1,540 | 1,561.9 |
| Mon | 1,326 | 1,280.8 |
| Tue | 1,103 | 1,138.4 |
| Wed | 1,325 | 1,273.6 |
| Thu | 1,481 | 1,458.2 |
| Fri | 1,586 | 1,620.7 |
| Sat | 1,670 | 1,697.4 |

- The prediction fits closely (chi-square 6.6 against a 22.46 threshold). The odd shape — busy Saturdays and Sundays, quiet Tuesdays — is simply what a weekday order pattern looks like after adding a lag of 3–5 calendar days.
- Orders placed on Thursday and Friday wait no longer than Monday orders (4.53 and 4.78 days against 4.49), and 24–26 % of them are dispatched on a Sunday. A warehouse closed on Sundays would show the opposite.

**National holidays: only order intake stops.**

| Event | Events on the 8 holidays in range | Expected if calendar-blind | Ratio |
|---|---:|---:|---:|
| Order placed | 3 | 79.7 | **0.04** |
| Dispatched | 78 | 80.0 | 0.97 |
| Delivered | 70 | 79.6 | 0.88 |
| Payment | 72 | 84.3 | 0.85 |

**413 cheque and demand-draft receipts (₹2.49 crore) are dated on days banks do not clear.**

| Method | Payments | On Sundays | On national holidays (weekdays) | Share on non-working days | Value |
|---|---:|---:|---:|---:|---:|
| Cheque | 2,281 | **340** | 14 | 15.5 % | **₹217.0 lakh** |
| Demand Draft | 408 | **52** | 7 | 14.5 % | ₹31.5 lakh |
| NEFT | 4,787 | 629 | 28 | 13.7 % | ₹388.4 lakh (allowed) |
| RTGS | 1,144 | 159 | 4 | 14.2 % | ₹454.6 lakh (allowed) |
| UPI | 1,758 | 248 | 11 | 14.7 % | ₹76.6 lakh (allowed) |

Electronic payments can legitimately settle on Sundays, but cheques and drafts dated on Sundays at the same rate as any other day show that the payment date is not the bank clearing date.

## 9. Business implications and recommendations

1. **Treat dispatch, delivery and payment dates as entered, not observed, until proven otherwise.** Ask IT how each is captured: a dispatch date calculated from the order date, or entered without a calendar check, would explain every pattern here.
2. **Do not rely on them for weekend-sensitive tests.** Cut-off tests around 31 March (see [revenue cut-off reconciliation](../04_revenue_cutoff_reconciliation/)), Sunday-operations cost claims and lead-time KPIs in working days all depend on these dates being real.
3. **Record the bank value date for cheques and drafts.** 413 receipts worth ₹2.49 crore carry dates on which they cannot have cleared; the bank reconciliation should match on value date, and receivable ageing should use it.
4. **Add a calendar check at entry.** A warning when a dispatch, delivery or cheque receipt falls on a Sunday or national holiday costs nothing and catches keying and default-date errors.
5. **Confirm whether the warehouse really works Sundays.** If it does, Sunday labour and transport costs belong in the [cost-to-serve](../../03_operations_and_supply_chain/02_freight_cost_to_serve/) model; if it does not, 15 % of dispatch dates are wrong by at least a day.

## 10. Assumptions and limitations

- **Business calendar as described**: Monday–Saturday trading, Saturday half day, Sunday closed. Order dates confirm it; the other dates contradict it.
- **Fixed-date holidays only.** Diwali, Holi and other festival holidays move every year and would add more non-working days.
- **Payment date meaning.** The data does not say whether `payment_date` is the receipt, deposit or clearing date; the cheque finding applies if it is meant to be the clearing date.
- **No timestamps.** Events late on Saturday and early on Monday cannot be separated from Sunday events.
- **Synthetic regularity.** The very close fit of the dispatch model suggests dates generated by a rule; in a live system the same test would show how far reality departs from it.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Calendar, event, weekday and dispatch-model tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
