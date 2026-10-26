# Case Study · Freight Invoice Audit

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 10,031 shipments; 8,488 single-shipment charges audited against rate cards inferred for 44 destinations.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

Freight of about ₹1.2 crore over the period is paid on carrier invoices without a rate check, because the signed rate cards were never loaded into the system. Internal audit wants to know whether the company is being charged consistently. With no rate card to test against, the audit has to **infer the rate card from the charges themselves**, show how well it explains them, and then use it to find exceptions, check for rate creep and estimate freight on shipments where no cost was recorded.

## 2. Business questions

1. Can a rate card be inferred from the charges, and how well does it explain them?
2. Which shipments are charged materially more or less than the card?
3. Have rates crept up over time?
4. How are very large consignments charged?
5. What freight should be accrued for shipments with no cost recorded?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `shipments` | One row per shipment | Destination city, shipment date, freight charged |
| `sales_order_items` | One row per product per order | Consignment value |
| `city_alias_map` | One row per city alias | Standard city names (from the [ship-to vs bill-to reconciliation](../08_ship_to_bill_to_reconciliation/); created here if it does not exist) |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Consignment value | Order revenue. Used only for single-shipment orders, where the shipment carries the whole order. |
| **Rate card** | Per destination city: charge = **fixed charge + variable rate × consignment value**, fitted by least squares |
| Fitting set | Single-shipment orders with a recorded cost and value up to ₹10 lakh. Larger consignments are excluded from fitting because a few very large values would dominate the line. |
| Pooled card | One shared card for the 8 cities with fewer than 30 fitting shipments |
| **Variance %** | (charged − card) ÷ card |
| Audit status | Within tolerance (±15 %) · Over-charged · Under-charged · Above card range (value over ₹10 lakh) · Missing cost · Split shipment (not audited: the value of each part is unknown) |
| Accrual estimate | Card charge for single-shipment orders with no cost recorded |

## 5. Analytical approach

1. **Base table** (`sahyadri_b2b.freight_audit_base`). Every shipment with its standard city, consignment value and number of shipments in the order.
2. **Rate card** (`sahyadri_b2b.freight_rate_card`). Fixed charge, variable rate and R² per city and for the pooled group.
3. **Audit table** (`sahyadri_b2b.freight_audit`). Card charge, variance and audit status for every shipment. Exceptions by status, by card type and by city.
4. **Rate creep**: median variance by year.
5. **Large consignments**: charges above the card range.
6. **Accrual** for missing costs, by year.

## 6. SQL techniques used

- Least-squares regression per group with `COVAR_POP`, `VAR_POP` and `CORR`
- Trimmed fitting set to limit leverage from extreme values
- Fallback to a pooled model for small groups, decided in SQL by a count threshold
- `CREATE TABLE IF NOT EXISTS` to share a reference table between case studies without overwriting it
- Validation that recomputes every card from explicit sums of squares

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One base row per source shipment |
| 02 | One audit row per shipment |
| 03 | **Every card's slope and intercept = a sums-of-squares recount** |
| 04 | Fitting shipments per card = recount |
| 05 | Audit status agrees with the rules |
| 06 | Variance = charged − card |
| 07 | Split-shipment rows = source shipments of orders with 2+ shipments |
| 08 | Missing-cost rows = source nulls |
| 09 | Recorded freight = source total |
| 10 | Each city uses its own card if it has 30+ fitting shipments, otherwise the pooled card |

## 8. Findings

**The charges follow a clear rate card: a fixed charge that depends on the destination, plus about 0.6 % of the consignment value.**

| Destination group (examples) | Fixed charge | Variable rate |
|---|---:|---:|
| West: Mumbai, Pune, Surat, Vadodara, Aurangabad, Nashik | ₹337–367 | 0.61–0.65 % |
| Central: Raipur, Bhopal, Nagpur | ₹544–557 | 0.62–0.63 % |
| South: Chennai, Bengaluru, Hyderabad, Coimbatore, Kochi | ₹663–681 | 0.59–0.63 % |
| North: Gurugram, New Delhi, Lucknow, Jaipur, Ludhiana | ₹813–840 | 0.59–0.65 % |
| East: Kolkata, Patna, Jamshedpur, Rourkela, Ranchi | ₹952–992 | 0.59–0.64 % |

- Across 44 cards, the median R² is 0.978: **the inferred cards explain about 98 % of the variation in charges**. The weakest is the pooled card for small cities (0.889).
- The fixed charge rises steadily from west to east, which suggests the goods ship from western India. The variable rate is about the same everywhere.

**Charges are consistent with the card. There is no sign of systematic over-charging.**

