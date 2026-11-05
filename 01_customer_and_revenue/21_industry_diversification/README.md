# Case Study · Industry Diversification: Which Verticals Steady Revenue and Which Make It Swing?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study uses 33 months of revenue (January 2024 – September 2026) for 15 customer industries. It measures how far the industries' swings cancel out, tests that against 500 shuffles that make them independent, and splits the company's monthly swing into each industry's contribution. It ends by testing which industry would steady revenue most if growth came from it.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-05 |

---

## 1. Business problem

The board wants steadier monthly revenue for the working-capital plan. One director argues that the company depends too much on Industrial Distribution and should "diversify into more industries". Another says the industries all move together, so diversifying would not help. The commercial director wants data on how the verticals actually behave before the sales plan sets targets by industry.

## 2. Business questions

1. Do the industries' monthly revenues move together, or do their swings cancel out?
2. How much of the monthly swing does each industry cause, against its share of revenue?
3. What makes an industry volatile?
4. If steadiness matters, which industries should growth come from?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order month, status |
| `sales_order_items` | One row per product per order | Revenue |
| `customers` | One row per customer | Industry |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Revenue | Valid orders (not Cancelled or Returned), monthly by customer industry; no industry recorded = "Unknown" |
| **Swing** | An industry's monthly revenue minus its own straight-line trend (least squares). Company swing = the sum of industry swings. |
| **Risk share** | Cov(industry swing, company swing) ÷ Var(company swing). Shares add up to 100 %; a negative share means the industry offsets the rest. |
| Risk per revenue | Risk share ÷ revenue share: above 1 = more volatile than its size |
| **Diversification ratio** | Sum of the industries' swing standard deviations ÷ the company's. 1 = all move together; higher = swings cancel. |
| **Independence test** | 500 shuffles that move each industry's swings to random months (March kept among March months). If industries are independent, the company swing looks like the shuffled ones. |
| Swing CV | An industry's swing standard deviation ÷ its average monthly revenue |
| Growth scenario | ₹1 crore a year of extra revenue from one industry, with that industry's monthly pattern scaled up; change in the company's swing CV |

## 5. Analytical approach

1. **Industry months** (`sahyadri_b2b.id_months`): revenue, trend and swing for every industry and month.
2. **Company months** (`sahyadri_b2b.id_company`) and the **independence test** (`sahyadri_b2b.id_shuffles`); correlations between industries.
3. **Contributions** (`sahyadri_b2b.id_contribution`): revenue share, risk share and concentration by industry.
4. **Drivers of volatility** and the **growth scenarios**.

## 6. SQL techniques used

- Least-squares trends per group with `COVAR_POP ÷ VAR_POP`, and residuals as the measure of swing
- Portfolio risk decomposition: each part's covariance with the total, which adds up exactly to the total variance
- A block permutation test: an integer hash shuffles months within each industry (and within March), destroying co-movement but keeping each industry's own volatility
- A self-join on month for all industry pairs' correlations

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per industry per month; revenue = source |
| 02 | Swings around each trend sum to zero and are uncorrelated with time |
| 03 | Company revenue and swing = the sum over industries |
| 04 | **Risk shares add up to 100 %, with and without March** |
| 05 | Revenue shares add up to 100 % |
| 06 | 500 rearrangements, each with a positive company standard deviation |
| 07 | The sum of industry standard deviations exceeds the company's |
| 08 | Industry pairs = n(n − 1) ÷ 2 |
| 09 | Exactly three March months |
| 10 | **Risk share = covariance ÷ variance, recounted** |

## 8. Findings

**The industries' swings cancel out: diversification already halves the volatility.**

| | Value |
|---|---:|
| Average monthly revenue | ₹276.5 lakh |
| Sum of the 15 industries' swing standard deviations | ₹142.1 lakh |
| Company swing standard deviation | **₹67.9 lakh** |
| Diversification ratio | **2.09** |
| Company swing if industries were independent (500 shuffles) | ₹67.3 lakh |
| Shuffles at least as volatile as the real company | 38.8 % |

