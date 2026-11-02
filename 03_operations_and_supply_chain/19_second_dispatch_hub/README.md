# Case Study · A Second Dispatch Hub: Where Would It Cut Delivery Times Most?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study uses the 4,250 shipments dispatched between October 2025 and September 2026. It locates the warehouse from the data, models transit time and freight as functions of distance, and tests each of the 51 destination cities as a second hub. For the leading candidates it estimates the late deliveries prevented and the freight saved.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-02 |

---

## 1. Business problem

Every order ships from one warehouse. Customers in the north and east wait five to seven days in transit, and the [dispatch by deadline](../18_deadline_based_dispatch/) study showed that 258 late deliveries a year were dispatched on time and lost the days in transit. The board is considering a second dispatch point and wants to know where it should go, what it would change for customers, and what it could cost before freight savings stop covering it.

## 2. Business questions

1. Where does the warehouse ship from, judging by the data, and how do transit time and freight grow with distance?
2. Which city would cut the most transit days as a second hub?
3. How many late deliveries would it have prevented last year, and what freight would it save?
4. What does that mean for the decision?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `shipments` | One row per shipment | Dispatch and delivery dates, city, freight |
| `sales_orders` | One row per order | Promised delivery date |
| `sales_order_items` | One row per product per order | Shipment value |
| Inline city table | One row per city | Approximate latitude and longitude of 51 city centres |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Shipments | Dispatched 1 Oct 2025 – 30 Sep 2026; city names standardised (case, spacing, aliases such as Bombay → Mumbai) |
| Distance | Straight-line km between city centres (haversine) |
| **Origin** | The city whose distance best explains transit days (highest R² with every city tried as the origin) |
| **Transit curve** | Average transit days by 250 km band of distance from the origin, made non-decreasing |
| **Freight model** | Least squares: freight per shipment = fixed + rate × distance + rate × shipment value |
| Hub scenario | Each destination is served from the nearer of the origin and the candidate hub; predicted transit from either uses the same curve |
| Days saved | Curve(distance from origin) − curve(distance from the serving point) |
| Late deliveries prevented | Each delivered order's actual delivery moved earlier by its predicted saving, against its promised date |

## 5. Analytical approach

1. **Cities, shipments and distances** (`sahyadri_b2b.hb_cities`, `hb_shipments`, `hb_distances`).
2. **Origin** (`sahyadri_b2b.hb_origin_fit`), **transit curve** (`hb_curve`) and **freight model** (`hb_freight_model`).
3. **Scenarios** (`sahyadri_b2b.hb_scenarios`): every shipment against every candidate hub.
4. **Leading hubs**: late deliveries prevented, freight saved and where the hub's shipments would go.

## 6. SQL techniques used

- Great-circle distance in SQL (haversine with `ASIN`, `SIN`, `COS` and `ACOS(-1)` for π)
- Inferring an unknown location by fitting the model with every candidate and keeping the best R²
- A monotone step curve from band averages with a running `MAX() OVER`
- Two-variable least squares from `COVAR_POP` and `VAR_POP` (closed-form normal equations)
- A full scenario grid: every shipment × every candidate hub, served from the nearer point

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Shipments = those dispatched in the window; every city has coordinates |
| 02 | **Distances symmetric; Mumbai–Pune 100–140 km and Mumbai–Kolkata 1,600–1,700 km** |
| 03 | Origin has the highest R², recomputed as cov² ÷ (var × var) |
| 04 | Band averages = recount; the curve never falls |
| 05 | **Freight model residuals average zero and are uncorrelated with distance and value** |
| 06 | One scenario row per shipment per candidate hub |
| 07 | Each shipment is served from the nearer point; savings never negative |
| 08 | Transit with the hub = curve at the served distance |
| 09 | Shipments not served by the hub save nothing |
| 10 | Freight saving = per-km rate × km saved |

## 8. Findings

**The warehouse ships from the Mumbai–Pune area, and transit grows in steps with distance.**

The best-fitting origins are Mumbai (R² 0.357) and Pune (0.349), 120 km apart; Mumbai is used.

| Distance from Mumbai | Shipments | Average transit |
|---|---:|---:|
| Under 500 km | 1,064 | 2.1 days |
| 500–1,000 km | 1,164 | 3.8–4.0 days |
| 1,000–1,250 km | 1,018 | 4.8 days |
| 1,250–1,500 km | 653 | 5.7 days |
| 1,500 km + | 294 | 6.5 days (Guwahati 11) |

