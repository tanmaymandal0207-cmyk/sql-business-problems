# Case Study · Cross-Sell Stickiness (Category Trial-to-Repeat)

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 946 cross-sell trials (an existing customer buying a category for the first time, up to 30 September 2025) followed for 12 months.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-27 |

---

## 1. Business problem

Sales managers count a cross-sell as won when an existing customer buys a product category for the first time, and the [cross-sell white-space](../../02_sales_and_profitability/04_cross_sell_white_space/) study gave them a list of gaps to target. The commercial head suspects that many first purchases are one-offs that never become recurring business. Before setting cross-sell targets for next year, he wants to know which categories, once tried, are bought again.

## 2. Business questions

1. When an existing customer tries a new category, how often does it buy that category again within 12 months?
2. Which categories repeat more or less often than expected, once the customer's own ordering frequency is allowed for?
3. How much follow-on revenue does a trial bring?
4. Which recent trials in sticky categories have not repeated yet?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Line value |
| `products` · `product_categories` | One row per product / category | Category |
| `customers` | One row per customer | Names, segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Order lines | Lines on orders that are not Cancelled or Returned |
| **Cross-sell trial** | A customer's first purchase of a category, at least 90 days after the customer's first order in the data (an existing account, not onboarding) |
| Measured trial | Trial dated on or before 30 Sep 2025, so 12 months of follow-up can be observed |
| **Repeat** | Another order containing the category, on a later date, within 365 days of the trial |
| Frequency band | The customer's number of orders (any category) in the 365 days after the trial: 0–3, 4–8, 9–15, 16+ |
| **Expected repeats** | Σ over a category's trials of the repeat rate of all trials in the same frequency band (indirect standardisation) |
| **O/E** | Observed ÷ expected repeats. Above 1 = stickier than the customers trying it would suggest. |
| z | (observed − expected) ÷ √Σ p (1 − p). With 10 categories tested, \|z\| ≥ 2.81 is significant (Bonferroni, 5 %). |
| Follow-on value | Category revenue in the 12 months after the trial, excluding the trial order |

A frequent buyer repeats almost anything, so raw repeat rates mostly measure **who** tries a category. Indirect standardisation compares each category with what its triallists' ordering frequency predicts.

## 5. Analytical approach

1. **Trial table** (`sahyadri_b2b.xs_trials`). One row per customer × category first purchase: trial date and value, cross-sell and measured flags, repeat orders, follow-on value, days to repeat, orders next year and frequency band.
2. **Category table** (`sahyadri_b2b.xs_category`). Trials, observed and expected repeats, O/E, z, median days to repeat and follow-on value per category.
3. **Sensitivity** with a stricter 180-day rule for what counts as a trial.
4. **Follow-up list**: trials since October 2025 in sticky categories that have not repeated within the category's median repeat time.

## 6. SQL techniques used

- First-event detection per customer × category with `MIN()` and a join back for the trial value
- Range joins on `DATE_ADD(…, INTERVAL 365 DAY)` for 12-month follow-up windows, aggregated before joining to avoid row multiplication
- Indirect standardisation: expected counts from stratum rates, O/E ratios and z-scores
- Bonferroni-adjusted significance threshold as a script parameter
- Validation that recounts repeats independently and confirms that expected repeats sum to observed repeats overall

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per source customer × category |
| 02 | Trial date = first source purchase date |
| 03 | Trial value = source |
| 04 | Cross-sell and measured flags follow the rules |
| 05 | **Repeat orders = an independent recount** |
| 06 | Repeat orders never exceed all orders in the following year |
| 07 | Frequency band agrees with orders in the following year |
| 08 | Category trials add up to measured trials |
| 09 | **Total expected repeats = total observed** (the property of indirect standardisation) |
| 10 | z recomputed from observed, expected and variance |

## 8. Findings

**About two cross-sell trials in three are repeated within a year.**

| | Count |
|---|---:|
| Customer × category first purchases | 3,066 |
| Bought in the customer's first 90 days (onboarding, excluded) | 1,764 |
| Cross-sell trials | 1,302 |
| Measured trials (12-month follow-up available) | 946 |
| Repeated within 12 months | 615 (**65.0 %**) |

**But the repeat rate mostly reflects how often the customer orders.**

| Customer's orders in the year after the trial | Trials | Repeat rate |
|---|---:|---:|
| 0–3 | 277 | 33.6 % |
| 4–8 | 343 | 65.9 % |
| 9–15 | 190 | 87.4 % |
| 16+ | 136 | 95.6 % |

**Once frequency is allowed for, consumables stick and capital equipment does not.**

