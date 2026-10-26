# Case Study · Warehouse Slotting by Pick Frequency

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 11,219 picks of 186 products, 1 October 2025 – 30 September 2026.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

The warehouse is being re-racked. Today the locations nearest the dispatch bay hold the "A" products of the [ABC classification](../../05_advanced_analytics/01_abc_xyz_product_classification/), which ranks products by **revenue**. But a picker walks to a location once for every order line, whatever the line is worth. An expensive motor picked a dozen times a year needs far fewer trips than a box of fasteners picked hundreds of times. The warehouse manager wants to know whether slotting by **pick frequency** would make a material difference before the new layout is fixed.

## 2. Business questions

1. How different is a ranking by pick frequency from the revenue ABC?
2. How much walking would slotting by pick frequency save?
3. Which products should move closer to dispatch, and which further away?
4. Which products are picked together and should sit side by side?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Picks (order lines), units, revenue |
| `sales_orders` | One row per order | Order date, status |
| `products`, `product_categories` | One row per product / category | Names, categories |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Pick | One order line (orders not Cancelled or Returned) in the last 12 months |
| Pick ABC | Products ranked by picks: A = first 80 % of picks, B = next 15 %, C = last 5 % |
| Revenue ABC | The same on revenue |
| **Zones** | Zone 1 holds the top 20 % of products, Zone 2 the next 30 %, Zone 3 the rest. Distances from the dispatch bay: **10, 25 and 45 metres** (assumptions, set as parameters). |
| Today | Products placed in zones by revenue rank |
| Proposed | Products placed in zones by pick rank |
| Travel | Picks × 2 × zone distance (a round trip per pick) |

Zone capacities are identical under both rules, so the comparison changes only **which** products sit in each zone.

## 5. Analytical approach

1. **Product table** (`sahyadri_b2b.slotting_products`). Picks, units, revenue, both ranks, both ABC classes and both zone assignments.
2. **Comparison** of pick ABC against revenue ABC, and the most-picked products.
3. **Travel model**: metres walked under each rule, and picks per zone.
4. **Move list**: products whose zone changes the most.
5. **Co-picking**: product pairs that appear in the same order most often.

## 6. SQL techniques used

- Two independent Pareto rankings with running `SUM() OVER` window shares
- Fixed-capacity zone assignment with `ROW_NUMBER()` and `CEIL(share × products)`
- Parameterised travel model (`DECLARE` for zone shares and distances)
- Self-join on order lines for co-picked pairs
- Validation of class cut-offs, equal zone capacities and the optimality of pick-based slotting

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per product picked in the period |
| 02 | Picks = source order lines |
| 03 | Revenue = source |
| 04 | Both rankings run 1…n without gaps or ties |
| 05 | Pick classes follow the 80 % and 95 % cut-offs |
| 06 | Zone capacities are equal under both rules |
| 07 | Pick-based slotting never walks further than revenue-based slotting |
| 08 | Zone 1 under pick slotting holds the most-picked products |
| 09 | Never-picked products = product master − products picked |
| 10 | The top co-picked pair recounts to 144 orders |

## 8. Findings

**Pick frequency and revenue rank products differently.** The correlation between picks and revenue is only 0.45 (picks and units: 0.82).

| Pick class | Revenue A | Revenue B | Revenue C | Products | Share of picks | Share of revenue |
|---|---:|---:|---:|---:|---:|---:|
| A | 45 | 34 | 11 | 90 | 80.3 % | 80.0 % |
| B | 13 | 28 | 21 | 62 | 14.9 % | 14.5 % |
| C | 4 | 6 | 24 | 34 | 4.8 % | 5.5 % |

- Only **45 of the 90 pick-A products are revenue-A**. Eleven pick-A products are revenue-C: cheap, fast-moving items such as fasteners and safety consumables.
- Seventeen revenue-A products are not pick-A: expensive, rarely picked items such as large motors and pumps.

**The most-picked product is one in eleven of all picks.**

