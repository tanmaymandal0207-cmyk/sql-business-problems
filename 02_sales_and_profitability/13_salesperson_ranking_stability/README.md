# Case Study · Salesperson Ranking Stability (Bootstrap)

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The 16 ranked salespeople of the [salesperson scorecard](../02_salesperson_scorecard/), re-ranked in 500 bootstrap samples that re-draw each person's customers.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-27 |

---

## 1. Business problem

The [salesperson scorecard](../02_salesperson_scorecard/) ranks 16 salespeople on six metrics and combines them into a balanced rank. The sales director wants to use it to set this year's incentive tiers. HR asks a fair question first: how much of each rank is skill, and how much is the luck of which customers a person happened to serve? If one large customer had ordered differently, would the ranking change?

## 2. Business questions

1. How precisely is each salesperson's metric measured?
2. Which ranks are stable, and which could easily be different?
3. Which pairs of salespeople can really be told apart?
4. How should incentive tiers be set so that they reflect real differences?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Salesperson, customer, status, promise date |
| `sales_order_items` | One row per product per order | Revenue, discount |
| `products` | One row per product | Unit cost |
| `shipments` | One row per shipment | Final delivery date |
| `payments` | One row per payment | Amount paid |
| `employees` | One row per employee | Names, designation |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Metrics | Exactly as in the scorecard: net revenue, gross margin %, discount %, cancellation rate, on-time delivery %, overdue receivable % and the balanced rank (rank on the sum of the six ranks). Orders dated 1 Jan 2024 – 30 Sep 2026. |
| **Cluster** | One salesperson × customer combination, holding the additive totals behind every metric (revenue, cost, orders, on-time orders, overdue balance …) |
| **Bootstrap replicate** | Each salesperson's clusters re-drawn with replacement (same number), metrics recomputed and all 16 re-ranked. 500 replicates. Resampling whole customers keeps each customer's orders together. |
| Random draws | An integer hash that gives identical results in any SQL engine: x0 = MOD(b·7919 + j·104729 + employee·1299709, 2³¹ − 1), then x1 = MOD(x0² + 12345, 2³¹ − 1), x2 = MOD(x1² + 54321, 2³¹ − 1); drawn cluster = 1 + MOD(x2, clusters) |
| **90 % interval** | 5th to 95th percentile of a metric or rank across replicates |
| **Distinguishable pair** | One of the two is ranked better in at least 95 % of replicates |
| Evidence tier | Clearly above most: reliably better than 8 or more of the other 15. Clearly below most: reliably worse than 8 or more. Otherwise middle. |

## 5. Analytical approach

1. **Cluster table** (`sahyadri_b2b.rs_clusters`). One row per salesperson × customer with the additive totals; customers per salesperson and the largest customer's share.
2. **Replicate table** (`sahyadri_b2b.rs_replicates`). Metrics and ranks for the actual data (replicate 0) and 500 bootstrap replicates.
3. **Intervals** (`sahyadri_b2b.rs_long`, `sahyadri_b2b.rs_intervals`). 90 % intervals of every metric and rank; chance of being in the top or bottom three.
4. **Pairs** (`sahyadri_b2b.rs_pairs`). For each metric and each of the 120 pairs, the share of replicates in which one beats the other; evidence tiers for the balanced rank.

## 6. SQL techniques used

- Cluster bootstrap in SQL: `GENERATE_ARRAY` for replicates, a portable integer hash for random draws, a join back to the cluster table to rebuild each sample
- Ratio metrics rebuilt from additive totals so that every replicate is a simple `SUM`
- Ranking within replicate with `RANK() OVER (PARTITION BY replicate …)`
- Percentile intervals with `APPROX_QUANTILES`
- Pairwise win probabilities by joining the long table to itself within replicate

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Clusters = distinct salesperson × customer pairs in the source |
| 02 | Cluster net revenue = source |
| 03 | **Replicate 0 gross margin % and on-time % = an independent recomputation from source** (the scorecard is reproduced exactly) |
| 04 | Rows = (500 + 1) × 16 salespeople |
| 05 | Every replicate draws exactly as many customers as each salesperson has |
| 06 | Bootstrap mean revenue within 4 standard errors of the actual |
| 07 | Ranks lie in 1–16 and every replicate has a rank 1 on each metric |
| 08 | Rank sum = sum of the six metric ranks |
| 09 | Pair table = 7 metrics × 120 pairs, probabilities between 0 and 1 |
| 10 | **Balanced-rank pair probabilities = a recount from the replicate table** |

## 8. Findings

**Only 19 of 120 pairs of salespeople can be told apart on the balanced rank.**

| Metric | Average width of 90 % rank interval | Pairs distinguishable | Salespeople whose interval spans 8+ places |
|---|---:|---:|---:|
| Net revenue | 6.7 places | **50.0 %** | 5 |
| Gross margin % | 7.1 | **50.0 %** | 7 |
| On-time delivery % | 7.9 | 39.2 % | 12 |
| Discount % | 9.7 | 22.5 % | 12 |
| Cancellation rate | 11.6 | 7.5 % | 15 |
| Overdue receivable % | 12.0 | **5.8 %** | 15 |
| **Balanced rank** | **11.0** | **15.8 %** | 15 |

- **Cancellation rate and overdue receivable % are almost pure noise at salesperson level.** A different draw of the same customers could put almost anyone anywhere in the table. Each counts as one-sixth of the balanced rank.
- Revenue and margin carry real information: half of all pairs can be separated.

