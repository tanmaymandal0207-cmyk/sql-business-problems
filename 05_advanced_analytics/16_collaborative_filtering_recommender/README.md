# Case Study · Product Recommendations: Collaborative Filtering vs Simple Rules

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Trained on purchases from January 2024 to September 2025 and tested on what 308 customers bought for the first time from October 2025 to September 2026 (48,421 candidate recommendations, 4,016 new products bought).

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-27 |

---

## 1. Business problem

A software vendor has offered the sales team a recommendation engine that suggests, for each customer, the products it is most likely to buy next but has not bought before ("customers like you also buy"). Before paying for it, the commercial head wants the idea tested on the company's own history with a method he can audit: build the same kind of recommender in SQL, pretend it is September 2025, and check its suggestions against what customers actually bought in the following year.

## 2. Business questions

1. How well would item-based collaborative filtering have predicted the new products customers bought the following year?
2. Does it beat simple rules: the best sellers overall, or the best sellers in the customer's segment?
3. What, if anything, does personalisation add?
4. What should the sales team use?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Products bought |
| `customers` | One row per customer | Segment |
| `products` | One row per product | Names |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Purchases | Customer × product pairs on orders not Cancelled or Returned |
| Training / test | Training: 1 Jan 2024 – 30 Sep 2025. Test: 1 Oct 2025 – 30 Sep 2026. |
| Customers evaluated | Bought in both periods (308) |
| **Candidate** | A product sold in training that the customer did not buy in training |
| **Hit** | The customer buys the candidate in the test period |
| **Item similarity (cosine)** | Customers who bought both products ÷ √(customers who bought i × customers who bought j), training only |
| **Collaborative filtering (CF) score** | Σ over products the customer bought of their similarity to the candidate |
| Best sellers overall | Candidates ranked by the number of training customers who bought them |
| Best sellers in segment | The same within the customer's segment |
| **Precision@5** | Hits among each customer's top 5 ÷ 5 |
| Hit rate | Share of customers with at least one hit in their top 5 |
| Recall | Hits ÷ all new products the customers bought |
| Tests | Paired t on the per-customer difference in hits; McNemar z on "at least one hit" |

## 5. Analytical approach

1. **Purchase sets** (`sahyadri_b2b.rec_purchases`) and **item similarity** (`sahyadri_b2b.rec_similarity`) from training purchases.
2. **Score table** (`sahyadri_b2b.rec_scores`). Every candidate with its CF score, popularity, segment popularity, rank under each method and whether it was bought in the test period.
3. **Back-test** (`sahyadri_b2b.rec_customer_eval`). Precision, hit rate, recall and coverage per method; paired tests of CF against best sellers.
4. **What personalisation adds**: precision of recommendations unique to each method; precision at different list lengths; the best-seller list itself.

## 6. SQL techniques used

- Item-item cosine similarity from a self-join of the customer × product purchase set
- Candidate generation with `CROSS JOIN` and an anti-join (`LEFT JOIN … WHERE … IS NULL`)
- Scoring by joining a customer's history to the similarity table, then `ROW_NUMBER()` top-K per customer for three methods at once
- Time-based back-test: train on one period, evaluate on the next
- Paired t-test and McNemar test written in SQL
- Validation that rebuilds each customer's top CF score from raw co-purchases, without the similarity table

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Purchase sets = distinct source customer × product × period |
| 02 | Similarity is symmetric |
| 03 | Cosine = co-customers ÷ √(nᵢ × nⱼ), between 0 and 1 |
| 04 | No candidate was already bought in training |
| 05 | Candidates = customers × products − training purchases |
| 06 | Ranks run 1..n for every customer and method |
| 07 | Hit flag = purchase in the test period (recount) |
| 08 | **Top CF score = a recount from raw co-purchases** |
| 09 | New products bought = test purchases outside the training sets |
| 10 | Hits per method = recount from the score table |

## 8. Findings

**Any sensible list is four times better than chance. The best-seller list is the best of them.**

