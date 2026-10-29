# Case Study · Revenue Driver Tree (LMDI Decomposition)

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Revenue in January–September 2024, 2025 and 2026 split into five drivers for the company and each customer segment, with an exact decomposition of each year's change.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-29 |

---

## 1. Business problem

The board pack shows revenue growth as one number: +10 % in 2025, +39 % in 2026 (January–September). The CEO is preparing next year's plan and wants a driver tree behind those numbers. Did revenue grow because there were more customers, because each customer ordered more often, because orders were larger, or because each unit sold was worth more? And is the pattern the same in every segment and in both years? The [revenue growth bridge](../03_revenue_growth_bridge/) split 2026 growth into customers and order value; this study goes one level deeper and compares two years.

## 2. Business questions

1. Which drivers explain revenue growth in 2025 and in 2026?
2. Does the answer differ by segment?
3. Which drivers are steady enough to plan on, and which swing from year to year?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Lines, units, revenue |
| `customers` | One row per customer | Segment |
| `products` | One row per product | Today's list price (for the mix split) |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Revenue | Net revenue on orders not Cancelled or Returned, January–September of each year |
| **Driver tree** | Revenue = Customers × Orders per customer × Lines per order × Units per line × Revenue per unit |
| Revenue per unit | Revenue ÷ units: a mix of product mix, list price level and discount |
| **LMDI-I decomposition** | Effect of driver x = L(R₁, R₀) × ln(x₁ ÷ x₀), with the logarithmic mean L(a, b) = (a − b) ÷ (ln a − ln b). The five effects add up exactly to R₁ − R₀, with no residual and no order-dependence. |
| Revenue-per-unit split | Product mix = change in today's list value per unit sold; price level = invoice price ÷ today's list; discount = 1 − net ÷ gross |

## 5. Analytical approach

1. **Driver table** (`sahyadri_b2b.dt_drivers`): the five drivers for the company and each segment, per year.
2. **Effects table** (`sahyadri_b2b.dt_effects`): the LMDI decomposition of each year's change, in rupees and as shares.
3. **Driver changes** in percent, and the split of revenue per unit into product mix, price level and discount.

## 6. SQL techniques used

- A multiplicative KPI tree computed from distinct counts and sums, for every scope at once with `UNION ALL`
- Logarithmic mean Divisia index (LMDI) decomposition in SQL: exact, additive and symmetric
- Year-on-year pairs with a self-join on `yr + 1`
- Validation of the identity (revenue = product of drivers) and of exact additivity of the effects

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Company revenue per year = source |
| 02 | Segment revenues add up to the company |
| 03 | **Revenue = the product of the five drivers** |
| 04 | **LMDI effects add up exactly to the change** |
| 05 | Customers and orders per year = source recount |
| 06 | Lines and units per year = source recount |
| 07 | Segment customers and orders add up to the company |
| 08 | Every effect has the sign of its driver change |
| 09 | Two periods for each of the five scopes |
| 10 | Revenue per unit = independent source recount |

## 8. Findings

**The drivers (January–September)**

| Year | Revenue | Customers | Orders per customer | Lines per order | Units per line | Revenue per unit |
|---|---:|---:|---:|---:|---:|---:|
| 2024 | ₹20.43 crore | 288 | 7.23 | 2.80 | 18.42 | ₹1,904.5 |
| 2025 | ₹22.52 crore | 322 | 7.78 | 2.82 | 17.16 | ₹1,858.9 |
| 2026 | ₹31.22 crore | 353 | 8.35 | 2.82 | 17.83 | ₹2,103.4 |

**Where each year's growth came from (₹ lakh)**

| Period | Growth | Customers | Orders per customer | Lines per order | Units per line | Revenue per unit |
|---|---:|---:|---:|---:|---:|---:|
| 2024 → 2025 | +₹209 lakh (+10.2 %) | **+239.4** | **+156.6** | +16.0 | **−151.0** | **−52.0** |
| 2025 → 2026 | +₹870 lakh (+38.7 %) | **+244.8** | **+189.9** | +5.7 | +101.1 | **+329.1** |

**Two engines: a steady one and a swinging one.**

