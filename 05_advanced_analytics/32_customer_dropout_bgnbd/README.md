# Case Study · Are Silent Customers Lost? A "Buy Till You Die" Test of Customer Dropout

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study fits the BG/NBD customer-base model to 412 customers' order histories up to 30 June 2026, entirely in SQL by grid search. It tests whether any customers drop out for good, and checks the model's predictions on July – September 2026. It also tests whether customers flagged as "silent" actually come back.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-07 |

---

## 1. Business problem

The [churn early-warning](../../01_customer_and_revenue/02_customer_churn_early_warning/) report flags any customer silent for more than twice their usual ordering gap, and sales spends a day a month calling them. The sales head suspects most of them were never leaving. The analytics lead proposes the standard model for customers who can leave without telling anyone, BG/NBD ("buy till you die"). Each customer orders at their own random rate, and after any order may drop out for good. If customers really drop out, the model will find it.

## 2. Business questions

1. Is there any evidence that customers drop out for good, or do they just order at random intervals?
2. How well does the fitted model predict who orders next quarter, and how many orders, against a naive run-rate?
3. Do customers flagged as silent actually come back?
4. Which customers should sales call instead?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Revenue for the call list |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Purchase | A distinct order day per customer, valid orders (not Cancelled or Returned) |
| Calibration / holdout | From each customer's first order to 30 June 2026 / July – September 2026 (92 days = 13.1 weeks) |
| x, t_x, T | Repeat purchases; week of the last purchase after the first; weeks from the first purchase to 30 June 2026 |
| **BG/NBD log-likelihood** | Fader, Hardie and Lee (2005), written without gamma functions: Γ(r + x)/Γ(r) = Π(r + k) and B(a, b + x)/B(a, b) = Π(b + k)/(a + b + k), k = 0 … x − 1. The sums over k use n_k = customers with x > k. The dropout term is computed by log-sum-exp to avoid overflow. |
| **Mean dropout chance** | m = a ÷ (a + b): the average chance a customer leaves for good after any purchase |
| **Profile likelihood** | m held at 0.05 % – 5 %, with a, r and α chosen by grid search, against m = 0: no dropout, the NBD model |
| NBD predictions (t weeks) | Expected purchases = (r + x) ÷ (α + T) × t; P(at least one) = 1 − ((α + T) ÷ (α + T + t))^(r + x) |
| Naive run-rate | x ÷ T × t |
| **Silent** | At least 3 repeat purchases and T − t_x above twice the average gap t_x ÷ x: the early-warning rule |

## 5. Analytical approach

1. **Purchase histories** (`sahyadri_b2b.bt_customers`) and repeat-purchase counts (`bt_kcounts`).
2. **Fits**: the NBD by a coarse-then-fine grid (`bt_nbd_grid`, `bt_nbd`), and the BG/NBD profile over dropout levels (`bt_profile`).
3. **Holdout** predictions (`bt_predictions`) against what happened, overall and by predicted chance.
4. **Silent customers** in the holdout, and a call list as of 30 September 2026.

## 6. SQL techniques used

- Maximum likelihood by grid search in SQL: two-stage grids from `GENERATE_ARRAY`, with each likelihood an aggregate over a grid × customers join
- Gamma and beta function ratios replaced by sums of logs over a `GENERATE_ARRAY` of k, collapsed with n_k counts
- Numerically stable log-sum-exp: `GREATEST(c, 0) + LN(1 + EXP(-ABS(c)))`
- `ARRAY_AGG(STRUCT(...) ORDER BY ll DESC LIMIT 1)` to keep the best fit per dropout level

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Customers and repeat purchases = recount of distinct order days |
| 02 | Holdout purchases = recount |
| 03 | Σ n_k = total repeat purchases (the shortcut identity) |
| 04 | NBD grid: 266 coarse + 441 fine points; the fitted point has the highest likelihood |
| 05 | **NBD log-likelihood = direct recount per customer**, without the n_k shortcut |
| 06 | BG/NBD profile: 7 dropout levels × 4 values of a × 266 points, all below the NBD fit |
| 07 | **BG/NBD log-likelihood at a grid point = direct recount per customer** |
| 08 | Predictions follow the NBD formulas; chances between 0 and 1 |
| 09 | Silent = 3+ repeat purchases and silence above twice the usual gap |
| 10 | Holdout is 92 days; every customer observed before it is predicted once |

## 8. Findings

**The model finds no customers leaving for good.**

| Customers | One purchase only | Average repeat purchases | Most | Average weeks observed |
|---:|---:|---:|---:|---:|
| 412 | 70 | 18.4 | 255 | 99.3 |

| Model | Mean dropout per purchase | a | r | α | Log-likelihood | Below no dropout |
|---|---:|---:|---:|---:|---:|---:|
| **No dropout (NBD)** | **0** | – | 0.65 | 3.9 | **−16,085.4** | – |
| BG/NBD | 0.05 % | 0.5 | 0.60 | 3.5 | −16,088.5 | 3.2 |
| BG/NBD | 0.1 % | 0.5 | 0.60 | 3.5 | −16,090.9 | 5.6 |
| BG/NBD | 0.2 % | 0.5 | 0.70 | 4.0 | −16,095.3 | 10.0 |
| BG/NBD | 0.5 % | 0.5 | 0.70 | 4.0 | −16,107.0 | 21.6 |
| BG/NBD | 1 % | 0.5 | 0.70 | 4.0 | −16,123.2 | 37.8 |
| BG/NBD | 2 % | 0.5 | 0.70 | 4.0 | −16,149.0 | 63.6 |
| BG/NBD | 5 % | 0.5 | 0.70 | 4.0 | −16,203.8 | 118.4 |

