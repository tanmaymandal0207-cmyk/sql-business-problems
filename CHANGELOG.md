# Changelog

All notable changes to this repository are recorded here, newest first. Dates are in `YYYY-MM-DD` format.

Each entry lists case studies **added**, existing documents **changed**, and **fixes** to earlier work. A case study is listed as added only when its SQL, validation checks and findings are all in place.

---

## 2026-10-22

### Added
- **Salesperson relationship risk** ([01_customer_and_revenue/04_salesperson_relationship_risk](01_customer_and_revenue/04_salesperson_relationship_risk/)). 69.7 % of revenue sits with customers where one salesperson holds at least 80 % of the relationship. Accounts that changed salesperson fell 7.1 % while retained accounts grew 35.0 %.
- **New customer onboarding and activation** ([01_customer_and_revenue/05_new_customer_activation](01_customer_and_revenue/05_new_customer_activation/)). 61 of 82 customers registered since 2024 have bought, and 52 % buy within 90 days. 14 of 39 SMB registrations have never ordered.
- **SKU rationalisation** ([02_sales_and_profitability/05_sku_rationalisation](02_sales_and_profitability/05_sku_rationalisation/)). 54 products earn 80 % of gross profit. Repricing 30 low-margin sellers to a 10 % margin is worth about ₹61.8 lakh a year. 9 delist candidates have no dependent customer.
- **Cancellation and return leakage** ([03_operations_and_supply_chain/06_cancellation_return_leakage](03_operations_and_supply_chain/06_cancellation_return_leakage/)). ₹5.23 crore of order value lost over 33 months. A statistical screen of 206 groups finds no segment, category, salesperson or order size that explains it beyond chance. Returns are not linked to late delivery.
- **Receivables roll-forward reconciliation** ([04_data_quality_and_reconciliation/05_receivables_rollforward](04_data_quality_and_reconciliation/05_receivables_rollforward/)). The receivables account rolls forward in all 33 months and agrees with the order-to-cash ageing to the paisa (₹10.97 crore). DSO rose to 97 days because invoices over 90 days old are not being collected; current invoices are paid in about 46 days.
- **Customer profitability and the whale curve** ([05_advanced_analytics/05_customer_profitability_whale_curve](05_advanced_analytics/05_customer_profitability_whale_curve/)). An activity-based customer P&L. The whale curve peaks at 106.5 %; 150 customers give back ₹19.6 lakh, and SMB is the only loss-making segment.

### Changed
- `metric_definitions.md`: added relationship, activation, gross profit, cost-to-serve, receivables and cancellation metrics, and a Statistical testing section.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 26 case studies are now complete.

---

## 2026-10-21

### Added
- **Cross-sell white-space analysis** ([02_sales_and_profitability/04_cross_sell_white_space](02_sales_and_profitability/04_cross_sell_white_space/)). Category penetration by segment. 190 customers have 473 category gaps worth an indicative ₹4.18 crore.
- **City-wise delivery promise standards** ([03_operations_and_supply_chain/05_promise_date_standards](03_operations_and_supply_chain/05_promise_date_standards/)). Standards set on 2024–2025 deliveries and tested on 2026. An 85 % city standard lifts on-time delivery from 81.6 % to 85.4 % for 0.9 extra days per promise.
- **Revenue cut-off reconciliation** ([04_data_quality_and_reconciliation/04_revenue_cutoff_reconciliation](04_data_quality_and_reconciliation/04_revenue_cutoff_reconciliation/)). Order-date versus delivery-date revenue. FY2025-26 overstated by ₹1.11 crore; ₹1.07 crore open at the 30 Sep 2026 half-year end.
- **Baseline revenue forecast with backtesting** ([05_advanced_analytics/04_revenue_forecast_baseline](05_advanced_analytics/04_revenue_forecast_baseline/)). Five methods backtested on Jan–Sep 2026. Q4 2026 forecast of ₹11.10 crore (range ₹9.15 – ₹13.04 crore).

### Changed
- **Customer revenue risk, version 2** ([01_customer_and_revenue/01_customer_revenue_risk](01_customer_and_revenue/01_customer_revenue_risk/)). Added `analysis_v2.sql` and `validation_v2.sql`, which resolve all four known issues listed on 2026-10-11. Findings published: 23 customers generate 50.7 % of revenue. The original `analysis.sql` is kept unchanged.
- `metric_definitions.md`: revenue share confirmed; added cumulative share, category penetration, promise standard, cut-off and forecast accuracy metrics.
- `README.md`, `GUIDE.md` and the category indexes updated. All 20 case studies are now complete.

---

## 2026-10-20

### Added
- **Price-volume-mix analysis** ([02_sales_and_profitability/03_price_volume_mix](02_sales_and_profitability/03_price_volume_mix/)). Splits the ₹8.71 crore year-to-date growth into price (+₹1.36 crore), volume (+₹5.08 crore) and mix (+₹2.27 crore). This answers the price-versus-volume question left open by the revenue growth bridge.
- **Dispatch workload and capacity planning** ([03_operations_and_supply_chain/04_dispatch_workload_planning](03_operations_and_supply_chain/04_dispatch_workload_planning/)). Weekday and monthly workload, capacity at normal, busy and peak levels, and a test of whether heavy order intake slows dispatch. It does not.
- **RFM customer segmentation** ([05_advanced_analytics/03_rfm_customer_segmentation](05_advanced_analytics/03_rfm_customer_segmentation/)). Eight behaviour segments. 103 Champions hold 78.4 % of 12-month revenue, and 17 "Cannot lose" accounts have gone quiet.
- `CHANGELOG.md` (this file).

