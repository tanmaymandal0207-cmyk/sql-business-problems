# Case Study · Price-Volume-Mix Analysis

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Like-for-like comparison: January–September 2026 vs January–September 2025.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-20 |

---

## 1. Business problem

Revenue for January–September grew 38.7 %. The [Revenue growth bridge](../../01_customer_and_revenue/03_revenue_growth_bridge/) showed that growth came from existing customers and bigger orders. It could not say whether "bigger" means customers bought **more units** or paid **higher prices**. Finance needs that split for next year's budget:

- price increases can be planned and repeated;
- volume growth needs supply capacity and stock;
- a shift in mix towards expensive products changes margin and working capital.

## 2. Business questions

1. How much of the revenue change came from price, from volume and from product mix?
2. How much came from products sold in only one of the two periods?
3. By how much did realised prices rise, overall and by category?
4. Which products drove the volume gains and losses?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Quantity and revenue |
| `sales_orders` | One row per order | Order date and status |
| `products`, `product_categories` | One row per product / category | Product and category names |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)` on orders not Cancelled or Returned |
| Realised price | Revenue ÷ quantity, per product and period (after discount) |
| Continuing product | Sold in both periods |
| **Price effect** | Σ (price CY − price PY) × quantity CY |
| **Quantity effect** | Σ (quantity CY − quantity PY) × price PY |
| **Volume effect** | (total units CY − total units PY) × average price PY |
| **Mix effect** | Quantity effect − volume effect: the gain from selling relatively more of the higher-priced products |
| New / discontinued | CY revenue of products not sold in PY / − PY revenue of products not sold in CY |
| Category price change | Σ (price CY × qty CY) ÷ Σ (price PY × qty CY) − 1, which compares prices on the same basket |

Price + volume + mix + new + discontinued = total revenue change, exactly (validation check 06).

## 5. Analytical approach

1. **Product table** (`sahyadri_b2b.product_price_volume`). PY and CY quantity, revenue, realised price, status, and price and quantity effects for each product.
2. **Revenue bridge** from PY to CY through price, volume, mix, new and discontinued products.
3. **Price and volume change by category**, plus a company total.
4. **Products with the largest volume gains and losses.**

## 6. SQL techniques used

- Period labelling and pivoting with `SUM(IF(period = …))`
- Per-product effects with `SAFE_DIVIDE` for realised prices
- A standard price-volume-mix decomposition built from the product-level effects
- A fixed-basket price index (CY quantities as weights) so mix does not distort the price change
- `UNION ALL` of parenthesised `ORDER BY … LIMIT` queries for top and bottom lists

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per product |
| 02 | Every product sold in either period is included (186) |
| 03 | PY revenue = source, to the paisa |
| 04 | CY revenue = source, to the paisa |
| 05 | Quantity = source |
| 06 | Price + volume + mix + new + discontinued = total change, to the paisa |
| 07 | For every continuing product, price effect + quantity effect = its revenue change |
| 08 | Product status agrees with the quantities |
| 09 | Every product with quantity has a realised price |
| 10 | Category effects add up to the total |

## 8. Findings

**Of the ₹8.71 crore growth, only 16 % came from price. The rest came from selling more, and from selling more expensive products.**

| Bridge | Amount | Share of growth |
|---|---:|---:|
| Revenue Jan–Sep 2025 | ₹22.52 crore | |
| + Price | +₹1.36 crore | 15.6 % |
| + Volume | +₹5.08 crore | 58.3 % |
| + Mix | +₹2.27 crore | 26.1 % |
| + New / − discontinued products | – | – |
| **Revenue Jan–Sep 2026** | **₹31.22 crore** | |

All 186 products sold in 2025 were also sold in 2026, so there is no new or discontinued product effect.

**Realised prices rose 4.6 % on a like-for-like basket.** Total units rose 22.5 %.

| Category | Price change | Unit volume change |
|---|---:|---:|
| Hydraulic Components | +5.6 % | +40.2 % |
| Electric Motors & Drives | +5.5 % | +15.6 % |
| Valves & Fittings | +5.4 % | +20.7 % |
| … | | |
| Bearings | +4.6 % | **+8.8 %** |
| Pumps | **+3.0 %** | +21.6 % |
| **All categories** | **+4.6 %** | **+22.5 %** |

- **One product drove 42 % of the growth.** Sales of the Fire Fighting Pump Diesel 20 HP rose from 72 to 243 units, a quantity effect of ₹3.65 crore. Its price rose only 1.2 %. Two customers bought 102 of the 243 units, including the one-off ₹1.19 crore order identified in the growth bridge. The mix effect is largely this pump: an expensive product selling in much higher volume.
- **Pumps took the smallest price increase (3.0 %)** while delivering the most volume growth. Pricing may have been used to win these orders.
- **The largest volume loss followed a price increase.** Taper Roller Bearing 30207 fell from 2,944 to 457 units (−84 %) after an 11.5 % price rise, a ₹15.0 lakh quantity loss. Bearings overall grew volume by only 8.8 %, the weakest of any category.

## 9. Business implications and recommendations

1. **Budget next year's growth mainly on volume, not price.** Price added only ₹1.36 crore. A plan that assumes growth continues at this rate needs supply, stock and working capital for over 20 % more units a year.
2. **Do not treat the fire pump surge as a run-rate.** ₹3.65 crore of growth came from one product, much of it from two customers. Build the forecast without it and treat a repeat as upside.
3. **Review the Taper Roller Bearing 30207 price.** An 84 % volume drop after an 11.5 % increase suggests customers moved to a competitor. Test whether a price correction recovers volume, and check other Bearings prices, since the category barely grew.
4. **Track the mix effect.** Mix added ₹2.27 crore because higher-priced products grew faster. Those categories (Pumps, Electric Motors) carry different margins (see [Discount and margin erosion](../01_discount_margin_erosion/)), so check what the mix shift did to gross margin, not just revenue.
5. **Run this decomposition every quarter** alongside the growth bridge, so the board sees *why* revenue moved as well as *who* moved it.

## 10. Assumptions and limitations

- **Volume across different products.** The volume effect adds units of different products (a motor and a box of bolts count the same). This is the standard simplification. The mix effect corrects for it in total, but volume and mix should be read together.
- **Realised price includes discounts.** A change in discounting shows up as a price effect.
- **Product level.** Price changes are measured per product, not per customer, so customer-specific pricing is averaged.
- **Revenue, not margin.** The analysis explains revenue movement. Margin effects need product cost (see the discount and margin case study).

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Product table and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
