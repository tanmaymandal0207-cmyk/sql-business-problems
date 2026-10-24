# Case Study · Ship-To vs Bill-To Reconciliation

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 10,031 shipments compared with the billing city in the customer master.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-25 |

---

## 1. Business problem

Every invoice carries the customer's billing address from the customer master. Every shipment carries a delivery city typed at dispatch. The tax team needs the two to agree: goods delivered to a different state from the billing state need the right GST treatment and transport documents (e-way bills). A raw text comparison shows **1,020 shipments** whose city does not match the customer's city. Before anyone reviews them one by one, the controller wants to separate spelling problems from genuine differences, and genuine second sites from possible keying errors.

## 2. Business questions

1. How many mismatches are only casing, spacing or old city names, and in which source does the non-standard name sit?
2. How many shipments really go to a different city, and how many cross a state border?
3. Which differences are regular second sites, and which are one-off destinations that need review?
4. Can delivery history fill the missing cities in the customer master?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `shipments` | One row per shipment | Shipping city, date |
| `sales_orders` | One row per order | Customer |
| `customers` | One row per customer | Billing city and state |
| `sales_order_items` | One row per product per order | Order value |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Standardised city | `TRIM`, case-fold, then an alias table for old or alternative names (Bangalore → Bengaluru, Gurgaon → Gurugram, Calcutta → Kolkata, Baroda → Vadodara, Madras → Chennai …). Applied to both sources. The aliases are the same as the city map in the [late delivery root cause](../../03_operations_and_supply_chain/01_late_delivery_root_cause/) study. |
| State of a delivery city | From the customer master. Every standardised city belongs to exactly one state (check 03), and every delivery city is found (check 04). |
| **Match type** | 1 Exact · 2 Case or spacing only · 3 City alias only · 4 Different city, same state · 5 Different city, other state · 6 No billing city |
| **Recurring destination** | The same customer shipped to the same other city 3 or more times. Otherwise **occasional**. |
| Order over ₹50,000 | Indicator for e-way bill review. Consignment value per shipment is not recorded, so order value is used. |

## 5. Analytical approach

1. **Reference tables**: `sahyadri_b2b.city_alias_map` and `sahyadri_b2b.city_state_lookup`.
2. **Reconciliation table** (`sahyadri_b2b.ship_bill_reconciliation`). One row per shipment with raw and standardised cities, both states, match type and destination pattern.
3. **Naming mismatches**: count, the variants behind them, and which source holds the non-standard name.
4. **Genuine differences**: recurring against occasional, same state against other state; a list of recurring second sites and a review list of the largest occasional other-state shipments.
5. **Missing billing cities**: the most frequent delivery city for each customer with no city, with a fill proposal.

## 6. SQL techniques used

- Layered match classification in one `CASE`: exact, then case-folded, then alias-mapped, then state comparison
- One standardisation rule applied identically to two sources, through a shared alias table
- A reference lookup derived from master data, with a validation that it is one-to-one
- Window counts (`COUNT(*) OVER (PARTITION BY customer, city)`) to separate recurring from one-off destinations
- Rule-based fill proposals with explicit "do not fill" outcomes, instead of automatic overwrites

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One reconciliation row per source shipment |
| 02 | Every shipment has a match type |
| 03 | Every standardised city belongs to one state only |
| 04 | Every delivery city is found in the city-state lookup |
| 05 | Exact and case-only rows agree with the raw values |
| 06 | Alias rows match only after standardising |
| 07 | Different-city rows have different cities and the correct state flag |
| 08 | **Recurring flag = an independent recount** of customer-city shipments |
| 09 | No-billing-city rows = shipments of customers with no city |
| 10 | Order value = source revenue, with one value per order |

## 8. Findings

**Almost half of the apparent mismatches are naming only.**

| Match type | Shipments | Share | Customers |
|---|---:|---:|---:|
| 1. Exact match | 9,011 | 89.8 % | 409 |
| 2. Case or spacing only | 135 | 1.3 % | 58 |
| 3. City alias only | 312 | 3.1 % | 45 |
| 4. Different city, same state | 240 | 2.4 % | 119 |
| 5. Different city, other state | **224** | **2.2 %** | 119 |
| 6. No billing city | 109 | 1.1 % | 5 |

- Of the 1,020 raw mismatches, **447 disappear** after trimming, case-folding and the alias table. The rest are 464 genuine differences and 109 shipments with no billing city.
- The largest variants are Bangalore / Bengaluru (131 shipments), Gurgaon / Gurugram (74 + 11), Kolkata / Calcutta (27) and Vadodara / Baroda (25). Case and spacing variants include "kolkata", "HYDERABAD", "PUNE" and "Pune " with a trailing space.