| Audit status | Shipments | Charged | Card value | Variance |
|---|---:|---:|---:|---:|
| Within tolerance (±15 %) | 8,402 | ₹1.006 crore | ₹1.006 crore | +₹1,067 |
| Over-charged | 36 | ₹54,275 | ₹43,199 | +₹11,076 |
| Under-charged | 50 | ₹46,478 | ₹58,620 | −₹12,142 |
| Above card range (> ₹10 lakh) | 35 | ₹4.38 lakh | ₹5.77 lakh | −₹1.39 lakh |
| Missing cost | 280 | — | — | — |
| Split shipment (not audited) | 1,228 | ₹12.33 lakh | — | — |

- **99.0 % of audited charges are within ±15 % of the card**, and their total differs from the card by ₹1,067 on ₹1.01 crore. Charges vary from −13.3 % to +13.1 % around the card (1st to 99th percentile), probably reflecting weight or volume, which is not recorded.
- Over- and under-charges almost cancel out (+₹11,076 and −₹12,142).

**Most exceptions come from the pooled card, not from carrier billing.**

| Card type | Cities | Audited | Exceptions | Exception rate |
|---|---:|---:|---:|---:|
| Own city card | 43 | 8,346 | 26 | **0.31 %** |
| Pooled card | 8 | 142 | 60 | **42.3 %** |

- In the pooled cities, the "exceptions" are regional rate differences. Bhilai (22 under-charges) is priced like neighbouring Raipur. Guwahati (7 over-charges), Bhubaneswar (10) and Durgapur (6) are priced like the East. These cities need their own cards, not a recovery claim.
- Among cities with their own card, only 26 charges (0.31 %) fall outside tolerance. The largest is shipment 9858 to Pune: ₹1,846 charged against a card of ₹2,891 (−36 %).

**No rate creep in three years.** The median variance against the card is 0.01 % in 2024, 0.12 % in 2025 and −0.34 % in 2026. Freight rates have stayed flat while selling prices rose each January.

**Very large consignments appear to be capped at about ₹25,000.**

| Shipment | Destination | Consignment value | Charged | Card | Charged % of value |
|---|---|---:|---:|---:|---:|
| 8038 | Surat | ₹1.19 crore | ₹24,967 | ₹77,324 | 0.21 % |
| 9481 | Pune | ₹1.11 crore | ₹24,871 | ₹67,734 | 0.22 % |
| 809 | Kolkata | ₹81.8 lakh | ₹23,565 | ₹50,438 | 0.29 % |
| 1826 | Jamshedpur | ₹49.4 lakh | ₹27,303 | ₹32,289 | 0.55 % |
| 8247 | Kolkata | ₹45.2 lakh | ₹23,036 | ₹28,280 | 0.51 % |

- Up to about ₹40 lakh, large consignments are charged within about 10 % of the card (for example ₹38.6 lakh to Pune: ₹25,513 against ₹23,785). Above that, charges stop rising at ₹23,000–27,300, consistent with a full-truck-load or maximum charge in the carrier contract.
- One shipment is out of line: 9925 to Pune (₹14.3 lakh) was charged ₹4,961, about half the card value of ₹9,069. It should be checked for a missing second invoice.

**₹3.38 lakh of freight is probably unrecorded.** 316 shipments have no cost: 96 in 2024, 109 in 2025 and 111 in 2026. The 280 single-shipment ones would cost about ₹3.38 lakh at card rates (₹1.06 lakh, ₹1.15 lakh and ₹1.17 lakh by year). The other 36 are parts of split orders and cannot be valued.

## 9. Business implications and recommendations

1. **Request the signed rate cards and load them.** The inferred cards show what they almost certainly contain; the signed version should confirm the fixed charges, the ~0.6 % variable rate and the maximum charge.
2. **Add an automatic check at invoice approval:** charge outside ±15 % of the card goes to review. On past volumes this would flag fewer than one invoice a month (26 in 33 months) for cities with their own card.
3. **Give the eight small cities their own cards** (or regional cards), so that Bhilai, Guwahati, Bhubaneswar, Durgapur and the others are not flagged wrongly.
4. **Accrue about ₹1.1–1.2 lakh a year for unrecorded freight** and find out why 3 % of shipments have no cost: missing carrier invoices, or invoices not matched to shipments.
5. **Use the cap when quoting very large orders.** Freight on consignments above about ₹40 lakh is a much smaller share of value (0.2–0.5 %) than on normal orders (about 0.6 % plus a fixed charge). Check shipments 9925 and 9858 against carrier invoices.

## 10. Assumptions and limitations

- **Value-based card.** Charges are modelled on consignment value because weight and volume are not recorded. A real rate card is usually based on weight or vehicle; value explains about 98 % of the variation here, so it is a close proxy.
- **Single-shipment orders only.** Split orders (1,228 shipments, ₹12.3 lakh) are not audited because the value of each part is unknown.
- **The tolerance band (±15 %)** is set just outside the normal ±13 % spread. A tighter band would flag ordinary variation.
- **One card for the whole period per city.** The year check shows no drift, so separate yearly cards are not needed.
- **Inferred, not contractual.** If the carriers have been over-charging consistently from the start, an inferred card would include that. The audit tests consistency, not the contract price.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Base, rate card and audit tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
