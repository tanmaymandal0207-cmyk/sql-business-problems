# Case Study · Quiet Categories: Are Customers Moving Categories to Competitors?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study covers 11 quarters of orders (January 2024 – September 2026) for every customer-category pair. It finds categories a customer bought regularly that went quiet for three quarters while the customer kept ordering other things. It then compares that rate with chance and tracks how many quiet categories came back.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-06 |

---

## 1. Business problem

The [churn early-warning](../02_customer_churn_early_warning/) report flags customers who stop buying altogether. The sales head suspects a quieter leak: customers who still buy from us but have taken one category, such as bearings or pumps, to a competitor. Before adding a "quiet category" alert to the weekly sales review, he wants to know how common it is, whether it is real, and which customers to call.

## 2. Business questions

1. How often does a category a customer bought regularly go quiet while the customer keeps ordering other things?
2. Is that more than the customer's normal gaps would produce?
3. How many quiet categories come back, and how quickly?
4. Which categories go quiet most, how much revenue is really lost, and which pairs should sales call now?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Line revenue |
| `products` | One row per product | Category |
| `product_categories` | One row per category | Category name |
| `customers` | One row per customer | Name and segment for the call list |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Panel | Every customer-category pair ever bought × each of the 11 quarters (q = 0 for 2024 Q1 to q = 10 for 2026 Q3), with revenue after line discounts from valid orders (not Cancelled or Returned) |
| **Established pair** at quarter t | Bought in at least 3 of the 4 quarters t−4 to t−1, including t−1 |
| **Quiet spell** starting at t | An established pair not bought in t, t+1 and t+2, while the customer ordered something in each of those quarters. Starts from 2025 Q1 to 2026 Q1 can be seen in full. |
| **Expected by chance** | For each established pair-quarter, (1 − p)³, where p = share of the customer's active quarters in which the pair bought the category |
| z-score | (observed spells − expected) ÷ √Σ p(1 − p), treating each pair-quarter as an independent draw |
| **Came back** | The pair bought the category again after the spell, by September 2026 |
| Value in the year before | The pair's revenue in the four quarters before the spell |

## 5. Analytical approach

1. **Panel** (`sahyadri_b2b.qc_panel`): pairs × quarters, with the customer's activity in each quarter.
2. **Events** (`sahyadri_b2b.qc_events`): every established pair-quarter whose next three quarters can be observed, with the quiet flag, the chance of a quiet spell and the return quarter. Quiet rate against chance, by start quarter.
3. **Returns**: how many quiet categories came back, by follow-up length.
4. **Categories, value and call list.**

## 6. SQL techniques used

- A dense panel from `CROSS JOIN UNNEST(GENERATE_ARRAY(0, 10))`, so quarters without purchases count as zero
- Rolling look-back and look-ahead windows (`ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING`, `CURRENT ROW AND 2 FOLLOWING`)
- `MIN(IF(value > 0, q, NULL)) OVER (... 3 FOLLOWING AND UNBOUNDED FOLLOWING)` to find the first return after a spell
- A chance baseline and z-score computed with plain aggregates

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Panel revenue = source revenue |
| 02 | Every pair has one row for each of the 11 quarters |
| 03 | Quarter index and customer activity match the calendar quarters of the source |
| 04 | **Events are established pairs** (recount of the prior four quarters and the last one) |
| 05 | The customer ordered in all three quarters of every window |
| 06 | **Quiet = no purchase in the three quarters** (recount) |
| 07 | Return quarter = first purchase after the spell (recount) |
| 08 | Chance of a quiet spell = (1 − pair buy rate)³ |
| 09 | Spell starts lie in 2025 Q1 – 2026 Q1 |
| 10 | Quiet spells of the same pair never overlap |

## 8. Findings

**About one established category in 28 goes quiet for three quarters, roughly 1.5 times as often as chance would produce.**

| Quiet from | Established pairs | Quiet spells | Quiet rate | Expected by chance | Expected spells | z |
|---|---:|---:|---:|---:|---:|---:|
| 2025 Q1 | 425 | 12 | 2.8 % | 2.13 % | 9.1 | 1.04 |
| 2025 Q2 | 452 | 21 | 4.6 % | 2.30 % | 10.4 | 3.47 |
| 2025 Q3 | 435 | 15 | 3.4 % | 2.36 % | 10.3 | 1.58 |
| 2025 Q4 | 478 | 16 | 3.3 % | 2.59 % | 12.4 | 1.10 |
| 2026 Q1 | 518 | 20 | 3.9 % | 2.65 % | 13.7 | 1.79 |
| **All** | **2,308** | **84** | **3.6 %** | **2.42 %** | **55.8** | **4.00** |

There are about 28 more quiet spells than customers' normal gaps would explain. The excess is clear overall, but in four of the five quarters on its own it is within chance.

**Most quiet categories come back.**

| Quiet from | Quarters of follow-up | Quiet spells | Back the next quarter | Back by September 2026 |
|---|---:|---:|---:|---:|
| 2025 Q1 | 4 | 12 | 7 | 9 (75.0 %) |
| 2025 Q2 | 3 | 21 | 15 | 20 (95.2 %) |
| 2025 Q3 | 2 | 15 | 7 | 10 (66.7 %) |
| 2025 Q4 | 1 | 16 | 6 | 6 (37.5 %) |
| 2026 Q1 | 0 | 20 | – | – |