| Non-standard name is in | Shipments | Customers |
|---|---:|---:|
| The shipment record | 234 | 78 |
| The customer master | 204 | 6 |
| Both | 9 | 3 |

- **Seven customer master records use old names** (4 Bangalore, 3 Gurgaon). Correcting those records removes 204 mismatches at once. The shipment-side variants come from free-text entry at dispatch.

**Genuine differences: regular second sites are local; one-off destinations are scattered across the country.**

| Match type | Pattern | Shipments | Customer-city pairs | Customers | Orders | Orders over ₹50,000 |
|---|---|---:|---:|---:|---:|---:|
| Same state | Recurring | 83 | 19 | 14 | 75 | 46 |
| Same state | Occasional | 157 | 134 | 109 | 153 | 63 |
| Other state | Recurring | 6 | 2 | 2 | 6 | 4 |
| Other state | **Occasional** | **218** | **203** | **119** | **207** | **101** |

- **Recurring second sites are almost all nearby plants in the same state**: Ganesh Precision Engineering, Haridwar → Rudrapur (12 shipments); Raipur → Bhilai for two customers (7 and 5); Panipat → Gurugram; Kolkata → Howrah and Durgapur for Krishna Castings; Ludhiana ↔ Jalandhar. These are legitimate delivery addresses that the master does not hold.
- Only two customers ship regularly to another state: Siddhivinayak Mishra Trading (Pune → Noida, alongside four Maharashtra sites) and Krishna Castings (Kolkata → Noida), 3 shipments each.
- **The 218 occasional other-state shipments are the review population.** They spread over 203 different customer-city pairs, almost all used once, often far from the billing city (Surat → Ghaziabad, Margao → Coimbatore, New Delhi → Visakhapatnam). That pattern fits keying errors or one-off project deliveries better than customer sites. 101 of the orders are above ₹50,000, the largest ₹4.91 lakh (Banerjee Sales Corporation, billed Surat, shipped Ghaziabad).

**Delivery history can fill three of the five missing billing cities.**

| Customer | State in master | Most frequent delivery city | Share of shipments | Proposal |
|---|---|---|---:|---|
| Gupta Infrastructure | Tamil Nadu | Chennai | 60 of 65 (92.3 %) | Propose fill |
| Bharat Menon Specialty Chemicals | Haryana | Gurugram | 33 of 33 | Propose fill |
| Modern Forgings | Gujarat | Ahmedabad | 9 of 9 | Propose fill |
| Shakti Fabricators | Madhya Pradesh | Indore | 1 of 1 | Confirm with customer: too few shipments |
| Kohinoor Specialty Chemicals | Chhattisgarh | Pithampur (Madhya Pradesh) | 1 of 1 | **Do not fill: state conflicts** |

## 9. Business implications and recommendations

1. **Fix the seven master records and make shipping city a pick-list.** Correcting 4 Bangalore and 3 Gurgaon customers removes 204 mismatches. A drop-down of standard cities at dispatch removes the remaining 243 naming variants and stops new ones.
2. **Add ship-to addresses to the customer master.** The 21 recurring second sites (16 customers) should be set up as delivery addresses linked to the customer, so their shipments match by design.
3. **Send the 218 occasional other-state shipments to the tax team for review**, starting with the 101 orders over ₹50,000. For each one, confirm whether goods really went to that state and whether the invoice, GST treatment and e-way bill reflected it. Correct the shipment record where it is a keying error.
4. **Apply the three proposed city fills** after a quick check with the account owner; confirm Shakti Fabricators with the customer; and resolve Kohinoor Specialty Chemicals' state conflict before filling anything.
5. **Run this reconciliation monthly** before GST returns are filed, so new other-state shipments are reviewed while the documents are still at hand.

## 10. Assumptions and limitations

- **Not tax advice.** The analysis identifies shipments whose delivery state differs from the billing state. Whether the GST treatment or e-way bill was correct depends on the invoice and transport documents, which are not in the data, and on rules the tax team should apply.
- **The alias table is curated.** It covers the old and alternative names found in this data. New variants would appear as "different city" until added.
- **State lookup from the customer master.** A delivery city that is not also a customer city would have no state; in this data every delivery city is found.
- **Order value, not consignment value.** For split orders, the value of each shipment is not recorded. The ₹50,000 indicator uses the whole order.
- **Customer master duplicates** are not merged here; see the [customer master de-duplication](../03_customer_master_deduplication/) study.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Reference and reconciliation tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
