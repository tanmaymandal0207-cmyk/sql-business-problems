# Case Study · Gateway Categories: Does the First Order Predict Customer Value?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 367 customers whose first order was placed by 30 September 2025, followed for 12 months, compared by the category of their first order with segment and first-order size held constant and a 1,000-shuffle permutation test.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-30 |

---

## 1. Business problem

Marketing is planning next year's acquisition campaigns and wants to lead with the product categories that bring in the best customers. A raw comparison looks convincing: customers whose first order was mainly hydraulic or pneumatic components spent ₹13–15 lakh in their first year, while those who started with valves or fasteners spent about ₹5 lakh. Before building campaigns around it, the commercial head wants to know whether the category matters, or whether bigger customers simply place bigger first orders.

## 2. Business questions

1. What do new customers buy first, and what do they spend in the following year?
2. Does the first-order category still matter once segment and first-order size are held constant?
3. Which gateway categories lead customers into other categories?
4. What should acquisition campaigns target instead?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | First order, later orders, status |
| `sales_order_items` | One row per product per order | Order values, categories bought |
| `products`, `product_categories` | One row per product / category | Category of each line |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Valid order | Not Cancelled or Returned |
| First order | The customer's earliest valid order (date, then order id) |
| **Gateway category** | The category with the largest net value on the first order |
| Follow-up | The 365 days after the first order, excluding the first order itself; first orders up to 30 Sep 2025 |
| Came back | Any valid order in the follow-up |
| 12-month revenue | Net revenue of valid orders in the follow-up |
| New categories | Categories bought in the follow-up that were not on the first order |
| Size band | Thirds of first-order value |
| **Expected outcome** | The average of the customer's segment × size-band cell |
| **Adjusted effect** | Category average of (outcome − expected) |
| **Permutation test** | Gateway labels shuffled 1,000 times within each segment × size cell. Overall statistic Σ n × effect²; per category, the share of shuffles with an effect at least as large. Revenue tested in rupees and as LN(1 + rupees). With 10 categories, p < 0.005 is needed (Bonferroni). |

## 5. Analytical approach

1. **Customer table** (`sahyadri_b2b.gw_customers`): first order, gateway category and 12-month outcomes for each customer.
2. **Scored table** (`sahyadri_b2b.gw_scored`): size band, segment × size cell and expected outcomes.
3. **Raw and adjusted outcomes** by gateway category, and by first-order size.
4. **Permutation statistics** (`sahyadri_b2b.gw_permutation_stats`): adjusted effects for the real labels (b = 0) and 1,000 stratified shuffles.
5. **Categories bought next**, by gateway.

## 6. SQL techniques used

- First-event analysis with `ROW_NUMBER()` (first order, then the largest category on it)
- Follow-up windows with a strict "after the first order" condition on date and order id
- Indirect adjustment for confounders with cell means from window functions
- A stratified permutation test in SQL: labels moved between positions inside each cell by an integer hash, 1,000 times
- Validation by independent recounts of the first order, the gateway choice and every 12-month outcome

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer whose first valid order is on or before the cut-off |
| 02 | First order = the earliest valid order (date, then order id) |
| 03 | **The gateway category has the largest value on the first order** |
| 04 | First-order value and category count = source recount |
| 05 | **12-month orders and revenue = an independent recount** |
| 06 | Came back = any later order; new categories ≤ categories ≤ 10 |
| 07 | Three size bands of near-equal size that do not overlap |
| 08 | Expected outcomes = segment × size cell means |
| 09 | 1,001 label sets, each keeping every category's customer count |
| 10 | Real-label effects = a direct recount |

## 8. Findings

**The raw comparison makes categories look very different.**

| Gateway category | Customers | Average first order | Came back | 12-month revenue (average) | Median |
|---|---:|---:|---:|---:|---:|
| Hydraulic Components | 24 | ₹76.5k | 91.7 % | **₹14.76 lakh** | ₹2.93 lakh |
| Pneumatic Components | 32 | ₹28.6k | 84.4 % | ₹12.91 lakh | ₹3.18 lakh |
| Electric Motors & Drives | 36 | ₹191.4k | **100 %** | ₹11.13 lakh | ₹3.45 lakh |
| Industrial Safety Equipment | 68 | ₹39.2k | 77.9 % | ₹9.69 lakh | ₹1.57 lakh |
| Bearings | 23 | ₹22.9k | 82.6 % | ₹9.02 lakh | ₹1.77 lakh |
| Pumps | 58 | ₹116.2k | 84.5 % | ₹8.80 lakh | ₹1.55 lakh |
| Cutting Tools & Abrasives | 22 | ₹49.3k | 77.3 % | ₹8.37 lakh | ₹2.31 lakh |
| Valves & Fittings | 64 | ₹35.4k | 79.7 % | **₹5.14 lakh** | ₹1.19 lakh |
| Fasteners | 33 | ₹29.0k | 84.8 % | ₹5.11 lakh | ₹1.87 lakh |
| Power Transmission | 7 | ₹64.9k | 100 % | ₹2.54 lakh | ₹0.82 lakh |
| **All** | **367** | ₹66.3k | **84.2 %** | **₹8.84 lakh** | ₹1.90 lakh |

