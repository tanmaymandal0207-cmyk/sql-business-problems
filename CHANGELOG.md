# Changelog

All notable changes to this repository are recorded here, newest first. Dates are in `YYYY-MM-DD` format.

Each entry lists case studies **added**, existing documents **changed**, and **fixes** to earlier work. A case study is listed as added only when its SQL, validation checks and findings are all in place.

---

## 2026-10-25

### Added
- **Revenue concentration trend** ([01_customer_and_revenue/08_revenue_concentration_trend](01_customer_and_revenue/08_revenue_concentration_trend/)). Quarterly and rolling 12-month HHI, effective customers and Gini. Concentration fell to 162 HHI points in March 2026 and rose to 200 by September. The Q3 2026 spike (one customer at 18.4 %) halves without its single largest order. Distributors are the most concentrated segment, with about 13 effective customers.
- **Reactivated customers** ([01_customer_and_revenue/09_reactivated_customers](01_customer_and_revenue/09_reactivated_customers/)). 230 returns after 180+ days of silence, now about twice as many as new customers. Returners buy 23 % more than before they lapsed but are fragile: 75.9 % reorder within 180 days, against 97.5 % after a regular repeat order.
- **Salesperson ramp-up** ([02_sales_and_profitability/09_salesperson_ramp_up](02_sales_and_profitability/09_salesperson_ramp_up/)). Every new joiner placed a first order after 30–32 days and was at peer level from month 3, because 85–99 % of their revenue came from handed-over customers. Plan for the September 2026 joiners: about ₹1.06 crore each in six months.
- **Split shipment drivers** ([03_operations_and_supply_chain/10_split_shipment_drivers](03_operations_and_supply_chain/10_split_shipment_drivers/)). No single-line order is ever split, and no category, size, segment or product drives splits beyond chance. The first part is on time as often as a single shipment; the second part makes splits a quarter of all late orders.
- **Ship-to vs bill-to reconciliation** ([04_data_quality_and_reconciliation/08_ship_to_bill_to_reconciliation](04_data_quality_and_reconciliation/08_ship_to_bill_to_reconciliation/)). 447 of 1,020 raw city mismatches are naming only; seven master records cause 204 of them. 224 shipments go to another state, mostly one-off destinations for tax review. Three missing customer cities can be filled from delivery history.
- **Cost of a late delivery** ([05_advanced_analytics/09_cost_of_late_delivery](05_advanced_analytics/09_cost_of_late_delivery/)). Within the same customer, lateness has no effect on reorder (the pooled 2.8-point gap is customer mix) but delays payment by 6.4 days (paired t = 5.8). The financing cost is about ₹1.4 lakh a year.
- **Customer momentum** ([05_advanced_analytics/10_customer_momentum](05_advanced_analytics/10_customer_momentum/)). Per-customer regression slopes with t-statistics and an out-of-sample back-test. Only 13 of 251 customers have a significant trend; growing customers kept growing, but declining customers recovered (+49.5 %). Recent revenue level predicts next year far better (ρ = 0.77) than trend (ρ = 0.12).

### Changed
- `metric_definitions.md`: added HHI, effective customers, Gini, reactivation, ramp index, product lift z-score, ship-to match types, within-customer (paired) difference and regression momentum definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 46 case studies are now complete.

---

## 2026-10-24

