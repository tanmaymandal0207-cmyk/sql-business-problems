# Case Study · Freight Zone Audit: Does the Carrier's Zone Map Match Distance?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study covers 9,703 shipments with a recorded cost from January 2024 to September 2026, to 51 destinations. It infers the carrier's zones from the charges and compares each destination's fixed charge with its distance from the warehouse. It then values each negotiating lever on the latest 12 months of freight.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-06 |

---

## 1. Business problem

The carrier contract is up for renewal. The [freight invoice audit](../../04_data_quality_and_reconciliation/09_freight_invoice_audit/) showed that the carrier bills consistently against a card: a fixed charge per destination plus a share of the consignment value. Procurement now wants to know whether the card itself is fair before negotiating. Are some destinations charged far more than their distance justifies, and which levers are worth pushing?

## 2. Business questions

1. What zones does the card use, and what does each zone charge?
2. Do the zones follow distance from the warehouse?
3. Which destinations are charged well above what their distance would suggest?
4. Where is the money in the freight bill, and what is each negotiating lever worth?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `shipments` | One row per shipment | Destination city, shipment date, freight charge |
| `sales_order_items` | One row per product per order | Order value, split across the order's shipments |

City coordinates are an inline table of approximate city centres, the same as in the [second dispatch hub](../19_second_dispatch_hub/) study.

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Shipment value | Order value ÷ number of shipments of the order |
| **Value rate** | One rate for all destinations: the within-city slope of charge on shipment value. Consignments of ₹20 lakh or more are left out, because the card caps their charge. |
| **Fixed charge** | For each destination: average of (charge − value rate × shipment value) |
| **Zone** | Destinations sorted by fixed charge; a new zone starts wherever the next destination is ₹50 or more dearer |
| Distance | Straight-line (haversine) km from Mumbai, the origin found in the second-hub study |
| **Distance benchmark** | Least squares of fixed charge on distance across destinations, weighted by shipments |
| **Flagged lane** | Fixed charge at least 15 % **and** ₹100 above the benchmark |
| Fixed / value part of the bill | Fixed part = the destination's fixed charge; value part = the rest of each charge |

## 5. Analytical approach

1. **Shipments** (`sahyadri_b2b.fz_shipments`) with city, value and distance; the **value rate** (`fz_rate`); **lanes** (`fz_lanes`) with fixed charge, zone and benchmark. Fit of the card and its stability between the two halves of the period.
2. **Zones**: charge, distance range and cities.
3. **Lanes against distance**: the benchmark, flagged and under-priced lanes, and destinations charged more than a farther one.
4. **The bill and the levers** in the latest 12 months (October 2025 – September 2026).

## 6. SQL techniques used

- A within-group (fixed-effects) slope from window averages: `SUM(dc * dv) / SUM(dv * dv)`
- Gap-based clustering in SQL: `LAG` to find jumps of ₹50 or more, then a running `SUM` to number the zones
- Weighted least squares from weighted sums, without a statistics library
- A self-join on distance to find a nearer destination charged more than a farther one, with `ROW_NUMBER` to keep the cheapest

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Shipments and freight = source; every destination has coordinates |
| 02 | Shipment values add up to order value for every shipped order |
| 03 | **Value rate = within-city slope** (recount by a second formula) |
| 04 | Fixed charges and shipments per lane = recount, for the whole period and both halves |
| 05 | **A new zone starts exactly where the next destination is ₹50 or more dearer** |
| 06 | Benchmark residuals satisfy the weighted normal equations |
| 07 | Distance sanity: Mumbai 0 km, Pune 110–130 km, Kolkata 1,500–1,700 km |
| 08 | Every shipment to a destination carries the same distance |
| 09 | Latest-12-month bill: fixed part + value part = freight |
| 10 | Flagged-lane premium = premium × latest-year shipments of the flagged lanes |

## 8. Findings

**The card is a zone charge plus 0.61 % of value, and it has not changed.**

