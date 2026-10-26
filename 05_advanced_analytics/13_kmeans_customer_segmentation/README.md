# Case Study · Customer Segmentation with k-means in SQL

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 367 active customers clustered on five behaviour features; k-means converged after 27 iterations.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script with a `WHILE` loop — run it as one script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

Every customer carries a segment label (Distributor, Enterprise, Mid-Market or SMB) set when it registered. Pricing, [discount bands](../../02_sales_and_profitability/06_discount_consistency/) and sales coverage all follow the label. The commercial head suspects the labels no longer describe how customers buy. Rather than another rule-based segmentation such as [RFM](../03_rfm_customer_segmentation/), he wants the data to find natural groups of customers and to compare them with the official labels.

## 2. Business questions

1. If customers are grouped purely by buying behaviour, what groups appear?
2. How well do the official segments line up with those groups?
3. Which customers behave unlike their label and should be reviewed?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, date, status |
| `sales_order_items` | One row per product per order | Revenue, discount |
| `products` | One row per product | Category |
| `customers` | One row per customer | Segment label, name |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Customers | Customers with an order (not Cancelled or Returned) in the 12 months to 30 Sep 2026 |
| Features | ln(revenue), ln(orders), categories bought, average discount %, ln(average order value) |
| Standardisation | Each feature converted to a z-score (mean 0, standard deviation 1), so no feature dominates the distance |
| **k-means** | k = 4. Repeat: assign each customer to the nearest centroid (squared Euclidean distance); move each centroid to the mean of its members. Stop when no customer changes cluster (maximum 30 iterations). |
| Start | The customers at the 12.5th, 37.5th, 62.5th and 87.5th revenue percentiles are the initial centroids, so the result is reproducible |
| **R²** | 1 − within-group sum of squares ÷ total sum of squares: the share of behavioural variation a grouping explains. Computed for the clusters and for the official segments on the same features. |

## 5. Analytical approach

1. **Feature table** (`sahyadri_b2b.km_features`). Raw and standardised features per customer.
2. **Initial centroids and assignment** (`sahyadri_b2b.km_centroids`, `sahyadri_b2b.km_assign`).
3. **Iterations**: a BigQuery scripting `WHILE` loop alternates the assignment and update steps and logs each iteration (`sahyadri_b2b.km_log`).
4. **Cluster profiles** (`sahyadri_b2b.km_customers`) in original units.
5. **Comparison** with official segments: cross-tab, R² for both groupings, and customers whose behaviour is rare for their label.

## 6. SQL techniques used

- An iterative machine-learning algorithm written in BigQuery scripting: `DECLARE`, `WHILE … DO … END WHILE`, `SET` from a scalar subquery, `CREATE OR REPLACE TABLE` and `INSERT` inside the loop
- Nearest-centroid assignment with `CROSS JOIN` and `QUALIFY ROW_NUMBER()`
- Z-score standardisation with window functions
- Variance decomposition (R²) for two groupings on the same data
- Validation that the result is a fixed point of the algorithm (nearest centroid = own cluster, centroid = mean of members)

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer active in the last 12 months |
| 02 | Revenue = source |
| 03 | Standardised features have mean 0 and standard deviation 1 |
| 04 | **Fixed point: every customer's nearest centroid is its own cluster** |
| 05 | **Every centroid equals the mean of its members** |
| 06 | The last iteration changed no customer (converged) |
| 07 | Final within-cluster sum of squares = last logged value |
| 08 | Four non-empty clusters |
| 09 | Total sum of squares = 5 × customers (as standardisation implies) |
| 10 | Within-cluster sum of squares never increased between iterations |

## 8. Findings

**Four clear behaviour groups emerge.**

| Cluster | Name | Customers | Revenue | Share | Typical revenue | Typical orders | Categories | Discount | Typical order value |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 4 | **Core accounts** | 103 | ₹32.60 crore | **80.8 %** | ₹18.45 lakh | 13.7 | 9.4 | 9.7 % | ₹1.34 lakh |
| 3 | **Regular buyers** | 105 | ₹6.19 crore | 15.3 % | ₹3.98 lakh | 10.5 | 8.2 | 2.6 % | ₹37,900 |
| 2 | **Occasional large orders** | 67 | ₹1.25 crore | 3.1 % | ₹1.37 lakh | 1.7 | 4.3 | 6.0 % | ₹79,200 |
| 1 | **Occasional small buyers** | 92 | ₹0.32 crore | 0.8 % | ₹24,000 | 1.9 | 2.9 | 2.0 % | ₹12,400 |

