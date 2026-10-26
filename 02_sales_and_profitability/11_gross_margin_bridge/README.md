# Case Study · Gross Margin Bridge

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Two 12-month periods (Oct 2024 – Sep 2025 and Oct 2025 – Sep 2026), 730 product × segment cells (705 sold in both periods).

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

Gross margin in rupees roughly doubled in the latest 12 months, and gross margin % rose by more than five points. The CFO has to explain the movement to the board in one slide: how much came from selling more, from selling a different mix, from list price increases and from discounting? The [price-volume-mix](../03_price_volume_mix/) study explained **revenue**; this study explains **gross margin**, and is honest about what the cost data can and cannot support.

## 2. Business questions

1. How did gross margin (rupees and %) change between the two periods?
2. What did volume, mix, price and discount each contribute?
3. Which product categories drove the change?
4. How much of the improvement could be supplier cost increases not visible in the data?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Units, price before discount, discount |
| `sales_orders` | One row per order | Order date, status |
| `customers` | One row per customer | Segment |
| `products`, `product_categories` | One row per product / category | Unit cost, category |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Periods | Prior = 1 Oct 2024 – 30 Sep 2025; Current = 1 Oct 2025 – 30 Sep 2026 |
| Cell | Product × customer segment, so "mix" covers both what is sold and to whom |
| q, P, d, c | Units; price before discount (gross value ÷ units); average discount (1 − net ÷ gross); unit cost |
| Unit margin | m = P × (1 − d) − c |
| **Volume** | (total units Current − Prior) × prior gross margin per unit |
| **Mix** | Σ (q1 − q0) × m0 − Volume: margin from selling relatively more of higher-margin cells |
| **Price** | Σ q1 × (P1 − P0) × (1 − d0) |
| **Discount** | Σ q1 × P1 × (d0 − d1); negative when discounts deepened |
| New / Lost cells | Cells sold in only one of the two periods |
| Margin % walk | The same steps applied one after another, recomputing margin % after each |

The four effects add up exactly to the change in continuing-cell margin (validation check 07).

> **Cost caveat.** `products.unit_cost` is a single current cost. Both periods are costed at today's cost, so any supplier cost increase between the periods is invisible and appears inside the **price** effect.

## 5. Analytical approach

1. **Cell table** (`sahyadri_b2b.margin_bridge_cells`). Units, gross value, net revenue, price, discount and margin for each product × segment in both periods.
2. **Bridge table** (`sahyadri_b2b.margin_bridge`). Volume, mix, price, discount, new and lost effects in rupees.
3. **Margin % walk** and a **cost-inflation sensitivity**; discount change by segment.
4. **Bridge by product category**, and the lines excluded for missing cost.

## 6. SQL techniques used

- Exact additive margin bridge at product × segment level, with no unexplained remainder
- Sequential substitution for the margin % walk
- Sensitivity analysis written into the script (cost inflation that would cancel the price effect)
- Validation of the bridge identity, the P × (1 − d) × q = revenue identity in every cell, and category totals

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per product × segment |
| 02 | Net revenue = source lines with a known cost |
| 03 | Current margin = source |
| 04 | **Bridge identity**: prior + all effects = current |
| 05 | Cell status agrees with quantities |
| 06 | Price × (1 − discount) × units = net revenue in every cell |
| 07 | **The four effects explain the continuing-cell margin change exactly** |
| 08 | Volume + mix = Σ (q1 − q0) × prior unit margin |
| 09 | Category price and discount effects add up to the bridge totals |
| 10 | Prior margin = source |

## 8. Findings

**Gross margin rose from ₹3.03 crore to ₹6.21 crore. Two thirds of the increase is price.**

| Step | ₹ lakh |
|---|---:|
| Gross margin, prior 12 months | 302.8 |
| Volume | +69.7 |
| Mix (product × segment) | +52.5 |
| **List price** | **+210.5** |
| Discount | −16.2 |
| New product-segment cells | +2.1 |
| Lost product-segment cells | −1.0 |
| **Gross margin, current 12 months** | **620.5** |

**Margin % walk (continuing cells)**

| | Gross margin % |
|---|---:|
| Prior 12 months | 9.99 % |
| Mix | +1.15 pts |
| **List price** | **+4.66 pts** |
| Discount | −0.34 pts |
| Current 12 months | 15.46 % |

