# Case Study · Liquidated Damages: What a Standard Delay-Penalty Clause Would Cost on Our Late Deliveries, and How Much Promise Buffer Avoids It

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study applies a standard public-sector liquidated damages clause (0.5 % a week, capped at 10 %) to 9,125 delivered orders from January 2024 to September 2026. It tests whether any customer already deducts delay penalties and how much buffer on the promised date would remove the exposure.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-09 |

---

## 1. Business problem

Large buyers, public-sector units in particular, are moving purchase orders onto standard terms with a liquidated damages (LD) clause for late delivery. Sales wants to bid for that business, and two enterprise customers have asked to add the clause at renewal. Operations wants to pad every promised date by a week first. Before agreeing to either, the COO wants the cost measured on actual deliveries.

## 2. Business questions

1. What would the clause have cost on our actual deliveries, for all customers and for enterprise customers only?
2. Is any customer already deducting delay penalties from payments?
3. Which customers and lanes would generate the deductions?
4. How many days of buffer on the promised date would remove most of the exposure, and what does that do to the promises we quote?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, promised delivery date, status |
| `sales_order_items` | One row per product per order | Order value |
| `shipments` | One row per shipment | Delivery date, city |
| `payments` | One row per receipt | Short-payment test |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

**Clause applied** (as written in published public-sector purchase terms; see the sources at the end):

| Term | Value |
|---|---|
| Rate | **0.5 % of the value of the delayed portion of supply per week** or part of a week |
| Cap | **10 % of the total order value** |
| Value | Including taxes and freight; GST at 18 % added here |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Orders | Delivered orders with a promised date and every shipment delivered; last delivery 1 January 2024 – 30 September 2026 |
| Delayed portion | Each shipment delivered after the promised date; shipment value = order value ÷ shipments of the order (as in the [e-way bill study](../22_eway_bill_exposure/)) × 1.18 |
| **Weeks of delay** | CEIL(days late ÷ 7) per late shipment |
| **LD per order** | MIN(Σ 0.5 % × late shipment value × weeks, 10 % × order value × 1.18) |
| Short paid | Paid more than ₹1 below the order value; orders delivered by 31 March 2026 |
| Buffer | The promised date moved later by 0–10 days |

## 5. Analytical approach

1. **Shipments** (`sahyadri_b2b.ld_shipments`) with value, days late and weeks of delay; **orders** (`ld_orders`) with LD before and after the cap and amount paid.
2. **Cost**: LD by segment and per year; distribution by weeks of delay.
3. **Deductions today**: short-payment rates, on-time against late orders.
4. **Drivers**: customers and delivery cities.
5. **Buffer test**: late orders, LD and quoted lead time for buffers of 0–10 days.

## 6. SQL techniques used

- A contract clause as parameters (`DECLARE ld_rate_per_week`, `ld_cap`), so other clauses can be tested by editing two lines
- Per-shipment penalty rolled up to the order and capped with `LEAST`
- A scenario table from `GENERATE_ARRAY(0, 10)` crossed with shipments to test every buffer in one query
- Validation of weeks with integer arithmetic (`DIV(days + 6, 7)`), independent of `CEIL`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders = Delivered, fully delivered, with a promised date, in the window; value = source |
| 02 | Shipments add up to order value × 1.18; one row per shipment |
| 03 | **Days late and weeks of delay = integer recount** |
| 04 | **LD before cap = 0.5 % × late shipment value × weeks** (recount) |
| 05 | LD = MIN(before cap, 10 % of order value); cap flag consistent |
| 06 | LD is positive exactly when some shipment was late |
| 07 | Paid = payments to 30 September 2026 (recount) |
| 08 | Segment LD adds up to the total |
| 09 | A 7-day buffer removes every shipment up to 7 days late |
| 10 | Order maximum days late and weeks = recount |

## 8. Findings

**The clause would have cost ₹4.5 lakh a year on all customers, 0.12 % of order value. The 10 % cap never comes into play.**

| Segment | Orders | Late | Late share | Order value | LD | LD a year | LD as % of value |
|---|---:|---:|---:|---:|---:|---:|---:|
| Distributor | 1,841 | 395 | 21.5 % | ₹35.48 crore | ₹5.06 lakh | ₹1.84 lakh | 0.121 % |
| **Enterprise** | 3,105 | 407 | **13.1 %** | ₹35.98 crore | ₹4.40 lakh | **₹1.60 lakh** | 0.104 % |
| Mid-Market | 2,280 | 500 | 21.9 % | ₹12.36 crore | ₹2.11 lakh | ₹0.77 lakh | 0.145 % |
| SMB | 1,899 | 370 | 19.5 % | ₹5.00 crore | ₹0.84 lakh | ₹0.31 lakh | 0.143 % |
| **All** | **9,125** | **1,672** | **18.3 %** | ₹88.82 crore | **₹12.42 lakh** | **₹4.51 lakh** | **0.118 %** |

| Weeks of delay | Late orders | LD | Share of LD | Rate on the late value |
|---:|---:|---:|---:|---:|
| 1 | 1,058 | ₹6.18 lakh | 49.7 % | 0.5 % |
| 2 | 486 | ₹4.36 lakh | 35.1 % | 1.0 % |
| 3 | 109 | ₹1.59 lakh | 12.8 % | 1.5 % |
| 4 | 17 | ₹0.23 lakh | 1.9 % | 2.0 % |
| 5 | 2 | ₹0.06 lakh | 0.5 % | 2.5 % |

