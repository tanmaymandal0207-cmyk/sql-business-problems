# Case Study · Logistic Regression Churn Model, Trained in SQL

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. A six-feature logistic regression fitted by gradient descent in a BigQuery `WHILE` loop on 972 customer snapshots (three quarter-ends), tested on 340 customers at 30 Sep 2025 and used to score 367 customers at 30 Sep 2026.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script with a `WHILE` loop — run it as one script; 600 iterations take several minutes) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-28 |

---

## 1. Business problem

The [customer health score](../../01_customer_and_revenue/12_customer_health_score/) study replaced a seven-signal score with a simple activity score: the average percentile of recency, order frequency and category breadth. The CRM team now asks whether a properly fitted statistical model would do better, and whether it can be built where the data lives, without exporting data to another tool. They also want to know whether its probabilities can be used to forecast how many customers will be lost next year.

## 2. Business questions

1. Can a logistic regression be trained inside the warehouse?
2. Which signals carry weight once they are fitted together?
3. Does the fitted model rank churners better than the activity score on a period it has not seen?
4. Are its probabilities trustworthy enough to forecast customer losses?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Revenue |
| `products` | One row per product | Category |
| `customers` | One row per customer | Names, segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Population | Customers with an order (not Cancelled or Returned) in the 12 months before a snapshot |
| **Churned** | No such order in the 12 months after the snapshot |
| Samples | Train: 31 Dec 2024, 31 Mar 2025, 30 Jun 2025. Test: 30 Sep 2025. Score: 30 Sep 2026. |
| Features | x1 ln(1 + days since last order) · x2 ln(orders) · x3 categories bought · x4 share of revenue in the last 6 months · x5 ln(revenue) · x6 share of orders cancelled or returned — all over the 12 months before the snapshot, standardised with the training mean and standard deviation |
| **Logistic regression** | P(churn) = 1 ÷ (1 + e^−(b₀ + Σ bⱼxⱼ)) |
| **Gradient descent** | bⱼ ← bⱼ − 2.0 × average((p − y) × xⱼ), 600 iterations, each one an `INSERT` inside a `WHILE` loop |
| Odds ratio per s.d. | e^bⱼ: how the odds of churn change when a feature rises by one standard deviation, others held constant |
| Activity score | Average `PERCENT_RANK` of recency (reversed), orders and categories within each snapshot |
| AUC | Probability that a retained customer is scored as healthier than a churned one (Mann–Whitney, average ranks) |
| Calibration | Predicted churners (Σ p) against actual churners, overall and by risk band |

## 5. Analytical approach

1. **Feature table** (`sahyadri_b2b.lr_features`), **scaling** (`sahyadri_b2b.lr_scaling`) and **design matrix** (`sahyadri_b2b.lr_design`).
2. **Training loop**: a coefficient table (`sahyadri_b2b.lr_coefficients`) with one row per iteration and its training log-loss; final coefficients and odds ratios.
3. **Scores** (`sahyadri_b2b.lr_scores`) and **AUC** (`sahyadri_b2b.lr_auc`) for the model, the activity score and recency alone; capture in the riskiest fifth.
4. **Calibration** by risk band and by order count; the forecast for the coming year and the highest-value customers at risk.

## 6. SQL techniques used

- A machine-learning model trained in BigQuery scripting: `DECLARE`, `WHILE … DO … END WHILE`, and `INSERT … WITH … SELECT` writing one row of coefficients per iteration
- Vectorised gradient: one `AVG((p − y) × xⱼ)` per coefficient over the whole training set
- Feature standardisation stored in a one-row scaling table and applied to every sample
- Point-in-time features and outcomes for several snapshots in one query
- Validation that proves convergence (gradient below 0.0001), recomputes the log-loss and checks AUC by brute-force pair counting

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per active customer per snapshot |
| 02 | Churn label = no valid order in the next 12 months (independent recount) |
| 03 | Training features standardised (mean 0, standard deviation 1) |
| 04 | One coefficient row per iteration, 0 to 600 |
| 05 | Log-loss never rises over the last 500 iterations |
| 06 | **Converged: every gradient component below 0.0001** |
| 07 | Predicted churners = actual churners on training data (a property of the fitted intercept) |
| 08 | Final log-loss = a recount from the fitted probabilities |
| 09 | **Test AUC of the model = a brute-force pair count** |
| 10 | Test AUC of the activity score = a brute-force pair count |

## 8. Findings

**The model trains in the warehouse and converges.**

