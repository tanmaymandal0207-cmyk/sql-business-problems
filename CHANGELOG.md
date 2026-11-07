# Changelog

All notable changes to this repository are recorded here, newest first. Dates are in `YYYY-MM-DD` format.

Each entry lists case studies **added**, existing documents **changed**, and **fixes** to earlier work. A case study is listed as added only when its SQL, validation checks and findings are all in place.

---

## 2026-11-07

### Added
- **KPI revisions after month-end** ([04_data_quality_and_reconciliation/18_kpi_revisions_after_month_end](04_data_quality_and_reconciliation/18_kpi_revisions_after_month_end/)). In all 18 months the board pack overstated on-time delivery (by 1.62 points on average) and understated delivery time (by 1.07 days), because orders not yet delivered were left out. Those 2 % of orders were all late. Dividing by all orders promised in the month gives the final figure exactly on the 5th.
- **Price ladders** ([02_sales_and_profitability/23_price_ladders](02_sales_and_profitability/23_price_ladders/)). Size read from product names builds 12 ladders (60 products, 27.2 % of revenue). Only 3 of 36 inner rungs are over 10 % off their neighbours, all too cheap; raising the 1-inch SS316 ball valve, UCP207 pillow block and 6205 bearing is worth about ₹17 lakh a year. Carbide end mills list below cost at both ends of their ladder.
- **E-way bill exposure** ([03_operations_and_supply_chain/22_eway_bill_exposure](03_operations_and_supply_chain/22_eway_bill_exposure/)). Half of all shipments (89 % of value) need a GST e-way bill, about 6 a day. About one in ten deliveries would arrive after the bill expired (8.8–11.3 % across distance assumptions), mostly on one-day lanes: 61 % of Pune bills.
- **Customer dropout (BG/NBD)** ([05_advanced_analytics/32_customer_dropout_bgnbd](05_advanced_analytics/32_customer_dropout_bgnbd/)). A BG/NBD model fitted in SQL finds no customers leaving for good: every level of dropout fits worse than none. The no-dropout model predicted 252 buyers next quarter against 251. Customers flagged as silent ordered at the same rate as the rest (77.1 % against 77.2 %).
- **DSO formula comparison** ([04_data_quality_and_reconciliation/19_dso_formula_comparison](04_data_quality_and_reconciliation/19_dso_formula_comparison/)). The pack's one-month DSO moves against the month's sales (correlation −0.87); May 2026's 41-day jump was a quiet month after two big ones. Countback DSO moves at most 12 days a month. No DSO shows the real problem: the average age of receivables rose from 94 to 289 days.

### Changed
- `metric_definitions.md`: added as-of on-time rate, fixed on-time rate and KPI revision, product family, ladder slope and neighbour price, e-way bill requirement, validity and outlived bill, BG/NBD dropout profile and NBD purchase chance, countback DSO, current-invoice DSO and average age of receivables definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 119 case studies are now complete.

---

## 2026-11-06

### Added
- **Large-order pull-forward** ([01_customer_and_revenue/22_large_order_pull_forward](01_customer_and_revenue/22_large_order_pull_forward/)). After an order of ₹5 lakh or more, the customer's regular ordering dips 8–10 % for one to two months, then recovers. Against 400 placebo date sets, only the 60-day window reaches p < 0.05, and not on a common event set. At most about 8 % of a large order is borrowed from the next two months.
- **Annual rate contracts** ([02_sales_and_profitability/22_annual_rate_contracts](02_sales_and_profitability/22_annual_rate_contracts/)). Half of revenue sits in customer-category pairs bought in 9+ of 11 quarters, against 8.8 % at product level. A commitment of 50 % of last year's value was met by about 82 % of qualifying pairs in both back-tests. 221 contracts with 60 customers would cover ₹20.01 crore and commit ₹10 crore.
- **Freight zone audit** ([03_operations_and_supply_chain/21_freight_zone_audit](03_operations_and_supply_chain/21_freight_zone_audit/)). The carrier charges six regional zones (₹361 to ₹1,498) plus 0.611 % of value, explaining 97.9 % of charges. Hubballi, Hyderabad and Jaipur sit 20–46 % above a distance benchmark, but the six flagged lanes cost only ₹0.39 lakh a year extra. A 0.1-point cut in the value rate is worth ₹3.64 lakh.
- **Quiet categories** ([01_customer_and_revenue/23_quiet_categories](01_customer_and_revenue/23_quiet_categories/)). 3.6 % of established customer-category pairs go quiet for three quarters while the customer keeps ordering, against 2.4 % expected by chance (z = 4.0). 81 % come back within two quarters; hydraulics, motors and pumps go quiet most.
- **FY target Monte Carlo** ([05_advanced_analytics/30_fy_target_monte_carlo](05_advanced_analytics/30_fy_target_monte_carlo/)). An order-level simulation of October 2026 – March 2027 gives a median FY 2026-27 of ₹44.45 crore if order sizes fall back and ₹50.78 crore if the 25 % jump holds. ₹40 crore is safe, ₹45 crore is reached in 69 % of pooled runs. Count-only growth was within 2 % from June in the FY 2025-26 back-test but missed April – September 2026 by 23 %.
- **Order size extreme value** ([05_advanced_analytics/31_order_size_extreme_value](05_advanced_analytics/31_order_size_extreme_value/)). Orders above ₹5 lakh follow a generalised Pareto with shape 0.625 (bootstrap 0.46–0.70). The size exceeded once a month is ₹11.6 lakh, once a quarter ₹21.4 lakh, once a year ₹48.5 lakh. A 2024–2025 fit expected 0.1 orders above ₹1 crore in 2026; there were 2.