| Category | Trials | Repeat rate | Observed | Expected | O/E | z | Verdict |
|---|---:|---:|---:|---:|---:|---:|---|
| Valves & Fittings | 90 | 77.8 % | 70 | 53.7 | **1.30** | **3.93** | Sticky |
| Industrial Safety Equipment | 67 | 71.6 % | 48 | 37.0 | **1.30** | **2.99** | Sticky |
| Bearings | 81 | 72.8 % | 59 | 50.9 | 1.16 | 2.07 | As expected |
| Pneumatic Components | 100 | 63.0 % | 63 | 60.4 | 1.04 | 0.61 | As expected |
| Fasteners | 100 | 65.0 % | 65 | 62.5 | 1.04 | 0.58 | As expected |
| Pumps | 94 | 68.1 % | 64 | 64.4 | 0.99 | −0.11 | As expected |
| Cutting Tools & Abrasives | 106 | 61.3 % | 65 | 71.3 | 0.91 | −1.54 | As expected |
| Hydraulic Components | 105 | 56.2 % | 59 | 69.5 | 0.85 | −2.51 | As expected |
| Electric Motors & Drives | 98 | 60.2 % | 59 | 69.4 | 0.85 | −2.64 | As expected |
| Power Transmission | 105 | 60.0 % | 63 | 75.8 | **0.83** | **−3.22** | One-off |

- **Valves & Fittings and Industrial Safety Equipment repeat 30 % more often than expected.** Both are replaced or consumed in normal operation.
- **Power Transmission repeats 17 % less often than expected**, and Electric Motors & Drives and Hydraulic Components are close to the significance line. Their raw repeat rates (56–60 %) look respectable only because they are tried by the most frequent buyers (9–11 orders a year on average).
- **The pattern survives a stricter definition.** Counting only trials 180 days or more after the first order, Valves & Fittings stays significant (z = 3.13), Bearings and Industrial Safety Equipment stay above 1.25 O/E, and Power Transmission and Electric Motors & Drives stay at 0.82–0.83.

**One-off categories still bring large follow-on revenue, because each sale is big.**

| Category | Average trial | Average follow-on (12 months) | Multiple | Median days to repeat |
|---|---:|---:|---:|---:|
| Industrial Safety Equipment | ₹15,780 | ₹44,600 | 2.83 | 106 |
| Pumps | ₹79,485 | ₹1,80,279 | 2.27 | 97 |
| Valves & Fittings | ₹19,631 | ₹43,967 | 2.24 | 109 |
| Electric Motors & Drives | ₹1,12,232 | ₹1,77,256 | 1.58 | 117 |
| Power Transmission | ₹19,860 | ₹25,738 | 1.30 | 115 |
| Pneumatic Components | ₹34,426 | ₹33,085 | 0.96 | 112 |

- A Pumps or Electric Motors & Drives trial is followed by ₹1.8 lakh of the category on average, mostly from fewer, larger orders. **Stickiness and value are different measures**: cross-sell targets should count both.
- **Pneumatic Components trials are followed by less revenue than the trial itself** (multiple 0.96), the weakest follow-on of any category.

**28 recent trials in the two sticky categories have not repeated yet**, worth ₹3.76 lakh at trial. Each is past the category's median repeat time (106–109 days). The largest are Laxmi Sales Corporation (Industrial Safety Equipment, ₹65,019, 1 Jun 2026), Banerjee Precision Engineering (Valves & Fittings, ₹42,442) and Bhatia Foods & Beverages (Valves & Fittings, ₹39,004). The full list is Step 4 of the script.

## 9. Business implications and recommendations

1. **Count a cross-sell as won at the second order, not the first.** For consumable categories, a first order without a repeat is a sample, not a new revenue stream.
2. **Lead cross-sell campaigns with Valves & Fittings and Industrial Safety Equipment.** They turn trials into recurring business 30 % more often than expected and bring about 2.2–2.8 times the trial value in the following year.
3. **Measure capital categories on order value, not repeat.** Pumps, Electric Motors & Drives and Power Transmission are bought when equipment is replaced; a single large follow-on order is success. Pair them with service and spares offers to create the repeat.
4. **Call the 28 un-repeated sticky trials.** Each is past the normal repeat point; a reminder or a standing order is the cheapest way to convert them. Combine with the [reorder reminder](../../05_advanced_analytics/06_reorder_reminders/) process.
5. **Review why Pneumatic Components trials do not grow.** Check whether the first order was a one-off project requirement or whether the customer found a cheaper supplier.

## 10. Assumptions and limitations

- **Left censoring.** The data starts in January 2024, so a "first purchase" may repeat a purchase made before 2024. The 90-day rule and the 180-day sensitivity limit this; the conclusions hold under both.
- **Category level.** Products within a category differ (a spare part inside Electric Motors & Drives may be consumable). A product-level study would need more trials per product.
- **12-month window.** Equipment replaced every few years cannot show a repeat in one year; this is why capital categories are judged on follow-on value too.
- **Association, not cause.** The study shows which trials repeat, not whether a sales push caused the trial.
- **Frequency bands use orders after the trial**, which describe the customer's activity, not a prediction available at the time of the trial.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Trial and category tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