| Iteration | 0 | 1 | 10 | 50 | 100 | 300 | 600 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Training log-loss | 0.6931 | 0.4377 | 0.2762 | 0.2578 | 0.2553 | 0.2545 | **0.2545** |

**Once fitted together, one signal does almost all the work: how many orders the customer placed.**

| Feature | Coefficient | Odds ratio per s.d. |
|---|---:|---:|
| Orders (log) | **−2.121** | **0.12** |
| Share of orders cancelled | −0.175 | 0.84 |
| Categories bought | −0.093 | 0.91 |
| Share of revenue in last 6 months | −0.074 | 0.93 |
| Days since last order (log) | −0.039 | 0.96 |
| Revenue (log) | −0.034 | 0.97 |
| Intercept | −3.362 | |

- Recency, breadth and revenue matter on their own but add almost nothing once order count is known, because customers who order often are also recent and broad.
- The cancellation share has a small protective sign: customers who cancel are active customers, as the [health score](../../01_customer_and_revenue/12_customer_health_score/) study also found.

**On the unseen test period, the model and the activity score rank churners equally well, but the model concentrates them better.**

| Model | Train AUC | Test AUC |
|---|---:|---:|
| **Logistic regression (6 features)** | 0.877 | **0.932** |
| Activity score (3 percentiles) | 0.861 | 0.926 |
| Recency only | 0.758 | 0.804 |

| Test snapshot (340 customers, 43 churners) | Logistic regression | Activity score |
|---|---:|---:|
| Churners in the riskiest fifth (68 customers) | **37 (86.0 %)** | 33 (76.7 %) |

**Its probabilities matched the training years exactly, but the test year was worse.**

| Orders in last 12 months | Train: actual | Train: predicted | Test: actual | Test: predicted |
|---|---:|---:|---:|---:|
| 1 | 44.2 % | 43.4 % | **64.3 %** | 44.2 % |
| 2 | 12.0 % | 16.5 % | 7.9 % | 16.6 % |
| 3 | 10.9 % | 8.2 % | 7.5 % | 8.2 % |
| 4 | 4.5 % | 4.6 % | 4.0 % | 4.8 % |
| 5+ | 1.4 % | 1.1 % | 0.0 % | 1.1 % |

- The model predicted 37.5 churners in the test year; 43 churned (13 % more). The shortfall comes from single-order customers: 64 % of them left in the test year against 44 % in the training years, about 11 more churners than predicted, partly offset by fewer losses among regular buyers.
- **For 30 Sep 2026 the model predicts 40.5 of 367 active customers will be lost in the coming year.** Given the test-year shortfall, the realistic range is higher.
- No customer today is above 50 % risk. The highest-revenue customers at 30 %+ risk are all single-order accounts, led by Pioneer Agencies (₹8.9 lakh, 302 days since its only order) and Tirupati Ghosh Traders (₹4.3 lakh).

## 9. Business implications and recommendations

1. **Use the fitted model for the retention call list.** It catches 37 of 43 future churners in its riskiest fifth against 33 for the activity score, at no extra data cost, and it runs inside BigQuery.
2. **Keep the activity score for dashboards.** Its ranking is almost as good (AUC 0.926 against 0.932) and is easier to explain to account managers.
3. **Focus on converting single-order customers.** They are the churn problem: 44–64 % of them leave within a year, against at most 12 % of everyone else. A second order within the first months is the strongest retention lever (see [new customer activation](../../01_customer_and_revenue/05_new_customer_activation/)).
4. **Refit every quarter and treat the forecast as a floor.** Churn among single-order customers rose sharply in the test year; a model fitted on older quarters under-forecast losses by 13 %.
5. **Do not add more signals for now.** Five of the six features add little beyond order count; extra signals would add complexity without accuracy.

## 10. Assumptions and limitations

- **Gradient descent, not exact maximum likelihood.** The fit is stopped at 600 iterations; validation shows the gradient is below 0.0001, so the coefficients are within rounding of the exact solution.
- **Overlapping training snapshots.** The same customer appears in up to three training snapshots; this does not bias the coefficients but makes standard errors (not reported) too small.
- **Linear in the features.** Interactions and thresholds (for example a separate effect for exactly one order) are not modelled; the order-count table shows where that matters.
- **Churn as 12 months without an order** suits a B2B distributor with irregular ordering; a shorter window would label more seasonal buyers as churned.
- **Runtime.** Each iteration is a separate query; in BigQuery the loop takes several minutes. Reducing to 300 iterations changes the coefficients only in the second decimal.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Feature, scaling, design, coefficient, score and AUC tables; the training loop; 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