| Method | Hits | Precision@5 | Hit rate | Recall |
|---|---:|---:|---:|---:|
| **Best sellers overall** | **521** | **33.8 %** | 76.0 % | **13.0 %** |
| Best sellers in segment | 512 | 33.2 % | **76.9 %** | 12.7 % |
| Collaborative filtering | 488 | 31.7 % | 74.7 % | 12.2 % |
| Random pick (base rate) | | 8.3 % | | |

- **Collaborative filtering is slightly worse than the best-seller list**: 0.107 fewer hits per customer (paired t = −2.63). On "at least one hit", 14 customers were helped only by CF and 18 only by best sellers (McNemar z = −0.71, no real difference).
- Best sellers win at every list length:

| Recommendations per customer | Best sellers | Collaborative filtering |
|---:|---:|---:|
| 1 | **47.7 %** | 41.6 % |
| 3 | 37.6 % | 36.5 % |
| 5 | 33.8 % | 31.7 % |
| 10 | 28.3 % | 26.9 % |
| 20 | 22.7 % | 22.3 % |

**Personalisation changes the list, but the products it adds sell less.**

| Recommendation | Recommendations | Hits | Precision | Average product popularity (training customers) |
|---|---:|---:|---:|---:|
| Recommended by both | 1,113 | 380 | 34.1 % | 151.7 |
| CF only | 427 | 108 | **25.3 %** | 93.0 |
| Best sellers only | 427 | 141 | **33.0 %** | 126.0 |

- 72 % of CF's recommendations are on the best-seller list anyway. The products CF adds in their place are less popular and convert less often (25.3 % against 33.0 %).
- CF recommends a wider range (79 products against 69), but wider is not better here.
- **Why:** customers' purchases have little structure beyond popularity. The [market basket study](../../02_sales_and_profitability/08_market_basket_affinity/) found that only 2 of 411 product pairs are bought together more than chance; a "customers like you" method has little to learn from.

**The best-seller list, as a cross-sell prompt**

| Product | Training customers | Evaluated customers not yet buying | Bought it next year | Conversion |
|---|---:|---:|---:|---:|
| Safety Shoes Steel Toe Size 9 | 274 | 57 | 29 | **50.9 %** |
| Non Return Valve 2 in Swing Type | 221 | 99 | 39 | 39.4 % |
| Pillow Block Bearing UCP207 | 173 | 139 | 42 | 30.2 % |
| Hex Nut HT M16 (Box of 100) | 165 | 149 | 44 | 29.5 % |
| Dewatering Pump 5 HP | 170 | 143 | 38 | 26.6 % |

Half of the customers who had not bought the best-selling safety shoes did so the following year.

## 9. Business implications and recommendations

1. **Do not buy the recommendation engine on accuracy grounds.** On this data, a "customers like you" recommender is no better, and at short list lengths worse, than a list of best sellers the customer has not yet bought.
2. **Give the sales team a simple best-seller gap list.** For each customer, the top 5 best sellers it does not buy: one in three suggestions turns into a purchase within a year, four times the rate of a random product.
3. **Lead with the single top gap.** The first suggestion converts 47.7 % of the time; use it as the one prompt on the account page or call plan.
4. **Combine with consumable categories.** The [cross-sell stickiness](../../01_customer_and_revenue/13_cross_sell_stickiness/) study shows Valves & Fittings and Industrial Safety Equipment repeat after a first purchase; best-seller gaps in those categories are the most valuable to close.
5. **Re-test before revisiting.** If the product range or customer base grows enough for real co-purchase patterns to appear, re-run this script; it compares the methods on the same footing.

## 10. Assumptions and limitations

- **Binary purchases.** The recommender uses whether a customer bought a product, not how much. Quantity-weighted similarity is a possible refinement.
- **Products sold in training only.** Products launched in the test period cannot be recommended by any method; there were none.
- **A hit is any purchase in the next 12 months.** It does not prove the recommendation caused the purchase; it measures how well each method anticipates demand.
- **One split in time.** The back-test uses a single training cut-off. The ranking of methods was the same at every list length tested, but a rolling back-test over several cut-offs would make the comparison firmer.
- **Item-based CF only.** User-based and matrix-factorisation methods were not tested; with weak co-purchase structure they face the same limit.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Purchase, similarity, score and evaluation tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