**The balanced rank changes a lot under resampling.**

| Balanced rank | Salesperson | Designation | 90 % rank interval | Chance of top 3 | Chance of bottom 3 | Margin % (90 % interval) |
|---:|---|---|---|---:|---:|---|
| 1 | Tushar Gill (115) | Sales Executive | 1–11 | 48.4 % | 1.6 % | 12.50 (10.67 to 14.66) |
| 2 | Ritu Mishra (109) | Senior Sales Executive | 1–8 | **62.8 %** | 0.2 % | 13.34 (11.96 to 17.29) |
| 3 | Deepak Chatterjee (106) | Key Account Manager | 1–8 | 47.0 % | 0.0 % | 11.17 (10.35 to 11.93) |
| 4 | Deepika Jadhav (108) | Key Account Manager | 1–13 | 35.0 % | 3.0 % | 12.50 |
| 7 | Vikram Gupta (113) | Sales Executive | 1–14 | 28.2 % | 7.4 % | 15.63 (13.51 to 17.50) |
| 13 | Anjali Jadhav (110) | Senior Sales Executive | 6–16 | 0.8 % | 25.6 % | 12.12 |
| 14 | Ananya Bose (101) | Head of Sales | 8–16 | 0.4 % | 45.8 % | 8.52 (7.39 to 10.25) |
| 15 | Arjun Gaikwad (107) | Key Account Manager | 8–16 | 0.0 % | 66.2 % | 10.60 (7.69 to 13.44) |
| 16 | **Tanvi Sandhu (102)** | Regional Sales Manager | **12–16** | 0.0 % | **85.0 %** | **8.29 (6.74 to 9.99)** |

- **The scorecard's number 1, Tushar Gill, could be anywhere from 1st to 11th.** Ritu Mishra is more likely to be in the top three (62.8 %) than he is (48.4 %).
- **Only one result is robust at the bottom.** Tanvi Sandhu is reliably worse than 11 of the other 15 on the balanced rank, and her margin interval (6.74 % to 9.99 %) sits below almost everyone else's. She is the second-largest seller by revenue (rank interval 1–6).
- **No one is reliably better than most.** The best record, Ritu Mishra and Deepak Chatterjee, is reliably better than 4 of 15.

**Some single-metric results are solid.**

- **On-time delivery:** Deepak Chatterjee (89.4 %, rank interval 1–2) and Ritu Mishra (87.3 %, 1–3) are clearly the best; Anjali Jadhav (70.7 %) is last in every replicate.
- **Margin:** Ramesh Patil (16.36 %), Rahul Kapoor (15.55 %), Vikram Gupta (15.63 %) and Harish Tiwari (14.97 %) all have rank intervals inside 1–6; Tanvi Sandhu and Ananya Bose sit in 14–16.
- **Revenue:** Deepak Chatterjee (₹12.77 crore) ranks 1st–5th; Ramesh Patil (₹0.80 crore) 15th–16th.

**Why ranks move: a few customers carry several books.**

| Salesperson | Customers | Largest customer's share of revenue |
|---|---:|---:|
| Harish Tiwari (114) | 56 | **64.0 %** |
| Ritu Mishra (109) | 70 | 53.9 % |
| Rahul Kapoor (111) | 34 | 52.1 % |
| Manoj Verma (105) | 28 | 40.2 % |

Harish Tiwari has the best overdue receivable % (2.36 %), but its 90 % interval is 0.78 % to 10.78 %: it mostly reflects how one customer pays.

## 9. Business implications and recommendations

1. **Do not pay incentives on a 1-to-16 ranking.** Fifteen of sixteen balanced-rank intervals span eight or more places; a ranked payout would reward luck as much as performance.
2. **Use three evidence-based bands instead.** On this data, only Tanvi Sandhu belongs in a "clearly below" band; everyone else is in one middle band. Revisit after another year of data rather than forcing artificial differences.
3. **Drop cancellation rate and overdue receivable % from the individual scorecard,** or measure them at team level. At salesperson level, 92–94 % of pairs cannot be separated on them. Collections are better managed by account, as the [late payment scorecard](../../05_advanced_analytics/15_late_payment_scorecard/) shows: lateness is a segment habit.
4. **Keep revenue, margin and on-time delivery,** and show each with its interval. These are the metrics where differences are real.
5. **Review Tanvi Sandhu's pricing.** A top-two seller with a reliably bottom margin is the one finding that survives resampling; check her discounts against the [discount consistency](../06_discount_consistency/) bands.
6. **Show the largest customer's share next to each person's results.** Where one customer is more than half of a book, the metrics describe that customer more than the salesperson.

## 10. Assumptions and limitations

- **Resampling customers within each salesperson** treats each person's customer book as a sample of the customers they might have served. It measures luck in customer mix and order outcomes, not differences in territory potential.
- **500 replicates.** Interval ends and pair probabilities near the 95 % line can move by a few points with more replicates; the overall conclusions do not.
- **`APPROX_QUANTILES`** is approximate in BigQuery. With 500 values the 5th and 95th percentiles may differ from the figures above by one rank place at most.
- **Same metric definitions as the scorecard**, including its period and the treatment of unassigned orders (excluded). The Head of Sales is ranked, as in the scorecard.
- **Rank-based composite.** The balanced rank adds ranks, so a noisy metric moves it as much as a precise one. A composite of standardised values weighted by precision would be more stable.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Cluster, replicate, interval and pair tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
