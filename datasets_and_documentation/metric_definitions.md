# Metric Definitions

Shared definitions for metrics used across case studies. Each case study references these definitions and states any deviation explicitly.

**Status key:** _Draft_ means a proposed definition, not yet used in a published case study. _Confirmed_ means the metric has been used and validated in at least one case study (see the "Used in" column).

**Case study key** (used in the tables below):

| Code | Case study |
|---|---|
| CR | [Customer revenue risk](../01_customer_and_revenue/01_customer_revenue_risk/) (version 2) |
| CH | [Customer churn early warning](../01_customer_and_revenue/02_customer_churn_early_warning/) |
| GB | [Revenue growth bridge](../01_customer_and_revenue/03_revenue_growth_bridge/) |
| DM | [Discount and margin erosion](../02_sales_and_profitability/01_discount_margin_erosion/) |
| SP | [Salesperson performance scorecard](../02_sales_and_profitability/02_salesperson_scorecard/) |
| LD | [Late delivery root cause](../03_operations_and_supply_chain/01_late_delivery_root_cause/) |
| FC | [Freight cost-to-serve](../03_operations_and_supply_chain/02_freight_cost_to_serve/) |
| OC | [Order-to-cash reconciliation](../04_data_quality_and_reconciliation/01_order_to_cash_reconciliation/) |
| DQ | [Data quality scorecard](../04_data_quality_and_reconciliation/02_data_quality_scorecard/) |
| AX | [ABC-XYZ product classification](../05_advanced_analytics/01_abc_xyz_product_classification/) |
| PB | [Customer payment behaviour](../05_advanced_analytics/02_customer_payment_behaviour/) |
| PV | [Price-volume-mix analysis](../02_sales_and_profitability/03_price_volume_mix/) |
| OB | [Open order backlog review](../03_operations_and_supply_chain/03_open_order_backlog_review/) |
| DW | [Dispatch workload and capacity planning](../03_operations_and_supply_chain/04_dispatch_workload_planning/) |
| MD | [Customer master de-duplication](../04_data_quality_and_reconciliation/03_customer_master_deduplication/) |
| RF | [RFM customer segmentation](../05_advanced_analytics/03_rfm_customer_segmentation/) |
| WS | [Cross-sell white-space analysis](../02_sales_and_profitability/04_cross_sell_white_space/) |
| PS | [City-wise delivery promise standards](../03_operations_and_supply_chain/05_promise_date_standards/) |
| RC | [Revenue cut-off reconciliation](../04_data_quality_and_reconciliation/04_revenue_cutoff_reconciliation/) |
| FB | [Baseline revenue forecast](../05_advanced_analytics/04_revenue_forecast_baseline/) |
| RR | [Salesperson relationship risk](../01_customer_and_revenue/04_salesperson_relationship_risk/) |
| NA | [New customer onboarding and activation](../01_customer_and_revenue/05_new_customer_activation/) |
| SR | [SKU rationalisation](../02_sales_and_profitability/05_sku_rationalisation/) |
| CL | [Cancellation and return leakage](../03_operations_and_supply_chain/06_cancellation_return_leakage/) |
| AR | [Receivables roll-forward reconciliation](../04_data_quality_and_reconciliation/05_receivables_rollforward/) |
| WC | [Customer profitability and the whale curve](../05_advanced_analytics/05_customer_profitability_whale_curve/) |
| RG | [Regional performance and market coverage](../01_customer_and_revenue/06_regional_performance/) |
| DC | [Discount consistency and price leakage](../02_sales_and_profitability/06_discount_consistency/) |
| PE | [Period-end sales push](../02_sales_and_profitability/07_period_end_sales_push/) |
| SC | [Shipment consolidation opportunity](../03_operations_and_supply_chain/07_shipment_consolidation/) |
| AN | [Order anomaly screen](../04_data_quality_and_reconciliation/06_order_anomaly_screen/) |
| RM | [Replenishment reorder reminders](../05_advanced_analytics/06_reorder_reminders/) |

---

## Conventions

- **Currency:** values are reported as stored in the dataset (Indian rupees). No currency conversion or tax adjustment is applied.
- **Revenue basis:** revenue is calculated from `sales_order_items` (quantity × price × discount), not from `payments`. Cash collected is a separate metric.
- **Order status scope:** revenue excludes `Cancelled` and `Returned` orders unless a case study states otherwise. Receivables, delivery and payment-timing metrics use `Delivered` orders only.
- **Missing discounts:** a NULL `discount_percent` is treated as 0 %. Evidence: every order marked Paid that contains a NULL-discount line was paid at exactly the undiscounted value (260 orders; OC validation check 10).
- **Grain:** every metric is defined at a stated grain. Metrics are aggregated to that grain before tables at a different grain are joined.
- **Period:** analysis periods use `order_date` unless stated otherwise. Each case study states its as-of date or period.

---

