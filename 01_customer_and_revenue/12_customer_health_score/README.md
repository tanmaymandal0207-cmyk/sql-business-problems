# Case Study · Customer Health Score

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Back-tested on 663 customer snapshots (31 Mar 2025 and 30 Sep 2025, 85 of which churned in the following year); current scores for 367 customers at 30 Sep 2026.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

Account managers want one number per customer that says "this account is at risk". The CRM team has proposed a health score that combines seven signals: recency, frequency, spend trend, category breadth, late deliveries, unpaid invoices and cancellations. It sounds sensible, but nobody has tested it. Before it goes on the dashboard, the commercial head wants proof that it identifies customers who later stop buying, and that it does better than the simplest rule (days since the last order).

## 2. Business questions

1. Which signals actually predict that a customer stops buying?
2. Does a combined score beat the simplest rule?
3. How many of the customers who later left would the score have flagged in advance, and how much revenue did they represent?
4. Which current customers score lowest?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, dates, status |
| `sales_order_items` | One row per product per order | Revenue, products |
| `products` | One row per product | Category |
| `shipments` | One row per shipment | Delivery dates |
| `payments` | One row per payment | Amounts paid by a date |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Snapshots | 31 Mar 2025 and 30 Sep 2025 (back-test), 30 Sep 2026 (current). Each customer with an order in the previous 12 months is scored using **only data dated up to the snapshot**. |
| **Churned** | No order (not Cancelled or Returned) in the 12 months after the snapshot |
| Recency | Days since the last order |
| Frequency | Orders in the last 12 months |
| Trend | Share of 12-month revenue earned in the last 6 months |
| Breadth | Product categories bought in the last 12 months |
| Late share | Share of delivered orders that arrived after the promised date |
| Unpaid share | Share of orders delivered 60–365 days before the snapshot that were not fully paid by the snapshot date |
| Cancel share | Share of orders Cancelled or Returned |
| Points | Each signal's percentile rank within its snapshot (0–100), oriented so that 100 = healthiest |
| **Health score** | Average of the seven points, as proposed by the CRM team |
| **Activity score** | Average of recency, frequency and breadth points (the revision this study recommends) |
| **AUC** | Probability that a randomly chosen retained customer scores higher than a randomly chosen churned one. 0.5 = no skill, 1.0 = perfect. Computed with the Mann–Whitney rank formula and average ranks for ties. |

## 5. Analytical approach

1. **Signals table** (`sahyadri_b2b.health_signals`). Seven point-in-time signals and the churn outcome for every customer and snapshot.
2. **Scores table** (`sahyadri_b2b.health_scores`). Points per signal, the proposed health score and the activity score.
3. **AUC table** (`sahyadri_b2b.health_auc`). Predictive power of each signal and score on the back-test snapshots.
4. **Quintiles**: churn rate and share of all churners in each fifth of customers, for the health score, the activity score and recency alone; and the churners' revenue each one captures.
5. **Current list**: the lowest-scoring customers with at least ₹5 lakh of revenue in the last 12 months.

## 6. SQL techniques used

- Point-in-time feature engineering for several snapshot dates at once (`UNNEST` of a date array), with payments joined only up to each snapshot to avoid look-ahead
- `PERCENT_RANK()` to put different signals on one 0–100 scale
- AUC computed in SQL from average ranks (Mann–Whitney U)
- Validation that recomputes AUC by brute force over every retained × churned pair

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per snapshot and customer |
| 02 | Scored customers = source customers active in each 12-month window |
| 03 | 12-month revenue = source |
| 04 | **Churn flag = an independent recount** of next-year orders |
| 05 | No look-ahead: no customer's last order falls after the snapshot |
| 06 | Points between 0 and 100; both scores equal the average of their points |
| 07 | **Health score AUC = a brute-force pair count** |
| 08 | Activity score AUC = a brute-force pair count |
| 09 | Frequency AUC = a brute-force pair count |
| 10 | Outcomes exist only for back-test snapshots |

## 8. Findings

**Three of the seven proposed signals point the wrong way.**

| Signal | AUC |
|---|---:|
| Frequency | **0.894** |
| Breadth | 0.863 |
| Recency | 0.789 |
| Trend | 0.505 (no skill) |
| Cancellations | **0.388** |
| Payment (unpaid share) | **0.370** |
| Delivery (late share) | **0.320** |
| Health score, all seven (as proposed) | 0.811 |
| Health score without recency | 0.790 |
| **Activity score (recency, frequency, breadth)** | **0.886** |