- The real company is no more volatile than it would be if the industries moved independently. The average correlation between two industries' swings is 0.11, and 0.03 outside March. Only 2 of 105 pairs exceed 0.5.
- Without the March months, the company swing (₹44.3 lakh) is slightly higher than the independent benchmark (₹39.6 lakh), but 12.4 % of shuffles are as high. There is no clear sign of industries moving together beyond the year-end peak.

**Steel & Metals and "Unknown" add more swing than their size; General Engineering steadies revenue.**

| Industry | Customers | Revenue share | Risk share | Risk per revenue | Top customer's share of the industry |
|---|---:|---:|---:|---:|---:|
| Industrial Distribution | 66 | **36.6 %** | 33.5 % | 0.92 | 20.4 % |
| Unknown (no industry recorded) | 16 | 4.1 % | **18.1 %** | **4.39** | 66.8 % |
| Steel & Metals | 39 | 9.8 % | 13.0 % | 1.33 | 55.6 % |
| Textiles | 32 | 6.7 % | 7.0 % | 1.05 | 54.6 % |
| Packaging | 20 | 4.7 % | 5.5 % | 1.16 | 33.0 % |
| Chemicals | 24 | 5.8 % | 4.3 % | 0.75 | 44.3 % |
| General Engineering | 49 | 11.6 % | **3.6 %** | **0.31** | 17.0 % |
| Construction | 25 | 2.8 % | 1.2 % | 0.41 | 23.6 % |
| Pharmaceuticals | 18 | 1.6 % | **−0.6 %** | −0.34 | 24.0 % |
| *Six others* | 137 | 16.5 % | 14.5 % | 0.68–1.19 | |

- **Industrial Distribution is not over-risky.** It contributes risk in line with its size (0.92). Its swings are, however, the main source of volatility outside March (55.6 % of the non-March swing).
- **The "Unknown" group is the riskiest per rupee.** One customer makes up two-thirds of its revenue, and its swing falls almost entirely in March (−2.0 % of the non-March swing). Recording the industry for these 16 customers would show where that risk really sits.
- **General Engineering is the steadiest large industry.** It has 11.6 % of revenue but only 3.6 % of the swing, because its swings are uncorrelated with the rest of the company (correlation −0.00). Pharmaceuticals moves slightly against the rest.

**Volatility comes from concentration, not from the industry itself.**

| Industry swing CV against | Correlation |
|---|---:|
| Top customer's share of the industry | **+0.61** |
| Number of customers | −0.44 |
| Industry size | −0.30 |

Industries where one customer dominates swing more. Steel & Metals (top customer 55.6 %) and Textiles (54.6 %) are lumpy because of single accounts.

**Where an extra ₹1 crore a year of growth would steady revenue most**

| Growth from | Company swing CV (today 24.56 %) |
|---|---:|
| Pharmaceuticals | **23.67 %** (−0.88 points) |
| General Engineering | 24.08 % (−0.47) |
| Construction | 24.18 % (−0.37) |
| Industrial Distribution | 24.49 % (−0.05) |
| Steel & Metals | 24.84 % (+0.29) |

## 9. Business implications and recommendations

1. **Tell the board that diversification is already working.** Industries move almost independently, which halves the monthly swing. Adding more industries for their own sake will not change much.
2. **Grow General Engineering, Construction and Pharmaceuticals for steadiness.** Their revenue moves independently of, or against, the rest. None of them depends on one customer (the largest has 17–24 % of each).
3. **Grow by customers, not by single accounts.** Volatility follows concentration. A new industry won through one large account adds swing; the same revenue spread over ten customers does not.
4. **Record the industry of the 16 "Unknown" customers.** They are 4 % of revenue but 18 % of the swing, led by one large account.
5. **Plan March separately.** Most of the company's swing is the year-end peak shared by every industry (see [March peak](../19_march_peak_drivers/)); diversification cannot remove it.

## 10. Assumptions and limitations

- **33 months.** Correlations between industries rest on 33 points each and are noisy individually; the pooled tests are more reliable.
- **A straight-line trend per industry.** Growth that speeds up or slows down shows up as swing.
- **Revenue by order date.** Booked revenue, not delivery or cash.
- **Growth scenarios scale an industry's existing pattern;** new customers in that industry may behave differently.
- **Industry as recorded** in the customer master; 16 customers with orders have none.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Industry-month, company, shuffle and contribution tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
