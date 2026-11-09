# Case Study · Inventory Pooling: How Much Extra Safety Stock a Second Dispatch Hub Would Need, and Which Products It Should Stock

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study splits two years of weekly demand for 183 products between the main warehouse in Mumbai and a proposed hub in Kanpur. It measures the safety stock each arrangement needs at the same service level, tests the square-root law against the regions' actual correlation, and finds how few products the hub could stock while still serving most of its customers' units.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-09 |

---

## 1. Business problem

The [second dispatch hub](../../03_operations_and_supply_chain/19_second_dispatch_hub/) study found that a hub in Kanpur would serve 31 cities in the north and east and cut transit by about 1.2 days per shipment. It assumed the hub would always have the stock. Splitting one warehouse's stock across two locations needs more safety stock in total, because each location must cover its own demand swings that used to partly cancel out. Before the board decides, the supply chain manager wants that cost measured.

## 2. Business questions

1. How much more safety stock would two locations need than one, at the same service level?
2. What would that cost to hold, against the freight the hub saves?
3. Is the rise close to the textbook square-root law, or do the two regions' demands move together?
4. Would stocking only the fast movers at the hub capture most of the benefit for a fraction of the extra stock?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, status |
| `sales_order_items` | One row per product per order | Units ordered |
| `shipments` | One row per shipment | Destination city |
| `products`, `product_categories` | One row per product / category | Unit cost, category |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Demand | Units ordered per product per week; valid (not Cancelled), shipped orders; 104 seven-day weeks from 1 October 2024 |
| **Region** | The city of the order's first shipment, served from the nearer of Mumbai and Kanpur by straight-line distance (as in the hub study) |
| **Safety stock** | z × σ(weekly demand) × √(lead time); z = 1.645 (95 % cycle service), lead time 2 weeks |
| One location | σ of total weekly demand |
| **Two locations** | σ of Mumbai demand + σ of hub demand, each stocked separately |
| Square-root law | With independent regions, two locations need (σ₁ + σ₂) ÷ √(σ₁² + σ₂²) times the pooled stock |
| Value / holding cost | Units × product unit cost / 20 % of value a year |
| Hub range | The hub stocks only its N fastest-moving products; the rest ship from Mumbai |

## 5. Analytical approach

1. **Cities** (`sahyadri_b2b.ip_cities`) and **regions** (`ip_regions`); **order lines** (`ip_order_lines`); **weekly demand** with zero weeks filled (`ip_weekly`); **per-product statistics and safety stock** (`ip_products`).
2. **One location against two**: safety stock value and extra holding cost.
3. **Square-root law**: correlation between regions, and the increase by category.
4. **Hub range**: extra stock and units covered for the top 10 – 150 products.

## 6. SQL techniques used

- A complete product × week grid (`GENERATE_ARRAY` cross join, then `LEFT JOIN`) so zero-demand weeks count in the standard deviation
- `STDDEV_SAMP` and `CORR` per product for both regions and the total
- Haversine distance to two candidate warehouses to assign each city
- Validation by the variance identity σ²(A + B) = σ²(A) + σ²(B) + 2ρσ(A)σ(B)

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | 51 cities, each served from the nearer warehouse |
| 02 | Order lines = every shipped, non-cancelled line in the window; every city mapped |
| 03 | Week index = whole weeks since 1 October 2024 |
| 04 | 104 weeks per product; weekly units = order lines |
| 05 | **Variance identity holds for every product** |
| 06 | Safety stock formulas (recount) |
| 07 | Two locations never need less than one |
| 08 | Product totals = weekly grid totals |
| 09 | Every product with demand has a cost and a category |
| 10 | City table: one row per city, coordinates within India |

## 8. Findings

**Two locations would need a third more safety stock: ₹66 lakh more, costing about ₹13 lakh a year to hold.**

| | Value |
|---|---:|
| Cities served from Kanpur / Mumbai | 31 / 20 |
| Products | 183 |
| Hub's share of units | 53.6 % |
| Safety stock, one location | ₹193.03 lakh |
| Safety stock, two locations | ₹258.74 lakh |
| **Extra safety stock** | **₹65.71 lakh (+34.0 %)** |
| **Extra holding cost at 20 % a year** | **₹13.14 lakh** |

