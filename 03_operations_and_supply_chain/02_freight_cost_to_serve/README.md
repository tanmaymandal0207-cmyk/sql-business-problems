# Case Study · Freight Cost-to-Serve and Minimum Order Value

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Period: orders dated 1 Jan 2024 to 30 Sep 2026.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-16 |

---

## 1. Business problem

The company pays outbound freight on every order and does not charge it to the customer. The logistics manager believes small orders cost more to ship than they earn and has proposed a **minimum order value (MOV)** of ₹10,000. Finance wants evidence before customers are told: what freight really costs by order size, and whether refusing small orders would help or hurt profit.

## 2. Business questions

1. What does freight cost as a share of revenue, overall and by order size?
2. After product cost and freight, which order sizes make or lose money?
3. How much more does a split shipment cost?
4. Which customer segments place the most small orders?
5. What would a ₹10,000 MOV affect: orders, customers, revenue, freight and profit?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, customer, date |
| `sales_order_items` | One row per product per order | Revenue |
| `products` | One row per product | Unit cost |
| `shipments` | One row per shipment | Freight cost |
| `customers` | One row per customer | Segment |

Line items and shipments are each aggregated to order level before joining.

**Scope:** 9,288 Delivered orders, of which 8,691 are in scope. 311 were excluded because a shipment has no freight cost, 282 because a product has no unit cost, and 4 because they have no shipment record. These reconcile exactly in validation check 02.

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | `SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))` |
| Product cost | `SUM(quantity * products.unit_cost)` |
| Freight | `SUM(shipments.shipping_cost)` for the order |
| Gross margin | Revenue − product cost |
| Contribution after freight | Gross margin − freight |
| Loss-making order | Contribution after freight < 0 |
| Order size band | Under ₹10k · ₹10k–25k · ₹25k–50k · ₹50k–1 lakh · ₹1–5 lakh · ₹5 lakh and above |

## 5. Analytical approach

1. **Order cost-to-serve table** (`sahyadri_b2b.order_cost_to_serve`). One row per in-scope order with revenue, product cost, freight, contribution and size band.
2. **Headline freight burden.**
3. **Cost-to-serve by order size.**
4. **Single vs split shipments.**
5. **Small orders by customer segment.**
6. **MOV scenario** at ₹10,000 (declared once as `mov_threshold`, so other thresholds can be tested).

## 6. SQL techniques used

- Pre-aggregation of two one-to-many tables before joining
- Order-level profitability (revenue → gross margin → contribution after freight)
- `CASE` banding and `IF()` for the shipment pattern
- Conditional aggregation for the scenario: `SUM(IF(...))`, `COUNT(DISTINCT IF(...))`
- A declared threshold variable, so the scenario can be re-run at any MOV

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order |
| 02 | Delivered orders = in scope + each exclusion reason (9,288 = 8,691 + 597) |
| 03 | Freight = shipments table total for in-scope orders, to the paisa |
| 04 | Revenue = line-item total for in-scope orders, to the paisa |
| 05 | Contribution = revenue − product cost − freight on every row |
| 06 | No missing revenue, cost or freight in scope |
| 07 | Shipment count matches the source on every order |
| 08 | Every order sits in the correct size band |
| 09 | Size band freight adds up to total freight |
| 10 | Every order has a customer segment |

## 8. Findings

**Freight is 1.34 % of revenue overall (₹1.12 crore), but its burden depends almost entirely on order size.**