- The latest delivery was 32 days late, five weeks of delay, so the most any order would lose is 2.5 %. The 10 % cap would never apply.
- Enterprise customers, who are asking for the clause, are delivered late least often (13.1 %). On them the clause would cost about ₹1.6 lakh a year.

**No customer is deducting delay penalties today.** Orders delivered by 31 March 2026:

| Delivery | Orders | Short paid | Average shortfall when short | Short by 10 % or less |
|---|---:|---:|---:|---:|
| On time | 5,976 | 6.56 % | 45.9 % | 6 |
| Late | 1,327 | 6.25 % | 49.4 % | 1 |

Late orders are short paid no more often than on-time ones, and the shortfalls are around half the order, not the 0.5–2.5 % an LD would take. Short payments have other causes (see [trade credit insurance](../../05_advanced_analytics/33_trade_credit_insurance/)).

**The exposure is spread thinly across customers and lanes.**

| Customer | Segment | Orders | Late | LD over 33 months | LD as % of value |
|---|---|---:|---:|---:|---:|
| Krishna Castings Ltd | Enterprise | 348 | 60 | ₹1.17 lakh | 0.21 % |
| Maa Joshi Industrial Suppliers | Distributor | 191 | 35 | ₹0.74 lakh | 0.16 % |
| Siddhivinayak Mishra Trading Co. | Distributor | 281 | 41 | ₹0.54 lakh | 0.07 % |
| Navkar Agencies Pvt Ltd | Distributor | 124 | 33 | ₹0.48 lakh | 0.17 % |
| Mahavir Pillai Spinning Mills Pvt Ltd | Enterprise | 265 | 41 | ₹0.47 lakh | 0.12 % |

| City (100+ shipments) | Shipments | Late | Average days late when late | LD before cap |
|---|---:|---:|---:|---:|
| Kolkata | 608 | 22.5 % | 6.2 | ₹1.58 lakh |
| Raipur | 609 | 19.0 % | 7.0 | ₹1.32 lakh |
| Gurugram | 512 | 18.4 % | 6.4 | ₹0.74 lakh |
| Jamshedpur | 186 | 19.9 % | 7.5 | ₹0.69 lakh |
| Panipat | 204 | 25.5 % | 6.6 | ₹0.67 lakh |

**A week of buffer would cut the LD by three-quarters, but add a week to every promise.**

| Buffer on the promised date | Late orders | Late share | LD a year, all customers | LD a year, Enterprise | Average promised lead time |
|---:|---:|---:|---:|---:|---:|
| 0 days | 1,672 | 18.3 % | ₹4.51 lakh | ₹1.60 lakh | 12.6 days |
| 3 days | 1,069 | 11.7 % | ₹2.65 lakh | ₹1.00 lakh | 15.6 days |
| 5 days | 842 | 9.2 % | ₹1.90 lakh | ₹0.72 lakh | 17.6 days |
| 7 days | 614 | 6.7 % | ₹1.21 lakh | ₹0.40 lakh | 19.6 days |
| 10 days | 361 | 4.0 % | ₹0.66 lakh | ₹0.21 lakh | 22.6 days |

A 7-day buffer saves about ₹3.3 lakh a year of LD across all customers, and ₹1.2 lakh on enterprise customers, at the cost of quoting 19.6 days instead of 12.6. On a tender judged on delivery period, that is likely to lose more business than the LD costs.

## 9. Business implications and recommendations

1. **Accept the standard LD clause.** At current lateness it would cost about ₹1.6 lakh a year on enterprise customers and ₹4.5 lakh on all customers, about 0.1 % of value. Price 0.15 % into tender bids to cover it.
2. **Do not pad every promise by a week.** It would save about ₹3 lakh a year of LD but add 7 days to every quoted lead time. Add buffer only on the lanes where lateness is long, such as Raipur, Jamshedpur and Patna (7–7.5 days late on average when late).
3. **Never let an order run past two weeks late.** 85 % of the LD comes from orders one or two weeks late; three weeks or more is 15 %. A dispatch alert at the promised date + 7 days stops the second and third week accruing.
4. **Watch for LD deductions once the clause is live.** Today no short payment looks like an LD. After signing, reconcile deductions against the calculation here, so customers deduct no more than the clause allows.
5. **Read the clause's value basis before signing.** Some versions charge 0.5 % on the whole order, not the delayed part. For split orders that raises the cost, so check which basis each customer uses.

## 10. Assumptions and limitations

- **One standard clause for all customers.** Real contracts vary (some charge per day, cap at 5 %, or allow a grace period); the parameters at the top of `analysis.sql` can be changed.
- **Shipment value is the order value split evenly across shipments.** Where the first shipment carried most of the goods, the delayed portion is smaller.
- **Lateness is as recorded.** If customers sign proof of delivery late, or force majeure applies, LD would be lower.
- **Past lateness is assumed to continue.** Once LD is live, operations may prioritise those customers, which would lower the cost further.
- **Not legal advice.** Whether LD is enforceable as a genuine pre-estimate of loss depends on the contract and Indian contract law.

**Source for the clause:** [BHEL general conditions of contract: liquidated damages for delayed delivery](https://tenders.bhel.com/sites/default/files/GCC-2021-03-16-04%3A57%3A52.pdf)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Shipment and order tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