| | Value |
|---|---:|
| Value rate | **0.611 % of shipment value** |
| Share of the variation in charges explained by the card | **97.9 %** |
| Median gap between charge and card | ₹58 |
| Correlation of fixed charges, first half against second half of the period | 0.992 |

The largest change between halves is at Hubballi (₹632 to ₹736, on 54 shipments). Every other destination moved by less than ₹100.

**The carrier uses six zones, and they are regions, not distance bands.**

| Zone | Destinations | Shipments | Fixed charge | Distance from Mumbai | Destinations |
|---:|---:|---:|---:|---|---|
| 1 West | 9 | 2,310 | **₹361** | 0–440 km | Mumbai, Pune, Nashik, Surat, Aurangabad, Vadodara, Rajkot, Margao, Ahmedabad |
| 2 Central | 6 | 1,167 | **₹565** | 489–944 km | Pithampur, Indore, Bhopal, Nagpur, Bhilai, Raipur |
| 3 South | 10 | 2,047 | **₹672** | 477–1,163 km | Hubballi, Hyderabad, Bengaluru, Mysuru, Hosur, Coimbatore, Chennai, Kochi, Visakhapatnam, Madurai |
| 4 North | 16 | 2,732 | **₹823** | 796–1,389 km | Jodhpur, Jaipur, Bhiwadi, Kanpur, Delhi NCR, Lucknow, Panipat, Rudrapur, Haridwar, Punjab, Baddi |
| 5 East | 9 | 1,440 | **₹972** | 1,294–1,654 km | Rourkela, Bhubaneswar, Ranchi, Jamshedpur, Patna, Dhanbad, Durgapur, Howrah, Kolkata |
| 6 North-east | 1 | 7 | ₹1,498 | 2,086 km | Guwahati |

The zones overlap in distance: the Central zone reaches 944 km at ₹565, while the South zone starts at 477 km at ₹672.

**Distance explains most of the fixed charge, but a few lanes sit well above it.** Benchmark: ₹279 + **₹43.6 per 100 km** (R² 0.848 across destinations).

| Destination | Zone | km | Fixed charge | Benchmark | Premium | Shipments in the latest 12 months | Premium paid in the latest 12 months |
|---|---:|---:|---:|---:|---:|---:|---:|
| Hubballi | South | 477 | ₹711 | ₹487 | **+46 %** | 32 | ₹7,163 |
| Jodhpur | North | 796 | ₹820 | ₹626 | +31 % | 4 | ₹777 |
| Guwahati | North-east | 2,086 | ₹1,498 | ₹1,188 | +26 % | 1 | ₹311 |
| Hyderabad | South | 622 | ₹668 | ₹550 | +21 % | 102 | ₹12,027 |
| Jaipur | North | 920 | ₹818 | ₹680 | +20 % | 88 | ₹12,106 |
| Rourkela | East | 1,294 | ₹980 | ₹843 | +16 % | 47 | ₹6,450 |

The six flagged lanes cost **₹38,834** above benchmark in the latest 12 months.

**The same card also undercharges several busy lanes.**

| Destination | Zone | km | Fixed charge | Benchmark | Below benchmark | Shipments in the latest 12 months |
|---|---:|---:|---:|---:|---:|---:|
| Raipur | Central | 944 | ₹563 | ₹691 | −18.5 % | 225 |
| Rajkot | West | 418 | ₹358 | ₹461 | −22.4 % | 101 |
| Ahmedabad | West | 440 | ₹365 | ₹471 | −22.5 % | 72 |
| Vadodara | West | 361 | ₹365 | ₹436 | −16.4 % | 127 |
| Margao | West | 439 | ₹352 | ₹470 | −25.2 % | 21 |
| Bhilai | Central | 918 | ₹542 | ₹679 | −20.1 % | 14 |

Raipur alone was charged ₹28,682 below benchmark in the latest year. The benchmark is weighted so that, over the whole period, it gives the same total as the current card. **A pure distance card would therefore move cost between lanes rather than cut it**, and it would make Gujarat and Raipur dearer.

