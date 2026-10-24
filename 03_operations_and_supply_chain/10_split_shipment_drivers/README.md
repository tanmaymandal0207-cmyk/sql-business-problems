# Case Study · Split Shipment Drivers

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 9,417 shipped orders, of which 614 were split into two shipments.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-25 |

---

## 1. Business problem

Earlier studies found that split shipments are late far more often ([late delivery root cause](../01_late_delivery_root_cause/)) and cost more freight ([freight cost to serve](../02_freight_cost_to_serve/)). Neither asked **why orders are split**. Before changing the dispatch policy, for example "ship complete" instead of "ship what is available", the operations director needs to know whether splits are driven by something that can be targeted (large orders, certain categories, certain products, certain customers), what they really cost once order size is allowed for, and how much of the company's lateness they cause.

## 2. Business questions

1. Which orders get split: is it order size, product category, specific products or customer segment?
2. How much later does a split order arrive, holding order size constant, and how much of total lateness do splits cause?
3. What is the extra freight per split, once order size is allowed for?
4. How long does the second shipment follow the first, and was the first part on time?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `shipments` | One row per shipment | Shipment and delivery dates, freight |
| `sales_orders` | One row per order | Order and promised dates |
| `sales_order_items` | One row per product per order | Lines, units, revenue, products |
| `products`, `product_categories` | One row per product / category | Product and category names |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Shipped order | An order with at least one shipment row |
| **Split order** | An order with two shipments. No order has more than two. |
| Final delivery | The last shipment's delivery date, only when every shipment has a delivery date |
| Late | Delivery after the promised delivery date. Measured on the first and on the final delivery. |
| Multi-line order | An order with two or more products. Drivers are measured on these only, because a single-line order cannot be split by line. |
| **Product lift** | Split rate of multi-line orders containing the product ÷ split rate of all multi-line orders |
| **z-score** | (product split rate − base rate) ÷ √(base rate × (1 − base rate) ÷ orders). Products need 50+ multi-line orders. |
| Significance rule | \|z\| ≥ 3, because 133 products are tested at once. At \|z\| ≥ 2, about 6 products would cross by chance alone. |
| Extra freight | Average freight of split orders minus single-shipment orders **with the same number of lines**, fully costed orders only |

## 5. Analytical approach

1. **Fulfilment table** (`sahyadri_b2b.order_fulfilment`). One row per shipped order: lines, units, revenue, segment, shipments, dates, lateness and freight.
2. **Drivers.** Split rate by line count, units, segment and category.
3. **Product lift table** (`sahyadri_b2b.split_product_lift`). Lift and z-score for each product, and a count of products beyond chance.
4. **Delay.** First and final lateness for split and single orders, the same comparison by line count, and the late rate if splits were late only as often as single shipments.
5. **Freight.** Extra freight per split by line count, and in total.
6. **Timing** of the second shipment.

## 6. SQL techniques used

- Order-level aggregation of shipments before joining to line items, avoiding the shipments × lines fan-out
- Stratified comparisons (by line count) to separate the effect of splitting from the effect of order size
- Multiple-testing aware screening with z-scores and a stricter threshold, plus a count of how many products cross it
- Counterfactual rate (`late if splits behaved like single shipments`) computed in one query

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One fulfilment row per distinct shipped order |
| 02 | No order has more than 2 shipments |
| 03 | Split orders = orders with 2 shipment rows |
| 04 | No single-line order is split |
| 05 | Freight = source freight for fully costed orders |
| 06 | Final delivery not before first delivery; last shipment not before first |
| 07 | Single-shipment orders have one delivery date |
| 08 | **Product split counts = an independent recount** from line items and shipments |
| 09 | Lift table holds exactly the products with 50+ multi-line orders |
| 10 | Fulfilment revenue = source revenue of shipped orders |

## 8. Findings

**Splits are not driven by anything in the order. They look like a dispatch practice.**

| Order lines | Shipped orders | Split |
|---|---:|---:|
| 1 | 2,759 | **0.0 %** |
| 2 | 2,303 | 9.4 % |
| 3 | 1,667 | 8.6 % |
| 4 | 1,064 | 8.6 % |
| 5 | 676 | 11.5 % |
| 6+ | 948 | 8.9 % |

