# Case Study · Key-Account Service: Better Service or Easier Promises?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 9,125 delivered orders (425 customers, 61 destination cities) with a promise date and a delivery date on every shipment.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-27 |

---

## 1. Business problem

The key-account team reports 87 % on-time delivery to Enterprise customers against about 79 % for everyone else, and presents it as proof that key accounts get priority service. The operations head is not sure the warehouse treats them any differently. Before the figure goes into Enterprise contract reviews, she wants to know what the gap is made of: faster service, or something else.

## 2. Business questions

1. Do Enterprise and top-revenue customers get faster dispatch or faster transit than other customers in the same city?
2. Are their promise windows different?
3. Measured against one common standard, is their delivery any better?
4. What service KPI should be reported to key accounts?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order and promise dates, status |
| `shipments` | One row per shipment | Shipment and delivery dates, city |
| `sales_order_items` | One row per product per order | Order value (for revenue tiers) |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Orders | Delivered orders with a promise date and a delivery date on every shipment |
| Dispatch days | First shipment date − order date |
| Transit days | Final delivery date − first shipment date |
| Lead time | Final delivery date − order date |
| **Promise window** | Promised delivery date − order date |
| City | `INITCAP(TRIM(shipping_city))` of the first shipment |
| **Lead time vs city** | Lead time − average lead time of all orders to the same city. Positive = slower than usual for that destination. |
| **Common standard** | The 80th percentile of lead time in the order's city, the same for every customer |
| On-time (reported) | Final delivery on or before the promised date |
| **On-time vs common standard** | Lead time ≤ the city's common standard |
| Revenue tier | Customers ranked by net revenue of these orders, in five equal groups (tier 1 = largest) |
| Tests | Two-proportion z for on-time rates; Welch t for days. Enterprise against all other segments. |

## 5. Analytical approach

1. **Order table** (`sahyadri_b2b.sq_orders`). Dates, dispatch, transit, lead time, promise window, city norms, the common standard and both on-time flags for each order.
2. **By segment**: promise windows, speed, reported on-time and on-time against the common standard, with significance tests for Enterprise.
3. **Same promise, same result?** On-time by promise window band, and the on-time rate other segments would report with Enterprise-style promises (re-weighted by the Enterprise band mix).
4. **By revenue tier**, and Enterprise against other customers inside the largest tier.

## 6. SQL techniques used

- Order-level shipment roll-up with the first shipment's city from `ARRAY_AGG(… ORDER BY … LIMIT 1)`
- City norms and a percentile standard with `AVG()` and `PERCENTILE_CONT()` window functions
- Revenue tiers with `NTILE(5)` over an aggregate
- Two-proportion z and Welch t statistics side by side in one `UNION ALL` result
- Direct standardisation: re-weighting one group's band rates by another group's mix

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per eligible delivered order |
| 02 | Dispatch, transit and lead time recomputed from shipments; lead time = dispatch + transit |
| 03 | On-time flag = final delivery on or before the promise |
| 04 | Promise window = promised date − order date |
| 05 | City = standardised name of the first shipment (independent recount) |
| 06 | Lead time vs city sums to zero in every city |
| 07 | Each city standard covers at least the 80th-percentile position |
| 08 | Common-standard flag = lead time ≤ city standard |
| 09 | Revenue tiers are equal in size (within one customer) |
| 10 | Every tier-1 customer outsells every tier-2 customer |

## 8. Findings

**Enterprise orders are delivered no faster. They are promised 3 days more.**

| Segment | Orders | Average promise | Shortest promise | Dispatch days | Transit days | Lead time vs city | On-time (reported) | On-time vs common standard |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Enterprise | 3,105 | **14.7 days** | **8** | 3.97 | 5.04 | −0.04 | **86.9 %** | 80.8 % |
| SMB | 1,899 | 11.7 | 5 | 4.15 | 4.21 | −0.11 | 80.5 % | 81.7 % |
| Distributor | 1,841 | 11.6 | 5 | 4.02 | 4.53 | +0.28 | 78.5 % | 79.1 % |
| Mid-Market | 2,280 | 11.5 | 5 | 4.00 | 4.77 | −0.08 | 78.1 % | 82.0 % |

| Enterprise vs other segments | Enterprise | Others | z |
|---|---:|---:|---:|
| On-time vs promise | 86.9 % | 79.0 % | **9.25** |
| On-time vs common city standard | 80.8 % | 81.0 % | −0.24 |
| Promise window (days) | 14.69 | 11.58 | **41.32** |
| Dispatch days | 3.97 | 4.05 | −0.88 |
| Lead time vs city average (days) | −0.04 | +0.02 | −0.49 |