### Changed
- `metric_definitions.md`: added pull-forward relative change and placebo p-value, rate-contract qualification and safe commitment, freight zone and distance benchmark, quiet spell and chance rate, compound Poisson FY simulation and back-test percentile, and GPD shape, scale and return level definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 114 case studies are now complete.

---

## 2026-11-05

### Added
- **Industry diversification** ([01_customer_and_revenue/21_industry_diversification](01_customer_and_revenue/21_industry_diversification/)). The 15 industries' monthly swings largely cancel (diversification ratio 2.09; the company is no more volatile than 500 independent shuffles). Industrial Distribution adds risk in line with its 36.6 % share. "Unknown" (4.1 % of revenue, 18.1 % of the swing) and Steel & Metals add more; General Engineering steadies revenue. Volatility follows top-customer concentration (correlation +0.61).
- **Early-payment discount** ([02_sales_and_profitability/21_early_payment_discount](02_sales_and_profitability/21_early_payment_discount/)). "2/10 net 60" implies about 15 % a year against a 12 % cost of money. It loses ₹16.8 lakh a year if every slower order switches, and only orders paid after day 71 gain. 1/10 breaks even at 13 % uptake and suits Enterprise (no early payers today). SMB customers already pay at day 10.
- **Six-day dispatch week** ([03_operations_and_supply_chain/20_six_day_dispatch_week](03_operations_and_supply_chain/20_six_day_dispatch_week/)). Sunday carries 15.2 % of dispatch but only 55 orders arrive on Sundays. Deadline-first dispatch at 14 a day on six days meets every deadline: the same 84 order slots a week as 12 × 7. First-in-first-out would need 18.
- **Working-day adjustment** ([05_advanced_analytics/29_working_day_adjustment](05_advanced_analytics/29_working_day_adjustment/)). A Sunday brings 0.09 of an average day and a Saturday about half; months differ by up to 14.5 % in trading days. The calendar explains about 8 % of month-on-month variation (slope 0.94 out of sample) and flips the sign of 1 of 32 changes. February is the one month where it is the story.

### Changed
- `metric_definitions.md`: added industry swing, risk contribution, diversification ratio, early-payment break-even day and uptake, six-day window capacity, working-day FIFO departures, weekday weight and trading-day index definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 108 case studies are now complete.

---

## 2026-11-02

### Added
- **Overdue balances and ordering** ([01_customer_and_revenue/20_overdue_balances_and_ordering](01_customer_and_revenue/20_overdue_balances_and_ordering/)). In overdue months customers place 1.49 orders a month against 0.43, but that compares big customers with small ones. For the same customer at the same recent activity, the difference is +0.011 orders (p = 0.71 over 500 relabellings). Collections can be firm without costing orders.
- **Discount creep** ([02_sales_and_profitability/20_discount_creep](02_sales_and_profitability/20_discount_creep/)). Discount rises from 4.9 % on first orders to 7.0 % after the 30th, but the same customer's discount moves +0.06 points a year (p = 0.22). Segment sets the discount. A "no creep" cap would net −₹1.8 lakh.
- **Second dispatch hub** ([03_operations_and_supply_chain/19_second_dispatch_hub](03_operations_and_supply_chain/19_second_dispatch_hub/)). The data place the warehouse in the Mumbai–Pune area. A Kanpur hub would cut 1.16 transit days per shipment and late deliveries from 730 to 598 a year, but would save only about ₹7 lakh of outbound freight.
- **Data quality materiality** ([04_data_quality_and_reconciliation/17_data_quality_materiality](04_data_quality_and_reconciliation/17_data_quality_materiality/)). Five of ten board KPIs move materially: NULL discounts take ₹53 lakh off revenue, missing promise dates cost 1.5 points of on-time delivery, unassigned orders leave the league table 3.1 % short, and city spellings cut Bengaluru revenue by a fifth.
- **Salesperson handover difference in differences** ([05_advanced_analytics/27_salesperson_handover_did](05_advanced_analytics/27_salesperson_handover_did/)). The raw −6.9 % against +15.6 % becomes a matched effect of −12.3 % with p = 0.28. The changed accounts had grown faster just before (+18.5 % pre-trend). Handovers to new hires were close to neutral (−2.6 %).
- **Conformal forecast intervals** ([05_advanced_analytics/28_conformal_forecast_intervals](05_advanced_analytics/28_conformal_forecast_intervals/)). The normal ± 1.28 SD range covers 82 % but is exceeded 13.3 % of the time (meant to be 10 %), because errors are skewed. A pooled conformal range is exceeded 10.1 % of the time; the product's own errors suit intermittent items.