(Typical values are geometric means.) The algorithm converged after 27 iterations; the within-cluster sum of squares fell from 698 to 543.

**The official segments explain much less of how customers behave.**

| Grouping | Share of behavioural variation explained (R²) |
|---|---:|
| k-means clusters | **0.704** |
| Official segments | 0.446 |

| Official segment | Core accounts | Regular buyers | Occasional large | Occasional small | Customers |
|---|---:|---:|---:|---:|---:|
| Distributor | 48 | 0 | 15 | 1 | 64 |
| Enterprise | 53 | 0 | 9 | 0 | 62 |
| Mid-Market | 2 | 56 | 32 | 14 | 104 |
| SMB | 0 | 49 | 11 | 77 | 137 |

- **Distributor and Enterprise behave the same.** Both are mostly core accounts; the label difference does not show in buying behaviour.
- **Mid-Market and SMB overlap heavily.** 49 SMB customers buy like regular Mid-Market buyers (about 10 orders a year across 8 categories), while 46 Mid-Market customers buy only once or twice a year.
- **About a fifth of Distributor and Enterprise customers are occasional buyers** (25 of 126). They keep large-account discount terms without large-account behaviour.

**Customers whose behaviour is rare for their label (fewer than 10 % of their segment in that cluster), largest first.**

| Customer | Label | Behaves like | Revenue (12 m) | Orders | Categories | Discount |
|---|---|---|---:|---:|---:|---:|
| Ganesh Precision Engineering | Mid-Market | Core account | ₹71.4 lakh | 105 | 10 | 4.0 % |
| Tirupati Infrastructure | Mid-Market | Core account | ₹14.8 lakh | 13 | 9 | 7.6 % |
| Sudarshan Saxena Autoparts | SMB | Occasional large orders | ₹3.2 lakh | 2 | 5 | 2.7 % |
| Krishna Plastics | SMB | Occasional large orders | ₹2.6 lakh | 1 | 2 | 0.0 % |
| Narmada Naidu Petrochem | SMB | Occasional large orders | ₹2.5 lakh | 4 | 5 | 4.6 % |

- **Ganesh Precision Engineering is a core account labelled Mid-Market**: ₹71.4 lakh and 105 orders a year, larger than most Distributor and Enterprise customers.

## 9. Business implications and recommendations

1. **Re-segment on behaviour.** Replace or supplement the registration label with the four behaviour groups. They explain 70 % of the variation in buying behaviour against 45 % for the labels.
2. **Merge Distributor and Enterprise for coverage and pricing reviews.** Their behaviour is the same; keep the distinction only where contracts differ (for example resale rights).
3. **Move Ganesh Precision Engineering into key-account management.** It already buys like a core account.
4. **Review discount terms for the 25 occasional Distributor and Enterprise customers.** They receive large-account discounts for occasional buying; the [discount response](../11_discount_volume_response/) study shows those discounts do not buy volume.
5. **Give the 49 "regular" SMB customers Mid-Market service.** They order about ten times a year; the label puts them in low-touch coverage.
6. **Refresh the clusters every six months** by re-running the script; the deterministic start keeps the results comparable.

## 10. Assumptions and limitations

- **k = 4** to match the number of official segments. A different k would give a finer or coarser split; four groups are easy to act on.
- **Feature choice.** Five features describe size, frequency, breadth, price and order size. Payment behaviour and delivery experience are not included.
- **k-means finds a local optimum.** A different start could give slightly different clusters. The deterministic start makes the result reproducible; the validation proves the result is a stable solution.
- **Last 12 months only.** Customers with no order in the year are not clustered.
- **Euclidean distance on z-scores** weights the five features equally.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Feature, centroid, assignment, log and customer tables; the k-means loop; 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