- The fit gets steadily worse as dropout is allowed. Even a 1-in-2,000 chance of leaving after each order fits worse than none.
- The order histories are what random ordering at a customer's own steady rate looks like: long silences happen, then the customer orders again. Rates vary a lot between customers (r = 0.65), with the average customer ordering on about one day in six weeks.

**The no-dropout model predicts the next quarter well in total, though not customer by customer.**

| July – September 2026 | Actual | NBD | Naive run-rate |
|---|---:|---:|---:|
| Purchases | 899 | 903.3 | 886.8 |
| Customers who bought | 251 | 252.1 | – |
| Mean absolute error per customer | – | 1.011 | **0.957** |

| Predicted chance of buying | Customers | Predicted | Actual | Predicted purchases | Actual purchases |
|---|---:|---:|---:|---:|---:|
| Below 25 % | 73 | 13.7 % | 8.2 % | 12.1 | 7 |
| 25 – 50 % | 85 | 39.2 % | 41.2 % | 47.6 | 51 |
| 50 – 75 % | 86 | 63.8 % | 61.6 % | 99.5 | 84 |
| 75 – 95 % | 88 | 86.3 % | 88.6 % | 199.5 | 208 |
| 95 % and above | 79 | 98.7 % | 100.0 % | 544.7 | 549 |

The predicted chance of buying is well calibrated: in every band the share who bought is within 6 points of the prediction. Customer by customer, a simple run-rate is as good (mean absolute error 0.957 against 1.011).

**Silent customers came back at exactly the same rate as everyone else.** Customers with 3+ repeat purchases, status on 30 June 2026:

| Status | Customers | Ordered July – September | Share | NBD expected buyers | Purchases | NBD expected |
|---|---:|---:|---:|---:|---:|---:|
| **Silent** (over twice their usual gap) | 48 | **37** | **77.1 %** | 32.2 | 105 | 99.3 |
| Not silent | 259 | 200 | **77.2 %** | 196.6 | 775 | 763.6 |

The silence flag carried no information about whether a customer would order next. Silent customers even ordered slightly more than the model expected (37 against 32.2).

**Whom to call instead: big customers who order rarely.** As of 30 September 2026, customers with ₹10 lakh or more in the last 12 months and the lowest chance of ordering in the next 13 weeks:

| Customer | Segment | Revenue, 12 months | Weeks since last order | Usual gap | Chance of an order in 13 weeks |
|---|---|---:|---:|---:|---:|
| Chettiar Trading Co. | Distributor | ₹14.2 lakh | 2.6 | 9.8 weeks | 72 % |
| Mittal Traders | Distributor | ₹10.0 lakh | 9.1 | 8.1 weeks | 77 % |
| Kohinoor Reddy Industrial Suppliers | Distributor | ₹13.7 lakh | 7.1 | 7.9 weeks | 78 % |
| Krishna Enterprises | Distributor | ₹15.3 lakh | 13.9 | 6.6 weeks | 81 % |
| Laxmi Petrochem Ltd | Enterprise | ₹25.0 lakh | 11.7 | 6.7 weeks | 82 % |
| Tirupati Infrastructure | Mid-Market | ₹14.8 lakh | 14.0 | 6.5 weeks | 82 % |

Under a no-dropout model, the chance of ordering depends on how often a customer buys, not on how long it has been quiet. The list is therefore about infrequent buyers, where one more order matters most.

## 9. Business implications and recommendations

1. **Stop treating silence as churn.** In this customer base, a customer silent for twice their usual gap is as likely to order next quarter as any other (77 %). The monthly silent-customer calls can be dropped or repurposed.
2. **Keep the churn report, but measure churn over a longer horizon.** Customers do stop eventually (the [net revenue retention](../../01_customer_and_revenue/11_net_revenue_retention/) study counts lost logos). But at a quarter's horizon, dropout cannot be told apart from a long gap.
3. **Use the predicted chance of buying for planning, not single-account calls.** It is well calibrated in total (252 predicted buyers against 251), so it suits capacity and revenue planning. For any one customer a run-rate is just as good.
4. **Call infrequent large buyers before their expected order, not after.** Combine the model's chance of an order with value, as in the list above, and pair it with [reorder reminders](../06_reorder_reminders/).
5. **Re-test once a year.** If dropout appears (the profile likelihood peaks above zero), switch the report to BG/NBD's chance-of-being-active.

## 10. Assumptions and limitations

- **History starts in January 2024.** A customer's "first purchase" is its first in the data, not its first ever, which shortens T for long-standing customers.
- **Purchases are order days.** Several orders on one day count once; order value is not modelled (a Gamma-Gamma spend model would add it).
- **Grid search, not a continuous optimiser.** The NBD fit (r = 0.65, α = 3.9) matches a numerical optimiser run outside SQL during the analysis. The BG/NBD grid only needs to show the direction: allowing more dropout makes the fit worse.
- **One holdout quarter.** The calibration and silent-customer results come from 92 days; a longer holdout would show slower dropout if it exists.
- **The model assumes steady rates.** A customer whose rate falls slowly (rather than stopping) is not captured by either model; see [customer momentum](../10_customer_momentum/).

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer, count, grid, profile and prediction tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