### Changed
- `metric_definitions.md`: added overdue month, activity-matched within-customer difference, within-customer discount slope, haversine distance, transit curve, hub saving, materiality test, handover effect, pre-trend effect, MA6 forecast and conformal range definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 104 case studies are now complete.

---

## 2026-11-01

### Added
- **Who drives the March peak?** ([01_customer_and_revenue/19_march_peak_drivers](01_customer_and_revenue/19_march_peak_drivers/)). March runs 61–78 % above the surrounding months, split about evenly between more customers, more orders each and bigger orders. Every segment and industry joins in equally (chi-square 2.6 against 7.8 needed). The customers who order extra change every year: the year-on-year correlation is 0.07, and 2025 spikers repeat at the base rate.
- **Product profitability after cost to serve** ([02_sales_and_profitability/18_product_cost_to_serve](02_sales_and_profitability/18_product_cost_to_serve/)). ₹4.49 crore of gross profit becomes ₹1.36 crore of operating contribution in FY 2025–26, and −₹1.03 crore after credit losses. 94 of 183 products lose money before credit loss (6 on gross profit). Low margin and small lines drive losses; two carbide end mills are listed below cost. Credit loss does not persist by product (split-half correlation 0.01).
- **Salesperson workload balancing** ([02_sales_and_profitability/19_salesperson_workload_balancing](02_sales_and_profitability/19_salesperson_workload_balancing/)). Workloads range from 77 to 451 orders; busy months do not raise cancellations. 14 greedy moves, each to a salesperson the customer already knows, cut the coefficient of variation from 0.41 to 0.15 and bring 11 of 15 salespeople within ±15 %. Three more moves would bring 14 of 15.
- **Dispatch by deadline** ([03_operations_and_supply_chain/18_deadline_based_dispatch](03_operations_and_supply_chain/18_deadline_based_dispatch/)). Hall's condition over 66,961 windows: deadline-first dispatch meets every deadline at 12 orders a day, where FIFO needs 17. A seasonal plan of 12 (October–March) and 10 (April–September) also works. Today 13.2 % of deadlines are missed, and tight and loose orders wait the same 4 days.
- **Month-end revenue nowcast** ([05_advanced_analytics/25_month_end_revenue_nowcast](05_advanced_analytics/25_month_end_revenue_nowcast/)). Back-tested on 30 months: booked-so-far plus the prior beats the 3-month prior from day 1. The weekday run-rate leads from day 8, with a mean error of 12.3 % on day 15. Large orders cause about half of the error, and March is back-loaded (29 % of its revenue comes after the 25th).
- **Time to cash with Kaplan–Meier** ([05_advanced_analytics/26_time_to_cash_kaplan_meier](05_advanced_analytics/26_time_to_cash_kaplan_meier/)). Counting 1,419 unsettled orders as censored moves the median from 45 to 51 days and the average within the first year from 47 to 81 days. 10.3 % of orders are still unsettled at 180 days, in every segment. Paid-only figures make the latest deliveries look 17 days faster.

### Changed
- `metric_definitions.md`: added uplift share, expected March orders, operating contribution, rupee-day credit cost, split-half reliability, account owner, workload band, known contact, dispatch deadline, EDF feasibility ratio, weekday run-rate, nowcast blend, Kaplan–Meier time to cash and restricted mean definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 98 case studies are now complete.
- Dispatch by deadline links the [queue discipline](03_operations_and_supply_chain/15_dispatch_queue_discipline/) study's FIFO recommendation to a deadline-sorted pick list.

---

## 2026-10-31

