# Case Study · Category Breadth and Retention

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 1,121 customer half-years (base halves 2024 H1 – 2025 H2), each followed into the next half-year.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

The [cross-sell white space](../../02_sales_and_profitability/04_cross_sell_white_space/) programme is sold internally on one claim: **customers who buy from more product categories stay longer**. The raw numbers look overwhelming. But customers who buy more categories also buy more often, and frequent buyers stay anyway. Before funding cross-sell targets, the commercial head wants to know whether breadth itself matters once frequency is held constant, and for which customers.

## 2. Business questions

1. How strongly is category breadth linked to retention?
2. Does breadth still matter for customers who buy equally often?
3. For which customers does breadth matter most?
4. Do broader customers also grow more?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Revenue, products |
| `products` | One row per product | Category |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Half-year | January–June (H1) or July–December (H2) |
| Panel | Every customer active in a base half (2024 H1 to 2025 H2), followed into the next half (2024 H2 to 2026 H1). 2026 H2 is incomplete and is not used as an outcome. |
| **Breadth** | Distinct product categories bought in the base half (10 categories exist) |
| **Retained** | Bought again in the following half-year |
| Frequency band | Orders in the base half: 1, 2, 3–4, 5–8, 9+ |
| **Broad / Narrow** | Within a frequency band: breadth above the band's median = Broad; at or below = Narrow |
| **Pooled within-band difference** | Mantel–Haenszel weighted average of (Broad − Narrow) retention, weight = n_broad × n_narrow ÷ (n_broad + n_narrow), with a z-statistic from the weighted binomial variances |
| Next-half revenue % | Revenue in the next half ÷ revenue in the base half |

Comparing customers with the same number of orders removes the main confounder: buying often both widens the basket and keeps a customer active.

## 5. Analytical approach

1. **Panel table** (`sahyadri_b2b.breadth_panel`). One row per customer and base half: categories, orders, revenue, retention, next-half revenue, frequency band and breadth group.
2. **Raw link**: retention by breadth band, and the correlation between breadth and frequency.
3. **Within-band table** (`sahyadri_b2b.breadth_within_band`). Broad against Narrow retention and revenue in each frequency band; the pooled difference and its z-statistic.
4. **One-order customers**: retention by the number of categories in their single order.

## 6. SQL techniques used

- Customer × half-year panel with a self-join to the next period
- Stratification (holding frequency constant) and a Mantel–Haenszel pooled estimate written in SQL
- Band-specific medians with `APPROX_QUANTILES` to define Broad and Narrow fairly in each band
- Validation that recomputes retention, revenue and categories from source by an independent join

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer and half-year |
| 02 | Base revenue = source revenue for the four base halves |
| 03 | **Retained flag = an independent recount** |
| 04 | Next-half revenue = source |
| 05 | Categories = source recount |
| 06 | Frequency band agrees with orders |
| 07 | Broad / Narrow agrees with the band median |
| 08 | Within-band counts add up to the panel |
| 09 | Within-band retention = a panel recount |
| 10 | Base halves are exactly 2024 H1 – 2025 H2 |

## 8. Findings

**The raw link is strong, but most of it is frequency.**

| Categories in the half | Customer half-years | Average orders | Retained next half | Next-half revenue |
|---|---:|---:|---:|---:|
| 1–2 | 276 | 1.3 | 61.6 % | 190.0 % |
| 3–4 | 214 | 2.1 | 80.8 % | 135.8 % |
| 5–6 | 180 | 3.6 | 88.9 % | 150.3 % |
| 7+ | 451 | 11.1 | **97.6 %** | 100.8 % |

- Retention rises from 61.6 % to 97.6 % with breadth, but so does frequency: customers buying 7+ categories place 11.1 orders a half-year, against 1.3 for those buying 1–2. The correlation between breadth and orders is 0.62.

**Holding frequency constant, breadth still helps, but by about 6 points, not 36.**

| Orders in the half | Median categories | Broad | Narrow | Broad retained | Narrow retained | Difference |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 2 | 91 | 205 | 70.3 % | 56.6 % | **+13.7** |
| 2 | 3 | 76 | 105 | 82.9 % | 78.1 % | +4.8 |
| 3–4 | 5 | 112 | 114 | 93.8 % | 89.5 % | +4.3 |
| 5–8 | 8 | 65 | 149 | 96.9 % | 96.6 % | +0.3 |
| 9+ | 10 | 0 | 204 | — | 100.0 % | — |

- **Pooled within-band difference: +6.4 points (z = 2.59)**, across 917 customer half-years in the four comparable bands. Breadth matters on its own, but its true effect is about a sixth of the raw gap.
- **The effect is concentrated in occasional buyers.** For one-order customers, a broader basket goes with 13.7 points better retention. For customers with 5 or more orders, breadth makes no difference: they stay regardless.
- In the 9+ band the median is 10 categories, the maximum possible, so no customer can be Broad; all 204 were retained.

**For one-order customers, broader first baskets are also bigger baskets.**

| Categories in the single order | Customer half-years | Retained next half | Average order value |
|---|---:|---:|---:|
| 1 | 116 | 56.9 % | ₹15,660 |
| 2 | 89 | 56.2 % | ₹46,214 |
| 3 | 45 | 66.7 % | ₹63,605 |
| 4 | 28 | 71.4 % | ₹1.49 lakh |
| 5+ | 18 | 77.8 % | ₹2.91 lakh |

- Retention improves from three categories upwards, but the order value rises with it, so part of this is customer size. The 13.7-point figure should be read as an upper bound.

**Broader customers do not grow faster.** Within every frequency band, Narrow customers' next-half revenue is a larger share of their base (for example 203.3 % against 127.7 % for one-order customers). Narrow customers start smaller and have more room to grow; breadth predicts staying, not growing.

## 9. Business implications and recommendations

1. **Set cross-sell targets for occasional customers, not for key accounts.** Breadth adds about 14 points of retention for one-order customers and about 5 points for two to four orders. Frequent buyers already buy everything and stay.
2. **Use a second category in the first or second order as the onboarding goal.** For new and occasional customers, the [new customer activation](../../01_customer_and_revenue/05_new_customer_activation/) programme can suggest a complementary category from the [market basket](../../02_sales_and_profitability/08_market_basket_affinity/) results.
3. **Report the realistic effect.** When presenting the cross-sell business case, use the within-band +6.4 points, not the raw 36-point gap.
4. **Do not expect cross-sell to drive growth on its own.** Breadth is linked to customers staying, not to them spending more next period.
5. **Test it.** Run a controlled cross-sell offer for a random half of one- and two-order customers and compare retention after six months. That would confirm whether the link is causal.

## 10. Assumptions and limitations

- **Observational.** Holding frequency constant removes the biggest confounder, but not others, such as customer size or industry. For one-order customers, order value rises with breadth.
- **Half-year windows.** A customer who buys once a year can look "lost" in a half-year with no order. Retention rates are therefore lower than in annual studies such as [customer lifetime value](../../01_customer_and_revenue/07_customer_lifetime_value/).
- **Repeated customers.** The same customer appears in up to four base halves; the z-statistic treats them as independent and is somewhat optimistic.
- **Median split.** Broad and Narrow are defined relative to each band's median; a different split would change the sizes but not the direction.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Panel and within-band tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
