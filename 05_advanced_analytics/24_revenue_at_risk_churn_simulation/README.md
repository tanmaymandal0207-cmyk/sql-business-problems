# Case Study · Revenue at Risk from Customer Churn: A Monte Carlo Stress Test

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Churn probabilities by ordering frequency, 2,000 simulated years of customer losses at each of two snapshots, a back-test of the September 2025 forecast against what happened by September 2026, and today's revenue at risk at the 95 % and 99 % levels.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-31 |

---

## 1. Business problem

The bank reviewing the company's working-capital facility asks for a "revenue at risk" figure: how much of today's revenue base could be lost next year if customers stop buying, at a 95 % confidence level. The CFO wants a number that is defensible: based on how customers have actually behaved, tested against a year that has already happened, and clear about where the risk sits.

## 2. Business questions

1. How likely is each kind of customer to stop buying within a year?
2. What revenue loss should be expected, and how bad could it be in one year in twenty?
3. Would the method have predicted the loss that actually happened last year?
4. Where does the risk sit?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Revenue |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Snapshots | 30 Sep 2024, 30 Sep 2025 and 30 Sep 2026 |
| Customer base | Customers with a valid order (not Cancelled or Returned) in the 9 months before the snapshot (the longest window available at the first snapshot) |
| **Exposure** | The customer's revenue in those 9 months |
| **Churn** | No valid order in the 12 months after the snapshot |
| Frequency band | Orders in the 9 months: 1, 2–3, 4–8, 9+ |
| **Churn probability** | (churners + 0.5) ÷ (customers + 1) in the band at the previous snapshot; the 0.5 keeps a small risk on bands that have never lost a customer |
| **Monte Carlo** | 2,000 simulated years; in each, every customer churns with its band probability (independent draws from an integer hash); revenue lost = exposure of the customers that churn |
| Revenue at risk (95 % / 99 %) | The 95th / 99th percentile of revenue lost across the 2,000 years |
| Stress case | Every churn probability doubled |

## 5. Analytical approach

1. **Customers** (`sahyadri_b2b.rr_customers`) at each snapshot with exposure, band and outcome.
2. **Probabilities** (`sahyadri_b2b.rr_probabilities`) from the previous snapshot.
3. **Scenarios** (`sahyadri_b2b.rr_scenarios`): 2,000 simulated years for 2025 (back-test) and 2026 (live), with the closed-form check.
4. **Back-test** of the 2025 forecast against the actual loss.
5. **Risk by band** today.

## 6. SQL techniques used

- Point-in-time snapshots with a train-on-last-year, apply-this-year rule
- A Monte Carlo simulation in SQL: independent Bernoulli draws from an integer hash for every customer and scenario
- Percentile risk measures with `APPROX_QUANTILES`, checked against the closed-form mean and standard deviation
- A smoothed (Jeffreys-style) probability so that "never happened" does not become "cannot happen"

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Customers and exposure at each snapshot = a recount of orders in the previous 9 months |
| 02 | Churned = no valid order in the next 12 months |
| 03 | Outcomes known for the 2024 and 2025 snapshots only |
| 04 | Band follows the number of orders |
| 05 | Probability = (churners + 0.5) ÷ (customers + 1), applied one year later |
| 06 | 2,000 simulated years for each of the two snapshots |
| 07 | Loss never exceeds exposure; the stress loss is never below the base loss |
| 08 | Scenario exposure = total exposure of the customers |
| 09 | **Simulated mean within 3 standard errors of the closed-form mean** |
| 10 | **Simulated SD within 10 % of the closed-form SD** |

## 8. Findings

**Only occasional buyers churn, and they carry little revenue.**

| Band | 2024: customers / churned | 2025: customers / churned | Share of 2025 exposure |
|---|---:|---:|---:|
| One order | 72 / **29.2 %** | 59 / **47.5 %** | 1.0 % |
| 2–3 orders | 72 / 8.3 % | 91 / 5.5 % | 5.8 % |
| 4–8 orders | 73 / 0 % | 85 / 0 % | 16.4 % |
| 9+ orders | 71 / 0 % | 87 / 0 % | **76.9 %** |