- **Late deliveries, unpaid invoices and cancellations are more common among customers who stay.** An AUC below 0.5 means the signal ranks customers backwards. These signals measure exposure: a customer placing 30 orders a year is far more likely to have had one late, unpaid or cancelled order than a customer placing two, and the 30-order customer is also far more likely to stay. The [cost of a late delivery](../../05_advanced_analytics/09_cost_of_late_delivery/) study found the same: lateness does not reduce reordering.
- **Spend trend has no predictive value** (AUC 0.505), consistent with the [customer momentum](../../05_advanced_analytics/10_customer_momentum/) study.
- Adding the three backward signals to the score lowers its AUC from 0.886 to 0.811.

**The activity score finds far more of the leavers.**

| Ranking (bottom fifth of customers) | Churn rate in bottom fifth | Share of all churners caught |
|---|---:|---:|
| **Activity score** | **44.4 %** | **69.4 %** |
| Health score (as proposed) | 30.8 % | 48.2 % |
| Recency only | 31.6 % | 49.4 % |

| Activity score quintile | Customer snapshots | Churned | Churn rate | Prior 12-month revenue (both snapshots added) |
|---|---:|---:|---:|---:|
| 1 (lowest) | 133 | 59 | 44.4 % | ₹59.7 lakh |
| 2 | 133 | 19 | 14.3 % | ₹1.80 crore |
| 3 | 133 | 6 | 4.5 % | ₹5.31 crore |
| 4 | 132 | 1 | 0.8 % | ₹11.14 crore |
| 5 (highest) | 132 | 0 | 0.0 % | ₹41.57 crore |

- The proposed health score would have missed half of the customers who left. The activity score catches 69.4 % of them in its bottom fifth, and 91.8 % in its bottom two fifths.
- **But most churners are small.** The 85 churners had ₹85.7 lakh of revenue in their last year. The activity score's bottom fifth contains 29.2 % of that revenue; the proposed score's bottom fifth contains 42.2 %, because it also flags some larger accounts. The score finds **who** leaves very well; the money at risk is spread more widely.
- No customer in the top fifth by activity left.

**Current watch list (activity score, customers with ₹5 lakh+ in the last 12 months).**

| Customer | Segment | Activity score | Days since last order | Orders (12 m) | Revenue (12 m) |
|---|---|---:|---:|---:|---:|
| Pioneer Agencies | Distributor | 3.0 | 302 | 1 | ₹8.9 lakh |
| Annapurna Industrial Suppliers | Distributor | 30.3 | 160 | 4 | ₹6.0 lakh |
| Sai Menon Spinning Mills | Mid-Market | 32.2 | 113 | 3 | ₹6.4 lakh |
| Ganesh Singhania Sales Corporation | Distributor | 36.1 | 48 | 3 | ₹5.1 lakh |
| Vishwakarma Gupta Fabrics | Enterprise | 37.0 | 195 | 4 | ₹8.2 lakh |
| Sai Distributors | Distributor | 41.6 | 146 | 5 | ₹8.0 lakh |

## 9. Business implications and recommendations

1. **Do not launch the seven-signal score as proposed.** Three of its signals rank customers backwards and it misses half of the customers who leave.
2. **Use the activity score (recency, frequency and breadth)** for the churn-risk flag. It is simpler, it can be explained in one sentence ("customers who buy rarely, narrowly and not recently"), and it catches 69 % of leavers in the bottom fifth.
3. **Keep service signals, but as service measures, not churn predictors.** Late deliveries and unpaid invoices matter for operations and cash; normalise them per order and report them separately.
4. **Pair the risk flag with revenue.** Because churners are mostly small, sort the at-risk list by revenue, as in the watch list above, so account managers call the accounts that matter first. Start with Pioneer Agencies (302 days silent, ₹8.9 lakh last year) and Vishwakarma Gupta Fabrics (195 days).
5. **Re-run the back-test every six months** before changing weights. The SQL scores any new snapshot date added to the array.

## 10. Assumptions and limitations

- **Two back-test snapshots** with 85 churn events. The AUC values are reasonably stable at this size, but differences of 0.01–0.02 between scores are not meaningful.
- **Overlapping windows.** Many customers appear in both back-test snapshots, so the two are not independent samples.
- **Equal weights.** The scores average percentile points; a fitted model (for example logistic regression) could do slightly better but would be harder to explain.
- **Churn definition.** 12 months without an order. A shorter definition would raise churn counts and change which signals matter most.
- **Signals with no data** (no measurable delivery or payment yet) take the snapshot average, so they neither help nor harm a customer's score.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Signals, scores and AUC tables, and 2 analysis steps |
| `validation.sql` | 10 pass/fail checks |