- **No single-line order has ever been split**, so splits separate lines, not quantities. A single product is always shipped complete.
- Once an order has two or more lines, the split rate stays at about 9 % however many lines, units or which customer: 8.9–9.6 % across unit bands, 8.3–10.4 % across segments and 8.6–10.6 % across categories.

**No product reliably causes splits.**

| | Products |
|---|---:|
| Tested (50+ multi-line orders) | 133 |
| Base split rate | 9.2 % |
| z ≥ 3 | 1 |
| z ≤ −3 | 0 |
| \|z\| ≥ 2 (about 6 expected by chance) | 5 |

- Only Flexible Spider Coupling Insert L-110 crosses z = 3 (11 splits in 50 orders, 22 %), and only just (z = 3.12). Carbide Turning Insert CNMG 120408 is next (35 of 236, 14.8 %, z = 2.98).
- The pattern is what random variation would produce. **There is no stock-out product to fix.** If stock shortages cause splits, they are spread across the range, or splits are a warehouse picking choice.

**Splitting causes a quarter of all late orders.**

| Fulfilment | Orders measured | First part late | Final part late | Median days to final delivery | Share of late orders |
|---|---:|---:|---:|---:|---:|
| Single shipment | 8,603 | 14.7 % | 14.7 % | 7 | 75.2 % |
| Split | 601 | **13.8 %** | **69.2 %** | 16 | **24.8 %** |

- **The first part of a split order is on time as often as a single shipment.** The second part makes it late: it follows 3–15 days later (median 9, 90th percentile 14).
- Holding order size constant, split orders are late 65.9–71.8 % of the time against 12.6–14.8 % for single shipments, for every line count. Size does not explain the gap.
- **If split orders were late as often as single shipments, the company's late rate would fall from 18.2 % to 14.7 %** (1,678 late orders to about 1,350), with no other change.

**Extra freight is smaller than previously reported once size is allowed for.**

| Order lines | Split orders (fully costed) | Freight, single | Freight, split | Extra per split |
|---|---:|---:|---:|---:|
| 2 | 201 | ₹1,024 | ₹1,712 | ₹688 |
| 3 | 136 | ₹1,221 | ₹1,797 | ₹576 |
| 4 | 89 | ₹1,482 | ₹1,947 | ₹465 |
| 5 | 71 | ₹1,753 | ₹2,370 | ₹616 |
| 6+ | 81 | ₹2,528 | ₹3,261 | ₹734 |
| **All** | **578** | | | **₹625** |

- The extra freight totals **₹3.61 lakh** over 33 months. The freight study's ₹827 per split did not adjust for split orders being larger.
- **Freight is the minor cost. Lateness is the major one.**

## 9. Business implications and recommendations

1. **Keep splitting, but treat the second part as the problem.** "Ship complete" would hold the whole order for the 3–15 days the missing line already takes, making the on-time first parts late too. Splitting is the better choice for the customer; the target is the gap. Expedite second parts with a dispatch target (for example within 5 days of the first part) and review every second part still waiting after 7 days.
2. **Promise to the last line, not the first.** When a line is known to be short at order entry, set the promise date from its expected availability, as the [late delivery root cause](../01_late_delivery_root_cause/) study recommends.
3. **Record why each split happened** (stock shortage, customer request, warehouse choice). The data shows no product or customer pattern, so the cause has to be captured at dispatch.
4. **Report on-time delivery for split orders by part.** Customers receiving most of the order on time are being counted as fully late. Track "first part on time" and "complete on time" separately.
5. **Do not chase the freight.** At ₹625 per split and ₹3.61 lakh over 33 months, the extra freight does not justify holding orders back. The cost of splitting is in lateness, so measure the policy on on-time delivery.

## 10. Assumptions and limitations

- **No line-to-shipment link.** The data does not record which lines went in which shipment, so the products that caused a split cannot be identified directly. Product lift measures association with split orders, not the late line itself.
- **No stock data.** Stock-outs cannot be tested directly. The absence of a product pattern points away from a few chronic stock-outs, but not away from stock shortages in general.
- **Counterfactual is simple.** The 14.7 % late rate assumes split orders would behave like single shipments if shipped complete. It describes the gain from fixing availability of the missing line, not from holding orders until they are complete, which would make the first parts late as well.
- Orders with any shipment missing a delivery date (or cost) are excluded from the lateness (or freight) comparisons.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Fulfilment and product lift tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