No customer with four or more orders in nine months has stopped buying in either year.

**Today's revenue at risk is about 3 % of the base at the 95 % level.**

| Snapshot | Exposure (9 months) | Expected loss | Median | 95 % | 99 % | Stress 95 % (probabilities doubled) |
|---|---:|---:|---:|---:|---:|---:|
| 30 Sep 2025 | ₹22.52 crore | ₹32.6 lakh | ₹25.8 lakh | ₹80.2 lakh (3.6 %) | ₹140.2 lakh | ₹135.6 lakh |
| **30 Sep 2026** | **₹31.22 crore** | **₹45.3 lakh** | ₹37.0 lakh | **₹96.2 lakh (3.1 %)** | **₹188.2 lakh** | ₹185.2 lakh |

The simulation agrees with the closed form (mean ₹46.4 lakh, SD ₹35.8 lakh for 2026); the 99 % figure is well above a normal approximation because one large account can decide the tail.

**The method passed last year's test.** The September 2025 forecast, using 2024 probabilities, expected ₹32.6 lakh (range ₹10.5–80.2 lakh, 5th to 95th percentile). The actual loss by September 2026 was **₹24.6 lakh**, at the 46th percentile, from 33 customers against 26.7 expected.

**Where today's risk sits.**

| Band | Customers | Exposure | Churn probability | Expected loss | Share |
|---|---:|---:|---:|---:|---:|
| One order | 76 | ₹44.5 lakh | 47.5 % | ₹21.2 lakh | 45.6 % |
| 2–3 orders | 80 | ₹142.2 lakh | 6.0 % | ₹8.5 lakh | 18.3 % |
| 4–8 orders | 101 | ₹488.5 lakh | 0.6 % | ₹2.8 lakh | 6.1 % |
| 9+ orders | 96 | ₹2,447.1 lakh | **0.6 %** | **₹13.9 lakh** | **30.0 %** |

- Almost half of the expected loss is single-order customers: many leave, but each is small.
- **The 9+ band's risk is an assumption, not an observation.** None of 87 such customers churned last year; the 0.6 % comes from the smoothing. It still drives the tail, because one of these accounts is worth crores.

## 9. Business implications and recommendations

1. **Report revenue at risk as about ₹1 crore (3 %) at 95 % and ₹1.9 crore (6 %) at 99 %**, on a nine-month base of ₹31.2 crore, with the back-test as evidence.
2. **Explain that churn is not the main risk to revenue.** Full customer losses are small; shrinking revenue from customers who stay (see [net revenue retention](../../01_customer_and_revenue/11_net_revenue_retention/)) and [revenue volatility](../../02_sales_and_profitability/15_revenue_volatility_drivers/) matter more for the facility.
3. **Watch the large accounts individually.** The tail comes from a handful of customers that have never left; track their [health scores](../../01_customer_and_revenue/12_customer_health_score/) monthly rather than relying on a band probability.
4. **Use the second order as the retention lever.** Half of one-order customers do not order again within a year; the [activation study](../../01_customer_and_revenue/05_new_customer_activation/) shows where onboarding stalls.
5. **Re-run every September** and add each year's outcome to the probabilities.

## 10. Assumptions and limitations

- **Independent churn.** Customers are assumed to leave independently; an industry downturn that hits many at once would fatten the tail (the stress case gives a first idea).
- **Exposure is nine months of revenue**, not a full year; annual figures are about a third higher.
- **Two years of history.** Probabilities rest on one training year each; the 9+ band has no observed churn at all.
- **Churn means a full stop.** A customer that orders once in the next year counts as retained, however much it has shrunk.
- **New customers next year** are not in the base; the figure is a loss on today's customers, not a revenue forecast.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer, probability and scenario tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