- **The steady engine is customers × frequency.** Customers grew 11.8 % and 9.6 %, orders per customer 7.6 % and 7.4 %. Together they added about ₹4 crore in each year, almost the same amount.
- **Order size does not move.** Lines per order stayed at 2.8 in all three years.
- **The swinging engine is basket value.** Units per line fell 6.8 % in 2025 and rose 3.9 % in 2026; revenue per unit fell 2.4 %, then rose 13.2 %. In 2025 they took away ₹203 lakh, more than the whole gain from order frequency; in 2026 they added ₹430 lakh, half the year's growth.

**Revenue per unit is driven by product mix, not price.**

| Year | Revenue per unit change | Product mix | List price level | Discount |
|---|---:|---:|---:|---:|
| 2025 | −2.4 % | **−8.1 %** | +5.4 % | 8.39 % |
| 2026 | +13.2 % | **+8.0 %** | +5.4 % | 8.91 % |

The January price increases added 5.4 % in both years (see [price increase and price discipline](../../02_sales_and_profitability/12_price_increase_and_price_discipline/)). The swing came from what was sold: cheaper items in 2025, more pumps and motors in 2026 (see [price-volume-mix](../../02_sales_and_profitability/03_price_volume_mix/)).

**By segment (percentage change of each driver)**

| Segment | Period | Customers | Orders per customer | Lines per order | Units per line | Revenue per unit | Revenue |
|---|---|---:|---:|---:|---:|---:|---:|
| Distributor | 2025 → 2026 | +7.0 % | +8.1 % | −1.8 % | +5.8 % | **+18.2 %** | +42.1 % |
| Enterprise | 2024 → 2025 | +9.4 % | +8.4 % | −0.8 % | **−12.2 %** | −1.9 % | **+1.3 %** |
| Enterprise | 2025 → 2026 | +5.2 % | +10.8 % | +1.2 % | +3.8 % | +7.8 % | +31.9 % |
| Mid-Market | 2025 → 2026 | **+18.1 %** | +4.9 % | +2.8 % | +4.1 % | +18.6 % | **+57.2 %** |
| SMB | 2024 → 2025 | +14.8 % | +3.6 % | −2.0 % | +8.8 % | **−21.8 %** | −0.9 % |
| SMB | 2025 → 2026 | +7.3 % | +6.6 % | −1.3 % | +4.5 % | −1.4 % | +16.2 % |

- **Enterprise's flat 2025 was a basket problem, not a relationship problem.** More customers ordering more often, but 12.2 % fewer units per line.
- **SMB keeps adding customers without adding revenue per unit**: revenue per unit fell 21.8 % in 2025 and did not recover.
- **Mid-Market is the only segment where new customers lead** (+18.1 % in 2026).

## 9. Business implications and recommendations

1. **Plan on the steady engine.** Customers × frequency has added about ₹4 crore a year in both years (roughly +18–20 %). Use it as the base case for next year.
2. **Plan basket value as a range, not a point.** Revenue per unit has swung by ±10 % depending on product mix; plan it as a scenario (flat, +5 % price only, mix-driven upside).
3. **Treat order size as a lever nobody is pulling.** Lines per order has not moved from 2.8 in three years. Cross-sell prompts at order entry (see [cross-sell stickiness](../13_cross_sell_stickiness/) and the [best-seller gap list](../../05_advanced_analytics/16_collaborative_filtering_recommender/)) target exactly this driver.
4. **Report the driver tree each quarter by segment.** It would have shown in 2025 that Enterprise's slowdown was smaller baskets, not lost customers, and pointed account managers at the right fix.
5. **Look at SMB pricing and mix.** Revenue per unit in SMB fell a fifth in 2025 while customer numbers rose.

## 10. Assumptions and limitations

- **January–September windows** make years comparable with the latest data; the full-year picture includes the October–December peak.
- **Customers counted per segment** as recorded; a customer that changed segment would move between rows.
- **Revenue per unit** adds units of very different products (a bolt and a pump count the same), which is why it is split into mix and price.
- **LMDI is a decomposition, not causation.** It shows which arithmetic driver moved, not why.
- **Today's list price** is used as the mix weight for all years.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Driver and effects tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
