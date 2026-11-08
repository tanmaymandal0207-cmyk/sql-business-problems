# Case Study · Goods in Transit: How Much Is on the Road, What Limits the Transit Policy Needs, and What Sum Insured to Declare

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study follows 10,031 shipments dispatched from January 2024 to September 2026 and measures the insured value on the road every day. It sizes the largest load on one vehicle against per-conveyance limits and works out the sum insured to declare for the open transit policy in 2026-27. It also lists the shipments that never arrived.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-08 |

---

## 1. Business problem

The company's goods travel to customers by road under an annual open (turnover) inland transit policy. At renewal the insurer asks for three things: the estimated annual dispatches to insure, the most that can travel on one vehicle (the per-conveyance or "per-bottom" limit), and the claims history. The finance controller has always sent last year's sales figure and the limit the broker suggested years ago. Dispatches have grown fast this year, and she wants the figures checked against the shipment data before renewal.

## 2. Business questions

1. How much value is on the road on a typical day, and at the peak?
2. What per-conveyance limit is needed, and how much would be uninsured at lower limits?
3. What sum insured should be declared for 2026-27, and what happens if last year's figure is sent again?
4. Which shipments are still on the road, and are any of them now claims?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `shipments` | One row per shipment | Dispatch and delivery dates, city, status |
| `sales_orders` | One row per order | Customer |
| `sales_order_items` | One row per product per order | Order value, split across the order's shipments |
| `customers` | One row per customer | Name |

## 4. Method and metric definitions