Of the 48 spells with at least two quarters of follow-up, **60.4 % came back the very next quarter and 81.3 % within two quarters.**

**Hydraulics, motors and pumps go quiet most; bearings and safety equipment hardly do.**

| Category | Established pair-quarters | Quiet spells | Quiet rate | Expected by chance | Came back |
|---|---:|---:|---:|---:|---:|
| Hydraulic Components | 133 | 11 | **8.3 %** | 4.47 % | 4 |
| Electric Motors & Drives | 150 | 11 | **7.3 %** | 4.81 % | 6 |
| Pumps | 182 | 13 | **7.1 %** | 3.58 % | 9 |
| Power Transmission | 123 | 8 | 6.5 % | 5.02 % | 4 |
| Cutting Tools & Abrasives | 173 | 7 | 4.0 % | 3.15 % | 4 |
| Pneumatic Components | 273 | 9 | 3.3 % | 1.96 % | 7 |
| Fasteners | 294 | 7 | 2.4 % | 1.49 % | 3 |
| Valves & Fittings | 331 | 8 | 2.4 % | 1.87 % | 3 |
| Industrial Safety Equipment | 368 | 6 | 1.6 % | 1.12 % | 3 |
| Bearings | 281 | 4 | 1.4 % | 1.59 % | 2 |

Pumps go quiet twice as often as chance, but most of them came back (9 of 13). Bearings go quiet no more often than chance.

**The revenue truly lost is small, but the spells that do not come back tend to be the larger ones.**

| Follow-up | Quiet spells | Customers | Value in the year before | Not back yet | Value not back |
|---|---:|---:|---:|---:|---:|
| Two or more quarters | 48 | 34 | ₹119.3 lakh | **9** | **₹35.7 lakh** |
| Less than two quarters | 36 | 32 | ₹45.6 lakh | 30 | ₹41.3 lakh |
| **All** | **84** | **55** | **₹164.9 lakh** | **39** | **₹77.0 lakh** |

Among spells watched for at least two quarters, 9 have not come back. They held ₹35.7 lakh in the year before, about ₹4 lakh each, against ₹2.5 lakh for the average spell with that much follow-up.

**Call list: the largest pairs still quiet in September 2026**

| Customer | Segment | Category | Quiet since | Value in the year before |
|---|---|---|---|---:|
| Unique Trading Co. LLP | Distributor | Electric Motors & Drives | 2025 Q3 | ₹11.85 lakh |
| Siddhivinayak Tiwari Sales Corporation & Co. | Distributor | Electric Motors & Drives | 2025 Q2 | ₹5.90 lakh |
| Prime Bhatia Precision Engineering Pvt Ltd | Enterprise | Pumps | 2025 Q3 | ₹5.82 lakh |
| Kaveri Ghosh Dairy LLP | Mid-Market | Electric Motors & Drives | 2025 Q1 | ₹5.75 lakh |
| Navkar Agencies | Distributor | Hydraulic Components | 2026 Q1 | ₹3.83 lakh |
| Chopra Precision Engineering LLP | Mid-Market | Pumps | 2026 Q1 | ₹3.82 lakh |
| Unique Trading Co. LLP | Distributor | Cutting Tools & Abrasives | 2026 Q1 | ₹3.66 lakh |
| Iyer Food Industries Pvt Ltd | Mid-Market | Electric Motors & Drives | 2026 Q1 | ₹3.49 lakh |

## 9. Business implications and recommendations

1. **There is a category leak, but it is small.** Three quiet quarters are usually a normal gap: four in five come back within two quarters. A quiet-category alert should not be treated as lost business.
2. **Add the alert, but rank it by value and category.** Flag established pairs after three quiet quarters, and call first where the pair was worth ₹3 lakh or more a year, or the category is hydraulics, motors or pumps. Those are the spells least likely to be a normal gap.
3. **Call the eight pairs above this month.** Four of them are electric motors, two at distributors. A competitor may have won that line, which [cross-sell white space](../../02_sales_and_profitability/04_cross_sell_white_space/) and pricing should check.
4. **Give bearings and safety equipment a fourth quiet quarter before alerting.** They go quiet rarely, close to the chance rate.
5. **Review after two more quarters.** The 36 spells that began in 2025 Q4 and 2026 Q1 have little follow-up yet. Their return rate will show whether the leak is growing.

## 10. Assumptions and limitations

- **The chance baseline is approximate.** p is measured over all 11 quarters, including the spell itself. That raises the expected rate and makes the comparison conservative. But overlapping windows of the same pair are not independent, so the z-score overstates certainty.
- **Quarterly grain.** A customer that buys a category twice a year can look quiet by chance; the baseline allows for that only on average.
- **Coming back is not the same as full recovery.** A pair that returns with a small order counts as back.
- **No competitor data.** A quiet category may also mean the customer's own need ended (a project finished, a machine replaced).
- **Short follow-up for recent spells.** Spells starting in 2026 Q1 cannot be judged yet.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Panel and event tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
