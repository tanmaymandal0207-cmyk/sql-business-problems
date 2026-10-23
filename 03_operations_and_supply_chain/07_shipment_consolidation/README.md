# Case Study · Shipment Consolidation Opportunity

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Window: shipments dated 1 Oct 2025 – 30 Sep 2026.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-23 |

---

## 1. Business problem

The warehouse dispatches every order as soon as it is ready. Customers who order several times a week therefore receive several separate shipments to the same address, and each one carries a fixed transport charge. The logistics manager wants to test **fixed dispatch schedules per customer** ("ship to this customer twice a week") and needs to know what they would save and how much they would delay deliveries.

The [Freight cost-to-serve](../02_freight_cost_to_serve/) study looked at the cost of small orders. This study looks at combining shipments across orders.

## 2. Business questions

1. What does a shipment cost, and how much of that is a fixed charge that consolidation would save?
2. Under each dispatch schedule, how many shipments are avoided, what is saved, and how long do goods wait?
3. Which customers offer the biggest saving?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `shipments` | One row per shipment | Shipment date, city and freight cost |
| `sales_orders` | One row per order | Customer |
| `sales_order_items` | One row per product per order | Order value for the freight model |
| `customers` | One row per customer | Names and segment |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Destination | Customer + shipping city (trimmed, lower case). Only shipments to the same destination can be combined. |
| Freight model | Fitted on single-shipment orders: cost = fixed charge + rate × order value, by least squares in SQL |
| Schedule | **Daily** (same date, today's practice), **Every 2 days**, **Twice weekly** (Mon–Wed and Thu–Sun), **Weekly** (ISO week) |
| Shipments avoided | Shipments today − dispatches needed under the schedule |
| Saving | Shipments avoided × fixed charge per shipment |
| Added wait | Days from a shipment's actual date to the last shipment date in its bucket, when the combined load would leave |

## 5. Analytical approach

1. **Freight model** (`sahyadri_b2b.freight_cost_model`). The fixed charge per shipment and the variable rate, estimated from 3,599 single-shipment orders.
2. **Shipment base** (`sahyadri_b2b.shipment_consolidation_base`). One row per shipment with its destination and bucket for each schedule.
3. **Scenario table** (`sahyadri_b2b.consolidation_scenarios`). One row per schedule, destination and bucket, with shipments and added wait. It is summarised into saving and delay per schedule.
4. **Customer list** for a twice-weekly schedule.

## 6. SQL techniques used

- Linear regression in SQL: slope = `COVAR_POP(y, x) / VAR_POP(x)`, intercept = mean(y) − slope × mean(x), R² = `CORR(y, x)²`
- Time bucketing with `DATE_TRUNC(…, ISOWEEK)`, `EXTRACT(DAYOFWEEK …)` and `DIV(DATE_DIFF(…), 2)`
- `UNION ALL` to reshape four schedules into one long table, then one summary query
- `MAX(shipment_date) OVER (PARTITION BY …)` to find each bucket's departure date and measure the wait

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per shipment in the base |
| 02 | Base shipments = source shipments in the window with a cost |
| 03 | Base freight = source freight |
| 04 | Every schedule covers every shipment exactly once |
| 05 | Coarser schedules never need more dispatches than finer ones |
| 06 | No negative wait, and zero wait under the daily baseline |
| 07 | No bucket spans longer than its schedule allows (1, 3 and 6 days) |
| 08 | **Regression recomputed** with the sums formula gives the same slope and intercept |
| 09 | Twice-weekly half-weeks match an independent day-of-week rule |
| 10 | Orders used in the model = independent count |

## 8. Findings

**About three-quarters of a typical shipment's cost is a fixed charge.** The model gives **₹957 per shipment** plus 0.31 % of the value shipped, and explains 74 % of the variation in freight cost (R² = 0.74). The average shipment costs ₹1,268.

**A twice-weekly schedule would cut 13.5 % of shipments and save ₹5.3 lakh a year, with goods waiting less than a day on average.**

| Schedule | Dispatches | Shipments avoided | Annual saving | % of freight | Average added wait | Wait for combined shipments |
|---|---:|---:|---:|---:|---:|---:|
| Daily (today) | 3,923 | 182 (4.4 %) | ₹1.74 lakh | 3.4 % | 0 days | 0 days |
| Every 2 days | 3,771 | 334 (8.1 %) | ₹3.20 lakh | 6.3 % | 0.04 days | 0.25 days |
| **Twice weekly** | **3,551** | **554 (13.5 %)** | **₹5.30 lakh** | **10.4 %** | **0.16 days** | **0.67 days** |
| Weekly | 3,199 | 906 (22.1 %) | ₹8.67 lakh | 17.0 % | 0.54 days | 1.44 days |

Freight in the window was ₹50.9 lakh on 4,105 shipments.

- **182 shipments already leave on the same day for the same customer and city, but as separate loads.** Combining them needs no change to service and saves ₹1.74 lakh a year.
- **The saving is concentrated.** 101 customers benefit from a twice-weekly schedule, and the top 20 account for 70 % of the avoided shipments. Krishna Castings alone receives 155 shipments a year that could travel as 81 (₹70,800 saved), followed by Mahavir Pillai Spinning Mills (₹43,100) and Siddhivinayak Mishra Trading (₹40,200).
- **Weekly dispatch saves the most but delays combined shipments by about 1.4 days.** That conflicts with the delivery promises in [City-wise promise standards](../05_promise_date_standards/). Twice weekly keeps the delay under a day.

## 9. Business implications and recommendations

1. **Combine same-day shipments to the same customer and city now.** This is a dispatch-desk rule and needs no customer agreement: ₹1.74 lakh a year with no delay.
2. **Offer the top 20 customers a twice-weekly delivery schedule.** It covers 70 % of the twice-weekly saving. Agree fixed delivery days, so customers can plan around them and promise dates reflect them.
3. **Keep weekly consolidation for low-urgency, high-frequency accounts only**, and only where the customer accepts the longer lead time.
4. **Negotiate the fixed charge with transporters.** At ₹957 per shipment it is the largest part of freight. A lower fixed charge would make every small shipment cheaper.

## 10. Assumptions and limitations

- **Model-based saving.** The saving assumes the combined load costs one fixed charge plus the same variable rate. A real carrier tariff may have weight breaks or vehicle limits.
- **Bill-to customer and city.** Two shipments to different sites of the same customer in the same city are treated as one destination.
- **Stock availability.** The analysis takes shipment dates as given. In practice, waiting for a later order may also allow split shipments to be avoided, which would add to the saving.
- **Service impact.** Added wait is measured in days of holding. Whether that makes deliveries late depends on promise dates, which should be set with the schedule in mind.
- **Shipments without freight cost** (missing in the data) are excluded.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Freight model, shipment base and scenario tables, and 2 analysis steps |
| `validation.sql` | 10 pass/fail checks |
