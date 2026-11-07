# Case Study · Price Ladders: Are Size Variants Priced Consistently?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study reads size from product names to build 12 size ladders (60 products, 27.2 % of the latest year's revenue). It tests each rung's list price against its neighbours and checks margin along each ladder. It then values re-pricing the rungs out of line, using October 2025 – September 2026 sales.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-07 |

---

## 1. Business problem

Many products come in a ladder of sizes: motors from 0.5 to 50 HP, bearings by bore, valves and hoses by inch, bolts by thread. Each list price was set when the item was added, by whoever added it. The pricing manager suspects the ladders are uneven, with some sizes priced too cheaply or too dearly for their place in the range. She wants to know which, and what fixing them is worth, before the January price review.

## 2. Business questions

1. Which products form size ladders, and how does price rise with size?
2. Which rungs are out of line with the rest of their ladder?
3. Does margin hold up along each ladder, or do some sizes carry thin or negative margins?
4. What would bringing the out-of-line rungs back into line be worth?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `products` | One row per product | Name, list price (`selling_price`), unit cost |
| `product_categories` | One row per category | Category name |
| `sales_orders` | One row per order | Order date, status |
| `sales_order_items` | One row per product per order | Units and revenue |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| **Family** | Products whose names are identical once every number is masked (`REGEXP_REPLACE` digits → #), with 3 or more members. Deep groove ball and taper roller bearings are split by series (62 / 63, 302 / 322), because a wider series is a different product. |
| Size | Read from the name: HP; inches, including fractions such as 3/4; mm; thread M; bearing bore (code 00–03 = 10, 12, 15, 17 mm, from 04 = code × 5 mm) |
| **Ladder slope** | Least squares of ln(list price) on ln(size) within a family: 1 = price in proportion to size, below 1 = bigger sizes cost less per unit of size |
| **Neighbour price** | For an inner rung, the price interpolated between the next smaller and next larger size on the log-log scale |
| **Out of line** | List price more than 10 % above or below the neighbour price (5 % shown as a sensitivity) |
| Margin | (List price − unit cost) ÷ list price |
| Re-pricing value | Realised revenue October 2025 – September 2026 × (neighbour price ÷ list price − 1), at the same volume |

A single straight line per family is not used to flag rungs. Real ladders bend: a 0.5 HP motor carries fixed costs a line ignores, so a line would wrongly flag both ends.

## 5. Analytical approach

1. **Products** (`sahyadri_b2b.pl_products`) with family and size; **ladders** (`sahyadri_b2b.pl_ladders`) with slope, neighbour price and margin.
2. **Rungs out of line** and price inversions.
3. **Margin along each ladder.**
4. **Sales** (`sahyadri_b2b.pl_sales`) and the value of re-pricing.

## 6. SQL techniques used

- Product hierarchy from free text: `REGEXP_REPLACE` to mask numbers into a family key, and `REGEXP_EXTRACT` rules to read the size, including fractions
- Log-log regression per family from `COVAR_POP` / `VAR_POP`
- Neighbour interpolation with `LAG` and `LEAD` over a named `WINDOW`
- A self-join to look for price inversions within a family

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Every product in the master is read once |
| 02 | Family size = number of products sharing the family name |
| 03 | 12 families, 60 products, 3+ distinct positive sizes each |
| 04 | **Sizes read correctly**: spot checks across every rule (bearing codes, fractions, HP, thread, mm) |
| 05 | Wider bearing series are separate families |
| 06 | Ladder slopes = recount |
| 07 | **Neighbour price = log-log interpolation**; none at the two ends of a ladder |
| 08 | Margin = (list price − unit cost) ÷ list price |
| 09 | Product sales = source revenue for the latest 12 months |
| 10 | Re-pricing value = recount over the flagged rungs |

## 8. Findings

**Twelve ladders, and price follows size closely in all of them.**

| Family | Sizes | Range | Price slope | R² | Cost slope |
|---|---:|---|---:|---:|---:|
| 3-phase induction motors | 11 | 0.5 – 50 HP | 0.77 | 0.978 | 0.79 |
| Deep groove ball bearings, 62 series | 6 | 15 – 50 mm | 1.39 | 0.981 | 1.44 |
| Hex bolts HT 8.8 (box of 100) | 6 | M6 – M20 | 2.45 | 0.997 | 2.36 |
| Pneumatic cylinders | 6 | 32 – 100 mm bore | 1.40 | 0.993 | 1.39 |
| Centrifugal monoblock pumps | 5 | 0.5 – 5 HP | 0.66 | 0.987 | 0.67 |
| Hydraulic hoses (1 m assembly) | 5 | 1/4 – 1 in | 0.85 | 0.975 | 0.97 |
| Butterfly valves CI | 4 | 2 – 8 in | 1.12 | 0.982 | 1.12 |
| Carbide end mills | 4 | 6 – 16 mm | 1.45 | 0.969 | 1.31 |
| Hex nuts HT (box of 100) | 4 | M8 – M16 | 2.29 | 0.998 | 2.37 |
| Ball valves SS316 | 3 | 1/2 – 2 in | 1.24 | 0.994 | 1.39 |
| Deep groove ball bearings, 63 series | 3 | 25 – 50 mm | 1.90 | 0.998 | 1.10 |
| Pillow block bearings | 3 | 25 – 50 mm | 1.24 | 0.978 | 1.11 |

- Motors and pumps get cheaper per HP as they grow (slopes 0.77 and 0.66). Bolts and nuts rise much faster than diameter (2.3–2.5), because a box of bigger bolts holds far more steel.
- Where the price slope is below the cost slope, margin thins as size grows: hoses (0.85 against 0.97) and SS316 ball valves (1.24 against 1.39).

**The ladders are mostly tidy: 3 of 36 inner rungs are more than 10 % out, and all three are too cheap.**

| | Value |
|---|---:|
| Ladder products | 60 |
| Inner rungs tested | 36 |
| More than 10 % out of line | **3** (all below their neighbours) |
| More than 5 % out of line | 11 |
| Median gap to the neighbour price | 3.0 % |
| Price inversions (a bigger size at or below a smaller one) | **0** |

| Rung | List price | Neighbour price | Gap | Margin | Units, last 12 months | Revenue | Re-pricing value |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Ball valve SS316 1 in** | ₹1,475 | ₹1,663 | −11.3 % | 29.9 % | 6,129 | ₹81.49 lakh | **₹10.39 lakh** |
| **Pillow block bearing UCP207** | ₹856 | ₹958 | −10.6 % | 13.7 % | 6,585 | ₹50.74 lakh | **₹6.03 lakh** |
| Deep groove ball bearing 6205-2RS | ₹161 | ₹180 | −10.3 % | 15.5 % | 6,011 | ₹8.57 lakh | ₹0.99 lakh |
| **Total** | | | | | | | **₹17.41 lakh** |

The two biggest are busy middle sizes: the 1-inch ball valve and the UCP207 pillow block each sold over 6,000 units. They are priced as if they were a size smaller.

**Margin varies widely along some ladders; carbide end mills lose money at both ends.**

| Family | Lowest margin | Highest margin | Spread | Thinnest rung |
|---|---:|---:|---:|---|
| Carbide end mills | **−11.3 %** | 37.5 % | 48.8 points | 16 mm (the 6 mm is also below cost, at −10.6 %) |
| Pillow block bearings | 13.7 % | 33.5 % | 19.8 points | UCP207 |
| Pneumatic cylinders | 13.2 % | 31.4 % | 18.2 points | 100 × 400 mm |
| Hydraulic hoses | 16.1 % | 33.4 % | 17.4 points | 3/4 in |
| 3-phase induction motors | 12.0 % | 29.2 % | 17.2 points | 30 HP |
| Ball valves SS316 | 17.8 % | 33.1 % | 15.3 points | 2 in |
| Deep groove ball bearings, 62 series | 15.5 % | 30.0 % | 14.4 points | 6205-2RS |
| Centrifugal monoblock pumps | 18.4 % | 27.2 % | 8.8 points | 3 HP |

- The carbide end mill ladder is broken at both ends: 6 mm and 16 mm list below cost, while 12 mm earns 37.5 %. This is the master-data error flagged as rule V01 in the [data quality scorecard](../../04_data_quality_and_reconciliation/02_data_quality_scorecard/) and in [SKU rationalisation](../05_sku_rationalisation/). The ladder view shows it is a ladder problem, not two isolated typos.
- Large motors and large ball valves carry the thinnest margins. Margin falls with size in both families (correlation of margin with ln size −0.45 and −0.95).

## 9. Business implications and recommendations

1. **Raise three list prices in January to their neighbour level:** the 1-inch SS316 ball valve (to about ₹1,660), the UCP207 pillow block (about ₹960) and the 6205-2RS bearing (about ₹180). At this year's volumes that is about ₹17 lakh a year, and the new prices would still sit inside the ladder.
2. **Re-ladder carbide end mills from cost.** Set 6 mm and 16 mm at least at the 12 mm margin, and check the 10 mm and 12 mm costs, which are almost the same (₹1,168 and ₹1,194).
3. **Review the top of the motor and ball valve ladders.** 30–50 HP motors and 2-inch valves earn 12–18 % against 20–33 % for small sizes. Either the market sets those prices, or large sizes are underpriced.
4. **Use the neighbour test for every new size added to the master.** A new rung priced more than 10 % off its neighbours should need the pricing manager's sign-off.
5. **Keep a family and size field in the product master.** Reading size from free-text names works, but a proper attribute would make ladders, substitution and forecasting by family easy.

## 10. Assumptions and limitations

- **Families come from names.** Products named inconsistently (a missing space, a different word order) fall out of their ladder; 136 products are not in any ladder.
- **List prices, not realised prices.** Invoiced prices sit within about ±3 % of list (see [price discipline](../12_price_increase_and_price_discipline/)), so list-price gaps carry through to revenue.
- **The same volume after re-pricing.** A 10–11 % rise on a busy rung may lose some volume to the next size or to competitors; the value is an upper bound.
- **End rungs cannot be tested by neighbours.** The smallest and largest size of each ladder (24 products) are judged only by margin.
- **Unit cost is a single current figure** per product, with no history.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Product, ladder and sales tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