The hub study estimated outbound freight savings of about ₹7 lakh a year. Stocking the full range at Kanpur would cost about twice that in holding cost alone, before rent, staff and the trunk freight to refill the hub.

**The square-root law holds almost exactly: the two regions' demands are unrelated.**

| | Value |
|---|---:|
| Average weekly correlation, Mumbai and hub demand, by product | 0.004 |
| Middle half of products | −0.064 to 0.063 |
| Increase if the regions were exactly independent | × 1.351 |
| **Actual increase** | **× 1.340** |

| Category | Products | Hub share | One location | Two locations | Increase |
|---|---:|---:|---:|---:|---:|
| Power Transmission | 16 | 59.3 % | ₹6.61 lakh | ₹9.31 lakh | 40.8 % |
| Pneumatic Components | 19 | 53.2 % | ₹12.94 lakh | ₹18.02 lakh | 39.3 % |
| Valves & Fittings | 17 | 56.2 % | ₹15.69 lakh | ₹21.61 lakh | 37.8 % |
| Cutting Tools & Abrasives | 19 | 46.6 % | ₹10.06 lakh | ₹13.86 lakh | 37.8 % |
| Fasteners | 20 | 53.5 % | ₹9.41 lakh | ₹12.95 lakh | 37.6 % |
| Hydraulic Components | 19 | 53.5 % | ₹15.06 lakh | ₹20.64 lakh | 37.1 % |
| Industrial Safety Equipment | 17 | 54.3 % | ₹12.91 lakh | ₹17.62 lakh | 36.5 % |
| Electric Motors & Drives | 21 | 57.0 % | ₹44.11 lakh | ₹60.17 lakh | 36.4 % |
| Pumps | 17 | 50.0 % | ₹53.59 lakh | ₹68.77 lakh | 28.3 % |
| Bearings | 18 | 52.6 % | ₹12.66 lakh | ₹15.79 lakh | 24.7 % |

Demand splits almost evenly between the regions and the regions do not move together, which is the worst case for splitting stock. Every category needs 25–41 % more.

**Stocking the top 40 products at the hub would serve 73 % of its units for a sixth of the extra stock.**

| Products stocked at the hub | Hub units covered | Extra safety stock | Extra holding cost a year |
|---:|---:|---:|---:|
| 10 | 37.9 % | ₹4.29 lakh | ₹0.86 lakh |
| 20 | 52.9 % | ₹6.87 lakh | ₹1.37 lakh |
| **40** | **73.1 %** | **₹10.63 lakh** | **₹2.13 lakh** |
| 60 | 83.9 % | ₹15.59 lakh | ₹3.12 lakh |
| 100 | 94.0 % | ₹26.00 lakh | ₹5.20 lakh |
| All 183 | 100 % | ₹65.71 lakh | ₹13.14 lakh |

The last 83 products add ₹40 lakh of safety stock to cover 6 % of the hub's units.

## 9. Business implications and recommendations

1. **Do not stock the full range at a second hub.** At the same service level it needs ₹66 lakh more safety stock and ₹13 lakh a year to hold, about twice the freight the hub would save.
2. **If the hub goes ahead, stock the top 40–60 products there** and ship the rest from Mumbai. That serves 73–84 % of northern and eastern units faster for ₹2–3 lakh a year of extra holding cost.
3. **Review the hub range every quarter** by hub units, so products move in and out as demand shifts.
4. **Count the extra stock in the hub's business case.** ₹10–16 lakh of working capital for a 40–60 product range belongs next to rent and staff in the hub decision.
5. **Use the same method for any split of stock**, such as a consignment stock at a key customer: with unrelated demand, splitting always costs about √2 more safety stock for an even split.

## 10. Assumptions and limitations

- **Demand variability only.** Lead-time variability, which a long trunk route to the hub adds, would raise the hub's safety stock further.
- **Normal approximation and one service level.** Slow movers with lumpy demand (see [intermittent demand](../14_intermittent_demand_forecasting/)) need a different model; for them the extra stock is understated.
- **Weekly demand by order date.** Orders are assumed to be filled from the region's stock in the week they are placed.
- **Cycle stock is not modelled.** If the hub is refilled as often as Mumbai is today, cycle stock does not change in total; less frequent trunk deliveries would add to it.
- **Unit cost is today's cost.** A historical cost would change values slightly, not the ratios.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | City, region, order-line, weekly and product tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
