# Case Study · Order Timing: Do Customers Order Like Clockwork, or at Random?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 256 customers with seven or more order days, each compared with 200 random versions of their own ordering history, and 6,255 customer-month snapshots testing whether a customer is more likely to order when it is "due".

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-30 |

---

## 1. Business problem

The CRM vendor is selling a "next order date" feature: it learns each customer's ordering cycle and alerts the salesperson when the customer is due or overdue. Sales management likes the idea of calling customers just as their next order falls due. Before paying for it, the commercial head wants to know whether customers actually order on a cycle, and whether being "due" makes an order more likely.

## 2. Business questions

1. Do customers order on a regular cycle, or at random times?
2. Which customers, if any, are regular enough for a cycle-based alert?
3. Is a customer more likely to order when it is due or overdue against its own cycle?
4. What should alerts be based on instead?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Order day | A date with at least one valid order (not Cancelled or Returned) from the customer |
| Gap | Days between consecutive order days |
| **CV of gaps** | Standard deviation ÷ mean of a customer's gaps: near 0 = fixed cycle, near 1 = random (Poisson) ordering, above 1 = bursts |
| **Random benchmark** | 200 versions per customer with the same number of orders placed at random between its first and last order (positions from an integer hash). With few orders a random history has a CV somewhat below 1, so each customer is compared with its own benchmark. |
| More regular / burstier | CV in the lowest / highest 5 % of the customer's random versions. By chance alone about 5 % of customers fall in each group. |
| **Due-ness** | At a month-end: days since the last order ÷ the customer's average gap so far (customers with 4+ order days). 1 = exactly one cycle since the last order. |
| Outcome | Any order in the next 30 days |
| **Random-ordering prediction** | 1 − e^(−30 ÷ average gap): the chance of an order in 30 days if the customer orders at random at its usual rate, whatever the time since its last order |

## 5. Analytical approach

1. **Order days** (`sahyadri_b2b.ot_days`) and **customers** with 7+ order days (`sahyadri_b2b.ot_customers`).
2. **Random versions** (`sahyadri_b2b.ot_simulated_cv`) and the **regularity** of each customer (`sahyadri_b2b.ot_regularity`).
3. **Month-end snapshots** (`sahyadri_b2b.ot_snapshots`): due-ness, the next 30 days and the random-ordering prediction.

## 6. SQL techniques used

- Gap analysis with `LAG()` over each customer's order days
- A Monte Carlo benchmark per customer: random order positions from an integer hash, sorted with `LAG() OVER (ORDER BY u)`
- A binomial z-test of how many customers fall in each 5 % tail
- Point-in-time snapshots that use only history up to each month-end, scored against a closed-form Poisson prediction

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Order days = distinct valid order dates per customer, numbered 1..n |
| 02 | Gaps = days between consecutive order days, always positive |
| 03 | Customers with 7+ order days; mean gap and CV recomputed |
| 04 | **200 random versions per customer, each with n − 1 gaps spanning first to last order** |
| 05 | p-values recounted; the pattern follows them |
| 06 | Every qualifying customer has exactly one pattern |
| 07 | Snapshots are month-ends in range, with 4+ order days and no negative silence |
| 08 | **"Ordered in the next 30 days" = a direct recount** |
| 09 | Random-ordering prediction = 1 − e^(−30 ÷ average gap), between 0 and 1 |
| 10 | Customers per snapshot = a recount of customers with 4+ order days to date |

## 8. Findings

**Most customers order at random times.** The average CV of gaps is 0.905, against 0.919 for random versions of the same histories; only 6 of 256 customers have a CV below 0.5.

| Pattern | Customers | Expected by chance | Average CV | Average gap | Average order days |
|---|---:|---:|---:|---:|---:|
| Random-like | **217** | – | 0.91 | 53.8 days | 28.9 |
| More regular than random | **26** | 12.8 | 0.66 | 39.1 days | 72.3 |
| Burstier than random | 13 | 12.8 | 1.37 | 62.6 days | 22.7 |