**Eight busy destinations are charged at least ₹100 more than a farther one.**

| Destination | km | Fixed charge | Farther lanes charged ₹100+ less | Cheapest farther lane |
|---|---:|---:|---:|---|
| Jaipur | 920 | ₹818 | 5 | Raipur, 944 km, ₹563 |
| Hubballi | 477 | ₹711 | 6 | Bhilai, 918 km, ₹542 |
| Rourkela | 1,294 | ₹980 | 4 | Baddi, 1,378 km, ₹817 |
| Ranchi | 1,372 | ₹978 | 2 | Baddi, 1,378 km, ₹817 |
| Bengaluru | 845 | ₹683 | 2 | Bhilai, 918 km, ₹542 |
| Mysuru | 854 | ₹679 | 2 | Bhilai, 918 km, ₹542 |
| Hosur | 881 | ₹670 | 2 | Bhilai, 918 km, ₹542 |
| Hyderabad | 622 | ₹668 | 3 | Bhilai, 918 km, ₹542 |

**The bigger lever is the value rate, not the zone map.** Latest 12 months: 4,105 shipments, ₹50.87 lakh of freight (1.29 % of shipment value).

| | Value |
|---|---:|
| Fixed charges | 54.6 % of the bill |
| Value-based charges | 45.4 % of the bill |
| Lever: bring the six flagged lanes to benchmark | **₹0.39 lakh a year** |
| Lever: 5 % off every fixed charge | ₹1.39 lakh a year |
| Lever: value rate down 0.1 point (0.61 % → 0.51 %) | **₹3.64 lakh a year** |

| Zone | Shipments | Freight | Share of bill | Average charge |
|---|---:|---:|---:|---:|
| West | 980 | ₹9.85 lakh | 19.4 % | ₹1,005 |
| Central | 436 | ₹5.14 lakh | 10.1 % | ₹1,179 |
| South | 871 | ₹10.28 lakh | 20.2 % | ₹1,181 |
| North | 1,189 | ₹15.53 lakh | 30.5 % | ₹1,306 |
| East | 628 | ₹10.06 lakh | 19.8 % | ₹1,602 |
| North-east | 1 | ₹0.02 lakh | 0.0 % | ₹1,654 |

## 9. Business implications and recommendations

1. **Negotiate the value rate first.** Each 0.1 point off the 0.61 % rate is worth about ₹3.6 lakh a year, about nine times the whole excess on the flagged lanes. Because it is a share of value, it rises with every price increase even when nothing about the shipment changes.
2. **Ask for Hubballi and Hyderabad to be charged at the Central rate** (₹565). Hubballi is nearer than every Central destination, Hyderabad is nearer than four of the six, and Hyderabad is a busy lane (102 shipments a year).
3. **Ask for Jaipur and Jodhpur to be re-zoned or discounted.** Jaipur pays ₹818 at 920 km, while Raipur pays ₹563 at 944 km.
4. **Do not ask for a distance-based card.** It would raise charges on Gujarat and Raipur by about as much as it saves elsewhere. Defend the current West and Central rates.
5. **Keep the zone table in the freight audit.** Monitor every destination's fixed charge each quarter against its zone. Hubballi's ₹104 rise between halves shows how a lane can drift.

## 10. Assumptions and limitations

- **Straight-line distance.** Road distance and road quality differ by corridor (the Mumbai–Ahmedabad highway is a busy, cheap lane), and the carrier prices corridors, not crow-flight km.
- **Origin at Mumbai.** The second-hub study found Mumbai and Pune almost equally likely; using Pune would shift distances by at most 120 km (the distance between them) and would not change the zones, which come from the charges.
- **One value rate for all destinations.** The audit study found the same; a zone-specific rate would change the fixed charges slightly.
- **Charges as billed.** The study does not know the carrier's costs, so a lane above benchmark may be a fair corridor price, not an overcharge.
- **Small lanes are noisy.** Guwahati (7 shipments) and Jodhpur (12) are flagged on few shipments.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | City, shipment, rate and lane tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
