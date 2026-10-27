# Changelog

All notable changes to this repository are recorded here, newest first. Dates are in `YYYY-MM-DD` format.

Each entry lists case studies **added**, existing documents **changed**, and **fixes** to earlier work. A case study is listed as added only when its SQL, validation checks and findings are all in place.

---

## 2026-10-28

### Added
- **Key-account selection and regression to the mean** ([01_customer_and_revenue/14_key_account_regression_to_mean](01_customer_and_revenue/14_key_account_regression_to_mean/)). In both year pairs the top decile grew least (−8.8 % against +18.3 % for the rest; +27.6 % against +37.6 %); log-log slopes 0.68 and 0.80. Last year's revenue still picks the best key-account list (52.4 % of next year's revenue against 58.3 % with hindsight), but uniform targets leave key accounts short.
- **Sales commission plan simulation** ([02_sales_and_profitability/14_commission_plan_simulation](02_sales_and_profitability/14_commission_plan_simulation/)). Four budget-neutral plans (₹77.47 lakh) on 12 months of orders. Revenue and GP plans pay similar people similar amounts, but the GP plan makes a ₹100 discount cost the salesperson ₹13 instead of ₹2. Last-year quotas reward weak prior years.
- **Weekend and holiday postings test** ([04_data_quality_and_reconciliation/14_weekend_holiday_postings](04_data_quality_and_reconciliation/14_weekend_holiday_postings/)). Order dates follow the six-day business calendar; dispatch dates are "order date + N calendar days" (chi-square 6.6), and 413 cheque and DD receipts worth ₹2.49 crore are dated on Sundays or national holidays.
- **Logistic regression churn model** ([05_advanced_analytics/18_logistic_regression_churn](05_advanced_analytics/18_logistic_regression_churn/)). Gradient descent in a BigQuery `WHILE` loop, converged to a gradient below 0.0001. Test AUC 0.932 against 0.926 for the activity score, with 86 % of churners in the riskiest fifth against 77 %. Order count does almost all the work; the test year under-forecast losses by 13 % because single-order churn rose.
- **Empirical Bayes for operational rates** ([03_operations_and_supply_chain/14_empirical_bayes_rates](03_operations_and_supply_chain/14_empirical_bayes_rates/)). Cancellations by customer, salesperson and product and returns by city show no real variation; every customer's credible cancellation rate is the 5.4 % average. Late delivery varies for real, mostly by destination: seven cities are reliably worse.

### Changed
- `metric_definitions.md`: added budget-neutral commission rate, annualised quota, log-log persistence slope, logistic churn probability, weekday number, calendar-blind expectation, heterogeneity Q and τ², and credible rate definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 74 case studies are now complete.

---

## 2026-10-27

