# Case Study · E-Way Bills: How Many Consignments Need One, and How Many Outlive It?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study applies the GST e-way bill rules to the 4,250 shipments dispatched from October 2025 to September 2026. It counts the bills dispatch has to raise and checks each delivery against its bill's validity. It then finds the lanes where bills expire before the goods arrive.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-07 |

---

## 1. Business problem

Under GST, goods above a value threshold cannot move without an e-way bill, and the bill is valid for one day per 200 km. A truck stopped with an expired bill can be detained and the goods penalised under section 129 of the CGST Act. The dispatch team raises the bills by hand and has never checked how many it needs, or whether deliveries arrive within validity. After a detention at a check post, the finance controller wants the exposure measured.

## 2. Business questions

1. How many shipments need an e-way bill, and how many a day?
2. How many would have arrived after their bill expired, and on which lanes?
3. How sensitive is that to the distance assumption?
4. What should dispatch change?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `shipments` | One row per shipment | Destination city, shipment and delivery dates |
| `sales_order_items` | One row per product per order | Order value, split across the order's shipments |

City coordinates are an inline table of approximate city centres, the same as in the [second dispatch hub](../19_second_dispatch_hub/) and [freight zone audit](../21_freight_zone_audit/) studies.

## 4. Method and metric definitions

**Rules applied** (CGST Rule 138, as summarised by GST practitioners; see the sources at the end):

| Rule | Value |
|---|---|
| Inter-state threshold | Consignment value **including tax** above **₹50,000** |
| Within Maharashtra | Above **₹1 lakh** (Notification 15E/2018-State Tax) |
| Validity, normal cargo | **1 day per 200 km** or part of it; each day ends at midnight, so a bill raised on the dispatch date with n days covers delivery up to dispatch date + n |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Consignment value | Order value ÷ shipments of the order × 1.18 (GST **assumed at 18 %** on all products) |
| Road distance | Straight-line (haversine) km from Mumbai × a road factor of **1.3**; 1.15 and 1.5 as sensitivities |
| Intra-state | Mumbai, Pune, Nashik, Aurangabad and Nagpur; every other destination is inter-state |
| Validity days | MAX(1, CEIL(road km ÷ 200)) |
| **Outlived** | Transit days (delivery date − shipment date) > validity days: the bill would have needed an extension |

## 5. Analytical approach

1. **Shipments** (`sahyadri_b2b.ew_shipments`) with consignment value, state and distance; **bills** (`sahyadri_b2b.ew_bills`) for every shipment above its threshold, at three road factors.
2. **How many bills**, overall and per day.
3. **Deliveries after expiry**, by road factor, lane and validity band.
4. **Extensions** that would have been needed.

## 6. SQL techniques used

- A statutory rule turned into SQL: threshold by movement type with `IF`, validity with `CEIL`
- Haversine distance from an inline coordinates table
- A sensitivity dimension (three road factors) carried through one table instead of three runs
- Validation by recounting the rule from first principles

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Shipments = source for the window; every destination has coordinates |
| 02 | Shipment value = order value ÷ shipments; consignment value = value × 1.18 |
| 03 | Intra-state = the five Maharashtra destinations only |
| 04 | **A bill for every shipment above its threshold**, at each road factor, and none below |
| 05 | **Validity = 1 day per 200 road km or part of it**, at least 1 day |
| 06 | Validity never shrinks as the road factor grows |
| 07 | Outlived = transit days > validity; unknown when not yet delivered |
| 08 | Distance sanity: Mumbai 0 km, Pune 110–130 km straight line |
| 09 | Bills per day add up to all bills |
| 10 | Extension days = recount |

## 8. Findings

**Half of all shipments, and 89 % of the value shipped, need an e-way bill.**

| Movement | Shipments | Need a bill | Share | Share of value |
|---|---:|---:|---:|---:|
| Inter-state (above ₹50,000) | 3,596 | 1,857 | 51.6 % | 90.5 % |
| Within Maharashtra (above ₹1 lakh) | 654 | 248 | 37.9 % | 84.6 % |
| **All** | **4,250** | **2,105** | **49.5 %** | **89.3 %** |

| Bills per dispatch day | Value |
|---|---:|
| Days with at least one bill | 365 of 365 |
| Average | 5.8 |
| 90th percentile | 9 |
| Busiest day | 15 |

**About one bill in ten would have expired before delivery.**

| Road factor | Delivered bills | Outlived | Share | Of which 1-day bills |
|---:|---:|---:|---:|---:|
| 1.15 | 2,080 | 234 | 11.3 % | 43.6 % |
| **1.3** | **2,080** | **200** | **9.6 %** | **51.0 %** |
| 1.5 | 2,080 | 183 | 8.8 % | 53.6 % |

The answer barely depends on the distance assumption: between 8.8 % and 11.3 % of bills outlive their validity.

**Short lanes are the problem, not long ones.**