Freight per shipment = ₹541 + **₹43.7 per 100 km** + ₹314 per lakh of value. Distance is a modest part of freight: the 4,250 shipments cost ₹50.9 lakh.

**Kanpur or Lucknow would cut the most transit days.**

| Hub | Shipments it would serve | Model transit today → with hub | Transit days saved a year | Delivered within 3 days |
|---|---:|---:|---:|---:|
| **Kanpur** | 2,304 (54 %) | 4.13 → **2.97** | **4,928** | 54.9 % |
| Lucknow | 2,304 (54 %) | 4.13 → 3.05 | 4,616 | 50.6 % |
| Rudrapur | 2,123 (50 %) | 4.13 → 3.07 | 4,534 | 53.9 % |
| Faridabad / Delhi NCR | 2,216 (52 %) | 4.13 → 3.17 | 4,113 | 54.0 % |
| Patna | 2,041 (48 %) | 4.13 → 3.17 | 4,089 | 46.0 % |
| *Nagpur / Jamshedpur / Kolkata* | | | *3,576 / 3,004 / 2,824* | |
| *Bengaluru / Hyderabad* | | | *1,585 / 1,527* | |

- A hub in Kanpur would serve 31 cities: the whole north, the east (Kolkata 6.5 → 4.0 days, Patna 5.7 → 2.1) and central India (Bhopal, Raipur). It saves 1.16 transit days per shipment on average across the company.
- A southern hub saves less than a third as much (Bengaluru 1,585 days, Hyderabad 1,527): the south is 600–1,000 km from Mumbai, already about 4 days.

**It would prevent about 130 late deliveries a year and save little freight.**

| Hub | Delivered orders | Late today | Late with the hub | Freight saved a year | Hub shipments a day |
|---|---:|---:|---:|---:|---:|
| **Kanpur** | 3,865 | 730 (18.9 %) | **598 (15.5 %)** | ₹7.0 lakh (13.8 %) | 6.3 |
| Rudrapur | 3,865 | 730 | 601 (15.5 %) | ₹6.5 lakh | 5.8 |
| Lucknow | 3,865 | 730 | 610 (15.8 %) | ₹7.0 lakh | 6.3 |
| Delhi NCR | 3,865 | 730 | 620 (16.0 %) | ₹6.5 lakh | 6.0 |

- Late deliveries fall by 132 (18 %). Most lateness comes from dispatch waits and holds, which a hub does not fix (see [dispatch holds](../11_dispatch_holds/)).
- **Outbound freight savings of about ₹7 lakh a year would not pay for a hub.** They would also be offset by the cost of trucking stock from the main warehouse to the hub.

## 9. Business implications and recommendations

1. **Decide on service, not freight.** A northern hub is a customer-promise investment: 1.2 fewer transit days per shipment company-wide, about 3 days faster to Delhi NCR, Uttarakhand and Bihar, and 132 fewer late deliveries a year.
2. **If a hub is opened, put it in the Kanpur–Lucknow belt.** It serves both the north and the east. Delhi NCR is close behind and may be easier to staff and supply.
3. **Fix dispatch first; it is cheaper.** Deadline-sorted dispatch and clearing holds (see [dispatch by deadline](../18_deadline_based_dispatch/)) address the larger share of late deliveries without a building.
4. **Test the transit model before committing.** Ask the carrier for quoted transit times from Kanpur to the top 12 cities. The model assumes transit depends on distance the same way it does from Mumbai.
5. **Set promise dates by serving point** if a hub opens, so customers in the north see the faster delivery (see [promise date standards](../05_promise_date_standards/)).

## 10. Assumptions and limitations

- **Approximate coordinates.** City-centre latitudes and longitudes, rounded to 0.01°, from public geography; straight-line distance, not road distance.
- **Transit is zone-like, not purely distance-driven.** Ahmedabad, 440 km from Mumbai, gets deliveries in 1.7 days, while Hubballi, 477 km away, takes 4.2. The curve averages these, so savings for individual cities are estimates.
- **Stock availability is assumed.** The hub is assumed to hold whatever its customers order; inbound trunk freight, rent, staff and inventory are not modelled.
- **Freight and lateness only.** Revenue effects of faster delivery are not estimated (see [cost of late delivery](../../05_advanced_analytics/09_cost_of_late_delivery/)).
- **One year of shipments.** Shipments without a delivery date (57) are in the freight figures but not the transit curve.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | City, shipment, distance, curve, freight model and scenario tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