### Added
- **Customer lifetime value** ([01_customer_and_revenue/07_customer_lifetime_value](01_customer_and_revenue/07_customer_lifetime_value/)). Retention-based CLV with Laplace smoothing and confidence intervals. The base is worth ₹20.71 crore of margin over five years. One-order customers retain at 36 % against 94 % for repeat buyers, so a second order is worth about ₹9,800.
- **Market basket affinity with significance testing** ([02_sales_and_profitability/08_market_basket_affinity](02_sales_and_profitability/08_market_basket_affinity/)). Chi-square tests with Bonferroni correction. Of 411 product pairs, 68 look significant uncorrected but only 2 survive, and 1 is actionable.
- **Safety stock and reorder points** ([03_operations_and_supply_chain/08_safety_stock_reorder_points](03_operations_and_supply_chain/08_safety_stock_reorder_points/)). Service-level safety stock with lead-time variance, EOQ and a backtest. ₹3.25 crore of safety stock; ABC service levels save ₹20.8 lakh against a uniform 98 %. Regular products hit target once demand growth is allowed for, and 66 % of products are too lumpy for the method.
- **Statistical process control** ([03_operations_and_supply_chain/09_statistical_process_control](03_operations_and_supply_chain/09_statistical_process_control/)). p-charts with Western Electric rules. Both processes are stable: a simple target rule raised 61 alarms where SPC found none on the bad side. The only signal is a 10-week improvement in mid-2026.
- **Benford's law forensic test** ([04_data_quality_and_reconciliation/07_benford_forensic_test](04_data_quality_and_reconciliation/07_benford_forensic_test/)). All three amount populations conform closely. Subgroup testing exposes 543 "RTGS" receipts below the ₹2 lakh RTGS minimum (₹3.71 crore), which points to a mislabelled payment method.
- **Time-to-reorder survival analysis** ([05_advanced_analytics/07_time_to_reorder_survival](05_advanced_analytics/07_time_to_reorder_survival/)). Kaplan–Meier curves with censoring and Greenwood intervals. After 90 days of silence, 76 % of customers still return within six months, and the tipping point is about 270 days.
- **Customer state transitions (Markov chain)** ([05_advanced_analytics/08_customer_state_markov](05_advanced_analytics/08_customer_state_markov/)). A quarterly transition matrix projected with a BigQuery `WHILE` loop, with an out-of-time backtest and a win-back scenario worth about ₹1 crore a year.

### Changed
- `metric_definitions.md`: added CLV, survival, Markov, safety stock, control chart, Benford and chi-square definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 39 case studies are now complete.

---

## 2026-10-23

### Added
- **Regional performance and market coverage** ([01_customer_and_revenue/06_regional_performance](01_customer_and_revenue/06_regional_performance/)). The West earns 31 % of revenue and delivered 46 % of growth, but mostly through two accounts. Central is flat, and East and North have the lowest on-time delivery. 12 states depend on one customer for over 40 % of revenue.
- **Discount consistency and price leakage** ([02_sales_and_profitability/06_discount_consistency](02_sales_and_profitability/06_discount_consistency/)). Discounts are set by segment, not volume (correlation 0.64 overall, −0.10 to 0.18 within segments). Leakage beyond the segment band is small: ₹5.04 lakh, 1.3 % of discount.
- **Period-end sales push** ([02_sales_and_profitability/07_period_end_sales_push](02_sales_and_profitability/07_period_end_sales_push/)). No month-end order rush or routine discount creep. Year-end deals closed at 15 % and delivered in April, and quarter-end orders cancel more often (7.1 % against 4.5 %, z = 2.5).
- **Shipment consolidation opportunity** ([03_operations_and_supply_chain/07_shipment_consolidation](03_operations_and_supply_chain/07_shipment_consolidation/)). A fixed charge of ₹957 per shipment is estimated by regression in SQL. Twice-weekly dispatch would avoid 13.5 % of shipments and save ₹5.3 lakh a year, with less than a day's average wait.
- **Order anomaly screen** ([04_data_quality_and_reconciliation/06_order_anomaly_screen](04_data_quality_and_reconciliation/06_order_anomaly_screen/)). Four robust rules flag 307 orders. Most are genuine large orders, but the screen points to the ₹31 lakh order behind the largest overdue balance.
- **Replenishment reorder reminders** ([05_advanced_analytics/06_reorder_reminders](05_advanced_analytics/06_reorder_reminders/)). Product-level reorder cycles with a point-in-time backtest: due pairs were 1.37 times as likely to reorder, and 73 % of reorders were anticipated. 182 pairs worth ₹52 lakh are overdue.

### Changed
- `metric_definitions.md`: added regional, discount band, period-end, freight model, anomaly and reorder metrics, and z-test and lift definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 32 case studies are now complete.

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