**Once segment and first-order size are held constant, the gateway category predicts nothing.**

| Test (1,000 stratified shuffles) | Came back | Revenue (₹) | Revenue (log) | New categories |
|---|---:|---:|---:|---:|
| Does gateway category matter at all? (p-value) | 0.33 | 0.83 | 0.36 | 0.55 |

| Gateway category | Came back vs expected | Revenue vs expected | p (revenue, ₹) | p (came back) |
|---|---:|---:|---:|---:|
| Pneumatic Components | +2.2 pts | +₹4.30 lakh | 0.13 | 0.80 |
| Hydraulic Components | +7.1 pts | +₹3.49 lakh | 0.40 | 0.39 |
| Electric Motors & Drives | +10.2 pts | +₹1.20 lakh | 0.75 | **0.035** |
| Valves & Fittings | −2.6 pts | −₹1.97 lakh | 0.27 | 0.59 |
| Cutting Tools & Abrasives | −6.6 pts | −₹3.12 lakh | 0.49 | 0.54 |

- **Segment and first-order size explain 54.5 % of the spread** between the category averages; what is left is within the range that shuffling labels produces.
- No category passes the 0.005 threshold for 10 tests. The strongest signal (Electric Motors & Drives: all 36 customers came back, p = 0.035) is what one category in ten would show by chance.
- The ₹13–15 lakh averages for hydraulic and pneumatic starters come from a few large accounts: their medians are ₹2.9–3.2 lakh, and the rupee test does not separate them from chance (p = 0.13 and 0.40).

**The size of the first order is what predicts value.**

| First-order size | Customers | First-order range | Came back | 12-month revenue (average) | Median |
|---|---:|---:|---:|---:|---:|
| Smallest third | 123 | ₹0.3k – ₹15.6k | 78.0 % | ₹5.50 lakh | **₹0.71 lakh** |
| Middle third | 122 | ₹15.8k – ₹49.9k | 83.6 % | ₹6.60 lakh | ₹1.57 lakh |
| Largest third | 122 | ₹52.0k – ₹10.6 lakh | **91.0 %** | **₹14.45 lakh** | **₹5.81 lakh** |

The median customer in the largest third spends eight times as much in the following year as the median customer in the smallest third.

**Every gateway leads into other categories.** 76.6–100 % of customers bought at least one new category within a year, whatever they started with, and the number of new categories does not depend on the gateway (p = 0.55).

## 9. Business implications and recommendations

1. **Do not build acquisition campaigns around gateway categories.** The raw differences come from who the customer is and how much they first buy, not from what they buy.
2. **Target by size of first requirement.** A first order above about ₹50,000 marks a customer worth more than eight times the median small starter; qualify prospects on expected order size and segment.
3. **Treat small first orders as a nurture stream.** One in five small starters does not come back within a year. A follow-up after the first order (see [new customer activation](../05_new_customer_activation/)) costs little against that.
4. **Keep cross-sell generic in the first year.** Customers broaden into new categories at the same rate whatever they start with; the [cross-sell stickiness](../13_cross_sell_stickiness/) study shows which categories, once tried, repeat.
5. **Re-run when two more years of new customers are available.** With 7–68 customers per category, an effect of ₹2–3 lakh a customer could still be hiding in the noise.

## 10. Assumptions and limitations

- **One gateway per customer.** First orders average 2.2 categories; the largest by value is taken as the gateway.
- **Twelve-month window.** Longer-run value could differ, but the follow-up window must be observable for every customer.
- **Small groups.** Power Transmission has only 7 customers; its results are shown but cannot support any conclusion.
- **Adjustment by cells, not a model.** Segment × size thirds remove most, not all, of the size effect within each band.
- **Customers before 2024** are not observed; a customer whose real first order was earlier enters the data at its first order in 2024.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer, scored and permutation tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