### Added
- **Order frequency vs order size** ([01_customer_and_revenue/18_order_frequency_vs_size](01_customer_and_revenue/18_order_frequency_vs_size/)). Frequent buyers place bigger orders (correlation +0.29, mostly segment); within customers the gap before an order does not change its size (p = 0.89 over 500 shuffles); a 10 % rise in orders came with orders about 1.1 % smaller, so most extra frequency is extra revenue.
- **Price elasticity from a natural experiment** ([02_sales_and_profitability/17_price_elasticity_natural_experiment](02_sales_and_profitability/17_price_elasticity_natural_experiment/)). The random ±3 % invoice-price deviations pass every balance check; units respond with an elasticity of −0.26 (95 % interval −0.84 to +0.32) and repeat purchase is unaffected. Billing below-list lines at list would add about ₹20 lakh a year, and still gains at the worst end of the interval.
- **Dispatch capacity simulation** ([03_operations_and_supply_chain/17_dispatch_capacity_simulation](03_operations_and_supply_chain/17_dispatch_capacity_simulation/)). An exact FIFO queue in SQL for 11–20 orders a day: capacity is not today's constraint (up to 29 shipped in a day; 13 a day would average 0.9 days against 2.65 actual for non-held orders). 2027 needs about 16 a day, plus help in March–April; ending holds beyond six days meets the 3.4-day target alone.
- **Missing data mechanism** ([04_data_quality_and_reconciliation/16_missing_data_mechanism](04_data_quality_and_reconciliation/16_missing_data_mechanism/)). 29 chi-square tests across six fields: no gap is systematic at 1 %; delivery date is structural for all 55 shipments in transit (10 delivered shipments lack a date). Missing salespeople leave ₹3.94 crore (4.3 %) of revenue unattributed.
- **Pilot design: power and CUPED** ([05_advanced_analytics/23_pilot_design_power_cuped](05_advanced_analytics/23_pilot_design_power_cuped/)). A 3-month revenue pilot on 180 vs 180 customers could only detect a 115 % uplift; the 10 largest customers carry 92 % of the variance. Six months, orders and CUPED bring the MDE to 16.9 %; a 10 % answer needs about 500 customers per arm. 500 A/A splits per design confirm the formulas.
- **Revenue at risk from churn** ([05_advanced_analytics/24_revenue_at_risk_churn_simulation](05_advanced_analytics/24_revenue_at_risk_churn_simulation/)). 2,000 simulated years: expected loss ₹45.3 lakh, 95 % ₹96.2 lakh (3.1 % of the nine-month base), 99 % ₹188.2 lakh. The 2025 forecast put the actual loss (₹24.6 lakh) at its 46th percentile. No customer with four or more orders has churned.

### Changed
- `metric_definitions.md`: added within-customer size slope, frequency elasticity of order size, price deviation elasticity, FIFO cumulative departures, chi-square missingness test, minimum detectable effect, CUPED, A/A false-alarm rate, smoothed churn probability and revenue at risk definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 92 case studies are now complete.

---

## 2026-10-30

### Added
- **Gateway categories** ([01_customer_and_revenue/16_gateway_categories](01_customer_and_revenue/16_gateway_categories/)). Raw first-year revenue ranges from ₹2.5 to ₹14.8 lakh by first-order category, but with segment and first-order size held constant no category differs from chance (1,000 stratified shuffles, p = 0.33–0.83). First-order size predicts value: median first-year revenue ₹5.81 lakh in the top third against ₹0.71 lakh in the bottom third.
- **Customer credit limits** ([01_customer_and_revenue/17_customer_credit_limits](01_customer_and_revenue/17_customer_credit_limits/)). 83 % of 2026 orders come from customers with a balance unpaid for more than 90 days. Five rules back-tested on 2,100 orders: an overdue hold blocks 81.5 % of orders to catch 94 % of losses (lift 1.11), history limits do worse than random (0.80), and the best signal, past losses, has a lift of 1.40 and catches 6.9 %.
- **Revenue volatility drivers** ([02_sales_and_profitability/15_revenue_volatility_drivers](02_sales_and_profitability/15_revenue_volatility_drivers/)). Trend and the March (+63 %) and December (+29 %) peaks explain 72 % of monthly variance; the remaining 13.7 % swing is no larger than the 15.4 % chance alone produces with orders this uneven. 2 % of orders (₹5 lakh+) carry 21.9 % of revenue and explain about half of the big misses.
- **Salesperson category specialisation** ([02_sales_and_profitability/16_salesperson_category_specialisation](02_sales_and_profitability/16_salesperson_category_specialisation/)). Every salesperson's category mix matches random allocation of orders (team p = 0.26; 0.65 within customers), and focus does not bring lower discounts. 75 % of customers, with 98 % of revenue, buy from all three proposed product lines.
- **Little's Law backlog planning** ([03_operations_and_supply_chain/16_littles_law_backlog_planning](03_operations_and_supply_chain/16_littles_law_backlog_planning/)). L = λW holds within 2 % for the dispatch queue every year; the in-transit stage only holds once 63 never-closed shipments (oldest 997 days, 15.6 % of transit days) are removed. 2027 at today's speed: 52 orders waiting on an average day; dispatch must fall from 4.0 to 3.4 days to hold today's level.
- **Hierarchical forecast reconciliation** ([05_advanced_analytics/21_hierarchical_forecast_reconciliation](05_advanced_analytics/21_hierarchical_forecast_reconciliation/)). Exponential smoothing in SQL for 10 categories and the total over 21 months: the combined forecast is best at the total (18.0 % MAPE), top-down wins at category level (25.5 % WAPE) only because Pumps' tuned model over-fitted large orders.
- **Order timing regularity** ([05_advanced_analytics/22_order_timing_regularity](05_advanced_analytics/22_order_timing_regularity/)). 217 of 256 frequent customers order at random times (CV 0.91 against 0.92 for random histories); being "due" does not raise the chance of an order, but ordering rate predicts it within 5 points. 26 regular customers (twice chance) do follow a cycle: 66 % just after an order, 84 % when due.