- **A real but small group orders on a rhythm.** 26 customers are more regular than random, twice the 12.8 chance would give (z = 3.8). They are frequent buyers (72 order days on average) and mostly Enterprise (10 of 56 Enterprise customers) and Distributors (6 of 49).
- Bursty ordering is no more common than chance (13 against 12.8).

**For the typical customer, being "due" does not make an order more likely.**

| Position in own cycle | Customer-months | Ordered in next 30 days | Random ordering predicts |
|---|---:|---:|---:|
| Just ordered (< 0.5 cycles) | 2,591 | 53.9 % | 53.4 % |
| Not yet due (0.5–1) | 1,376 | 50.7 % | 53.9 % |
| Due (1–2 cycles) | 1,376 | **52.0 %** | 55.2 % |
| Overdue (2–4 cycles) | 705 | 48.4 % | 55.6 % |
| Long silent (4+ cycles) | 207 | **39.6 %** | 59.8 % |

- A customer that ordered last week is as likely to order in the next 30 days as one that is "due". Only a long silence (four or more cycles, about eight months for the average customer) signals lower odds, which is the churn signal studied in [time to reorder](../07_time_to_reorder_survival/).

**For the regular customers, the cycle does work.**

| Position in own cycle (regular customers) | Customer-months | Ordered in next 30 days | Random ordering predicts |
|---|---:|---:|---:|
| Just ordered | 282 | 66.3 % | 68.0 % |
| Not yet due | 161 | 75.2 % | 67.7 % |
| Due | 135 | **83.7 %** | 74.2 % |
| Overdue (2+ cycles) | 28 | 92.9 % | 77.3 % |

**How often a customer orders predicts the next month; when it last ordered does not.**

| Average gap so far | Customer-months | Ordered in next 30 days | Random ordering predicts |
|---|---:|---:|---:|
| Under 15 days | 772 | 94.2 % | 94.7 % |
| 15–30 days | 1,504 | 69.6 % | 74.1 % |
| 30–60 days | 1,919 | 48.2 % | 51.2 % |
| 60–120 days | 1,534 | 28.2 % | 31.0 % |
| 120+ days | 526 | 19.6 % | 18.0 % |

The random-ordering formula, using nothing but each customer's average rate, predicts the next 30 days within about 5 points in every band.

## 9. Business implications and recommendations

1. **Do not buy a "next order date" feature for the whole customer base.** For 217 of the 256 customers with seven or more order days, timing is random; an alert when a customer is "due" would be no more accurate than calling at random.
2. **Use cycle alerts for the 26 regular customers only.** For them the chance of an order rises from 66 % just after an order to 84 % when due; 16 of the 26 are Enterprise and Distributor accounts.
3. **Plan contact frequency on ordering rate.** Expected orders per month = 30 ÷ average gap; call high-rate customers often and use the rate to forecast each account's month.
4. **Alert on long silence, not on "overdue".** Four or more cycles without an order is the first point where the chance of an order falls clearly; combine it with the 270-day tipping point from the [survival analysis](../07_time_to_reorder_survival/).
5. **Keep product-level reminders where they help.** The [reorder reminders](../06_reorder_reminders/) study found a modest lift at product level; customer-level timing adds nothing beyond the rate.

## 10. Assumptions and limitations

- **Customer level only.** A customer that orders at random overall may still reorder individual products on a cycle.
- **Order days, not orders.** Several orders on the same day count once.
- **Fixed window.** The first and last order bound each random version, so a customer that started or stopped buying partway through is judged on its active span only.
- **Small regular group.** 26 customers and only 28 overdue months for them; the rise in the table is consistent but based on few observations.
- **Regular customers are classified with the full history**, including months after each snapshot; their table describes the pattern rather than testing a forecast.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order-day, customer, simulation, regularity and snapshot tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
