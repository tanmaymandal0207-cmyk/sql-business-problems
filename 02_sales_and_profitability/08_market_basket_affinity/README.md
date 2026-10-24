# Case Study · Market Basket Affinity with Significance Testing

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 9,391 orders, January 2024 – September 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-24 |

---

## 1. Business problem

The sales team wants product bundles and "customers who bought this also buy" prompts in the order system. These only make sense for products that are **genuinely** bought together more often than chance. With 200 products there are almost 20,000 possible pairs, so some pairs will look related purely by luck. Standard market basket tools rank pairs by lift without asking whether the lift is real. The sales head wants only associations that survive a proper statistical test.

## 2. Business questions

1. Which product categories and products are bought together more often than chance would explain?
2. How strong and how reliable are those associations?
3. Which pairs are good enough for a bundle or an order-entry prompt?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order status and date |
| `sales_order_items` | One row per product per order | Basket contents |
| `products`, `product_categories` | One row per product / category | Categories and names |

## 4. Method and metric definitions

| Metric | Definition |
|---|---|
| Support (A, B) | Orders containing both ÷ all orders |
| Confidence (A → B) | Orders containing both ÷ orders containing A |
| Lift | Support (A, B) ÷ (support A × support B). 1 means independent; above 1 means bought together more than chance. |
| Chi-square (1 df) | N (ad − bc)² ÷ ((a + b)(c + d)(a + c)(b + d)) on the 2 × 2 table: both, A only, B only, neither |
| Bonferroni correction | The 5 % level is divided by the number of pairs tested. The critical value is taken from the next stricter standard level, which is slightly conservative. |
| Actionable pair | Significant after correction, lift ≥ 1.5, and confidence ≥ 10 % in at least one direction |

Product pairs are tested only if bought together in at least 15 orders. Below that, no test has the power to detect a real association.

## 5. Analytical approach

1. **Basket table** (`sahyadri_b2b.basket_items`). One row per order and product, with category.
2. **Pair statistics** (`sahyadri_b2b.basket_pair_stats`). Support, confidence, lift, expected co-occurrence and chi-square for all 45 category pairs and every product pair with 15+ joint orders.
3. **Significance** (`sahyadri_b2b.basket_pair_results`). Bonferroni-corrected critical values, significant and actionable flags, and a summary.
4. **Category pairs** ranked by strength of evidence.
5. **Product pairs** that pass the test.

## 6. SQL techniques used

- A self-join on `order_id` with `y.item > x.item` to enumerate each unordered pair once
- A full 2 × 2 contingency table per pair derived from marginal counts
- Chi-square statistics and a multiple-testing correction in SQL
- Validation with arrays (`ARRAY_AGG`, `IN UNNEST`) to recount co-occurrence per order, and an independent (O − E)² / E chi-square formula

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Basket orders = in-scope orders (9,391) |
| 02 | All 45 category pairs are tested |
| 03 | No 2 × 2 table has a negative cell |
| 04 | **Category co-occurrence recounted** order by order with arrays |
| 05 | Product pairs tested = an independent count of pairs with 15+ joint orders (411) |
| 06 | No product pair below the minimum co-occurrence |
| 07 | **Chi-square recomputed** with the (O − E)² / E formula |
| 08 | Significant and actionable flags follow their rules |
| 09 | Confidence between 0 and 1, and support never above confidence |
| 10 | Lift = confidence (A → B) ÷ support (B) |

## 8. Findings

**Almost all apparent associations disappear under a proper test.**

| Level | Pairs tested | Significant at 5 % (no correction) | Expected by chance | Significant after Bonferroni | Actionable | Lift range |
|---|---:|---:|---:|---:|---:|---|
| Category | 45 | 12 | 2.3 | **1** | 0 | 0.97 – 1.18 |
| Product | 411 | 68 | 20.6 | **2** | **1** | 0.69 – 2.81 |

- **There is some real structure, but it is weak.** About five times as many category pairs pass an uncorrected test as chance would produce (12 against 2.3). After correcting for 45 tests, only one survives, and even its lift is only 1.18.
- **Categories are bought almost independently.** The strongest pair, Electric Motors & Drives with Cutting Tools & Abrasives, appears together in 299 orders against 253 expected (lift 1.18).
- **Only two product pairs survive correction:**

| Product A | Product B | Orders together | Expected by chance | Lift | Confidence A → B | B → A | Actionable |
|---|---|---:|---:|---:|---:|---:|---|
| Carbide End Mill 4 Flute 6 mm | Carbide Turning Insert CNMG 120408 | 19 | 6.8 | 2.81 | 7.9 % | 7.2 % | No (confidence under 10 %) |
| Stud Bolt B7 M16x120 | Ball Valve SS316 1 in Screwed | 18 | 6.8 | 2.66 | **19.8 %** | 2.6 % | **Yes** |

- **The one actionable rule is one-directional.** One in five orders for B7 stud bolts also contains the 1 in SS316 ball valve, which fits a pipework installation. The reverse prompt would be wrong 97 % of the time.
- **Baskets are small.** The median order has 2 products, and 3,014 orders (32 %) contain a single category. There is little room for pair patterns to form.

## 9. Business implications and recommendations

1. **Do not build bundles on raw lift.** Without the significance test, 68 product pairs would have looked like bundle candidates. Only 2 hold up, and only 1 is strong enough to act on.
2. **Add a single order-entry prompt:** when B7 stud bolts are ordered, suggest the SS316 1 in ball valve. Measure the take-up rate for a quarter before adding more prompts.
3. **Promote carbide tooling as a range, not a bundle.** End mills and turning inserts are linked, but each is in fewer than 8 % of the other's orders.
4. **Use customer-level cross-sell instead.** In this business, customers buy categories in separate orders as needs arise. The [Cross-sell white-space analysis](../04_cross_sell_white_space/) works at customer level over 12 months, which is where the opportunity lies (₹4.18 crore of gaps).
5. **Re-run the test yearly.** As order history grows, more pairs will reach the 15-order threshold and the test will gain power.

## 10. Assumptions and limitations

- **Order-level baskets.** Products bought by the same customer in separate orders a day apart are not treated as a basket. A customer-week basket would find more pairs.
- **Conservative correction.** Bonferroni controls false positives strictly and can miss weak real effects. The 68 uncorrected hits include some real but weak associations.
- **Association, not cause.** A significant pair shows products are bought together, not that prompting one will sell the other.
- **Minimum co-occurrence** (15 orders) and the actionable thresholds are declared at the top of the script and can be changed.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Basket, pair statistics and results tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