**Rules applied** (as summarised in insurers' policy prospectuses; see the sources at the end):

| Rule | Value |
|---|---|
| Open policy | One year; **a sum insured set on estimated dispatches**; every dispatch is covered until the sum insured is used up. It can be increased during the year, and unused sum insured is refunded at expiry. |
| Per-conveyance limit | The insurer's liability is limited per sending or per conveyance ("per bottom") |
| Basis of valuation | Agreed value, normally **invoice value + 10 %** for incidental expenses |
| Missing goods | Presumed a total loss **90 days after the expected delivery** |
| Claim against the carrier | Lodged **within six months** of the lorry receipt |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Shipment | Every shipment dispatched 1 January 2024 – 30 September 2026, whatever its later status (goods are at risk in transit even if later returned) |
| **Insured value** | Order value after discount ÷ shipments of the order (as in the [e-way bill study](../22_eway_bill_exposure/)) × 1.18 (GST assumed at 18 %) × 1.10 |
| **On the road** at the end of a day | Dispatched on or before that day and not yet delivered |
| Delivered without a date | 10 shipments marked Delivered with no delivery date; taken as delivered after the median transit (4 days) and listed separately |
| **Conveyance** | Shipments to the same city on the same day, assumed to travel on one vehicle (an upper bound on one vehicle's load) |
| Financial year | April – March |
| **2026-27 projection** | Actual April – September 2026, then each October – March month of 2025-26 × the April – September growth (61 %) |
| Expected delivery | Dispatch + 13 days, the 99th percentile of delivered transit times |

## 5. Analytical approach

1. **Shipments** (`sahyadri_b2b.gt_shipments`) with insured value; **value on the road every day** (`gt_daily`); **conveyances** (`gt_conveyances`).
2. **Exposure**: average, 95th percentile and peak value on the road by financial year, and what drives the peaks.
3. **Per-conveyance limit**: distribution of loads and the value above each candidate limit.
4. **Declaration** (`gt_declaration`): dispatches by month, the 2026-27 projection, and when each candidate sum insured runs out.
5. **Open shipments**: overdue shipments against the 90-day and six-month rules.

## 6. SQL techniques used

- A daily exposure series from a date spine (`GENERATE_DATE_ARRAY`) joined to shipments on an interval condition (`shipment_date <= day < delivery_date`)
- A candidate-limit table crossed with conveyances, with `LEAST` and `GREATEST` splitting each load into insured and uninsured parts
- Financial-year month numbers (`MOD(month + 8, 12) + 1`) to align years and project the rest of 2026-27 from last year's pattern
- Running totals within the financial year to find the month, and the day, a sum insured is used up

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Shipments = all dispatched in the window; **insured value per order = order value × 1.18 × 1.10** |
| 02 | Off-road date = delivery date, or dispatch + 4 days for Delivered without a date; open only when In Transit |
| 03 | Median transit of delivered shipments = 4 days |
| 04 | One daily row for every day, 1 January 2024 – 30 September 2026 |
| 05 | **Value on the road on 31 March 2026 = recount** from shipments |
| 06 | Largest shipment on the road never exceeds the value on the road |
| 07 | Conveyances add up to all shipments, one per day and city |
| 08 | Declaration months for 2024-25 and 2025-26 = dispatches by month |
| 09 | **2026-27 = actual April – September, then 2025-26 months × the growth** |
| 10 | 2025-26 at last year's sum insured: used up on 19 March 2026, not before |

## 8. Findings

**About ₹50–60 lakh is on the road on a typical day. The peaks come from single large consignments.**

| Financial year | Days | Shipments on the road (average) | Value on the road (average) | 95th percentile | Peak |
|---|---:|---:|---:|---:|---:|
| 2023-24 (January – March 2024) | 91 | 34.9 | ₹38.0 lakh | ₹65.9 lakh | ₹86.7 lakh |
| 2024-25 | 365 | 39.1 | ₹45.8 lakh | ₹83.3 lakh | ₹168.3 lakh |
| 2025-26 | 365 | 47.6 | ₹49.4 lakh | ₹83.0 lakh | ₹112.5 lakh |
| **2026-27 (to September)** | 183 | 50.0 | **₹59.6 lakh** | ₹98.3 lakh | **₹215.7 lakh** |

| Highest days | Shipments on the road | Value on the road | Largest single shipment | Its share |
|---|---:|---:|---:|---:|
| 1 Apr 2026 | 46 | ₹215.7 lakh | ₹154.9 lakh | 71.8 % |
| 18 Aug 2026 | 52 | ₹196.4 lakh | ₹144.0 lakh | 73.3 % |
| 2 Apr 2026 | 44 | ₹189.2 lakh | ₹154.9 lakh | 81.9 % |
| 6 Apr 2024 | 42 | ₹168.3 lakh | ₹106.2 lakh | 63.1 % |

On every peak day, one consignment was most of the value on the road.

**Three consignments were above ₹1 crore. A limit below ₹1.6 crore would have left part of them uninsured.**

| | Value |
|---|---:|
| Conveyances (city × day) | 8,517 (1,308 with more than one shipment) |
| Median load | ₹0.67 lakh |
| 90th / 99th percentile | ₹3.19 lakh / ₹9.57 lakh |
| **Largest** | **₹154.9 lakh** |

| Per-conveyance limit | Conveyances above it | Value above the limit (uninsured) | Value covered |
|---|---:|---:|---:|
| ₹10 lakh | 79 | ₹972.7 lakh | 91.81 % |
| ₹25 lakh | 14 | ₹506.8 lakh | 95.73 % |
| ₹50 lakh | 6 | ₹282.2 lakh | 97.62 % |
| ₹1 crore | 3 | ₹109.5 lakh | 99.08 % |
| **₹1.6 crore** | **0** | – | **100 %** |

| Largest loads | City | Shipments | Insured value |
|---|---|---:|---:|
| 1 Apr 2026 | Surat | 1 | ₹154.9 lakh |
| 18 Aug 2026 | Pune | 1 | ₹144.0 lakh |
| 4 Apr 2024 | Kolkata | 4 | ₹110.7 lakh |
| 15 Aug 2024 | Jamshedpur | 1 | ₹64.1 lakh |
| 22 Apr 2026 | Kolkata | 1 | ₹58.6 lakh |

99 % of loads are under ₹10 lakh. Sizing the policy for them would save little premium but leave the few very large consignments, where the risk is concentrated, mostly uninsured. Those are single shipments, so they are known before dispatch.

**Declaring last year's dispatches again would use up the sum insured in December.**

| Financial year | Insured dispatches | April – September | Share in April – September |
|---|---:|---:|---:|
| 2024-25 | ₹40.04 crore | ₹17.52 crore | 43.8 % |
| 2025-26 | ₹42.28 crore | ₹17.03 crore | 40.3 % |
| **2026-27 (projected)** | **₹68.20 crore** | ₹27.47 crore (actual) | 40.3 % |

- It has happened once already. Had 2025-26 been declared at 2024-25's dispatches (₹40.04 crore), the sum insured would have run out on **19 March 2026**, and the last ₹2.24 crore of dispatches would have been uninsured unless it had been increased.
- April – September 2026 dispatches are 61 % above the same months of 2025.

| Sum insured declared for 2026-27 | Amount | Runs out on the projection |
|---|---:|---|
| Dispatches of 2025-26 | ₹42.28 crore | **December 2026** (₹25.92 crore of dispatches uninsured unless increased) |
| Dispatches of the last 12 months (October 2025 – September 2026) | ₹52.72 crore | January 2027 |
| **Projection for 2026-27** | **₹68.20 crore** | Does not run out |

**Five shipments never arrived, and their carrier claims are already out of time.** Status on 30 September 2026 (expected delivery = dispatch + 13 days):

| Shipment | Customer | City | Dispatched | Days on the road | Insured value |
|---|---|---|---|---:|---:|
| 552 | Krishna Castings Ltd | Kolkata | 10 Mar 2024 | 934 | ₹0.83 lakh |
| 1571 | Banerjee Fabricators Pvt Ltd | Nagpur | 14 Jul 2024 | 808 | ₹0.32 lakh |
| 2717 | Mittal Food Industries Pvt Ltd | Nagpur | 28 Nov 2024 | 671 | ₹0.35 lakh |
| 6662 | Annapurna Precision Engineering Ltd | Jamshedpur | 17 Dec 2025 | 287 | ₹0.47 lakh |
| 7907 | Mehta Precision Engineering Pvt Ltd | Gurugram | 24 Mar 2026 | 190 | ₹0.62 lakh |

| Open on 30 September 2026 | Shipments | Insured value |
|---|---:|---:|
| In Transit, within 13 days of dispatch | 50 | – |
| **In Transit, overdue** (all more than 90 days past expected delivery and six months from dispatch) | **5** | **₹2.58 lakh** |
| Marked Delivered but no delivery date | 10 | ₹4.79 lakh |
| Returned shipments, January 2024 – September 2026 (reason not recorded) | 80 | ₹81.1 lakh |

The overdue shipments are small, but none was chased in time. Shipment 7907 passed the six-month carrier deadline in September 2026.

## 9. Business implications and recommendations

1. **Declare about ₹68 crore for 2026-27, not last year's ₹42 crore.** Unused sum insured is refunded at expiry, so over-declaring costs little. Under-declaring leaves dispatches uninsured from about December. If a lower figure is declared, set a review for December and increase the sum insured before it runs out.
2. **Set the per-conveyance limit at ₹1.6 crore, or insure very large consignments separately.** 99 % of loads are under ₹10 lakh, but three single consignments were above ₹1 crore. A cheaper option is a ₹25 lakh limit, with a rule that dispatch must notify the insurer before any consignment above it leaves.
3. **Make dispatch check the declaration monthly.** Report insured dispatches to date against the sum insured, as the policy's monthly declarations require.
4. **Chase overdue shipments at 30 days, not never.** Any In Transit shipment 30 days past dispatch should go to the carrier and the insurer. That leaves time inside the six-month carrier limit and the 90-day presumption of loss.
5. **Fix the 10 Delivered shipments with no delivery date.** Get the proof of delivery: without a date, a damage claim cannot show the loss happened in transit.
6. **Record why goods are returned.** ₹81 lakh of goods came back; any returned because of transit damage is a claim the company has not made.

## 10. Assumptions and limitations

- **Not insurance advice.** Policy wordings differ; the terms used are from insurers' prospectuses and must be checked against the company's own policy.
- **Shipment value is the order value split evenly across its shipments.** A split order whose first shipment carried most of the goods would change individual loads, not totals.
- **A conveyance is all shipments to one city on one day.** Different vehicles for the same city would make loads smaller; full-truck consolidation (see [shipment consolidation](../07_shipment_consolidation/)) would make them larger.
- **Goods held at the warehouse or at transporters' godowns** before dispatch are not in the data.
- **The projection assumes the second half of 2026-27 grows like the first.** If growth slows to zero, 2026-27 dispatches would be about ₹52.7 crore, the last-12-months figure.

**Sources for the rules:** [Universal Sompo: marine cargo open transit policy prospectus](https://www.universalsompo.com/assets/file/marine-cargo-open-transit-policy/marine-cargo-open-transit-policy-prospectus.pdf) · [ICICI Lombard: marine inland insurance prospectus](https://www.icicilombard.com/docs/default-source/default-document-library/45-prospectus-marine-inland-insurance-commercial.pdf) · [BimaKavach: marine open policy guide](https://www.bimakavach.com/blog/marine-open-policy-guide/)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Shipment, daily, conveyance and declaration tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