- **Dispatch and delivery speed are the same for every segment.** Enterprise orders leave the warehouse in 3.97 days against 4.05, and arrive as fast as any other order to the same city.
- Enterprise transit is longer (5.04 days) only because their sites are in farther cities; against each city's norm they are average.
- **Against one common standard, Enterprise on-time is 80.8 %, the same as everyone else (81.0 %).**
- **Enterprise orders are never promised in less than 8 days**; other segments get promises as short as 5 days.

**With the same promise, Enterprise orders are no more on time.**

| Promise window | Enterprise orders | Enterprise on-time | Other orders | Other on-time | Share of Enterprise orders | Share of other orders |
|---|---:|---:|---:|---:|---:|---:|
| 5–9 days | 114 | 76.3 % | 1,898 | 66.3 % | 3.7 % | **31.5 %** |
| 10–12 days | 838 | 79.2 % | 1,952 | 80.6 % | 27.0 % | 32.4 % |
| 13–15 days | 980 | 87.0 % | 1,250 | 87.4 % | 31.6 % | 20.8 % |
| 16+ days | 1,173 | 93.3 % | 920 | 90.2 % | **37.8 %** | 15.3 % |

- **If other segments had Enterprise-style promises, they would report 85.9 % on-time**, against 86.9 % for Enterprise. The promise mix explains 6.9 of the 7.9-point gap.
- Only 3.7 % of Enterprise orders get a promise under 10 days, against 31.5 % of other orders; that short-promise band is where most lateness happens (66 % on-time).

**The largest customers are not served faster either.**

| Revenue tier | Customers | Orders | Enterprise share | Average promise | Dispatch days | On-time (reported) | On-time vs common standard |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 (largest) | 85 | 5,623 | 48.4 % | 13.1 days | 3.98 | 82.4 % | 81.0 % |
| 2 | 85 | 2,001 | 16.2 % | 12.1 | 4.07 | 81.2 % | 80.4 % |
| 3 | 85 | 914 | 4.9 % | 11.8 | 4.36 | 79.2 % | 80.1 % |
| 4 | 85 | 460 | 1.5 % | 11.4 | 3.78 | 79.8 % | 83.9 % |
| 5 (smallest) | 85 | 127 | 3.9 % | 11.7 | 4.03 | 83.5 % | 84.3 % |

- Inside the largest tier, Enterprise customers report 86.8 % on-time and other large customers 78.2 %, but against the common standard they are equal (81.1 % and 80.8 %), with the same dispatch time (3.94 and 4.01 days). **A large non-Enterprise customer gets the same service but shorter promises, so it sees more late deliveries.**

## 9. Business implications and recommendations

1. **Stop presenting 87 % on-time as evidence of priority service.** It is a promise-setting effect. Report key-account service against the common city standard (80.8 %), which can be compared across segments and over time.
2. **Decide whether key accounts should actually get priority.** Today the warehouse treats every order the same. If key accounts are meant to be faster, it needs an explicit rule (dispatch-day target, pick priority) and this table to monitor it.
3. **Set promises from the destination, not from the segment.** The [city promise standards](../05_promise_date_standards/) already give a per-city promise; applying them to every segment removes the 5–9-day promises that cause most late deliveries for non-Enterprise customers.
4. **Review promises for large non-Enterprise customers first.** They place a lot of volume (tier 1 non-Enterprise: 2,899 orders) and see 78.2 % on-time on the same service that Enterprise customers experience as 86.8 %.
5. **Use the same standard in customer contracts.** An SLA written against today's padded Enterprise promise would be easy to meet but would not reflect service.

## 10. Assumptions and limitations

- **Promises are taken as recorded.** The data does not say who sets the promise or why Enterprise windows start at 8 days; this should be confirmed with the order-entry team.
- **Common standard** = city 80th percentile over the whole period, using all segments. A different percentile changes the level but not the comparison.
- **City from the first shipment.** For split orders the second shipment can go elsewhere; this affects few orders (see [split shipment drivers](../10_split_shipment_drivers/)).
- **Delivered orders only.** Cancelled, returned and in-transit orders are excluded, so service failures that end in a cancellation are not measured here.
- **Revenue tiers** use the delivered orders in this study, not total revenue.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