| Validity | Bills | Lanes | Average transit | 90th percentile transit | Outlived |
|---:|---:|---:|---:|---:|---:|
| **1 day** | 185 | 3 | 1.91 days | 2 days | **55.1 %** |
| 2 days | 118 | 2 | 2.26 days | 3 days | 16.2 % |
| 3 days | 140 | 4 | 2.04 days | 3 days | 5.0 % |
| 4 days | 42 | 3 | 4.41 days | 7 days | 24.4 % |
| 5 days | 116 | 3 | 3.78 days | 5 days | 6.1 % |
| 6 days | 175 | 6 | 4.13 days | 5 days | 5.7 % |
| 7 days | 329 | 3 | 3.78 days | 5 days | 3.7 % |
| 8 days | 447 | 12 | 4.94 days | 6 days | 3.6 % |
| 9 days | 198 | 7 | 5.51 days | 7 days | 3.6 % |
| 10 days | 186 | 4 | 6.14 days | 8 days | 2.2 % |
| 11 days | 169 | 3 | 6.49 days | 8 days | 3.6 % |

Validity grows by a day per 200 km, but transit time does not shrink below about two days however short the trip. On lanes under 200 km, a one-day bill is too short more often than not.

| Lane | Road km | Validity | Bills | Average transit | Outlived | Share |
|---|---:|---:|---:|---:|---:|---:|
| **Pune** (intra-state) | 157 | 1 day | 116 | 1.9 days | **71** | **61.2 %** |
| **Mumbai** (intra-state) | 0 | 1 day | 60 | 1.9 days | 27 | 45.0 % |
| Surat | 302 | 2 days | 61 | 2.5 days | 12 | 20.0 % |
| Raipur | 1,228 | 7 days | 154 | 3.8 days | 9 | 5.8 % |
| Bengaluru | 1,099 | 6 days | 83 | 4.2 days | 7 | 8.4 % |
| Hubballi | 620 | 4 days | 29 | 4.3 days | 7 | 25.0 % |
| Aurangabad (intra-state) | 355 | 2 days | 57 | 2.0 days | 7 | 12.3 % |
| Bhopal | 859 | 5 days | 60 | 4.0 days | 6 | 10.0 % |
| Nashik (intra-state) | 182 | 1 day | 9 | 2.3 days | 4 | 44.4 % |

**Extensions that would have been needed** (road factor 1.3)

| | Value |
|---|---:|
| Bills needing an extension | 200 |
| Extension days in total | 562 |
| Average days over validity | 2.81 |
| Most days over | 11 |
| Bills not yet delivered on 30 September 2026 | 25 |

## 9. Business implications and recommendations

1. **Treat Pune, Mumbai and Nashik as extension lanes.** A one-day bill fails on more than half of these deliveries. Either enter Part B (vehicle details) on the day the truck actually leaves, since validity starts from the first Part B entry, or extend the bill as routine before it expires.
2. **Set a daily check: any bill on an undelivered shipment that expires tonight gets extended.** Extensions are allowed within 8 hours before or after expiry. At about one outlived bill every other day, this is a few minutes' work.
3. **Plan for 6 bills a day and 15 on peak days.** Half of all shipments need one, so the job needs a named owner and a backup.
4. **Fix the long tail on far lanes separately.** On lanes with 5 or more days of validity only 2–6 % outlive their bill, but those that do run up to 11 days over. They are the same delayed shipments flagged in [late delivery root cause](../01_late_delivery_root_cause/) and [dispatch holds](../11_dispatch_holds/).
5. **Store the e-way bill number and expiry on the shipment record.** Today they are not in the data, so this study had to infer them. With them, the check in point 2 becomes a report.

## 10. Assumptions and limitations

- **Not legal advice.** The rules are as summarised by GST practitioners; check current notifications, state thresholds and exemptions (for example for movement within a city) with the tax adviser.
- **GST at 18 % for every product.** Products taxed at other rates move the consignment value and which shipments cross a threshold.
- **Straight-line distance × a road factor.** Validity uses the portal's PIN-to-PIN distance; the sensitivity shows the share outlived stays between 8.8 % and 11.3 %.
- **One bill per shipment.** Several consignments on one vehicle can need a bill together even when each is below the threshold, so the count of bills is a floor.
- **Transit from shipment date.** If goods wait at a transporter before Part B is entered, validity starts later and fewer bills would expire.

**Sources for the rules:** [ClearTax: e-way bill rules and compliance](https://cleartax.in/s//eway-bill-gst-rules-compliance) · [Taxscan: Maharashtra intra-state limit ₹1 lakh](https://www.taxscan.in/e-way-bill-maharashtra-intra-state-supply-goods-rs-1-lakh/25286) · [TaxHeal: Notification 15E/2018-State Tax](https://taxheal.com/maharashtra-notification-15e-2018-state-tax.html)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | City, shipment and bill tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