| Product | Picks | Share of picks | Revenue rank |
|---|---:|---:|---:|
| Safety Shoes Steel Toe Size 9 | 973 | 8.7 % | 4 |
| Non Return Valve 2 in Swing Type | 604 | 5.4 % | 5 |
| Pillow Block Bearing UCP207 | 335 | 3.0 % | 12 |
| Ball Valve SS316 2 in Screwed | 299 | 2.7 % | 6 |
| Ball Valve SS316 1 in Screwed | 290 | 2.6 % | 7 |
| Hex Nut HT M16 (Box of 100) | 287 | 2.6 % | 23 |
| Dewatering Pump 5 HP | 278 | 2.5 % | 2 |
| Pneumatic Silencer 1/4 in (Pack of 10) | 160 | 1.4 % | 68 |

**Slotting by pick frequency cuts walking by 13.4 %.**

| | By revenue (today) | By picks (proposed) |
|---|---:|---:|
| Picks served from Zone 1 | 5,168 | **6,470** |
| Picks served from Zone 2 | 3,180 | 2,644 |
| Picks served from Zone 3 | 2,871 | 2,105 |
| Walking per year | 520.8 km | **451.1 km** |
| Metres per pick | 46.4 | 40.2 |

- With the same racking, 1,302 more picks a year are served from the nearest zone. The saving is about 70 km of walking a year, 13.4 %, under the assumed distances.

**80 products change zone: 43 move closer, 37 move further away.**

| Move closer (cheap, frequently picked) | Picks | Revenue rank | Zone today → proposed |
|---|---:|---:|---|
| Rivet Aluminium 4 mm (Box of 1000) | 119 | 101 | 3 → 1 |
| SS Pipe Union 1 in | 89 | 121 | 3 → 1 |
| Ear Muffs 27 dB | 70 | 114 | 3 → 2 |
| Hex Nut HT M8 (Box of 100) | 59 | 164 | 3 → 2 |
| Cut Resistant Gloves Level 5 | 53 | 154 | 3 → 2 |

| Move further (expensive, rarely picked) | Picks | Revenue rank | Zone today → proposed |
|---|---:|---:|---|
| 3-Phase Induction Motor 30 HP | 15 | 18 | 1 → 3 |
| Hydraulic Power Pack 2 HP | 20 | 33 | 1 → 3 |
| Soft Starter 30 kW | 21 | 38 | 1 → 3 |
| VFD 5 HP 415V | 23 | 36 | 1 → 3 |
| Openwell Submersible Pump 3 HP | 24 | 34 | 1 → 3 |

**One product anchors most co-picks.** Safety Shoes Steel Toe Size 9 appears with the Non Return Valve 2 in (144 orders), the Pillow Block Bearing UCP207 (98), the Dewatering Pump 5 HP (77) and both SS316 ball valves (76 and 70). These should share a pick face near the dispatch bay.

**14 of the 200 products in the master were not picked at all in the year.** They occupy locations without generating work.

## 9. Business implications and recommendations

1. **Slot by pick frequency, not by revenue.** Use the pick ABC for location, and keep the revenue ABC for stock policy and cycle counting, where value matters.
2. **Create a "golden zone" pick face** around the safety shoes, the 2-inch non-return valve, the UCP207 bearing and the SS316 ball valves: together they account for about a fifth of all picks and are often picked together.
3. **Move large motors, pumps and drives back.** They are high value but picked once or twice a month; heavy items may still need floor locations near a forklift aisle, which this model does not include.
4. **Release the 14 unpicked locations** or review those products for delisting with the [SKU rationalisation](../../02_sales_and_profitability/05_sku_rationalisation/) study.
5. **Re-run the analysis before each re-slot.** Pick ranks change with demand; a quarterly refresh keeps the golden zone current.

## 10. Assumptions and limitations

- **Travel model.** Three zones at 10, 25 and 45 metres, one round trip per pick. Real savings depend on the layout, batch picking and route planning. The 13.4 % is an indication of scale, not a measured saving.
- **Size and weight are not modelled.** Bulky or heavy items may need specific locations regardless of pick frequency.
- **One pick per order line.** Multi-location picks (one line split across pallets) are not recorded.
- **Last 12 months only.** Products with seasonal peaks may need a different slot in their season.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Product table, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