### Added
- **Cross-sell stickiness** ([01_customer_and_revenue/13_cross_sell_stickiness](01_customer_and_revenue/13_cross_sell_stickiness/)). 946 category trials by existing customers, indirectly standardised for ordering frequency. Valves & Fittings and Industrial Safety Equipment repeat 30 % more often than expected; Power Transmission 17 % less. Capital categories still bring large follow-on value. 28 recent sticky trials have not repeated.
- **January price increase and price discipline** ([02_sales_and_profitability/12_price_increase_and_price_discipline](02_sales_and_profitability/12_price_increase_and_price_discipline/)). The +5.55 % and +5.32 % increases reached all 186 products on 1 January and customers did not buy ahead in December. Invoice prices are spread evenly within ±3 % of the list (₹77.9 lakh below, ₹80.7 lakh above), with no customer, salesperson or product pattern.
- **Salesperson ranking stability** ([02_sales_and_profitability/13_salesperson_ranking_stability](02_sales_and_profitability/13_salesperson_ranking_stability/)). A 500-replicate cluster bootstrap of the scorecard. Only 19 of 120 pairs can be told apart on the balanced rank; the top-ranked salesperson could be 1st to 11th. Cancellation rate and overdue receivable % separate fewer than 8 % of pairs; one bottom result is robust.
- **Key-account service equity** ([03_operations_and_supply_chain/13_key_account_service_equity](03_operations_and_supply_chain/13_key_account_service_equity/)). Enterprise on-time of 86.9 % against 79.0 % comes from promises 3 days longer, not faster service: against a common city standard both are 81 %, and dispatch speed is identical.
- **Order-to-cash process mining** ([04_data_quality_and_reconciliation/12_order_to_cash_process_mining](04_data_quality_and_reconciliation/12_order_to_cash_process_mining/)). A 40,565-event log with 43 variants, 8 of which cover 95 % of orders. Fulfilment takes 8–9 days and cash 45; three instalments double the time to cash. Advance payment is applied only to SMB and some Distributors. 24 orders show true process errors.
- **Data drift monitoring** ([04_data_quality_and_reconciliation/13_data_drift_monitoring](04_data_quality_and_reconciliation/13_data_drift_monitoring/)). PSI with an order-based noise test for 15 fields over 21 months. Only three fields alert, all explained (price increase, two immature status fields); line-level testing would have raised 8 false alarms. Thresholds by monitoring period are given.
- **Collaborative filtering vs best sellers** ([05_advanced_analytics/16_collaborative_filtering_recommender](05_advanced_analytics/16_collaborative_filtering_recommender/)). An item-based recommender built and back-tested in SQL scores 31.7 % precision@5 against 33.8 % for a simple best-seller gap list (random: 8.3 %). Purchase structure beyond popularity is too weak for personalisation to help.
- **Monte Carlo collections forecast** ([05_advanced_analytics/17_monte_carlo_collections_forecast](05_advanced_analytics/17_monte_carlo_collections_forecast/)). A two-level bootstrap over 28 month-end snapshots. Back-test error 5.3 %, range coverage 11 of 15. Nothing older than 180 days is ever collected: 46 % of the ₹10.96 crore book. Central 90-day forecast ₹4.54 crore.

### Changed
- `metric_definitions.md`: added indirect standardisation (O/E), price factor and price deviation, bootstrap rank interval and distinguishable pair, common service standard, event log, variant and fully paid date, PSI and its noise test, cosine similarity and precision@K, and Monte Carlo range and coverage definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 69 case studies are now complete.

---

## 2026-10-26 (second batch)

### Added
- **Customer health score** ([01_customer_and_revenue/12_customer_health_score](01_customer_and_revenue/12_customer_health_score/)). A point-in-time back-test of seven churn signals with AUC computed in SQL. Late deliveries, unpaid invoices and cancellations rank customers backwards (AUC 0.32–0.39) because they measure activity. A three-signal activity score (AUC 0.886) catches 69 % of leavers in its bottom fifth, against 48 % for the proposed seven-signal score.
- **Gross margin bridge** ([02_sales_and_profitability/11_gross_margin_bridge](02_sales_and_profitability/11_gross_margin_bridge/)). An exact product × segment bridge: margin rose from ₹3.03 to ₹6.21 crore and from 10.0 % to 15.5 %, two thirds from list price. With one current unit cost, supplier inflation of 6.2 % would cancel the whole price effect.
- **Warehouse slotting by pick frequency** ([03_operations_and_supply_chain/12_warehouse_slotting](03_operations_and_supply_chain/12_warehouse_slotting/)). Only 45 of 90 pick-A products are revenue-A. Slotting by picks instead of revenue cuts walking by about 13 % under the stated zone model; 80 products change zone.
- **Monetary unit sampling for the receivables audit** ([04_data_quality_and_reconciliation/10_monetary_unit_sampling](04_data_quality_and_reconciliation/10_monetary_unit_sampling/)). PPS sample design, selection and Poisson evaluation in SQL, re-drawn with 20 random starts. Three Unpaid-but-paid orders (₹4.37 lakh) give a 36.5 % chance that the sample rejects; the upper limit covered the truth in 20 of 20 samples.
- **Order splitting test** ([04_data_quality_and_reconciliation/11_order_splitting_test](04_data_quality_and_reconciliation/11_order_splitting_test/)). A pre-policy baseline: no bunching below round amounts, and fewer same-day orders than chance predicts. One large same-product, same-day pair at the financial year end is listed for review.
- **k-means customer segmentation** ([05_advanced_analytics/13_kmeans_customer_segmentation](05_advanced_analytics/13_kmeans_customer_segmentation/)). k-means written as a BigQuery `WHILE` loop finds four behaviour groups that explain 70 % of behavioural variation, against 45 % for the official segments. Distributor and Enterprise behave alike; Mid-Market and SMB overlap.
- **Intermittent demand forecasting** ([05_advanced_analytics/14_intermittent_demand_forecasting](05_advanced_analytics/14_intermittent_demand_forecasting/)). Croston and SBA in closed form with a rolling-origin back-test. 85 % of products are lumpy or intermittent weekly; Croston or SBA is best for 171 of 186 products, but SBA under-forecasts by 7.8 % while demand grows.
- **Late payment scorecard** ([05_advanced_analytics/15_late_payment_scorecard](05_advanced_analytics/15_late_payment_scorecard/)). Weight of evidence and information value with a time-based hold-out. Segment alone (test AUC 0.743) beats the five-characteristic scorecard (0.730): customer history adds nothing within a segment. Enterprise orders are 67 % late and 59 % of late orders.