### Changed
- `metric_definitions.md`: added price-volume-mix, RFM, backlog, workload and de-duplication metrics, and extended the case study key.
- `README.md`, `GUIDE.md` and the category indexes now list the new case studies.

---

## 2026-10-19

### Added
- **Revenue growth bridge** ([01_customer_and_revenue/03_revenue_growth_bridge](01_customer_and_revenue/03_revenue_growth_bridge/)). Year-to-date growth of 38.7 %, split by new, growing, declining and lost customers, and by order count versus order size.
- **Salesperson performance scorecard** ([02_sales_and_profitability/02_salesperson_scorecard](02_sales_and_profitability/02_salesperson_scorecard/)). A balanced ranking across revenue, margin, discount, cancellations, on-time delivery and collection.
- **Customer payment behaviour and credit terms** ([05_advanced_analytics/02_customer_payment_behaviour](05_advanced_analytics/02_customer_payment_behaviour/)). Days to pay by segment, cash tied up, and a credit terms scenario worth ₹88.2 lakh.
- **Open order backlog review** ([03_operations_and_supply_chain/03_open_order_backlog_review](03_operations_and_supply_chain/03_open_order_backlog_review/)). Month-end review of 103 open orders. Finds delivered orders never closed and shipments stuck in transit.
- **Customer master de-duplication** ([04_data_quality_and_reconciliation/03_customer_master_deduplication](04_data_quality_and_reconciliation/03_customer_master_deduplication/)). Name normalisation, match confidence and a reviewable master mapping table.

### Changed
- `metric_definitions.md`: draft metrics confirmed against the case studies that use them, with a "Used in" column and a case study key.
- `schema.md`: the duplicate-customer profiling note now reflects the de-duplication results (6 high-confidence pairs, 6 for review).

---

## 2026-10-16

### Added
- **Customer churn early warning** ([01_customer_and_revenue/02_customer_churn_early_warning](01_customer_and_revenue/02_customer_churn_early_warning/))
- **Discount and margin erosion** ([02_sales_and_profitability/01_discount_margin_erosion](02_sales_and_profitability/01_discount_margin_erosion/))
- **Freight cost-to-serve and minimum order value** ([03_operations_and_supply_chain/02_freight_cost_to_serve](03_operations_and_supply_chain/02_freight_cost_to_serve/))
- **Data quality scorecard** ([04_data_quality_and_reconciliation/02_data_quality_scorecard](04_data_quality_and_reconciliation/02_data_quality_scorecard/)), with 29 rules across 5 quality dimensions
- **ABC-XYZ product classification** ([05_advanced_analytics/01_abc_xyz_product_classification](05_advanced_analytics/01_abc_xyz_product_classification/))

### Changed
- `GUIDE.md` now lists the tables each case study creates.

---

## 2026-10-15

### Added
- **Order-to-cash reconciliation** ([04_data_quality_and_reconciliation/01_order_to_cash_reconciliation](04_data_quality_and_reconciliation/01_order_to_cash_reconciliation/)). Payment-status reconciliation and receivables ageing.
- **Late delivery root cause** ([03_operations_and_supply_chain/01_late_delivery_root_cause](03_operations_and_supply_chain/01_late_delivery_root_cause/)). An exact split of days late into dispatch, transit and promise, plus a city name mapping table.
- `GUIDE.md`: getting-started guide covering repository layout, how to read a case study, how to run the SQL in BigQuery, conventions and a glossary.

### Fixed
- `schema.md`: the "possible duplicate transactions" note was resolved. The 24 matching order headers have different line items, so they are separate orders. The 7 repeated payments are true duplicates.
- `schema.md`: recorded the evidence for treating a missing discount as 0 %.

---

## 2026-10-11

### Added
- **Customer revenue risk, version 1** ([01_customer_and_revenue/01_customer_revenue_risk](01_customer_and_revenue/01_customer_revenue_risk/)). Original analysis query with its documentation. Findings are held back until version 2.
- README banner and badges.

### Known issues (planned for version 2 of Customer revenue risk)
- Missing discounts make line revenue NULL, so it drops out of totals.
- Cancelled and returned orders are counted in revenue.
- The cumulative revenue share (Pareto) view is missing.
- The table name is written as `Sales_Orders`; BigQuery table names are case-sensitive.

---

## 2026-10-10

### Added
- Repository created with five problem categories and a documentation folder.
- `README.md`: project overview, analytical approach and structure.
- `datasets_and_documentation/schema.md`: tables, keys, relationships and profiling notes for the `sahyadri_b2b` dataset.
- `datasets_and_documentation/metric_definitions.md`: draft shared metric definitions.
- Case study documentation template.
