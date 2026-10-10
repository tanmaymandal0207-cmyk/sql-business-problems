# Metric Definitions

Shared definitions for metrics used across case studies. Each case study references these definitions and states any deviation explicitly.

**Status key:** _Draft_ — proposed definition, not yet used in a published case study. _Confirmed_ — used and validated in at least one case study (linked).

---

## Conventions

- **Currency:** values are reported as stored in the dataset; no currency conversion or tax adjustment is applied.
- **Revenue basis:** revenue is calculated from `sales_order_items` (quantity × price × discount), not from `payments`. Cash collected is a separate metric.
- **Order status scope:** each case study states which `order_status` values are included. The default for revenue is to exclude `Cancelled`; treatment of `Returned` is stated per analysis.
- **Null handling:** the treatment of nulls in any input column is stated with the metric (for example, a null `discount_percent` treated as no discount).
- **Grain:** every metric is defined at a stated grain. Metrics are aggregated to that grain before tables at a different grain are joined.
- **Period:** analysis periods use `order_date` unless stated otherwise.

---

## Revenue and sales

| Metric | Definition | Grain | Status |
|---|---|---|---|
| Gross line value | `quantity * unit_price` | Order line | Draft |
| Net line revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)` | Order line | Draft |
| Discount amount | Gross line value − Net line revenue | Order line | Draft |
| Order revenue | Sum of net line revenue for the order | Order | Draft |
| Customer revenue | Sum of order revenue for the customer within the period | Customer × period | Draft |
| Average order value | Total order revenue ÷ count of distinct orders | Any | Draft |

## Margin

| Metric | Definition | Grain | Status |
|---|---|---|---|
| Line cost | `quantity * products.unit_cost` | Order line | Draft |
| Gross margin | Net line revenue − Line cost | Order line | Draft |
| Gross margin % | Gross margin ÷ Net line revenue | Any | Draft |

> `products.unit_cost` is a single current cost per product, not a historical cost at the time of sale. Lines for products with a null `unit_cost` are excluded from margin metrics and the exclusion is reported.

## Customers

| Metric | Definition | Grain | Status |
|---|---|---|---|
| Active customer | Customer with at least one in-scope order in the period | Customer × period | Draft |
| Last order date | `MAX(order_date)` across in-scope orders | Customer | Draft |
| Recency (days) | `DATE_DIFF(<reference_date>, last_order_date, DAY)`; the reference date is stated per analysis | Customer | Draft |
| Order frequency | Count of distinct in-scope orders in the period | Customer × period | Draft |
| Revenue share | Customer revenue ÷ total revenue for the same period and scope | Customer × period | Draft |

## Collections

| Metric | Definition | Grain | Status |
|---|---|---|---|
| Amount collected | `SUM(payments.amount)` | Order | Draft |
| Outstanding amount | Order revenue − Amount collected | Order | Draft |
| Collection rate | Amount collected ÷ Order revenue | Any | Draft |

> Order revenue and amount collected are calculated independently and may not agree exactly (for example, due to rounding or freight charged separately). Differences are measured before outstanding amounts are reported.

## Fulfilment

| Metric | Definition | Grain | Status |
|---|---|---|---|
| On-time delivery | Final `delivery_date` ≤ `promised_delivery_date` | Order | Draft |
| On-time delivery rate | On-time orders ÷ delivered orders with both dates present | Any | Draft |
| Delivery lead time (days) | `DATE_DIFF(delivery_date, order_date, DAY)` using the final delivery for the order | Order | Draft |
| Shipping cost per order | `SUM(shipping_cost)` across the order's shipments | Order | Draft |

---

## Change log

| Date | Change |
|---|---|
| 2026-10-10 | Initial draft definitions |