### Changed
- `metric_definitions.md`: added gateway category, stratified permutation effect, credit exposure, old unpaid balance, lift vs random, revenue identity and variance split, irreducible swing, specialisation index, Little's Law stage count, smoothing forecast and top-down share, gap CV and the random-ordering prediction.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 86 case studies are now complete.

---

## 2026-10-29

### Added
- **Revenue driver tree** ([01_customer_and_revenue/15_revenue_driver_tree](01_customer_and_revenue/15_revenue_driver_tree/)). An exact LMDI decomposition of January–September revenue into five drivers. Customers × frequency added about ₹4 crore in both years; basket value swung from −₹203 lakh in 2025 to +₹430 lakh in 2026, driven by product mix (−8.1 %, +8.0 %) rather than the +5.4 % price increases. Lines per order stayed at 2.8.
- **Dispatch queue discipline** ([03_operations_and_supply_chain/15_dispatch_queue_discipline](03_operations_and_supply_chain/15_dispatch_queue_discipline/)). 638,635 order pairs: an order placed a day earlier is dispatched later 27.0 % of the time, exactly what random timing gives (26.9 %), and no segment jumps the queue. Strict FIFO at the same daily capacity would cut the longest wait from 22 to 7 days and late deliveries by 17 %.
- **Cash application matching** ([04_data_quality_and_reconciliation/15_cash_application_matching](04_data_quality_and_reconciliation/15_cash_application_matching/)). Two exact rules match 74.5 % of 10,568 receipts (85.7 % of value) from customer, date and amount alone, with no wrong matches. Every failure is a part payment, a short payment or one of the 7 duplicates; an invoice reference on part payments would raise the rate to 98.2 %. Defaulting to the oldest invoice would be wrong 85 % of the time.
- **Expected credit loss provision** ([05_advanced_analytics/19_expected_credit_loss_provision](05_advanced_analytics/19_expected_credit_loss_provision/)). A roll-rate matrix on calendar-month buckets: nothing is collected after bucket 6, and new invoices carry a 7.6 % loss rate (SMB 16.8 %). Provision at 30 Sep 2026 ₹6.22 crore (56.7 % of the book), of which ₹5.08 crore is already in default. In a 15-month back-test, all history to date beat a trailing 12-month window (mean absolute error 6.1 % against 13.4 % from July 2025).
- **KPI change-point detection** ([05_advanced_analytics/20_kpi_change_point_detection](05_advanced_analytics/20_kpi_change_point_detection/)). Exhaustive one- and two-shift search with BIC and a 500-permutation test on 10 monthly KPIs. The method finds the January 2025 and 2026 price steps exactly; orders and customers grow steadily (17.1 % and 13.8 % a year); discount, cancellation, return and late rates and dispatch lag have never changed, and their monthly swings are binomial noise.

### Changed
- `metric_definitions.md`: added driver tree, LMDI-I effect, overtaken pair, FIFO dispatch slot, cash application rule, open balance before a receipt, calendar-month age bucket, roll rate, loss rate and ECL provision, change-point BIC, shift permutation p-value and binomial dispersion test definitions.
- `README.md`, `GUIDE.md` (tables created and new glossary terms) and the category indexes updated. 79 case studies are now complete.

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