### Changed
- `metric_definitions.md`: added AUC, activity score, margin bridge effects, pick ABC and travel model, MUS design and evaluation, bunching ratio, coincidence model, k-means and R², ADI / CV² and Croston / SBA, WoE and IV definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 61 case studies are now complete.

---

## 2026-10-26

### Added
- **Industry vertical scorecard** ([01_customer_and_revenue/10_industry_vertical_scorecard](01_customer_and_revenue/10_industry_vertical_scorecard/)). Growth, margin, retention and payment speed for 15 industry groups. Several industries' growth rests on one customer (Textiles turns from +17.4 % to −7.5 % without it), and industry margins are within 2 points of what segment mix predicts. Construction is the only industry with broad, fast growth.
- **Net and gross revenue retention** ([01_customer_and_revenue/11_net_revenue_retention](01_customer_and_revenue/11_net_revenue_retention/)). Rolling NRR rose from 102.7 % to 126.6 % in 2026, but GRR is 77–85 %, constant-price NRR was below 100 % until mid-2026, and NRR is 111.8 % without the top five expanders. The leak is contraction, not churn.
- **Sales force cost efficiency** ([02_sales_and_profitability/10_sales_force_cost_efficiency](02_sales_and_profitability/10_sales_force_cost_efficiency/)). The team returns ₹3.3 of gross profit per rupee of salary; executives 4.9, managers 3.4. Four people are below a 3.0 break-even, and pay correlates only 0.47 with gross profit.
- **Dispatch holds** ([03_operations_and_supply_chain/11_dispatch_holds](03_operations_and_supply_chain/11_dispatch_holds/)). 11.7 % of orders wait 7–22 days before dispatch in a flat, separate queue. Holds are not linked to credit, order size, segment, salesperson or customer, but cause 51.7 % of late orders; releasing them normally would cut the late rate from 18.3 % to 10.0 %.
- **Freight invoice audit** ([04_data_quality_and_reconciliation/09_freight_invoice_audit](04_data_quality_and_reconciliation/09_freight_invoice_audit/)). Rate cards inferred by regression (fixed charge by destination + about 0.6 % of value) explain about 98 % of charges. 99 % of charges are within ±15 %; no rate creep; very large consignments appear capped at about ₹25,000; ₹3.38 lakh of freight is probably unrecorded.
- **Does discount buy volume?** ([05_advanced_analytics/11_discount_volume_response](05_advanced_analytics/11_discount_volume_response/)). Pooled, one discount point goes with 5.9 % more units; within the same customer and product, only 0.97 %. Break-even needs 10.5 %, so each extra point costs about 8.6 % of line gross profit.
- **Category breadth and retention** ([05_advanced_analytics/12_category_breadth_retention](05_advanced_analytics/12_category_breadth_retention/)). The raw 36-point retention gap shrinks to +6.4 points (z = 2.59) once purchase frequency is held constant, and the effect is concentrated in occasional buyers (+13.7 points for one-order customers).

### Changed
- `metric_definitions.md`: added industry, mix-expected margin, NRR, GRR, constant-price NRR, GP return, dispatch hold, over-dispersion, inferred rate card, fixed-effects slope, break-even response and Mantel–Haenszel definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 53 case studies are now complete.
- The freight invoice audit reuses `city_alias_map` with `CREATE TABLE IF NOT EXISTS`, so it does not overwrite the table created by the ship-to vs bill-to reconciliation.

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