- **Volume added ₹69.7 lakh but no margin %.** Selling more at the same unit margins does not change the percentage.
- **Mix added 1.15 points.** Units grew faster in higher-margin product × segment cells.
- **Discounting took back 0.34 points (₹16.2 lakh).** Distributors' average discount rose from 11.03 % to 11.44 % and Enterprise from 8.24 % to 8.71 %. Mid-Market discounts fell slightly.

**But the price effect assumes costs did not change.**

| Sensitivity | Value |
|---|---:|
| Product cost as a share of current revenue | 84.5 % |
| **Supplier cost inflation that would cancel the whole price effect** | **6.2 %** |
| Prior margin % if prior costs were 5 % below today's | 14.28 % (against 15.46 % now) |

- With cost at 84.5 % of revenue, margins are very sensitive to cost. If supplier prices rose by about 6 % between the periods (similar to the company's own January price increase), the true margin improvement from price would be close to zero.
- **If costs rose 5 %, the real improvement in margin % is about 1.2 points, not 5.5.** The rest would be the company passing on cost inflation, which is necessary but is not a margin gain.

**Every category improved; Pumps contributed the most.**

| Category | Margin prior | Volume + mix | Price | Discount | Margin current | GM % prior → current |
|---|---:|---:|---:|---:|---:|---|
| Pumps | ₹76.7 lakh | +63.2 | +63.3 | −10.4 | ₹1.93 crore | 11.1 → 17.2 % |
| Industrial Safety Equipment | ₹51.9 lakh | +12.7 | +23.0 | −1.6 | ₹86.1 lakh | 14.9 → 19.1 % |
| Electric Motors & Drives | ₹28.7 lakh | +9.8 | +39.0 | −2.6 | ₹74.8 lakh | 4.7 → 10.1 % |
| Valves & Fittings | ₹39.2 lakh | +6.8 | +23.5 | −0.3 | ₹69.2 lakh | 10.3 → 15.0 % |
| Fasteners | ₹29.2 lakh | +8.1 | +11.1 | −1.0 | ₹47.4 lakh | 17.3 → 21.4 % |
| Bearings | ₹11.4 lakh | +2.9 | +10.0 | +0.1 | ₹24.4 lakh | 6.5 → 12.1 % |

(Category rows cover continuing cells; effects in ₹ lakh.)

- Pumps alone added ₹1.16 crore of margin, about equally from volume/mix and price, and gave back the most to discounting (₹10.4 lakh).
- Electric Motors & Drives and Bearings were the thinnest-margin categories in the prior period (4.7 % and 6.5 %); price did most of the work there.

231 order lines (₹46.7 lakh) for products with no unit cost are excluded from both periods.

## 9. Business implications and recommendations

1. **Present the margin gain with the cost caveat.** The board slide should show the bridge and state that it uses current costs. Without historical cost, a large part of the "price" effect may be pass-through of supplier inflation.
2. **Start recording historical cost.** Store the unit cost at the time of sale (or a dated cost table) so that future bridges separate price from cost. This is the single most important data fix for margin reporting.
3. **Stop the discount drift.** Distributor and Enterprise discounts each rose by about 0.4–0.5 points in a year, costing ₹16.2 lakh. The [discount consistency](../06_discount_consistency/) bands can cap it.
4. **Keep building mix.** Mix added 1.15 points; the [SKU rationalisation](../05_sku_rationalisation/) and [cross-sell](../04_cross_sell_white_space/) work push in the same direction.
5. **Review Electric Motors & Drives and Bearings.** Even after the price increases their margins (10.1 % and 12.1 %) remain below the company's 15.5 %.

## 10. Assumptions and limitations

- **One current cost per product** (see the caveat above). This is the main limitation of every margin figure in this repository.
- **Order-date basis** and orders not Cancelled or Returned, consistent with other studies.
- **Mix at product × segment level.** A finer cell (for example product × customer) would move some of the discount effect into mix.
- **Average price per cell.** Price and discount are averages within a cell; changes in pack sizes or customer-specific prices within a cell show up as price.
- **Excluded products** with no unit cost (₹46.7 lakh of revenue over two years).

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Cell and bridge tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