| Order size | Orders | Share of orders | Share of revenue | Avg freight | Freight % of revenue | Gross margin | Contribution after freight | Loss-making orders |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Under ₹10k | 1,389 | 16.0 % | 0.9 % | ₹708 | **12.79 %** | 17.32 % | 4.53 % | **40.0 %** |
| ₹10k–25k | 1,600 | 18.4 % | 3.2 % | ₹794 | 4.79 % | 16.49 % | 11.70 % | 11.1 % |
| ₹25k–50k | 1,579 | 18.2 % | 7.0 % | ₹959 | 2.61 % | 14.87 % | 12.26 % | 7.8 % |
| ₹50k–1 lakh | 1,746 | 20.1 % | 15.1 % | ₹1,179 | 1.64 % | 13.58 % | 11.94 % | 7.6 % |
| ₹1–5 lakh | 2,207 | 25.4 % | 52.2 % | ₹1,924 | 0.98 % | 11.02 % | 10.04 % | 10.1 % |
| ₹5 lakh and above | 170 | 2.0 % | 21.7 % | ₹6,459 | 0.61 % | 9.01 % | 8.40 % | 19.4 % |

- **Small orders cost more to ship than any other size, but they are not, in total, loss-making.** Orders under ₹10,000 are 16 % of all orders and absorb 8.8 % of total freight (₹9.84 lakh). Freight takes 12.79 % of their revenue, and 40 % of them lose money. Because they are sold with little discount (17.32 % gross margin), the group as a whole still contributes **₹3.48 lakh**.
- **Large orders lose money for a different reason.** 19.4 % of orders over ₹5 lakh are loss-making even though freight is only 0.61 % of their revenue. Their gross margin is the lowest (9.01 %), which points to discounting rather than logistics (see [Discount and margin erosion](../../02_sales_and_profitability/01_discount_margin_erosion/)).
- **Split shipments cost ₹2,060 per order on average, against ₹1,233 for single shipments.** Freight rises from 1.31 % to 1.68 % of revenue.
- **Small orders come mainly from SMB customers.** 39.1 % of SMB orders are under ₹10,000, and SMB freight is 3.13 % of revenue. For distributors the figures are 3.0 % and 0.93 %.

**A hard ₹10,000 MOV would cost more than it saves.**

| MOV at ₹10,000 | Value |
|---|---:|
| Orders below the MOV | 1,389 |
| Customers affected | 304 |
| Revenue on those orders | ₹76.9 lakh (0.93 %) |
| Freight on those orders | ₹9.84 lakh (8.8 % of freight) |
| Contribution after freight from those orders | **+₹3.48 lakh** |

If those orders were refused and not replaced, the company would lose ₹3.48 lakh of contribution and put 304 customer relationships at risk.

## 9. Business implications and recommendations

1. **Use a small-order freight charge instead of a hard minimum.** Charging freight on orders under ₹10,000 (average cost ₹708) would recover up to ₹9.84 lakh while keeping the ₹3.48 lakh contribution and the customers. The charge can be waived when the customer tops the order up above the threshold.
2. **Encourage SMB customers to consolidate orders.** Fixed delivery days or a weekly route for small accounts lets several orders share one shipment.
3. **Reduce split shipments.** Each one adds about ₹827 of freight on average. Ship complete orders unless the customer asks for part delivery (see also [Late delivery root cause](../01_late_delivery_root_cause/)).
4. **Fix large-order profitability in pricing, not logistics.** The loss-making orders above ₹5 lakh are a discount-policy issue.
5. **Record freight on every shipment.** 311 delivered orders could not be costed because freight was missing.
6. **Re-run the scenario at other thresholds** (for example ₹5,000 or ₹15,000) by changing `mov_threshold`, before fixing a policy.

## 10. Assumptions and limitations

- **Customer behaviour.** The MOV scenario assumes refused orders are lost entirely. In practice some customers would combine orders, which would make an MOV look better than shown here.
- **Cost basis.** Product cost uses the current unit cost per product, not historical cost.
- **Freight only.** Picking, packing, invoicing and collection costs also fall more heavily on small orders but are not in the data, so the true cost-to-serve of small orders is higher than shown.
- **Split shipments.** The freight comparison does not adjust for split orders being larger on average.
- **Exclusions.** Orders with missing freight or product cost are excluded. If those orders are systematically different (for example, all small), results could shift slightly.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order cost-to-serve table and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