## Revenue and sales

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Gross line value | `quantity * unit_price` | Order line | Confirmed | DM, SP |
| Net line revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)` | Order line | Confirmed | CH, GB, DM, SP, FC, OC, AX, PB |
| Discount amount | Gross line value − Net line revenue | Order line | Confirmed | DM, SP |
| Discount % | Discount amount ÷ Gross line value | Any | Confirmed | DM, SP |
| Order revenue | Sum of net line revenue for the order | Order | Confirmed | OC, FC, CH, GB, PB |
| Customer revenue | Sum of order revenue for the customer within the period | Customer × period | Confirmed | CH, GB |
| Average order value | Total order revenue ÷ count of distinct orders | Any | Confirmed | GB |
| Realised price | Revenue ÷ quantity, per product and period (after discount) | Product × period | Confirmed | PV |
| Price effect | Σ (price CY − price PY) × quantity CY | Product | Confirmed | PV |
| Quantity effect | Σ (quantity CY − quantity PY) × price PY; split into volume and mix | Product | Confirmed | PV |
| Effective discount | Discount amount ÷ gross value, per customer and period | Customer × period | Confirmed | DC, PE |
| Discount band | Segment median effective discount ± 2 points; excess = discount beyond the band | Customer | Confirmed | DC |
| Month position | Last 5 days, first 5 days or mid-month of the order date | Order | Confirmed | PE |

## Margin

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Line cost | `quantity * products.unit_cost` | Order line | Confirmed | DM, FC, SP |
| Gross margin | Net line revenue − Line cost | Order line | Confirmed | DM, FC, SP |
| Gross margin % | Gross margin ÷ Net line revenue (lines with a known cost) | Any | Confirmed | DM, FC, SP |
| Contribution after freight | Gross margin − freight | Order | Confirmed | FC |
| GP core | Products earning the first 80 % of gross profit, ranked by gross profit | Product | Confirmed | SR |
| Order handling cost | Operations and Supply Chain & Logistics salaries for the period ÷ all orders placed | Order | Confirmed | WC |
| Sales effort cost | Salesperson's salary for the period ÷ orders they booked (Head of Sales not allocated) | Order | Confirmed | WC |
| Cost of credit | Rupees outstanding × days from delivery to payment (or as-of) × cost of capital ÷ 365 | Order | Confirmed | WC |
| Customer contribution | Gross margin − freight − handling − sales effort − cost of credit | Customer × period | Confirmed | WC |

> `products.unit_cost` is a single current cost per product, not a historical cost at the time of sale. Lines for products with a null `unit_cost` are excluded from margin metrics, and the exclusion is reported.

## Customers

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Active customer | Customer with at least one in-scope order in the period | Customer × period | Confirmed | CH, GB |
| Last order date | `MAX(order_date)` across in-scope orders | Customer | Confirmed | CH |
| Recency (days) | `DATE_DIFF(<as-of date>, last_order_date, DAY)` | Customer | Confirmed | CH, RF |
| Usual ordering cycle | Median days between consecutive orders (3 or more orders) | Customer | Confirmed | CH |
| Annual run-rate | Revenue in the 365 days up to and including the last order | Customer | Confirmed | CH |
| Order frequency | Count of distinct in-scope orders in the period | Customer × period | Confirmed | CH, RF |
| RFM scores | Recency, frequency (12 months) and monetary value (12 months), each scored 1–5 with `NTILE(5)` | Customer | Confirmed | RF |
| Normalised customer name | Lower case, punctuation and legal-form words removed, spaces collapsed | Customer | Confirmed | MD |
| Revenue share | Customer revenue ÷ total revenue for the same period and scope | Customer × period | Confirmed | CR |
| Cumulative revenue share | Running revenue share, customers ranked by revenue (Pareto) | Customer | Confirmed | CR |
| Category penetration | Share of a segment's active customers buying a category | Segment × category | Confirmed | WS |
| Primary salesperson | Employee with the most attributed revenue for the customer in the period (ties to lower ID) | Customer × period | Confirmed | RR |
| Relationship type | Single-threaded (one salesperson in 24 months), Dominant (primary ≥ 80 %), Shared, Unassigned | Customer | Confirmed | RR |
| Activation stage | Not yet ordered, only cancelled or returned, one order only, repeat buyer | Customer | Confirmed | NA |
| Fair-window rate | Share achieving a milestone within n days, among customers observed for at least n days | Any | Confirmed | NA |
| Activation rate | Active customers ÷ registered customers | State / region | Confirmed | RG |
| Largest customer share | Largest customer's revenue ÷ revenue of the group | State | Confirmed | RG |
| Reorder cycle | Median gap between purchases of the same product by the same customer | Customer × product | Confirmed | RM |
| Reorder status | Days since last purchase ÷ median gap: not yet due, due, overdue, lapsed | Customer × product | Confirmed | RM |

## Collections

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Amount collected | `SUM(payments.amount)` | Order | Confirmed | OC, SP |
| Outstanding amount | Order revenue − Amount collected | Order | Confirmed | OC, SP |
| Days outstanding | As-of date − final delivery date, for open balances | Order | Confirmed | OC |
| Days to pay | Final payment date − final delivery date, for fully paid orders | Order | Confirmed | PB |
| Average cash tied up | Σ (order value × days to pay) ÷ days in the period | Segment | Confirmed | PB |
| Collection rate | Amount collected ÷ Order revenue | Any | Draft | – |
| Gross receivables | Sum of positive order balances (invoices − receipts) at a month-end, above ₹0.05 | Month-end | Confirmed | AR |
| Credit balance | Sum of negative order balances at a month-end, shown as a liability | Month-end | Confirmed | AR |
| DSO | Gross receivables ÷ invoices in the last 3 months × 91 days | Month-end | Confirmed | AR |

> Order revenue and amount collected are calculated independently. They agree within ₹0.05 on 99.74 % of orders. The differences are explained in OC (duplicate receipts, short payments, stale flags).

## Fulfilment

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| On-time delivery | Final `delivery_date` ≤ `promised_delivery_date` | Order | Confirmed | LD, SP |
| On-time delivery rate | On-time orders ÷ delivered orders with both dates present | Any | Confirmed | LD, SP |
| Dispatch days | Last shipment date − order date | Order | Confirmed | LD |
| Transit days | Final delivery date − last shipment date | Order | Confirmed | LD |
| Delivery lead time (days) | `DATE_DIFF(final delivery_date, order_date, DAY)` | Order | Confirmed | LD |
| Shipping cost per order | `SUM(shipping_cost)` across the order's shipments | Order | Confirmed | FC |
| Days in transit | As-of date − date of the oldest shipment still In Transit | Order | Confirmed | OB |
| Shipments per day | Shipment records per calendar day, zero-filled | Day | Confirmed | DW |
| Seasonality index | Average shipments per day in a month ÷ period average × 100 | Month | Confirmed | DW |
| Promise standard | Lead time met by s % of a city's training orders (`PERCENTILE_DISC`, rounded up) | City | Confirmed | PS |
| Fixed freight per shipment | Intercept of a least-squares fit of shipment cost on order value (single-shipment orders) | Company | Confirmed | SC |
| Shipments avoided | Shipments − dispatches needed when shipments to a destination are combined by schedule | Schedule | Confirmed | SC |

## Product and demand

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Monthly demand | Quantity on in-scope orders by order month, zero-filled | Product × month | Confirmed | AX |
| Coefficient of variation | Standard deviation ÷ mean of monthly demand | Product | Confirmed | AX |
| ABC class | Cumulative revenue share: A first 80 %, B next 15 %, C last 5 % | Product | Confirmed | AX, SR |
| Cancellation rate | Cancelled orders ÷ closed orders (Delivered, Cancelled, Returned) | Any | Confirmed | CL |

## Revenue recognition and forecasting

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Cut-off difference | Order-date revenue − delivery-date revenue for a period | Month / financial year | Confirmed | RC |
| Month-end exposure | Revenue ordered on or before a date but delivered after it | Date | Confirmed | RC |
| MAPE | Mean of \|forecast − actual\| ÷ actual across test months | Method | Confirmed | FB |
| Forecast bias | Mean of (forecast − actual) ÷ actual; negative = under-forecast | Method | Confirmed | FB |

## Data quality

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Rule pass rate | 1 − records failed ÷ records checked | Rule | Confirmed | DQ |
| Anomaly flag | Line quantity, price or order value beyond a multiple of a robust (median) benchmark | Order line | Confirmed | AN |

## Statistical testing

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Rate z-score | (group rate − overall rate) ÷ `SQRT(p * (1 - p) / n)`; \|z\| ≥ 2 flagged | Group | Confirmed | CL |
| Expected by chance | Groups tested × 4.55 %, reported beside groups flagged | Dimension | Confirmed | CL |
| Two-sample z-test | (mean₁ − mean₂) ÷ `SQRT(var₁/n₁ + var₂/n₂)` | Two groups | Confirmed | PE |
| Two-proportion z-test | Difference in rates ÷ pooled standard error | Two groups | Confirmed | CL, PE, AN |
| Lift | Outcome rate in the flagged group ÷ outcome rate in the rest | Method | Confirmed | RM |

---

## Change log

| Date | Change |
|---|---|
| 2026-10-10 | Initial draft definitions |
| 2026-10-19 | Confirmed metrics used in 10 case studies. Added a "Used in" column, a case study key, and Customer, Collections, Fulfilment, Product and Data quality metrics. Recorded the NULL-discount convention and its evidence. |
| 2026-10-20 | Added metrics for price-volume-mix, open order backlog, dispatch workload, customer de-duplication and RFM segmentation. Extended the case study key. |
| 2026-10-21 | Confirmed revenue share and added cumulative share (Customer revenue risk version 2). Added category penetration, promise standard, cut-off and forecast accuracy metrics. |
| 2026-10-22 | Added relationship, activation, GP core, cost-to-serve, receivables roll-forward and cancellation metrics, and a Statistical testing section. Extended the case study key. |
| 2026-10-23 | Added regional, discount band, period-end, freight model, anomaly and reorder-cycle metrics, and z-test and lift definitions. Extended the case study key. |
