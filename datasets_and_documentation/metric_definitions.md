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
| LV | [Customer lifetime value](../01_customer_and_revenue/07_customer_lifetime_value/) |
| MB | [Market basket affinity](../02_sales_and_profitability/08_market_basket_affinity/) |
| SS | [Safety stock and reorder points](../03_operations_and_supply_chain/08_safety_stock_reorder_points/) |
| PC | [Statistical process control](../03_operations_and_supply_chain/09_statistical_process_control/) |
| BF | [Benford's law forensic test](../04_data_quality_and_reconciliation/07_benford_forensic_test/) |
| KM | [Time-to-reorder survival analysis](../05_advanced_analytics/07_time_to_reorder_survival/) |
| MK | [Customer state transitions (Markov chain)](../05_advanced_analytics/08_customer_state_markov/) |
| CT | [Revenue concentration trend](../01_customer_and_revenue/08_revenue_concentration_trend/) |
| RA | [Reactivated customers](../01_customer_and_revenue/09_reactivated_customers/) |
| RU | [Salesperson ramp-up](../02_sales_and_profitability/09_salesperson_ramp_up/) |
| SD | [Split shipment drivers](../03_operations_and_supply_chain/10_split_shipment_drivers/) |
| ST | [Ship-to vs bill-to reconciliation](../04_data_quality_and_reconciliation/08_ship_to_bill_to_reconciliation/) |
| LC | [Cost of a late delivery](../05_advanced_analytics/09_cost_of_late_delivery/) |
| MO | [Customer momentum](../05_advanced_analytics/10_customer_momentum/) |
| IV | [Industry vertical scorecard](../01_customer_and_revenue/10_industry_vertical_scorecard/) |
| NR | [Net and gross revenue retention](../01_customer_and_revenue/11_net_revenue_retention/) |
| SE | [Sales force cost efficiency](../02_sales_and_profitability/10_sales_force_cost_efficiency/) |
| DH | [Dispatch holds](../03_operations_and_supply_chain/11_dispatch_holds/) |
| FA | [Freight invoice audit](../04_data_quality_and_reconciliation/09_freight_invoice_audit/) |
| DV | [Does discount buy volume?](../05_advanced_analytics/11_discount_volume_response/) |
| CB | [Category breadth and retention](../05_advanced_analytics/12_category_breadth_retention/) |
| HS | [Customer health score](../01_customer_and_revenue/12_customer_health_score/) |
| MG | [Gross margin bridge](../02_sales_and_profitability/11_gross_margin_bridge/) |
| SL | [Warehouse slotting](../03_operations_and_supply_chain/12_warehouse_slotting/) |
| MU | [Monetary unit sampling](../04_data_quality_and_reconciliation/10_monetary_unit_sampling/) |
| OS | [Order splitting test](../04_data_quality_and_reconciliation/11_order_splitting_test/) |
| KC | [k-means customer segmentation](../05_advanced_analytics/13_kmeans_customer_segmentation/) |
| ID | [Intermittent demand forecasting](../05_advanced_analytics/14_intermittent_demand_forecasting/) |
| LP | [Late payment scorecard](../05_advanced_analytics/15_late_payment_scorecard/) |
| XS | [Cross-sell stickiness](../01_customer_and_revenue/13_cross_sell_stickiness/) |
| PI | [January price increase and price discipline](../02_sales_and_profitability/12_price_increase_and_price_discipline/) |
| RS | [Salesperson ranking stability](../02_sales_and_profitability/13_salesperson_ranking_stability/) |
| KA | [Key-account service equity](../03_operations_and_supply_chain/13_key_account_service_equity/) |
| PM | [Order-to-cash process mining](../04_data_quality_and_reconciliation/12_order_to_cash_process_mining/) |
| DD | [Data drift monitoring](../04_data_quality_and_reconciliation/13_data_drift_monitoring/) |
| CF | [Collaborative filtering recommender](../05_advanced_analytics/16_collaborative_filtering_recommender/) |
| MC | [Monte Carlo collections forecast](../05_advanced_analytics/17_monte_carlo_collections_forecast/) |
| KR | [Key-account selection and regression to the mean](../01_customer_and_revenue/14_key_account_regression_to_mean/) |
| CM | [Sales commission plan simulation](../02_sales_and_profitability/14_commission_plan_simulation/) |
| WH | [Weekend and holiday postings test](../04_data_quality_and_reconciliation/14_weekend_holiday_postings/) |
| LR | [Logistic regression churn model](../05_advanced_analytics/18_logistic_regression_churn/) |
| EB | [Empirical Bayes for operational rates](../03_operations_and_supply_chain/14_empirical_bayes_rates/) |
| DT | [Revenue driver tree](../01_customer_and_revenue/15_revenue_driver_tree/) |
| FQ | [Dispatch queue discipline](../03_operations_and_supply_chain/15_dispatch_queue_discipline/) |
| CA | [Cash application matching](../04_data_quality_and_reconciliation/15_cash_application_matching/) |
| EC | [Expected credit loss provision](../05_advanced_analytics/19_expected_credit_loss_provision/) |
| CP | [KPI change-point detection](../05_advanced_analytics/20_kpi_change_point_detection/) |
| GW | [Gateway categories](../01_customer_and_revenue/16_gateway_categories/) |
| LM | [Customer credit limits](../01_customer_and_revenue/17_customer_credit_limits/) |
| RV | [Revenue volatility drivers](../02_sales_and_profitability/15_revenue_volatility_drivers/) |
| CS | [Salesperson category specialisation](../02_sales_and_profitability/16_salesperson_category_specialisation/) |
| LL | [Little's Law backlog planning](../03_operations_and_supply_chain/16_littles_law_backlog_planning/) |
| HF | [Hierarchical forecast reconciliation](../05_advanced_analytics/21_hierarchical_forecast_reconciliation/) |
| OT | [Order timing regularity](../05_advanced_analytics/22_order_timing_regularity/) |
| FS | [Order frequency vs order size](../01_customer_and_revenue/18_order_frequency_vs_size/) |
| EL | [Price elasticity natural experiment](../02_sales_and_profitability/17_price_elasticity_natural_experiment/) |
| CQ | [Dispatch capacity simulation](../03_operations_and_supply_chain/17_dispatch_capacity_simulation/) |
| NM | [Missing data mechanism](../04_data_quality_and_reconciliation/16_missing_data_mechanism/) |
| PD | [Pilot design: power analysis and CUPED](../05_advanced_analytics/23_pilot_design_power_cuped/) |
| VR | [Revenue at risk from churn](../05_advanced_analytics/24_revenue_at_risk_churn_simulation/) |
| MR | [Who drives the March peak?](../01_customer_and_revenue/19_march_peak_drivers/) |
| PP | [Product profitability after cost to serve](../02_sales_and_profitability/18_product_cost_to_serve/) |
| WL | [Salesperson workload balancing](../02_sales_and_profitability/19_salesperson_workload_balancing/) |
| ED | [Dispatch by deadline](../03_operations_and_supply_chain/18_deadline_based_dispatch/) |
| NW | [Month-end revenue nowcast](../05_advanced_analytics/25_month_end_revenue_nowcast/) |
| TK | [Time to cash with Kaplan–Meier](../05_advanced_analytics/26_time_to_cash_kaplan_meier/) |
| OV | [Overdue balances and ordering](../01_customer_and_revenue/20_overdue_balances_and_ordering/) |
| DK | [Discount creep](../02_sales_and_profitability/20_discount_creep/) |
| HB | [Second dispatch hub](../03_operations_and_supply_chain/19_second_dispatch_hub/) |
| MQ | [Data quality materiality](../04_data_quality_and_reconciliation/17_data_quality_materiality/) |
| HO | [Salesperson handover difference in differences](../05_advanced_analytics/27_salesperson_handover_did/) |
| CI | [Conformal forecast intervals](../05_advanced_analytics/28_conformal_forecast_intervals/) |
| VD | [Industry diversification](../01_customer_and_revenue/21_industry_diversification/) |
| EP | [Early-payment discount](../02_sales_and_profitability/21_early_payment_discount/) |
| SW | [Six-day dispatch week](../03_operations_and_supply_chain/20_six_day_dispatch_week/) |
| WD | [Working-day adjustment](../05_advanced_analytics/29_working_day_adjustment/) |
| LO | [Do large orders steal next quarter's demand?](../01_customer_and_revenue/22_large_order_pull_forward/) |
| AC | [Annual rate contracts](../02_sales_and_profitability/22_annual_rate_contracts/) |
| FZ | [Freight zone audit](../03_operations_and_supply_chain/21_freight_zone_audit/) |
| QC | [Quiet categories](../01_customer_and_revenue/23_quiet_categories/) |
| FT | [Will we hit the full-year target?](../05_advanced_analytics/30_fy_target_monte_carlo/) |
| XV | [How big can one order get?](../05_advanced_analytics/31_order_size_extreme_value/) |
| KV | [KPI revisions after month-end](../04_data_quality_and_reconciliation/18_kpi_revisions_after_month_end/) |
| PL | [Price ladders](../02_sales_and_profitability/23_price_ladders/) |
| EW | [E-way bill exposure](../03_operations_and_supply_chain/22_eway_bill_exposure/) |
| BT | [Are silent customers lost? (BG/NBD)](../05_advanced_analytics/32_customer_dropout_bgnbd/) |
| DF | [Which DSO should the board see?](../04_data_quality_and_reconciliation/19_dso_formula_comparison/) |

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
| Price factor | Median of unit_price ÷ selling_price in a calendar year; list in force = selling_price × factor | Year | Confirmed | PI, DD |
| Price deviation | unit_price ÷ list in force − 1 (invoice price before discount) | Order line | Confirmed | PI |
| Budget-neutral commission rate | Plan rate solved so that total payout = 2 % of team net revenue (e.g. GP plan rate = budget ÷ team GP) | Plan | Confirmed | CM |
| Quota (annualised) | Prior-12-month revenue × 12 ÷ months employed × 1.10 | Salesperson | Confirmed | CM |
| Discount band | Segment median effective discount ± 2 points; excess = discount beyond the band | Customer | Confirmed | DC |
| Month position | Last 5 days, first 5 days or mid-month of the order date | Order | Confirmed | PE |
| Driver tree | Revenue = customers × orders per customer × lines per order × units per line × revenue per unit | Company or segment × year | Confirmed | DT |
| LMDI-I effect | L(R₁, R₀) × ln(x₁ ÷ x₀), L(a, b) = (a − b) ÷ (ln a − ln b); the effects add up exactly to R₁ − R₀ | Driver × period | Confirmed | DT |
| Revenue identity and variance split | ln R = ln N + ln S (orders × average order value); var(swing R) = var(swing N) + var(swing S) + 2 cov, where swing = ln y − (trend + March and December effects) | Month | Confirmed | RV |
| Irreducible swing | √(1 ÷ N + s²), s = SD of ln average order value over 300 random redraws of the month's N orders from the same year | Month | Confirmed | RV |
| Specialisation index | 0.5 × Σ \|salesperson's category revenue share − company share\|, compared with shuffles of salesperson labels across orders and within customers | Salesperson | Confirmed | CS |
| Price deviation elasticity | Slope of ln(quantity) on ln(invoice ÷ list in force), both centred within product × year | Order line | Confirmed | EL |
| Uplift share | Log change of one driver (active customers, orders per customer, average order value) ÷ log change in revenue, March against the January–June baseline months; the three shares add to 100 % | Year | Confirmed | MR |
| Expected March orders | (March + baseline orders of the group) × all March orders ÷ all orders, for the 2 × k homogeneity test | Group | Confirmed | MR |
| Account owner | The field salesperson with the most orders on the account in the window (ties: latest order, then lowest ID) | Customer | Confirmed | WL |
| Workload band | Average workload (orders on owned accounts) ± 15 % | Salesperson | Confirmed | WL |
| Known contact | A salesperson who booked at least one order for the customer in the previous 24 months | Customer × salesperson | Confirmed | WL |
| Rate-contract qualifying pair | A customer-category pair bought in all 4 quarters of the year, worth ₹2 lakh or more | Customer × category | Confirmed | AC |
| Safe commitment level | The highest share of last year's value (5-point steps) met the following year by 80 %+ of qualifying pairs in every back-test | Rule | Confirmed | AC |

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
| Mix-expected margin | Σ segment costed revenue × company margin % of that segment; margin vs mix = actual − expected | Industry | Confirmed | IV |
| GP return | Gross profit ÷ salary cost (salary pro-rated from hire date) | Salesperson | Confirmed | SE |
| Cost of sales | Salary cost ÷ revenue | Salesperson / role | Confirmed | SE |
| Margin bridge effects | Product × segment cells, m = P (1 − d) − c: volume = Δ total units × prior margin per unit; mix = Σ Δq × m₀ − volume; price = Σ q₁ (P₁ − P₀)(1 − d₀); discount = Σ q₁ P₁ (d₀ − d₁); new and lost cells separate. Effects sum exactly to the continuing-cell margin change; both periods use current unit cost | Product × segment | Confirmed | MG |
| Operating contribution (product) | Gross profit − freight (by value) − handling and sales effort (per order, split equally by line) − cost of credit, before credit loss | Product | Confirmed | PP |
| Split-half reliability | Correlation of a product's rate in April–September with the same rate in October–March; near 0 means the rate is not a property of the product | Product | Confirmed | PP |
| Within-customer discount slope | Σ (years since first order − customer mean) × (order discount − customer mean) ÷ Σ (years − customer mean)², points a year; tested by 500 shuffles of discounts within customer | Customer pool | Confirmed | DK |

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
| Annual retention | Share of one year's active customers who buy again the next year; Laplace-smoothed (retained + 1) ÷ (n + 2) | Frequency band | Confirmed | LV |
| Customer lifetime value | Annual margin × Σₜ₌₁…₅ (r ÷ (1 + d))ᵗ, d = 12 % | Customer | Confirmed | LV |
| Survival S(t) | Kaplan–Meier probability of no reorder by day t, with right-censoring | Segment | Confirmed | KM |
| Customer state | High, Low, Silent 1–3 quarters, Lost, by quarter | Customer × quarter | Confirmed | MK |
| Transition probability | Transitions from state i to j ÷ all transitions from i | State pair | Confirmed | MK |
| HHI | Σ sᵢ² over customer revenue shares in the period; reported × 10,000 as points | Period | Confirmed | CT |
| Effective customers | 1 ÷ HHI: number of equal-sized customers giving the same concentration | Period | Confirmed | CT |
| Gini coefficient | 2 Σ(i · xᵢ) ÷ (n Σxᵢ) − (n + 1) ÷ n, customers sorted ascending | Period | Confirmed | CT |
| Return (reactivation) | An order placed more than 180 days after the customer's previous in-scope order | Order | Confirmed | RA |
| Stayed after return | Another in-scope order within 180 days of the return order; returns observed for 180 days only | Return | Confirmed | RA |
| Revenue momentum | Least-squares slope of zero-filled monthly revenue, `COVAR_POP(x, y) / VAR_POP(x)`; trend % = slope × 12 ÷ mean month | Customer × 12 months | Confirmed | MO |
| Momentum class | Growing if slope t ≥ 2, Declining if t ≤ −2, t = r √(n − 2) ÷ √(1 − r²); fewer than 3 active months not classified | Customer × 12 months | Confirmed | MO |
| NRR | Σ current 12-month revenue of base customers ÷ Σ their base 12-month revenue (year before) | Quarter end | Confirmed | NR |
| GRR | Σ LEAST(base, current) ÷ Σ base = 1 − (churn + contraction) ÷ base | Quarter end | Confirmed | NR |
| Constant-price NRR | NRR on quantity × list price × (1 − discount %), removing price increases | Quarter end | Confirmed | NR |
| Category breadth | Distinct product categories bought in a half-year | Customer × half-year | Confirmed | CB |
| Activity score | Average of recency, frequency and category-breadth percentile points (0–100, 100 = healthiest) at a snapshot date | Customer × snapshot | Confirmed | HS |
| k-means cluster | Nearest of k = 4 centroids on five standardised behaviour features, iterated to a fixed point | Customer | Confirmed | KC |
| Grouping R² | 1 − within-group sum of squares ÷ total sum of squares on standardised features | Grouping | Confirmed | KC |
| Cross-sell trial | A customer's first purchase of a category, 90+ days after its first order; repeat = another order of the category within 365 days | Customer × category | Confirmed | XS |
| Observed ÷ expected (indirect standardisation) | Observed count ÷ Σ over members of the rate of their stratum (e.g. ordering-frequency band) | Group | Confirmed | XS |
| Log-log persistence slope | Least-squares slope of ln(revenue year 2) on ln(revenue year 1); below 1 = regression to the mean | Customer pair | Confirmed | KR |
| Churn probability (logistic) | 1 ÷ (1 + e^−(b₀ + Σ bⱼxⱼ)) on standardised point-in-time features, fitted by gradient descent | Customer × snapshot | Confirmed | LR |
| Gateway category | The category with the largest net value on a customer's first valid order | Customer | Confirmed | GW |
| Stratified permutation effect | Category mean of (outcome − segment × size-cell mean), tested against 1,000 shuffles of labels within cells | Category | Confirmed | GW |
| Gap CV and random benchmark | SD ÷ mean of gaps between a customer's order days, against 200 histories with the same orders at random positions between first and last order | Customer | Confirmed | OT |
| Random-ordering prediction | 1 − e^(−30 ÷ average gap so far): chance of an order in 30 days if the customer orders at random at its usual rate | Customer × month-end | Confirmed | OT |
| Within-customer size slope | Slope of (ln order value − customer mean) on (ln(1 + days since previous order) − customer mean), tested by shuffling values within customers | Order | Confirmed | FS |
| Frequency elasticity of order size | Slope of Δ ln(average order size) on Δ ln(orders) between consecutive years | Customer | Confirmed | FS |
| Smoothed churn probability | (churners + 0.5) ÷ (customers + 1) in the frequency band at the previous snapshot | Band × snapshot | Confirmed | VR |
| Revenue at risk | 95th / 99th percentile of simulated revenue lost (exposure of customers that churn), 2,000 independent-churn scenarios | Snapshot | Confirmed | VR |
| Overdue month | At the start of the month the customer has a valid, fully delivered order delivered 90+ days earlier with under 99 % of its value received | Customer × month | Confirmed | OV |
| Activity-matched within-customer difference | Orders in overdue months − orders in clear months, both as deviations from the customer's mean within its band of orders in the previous six months; tested by 500 within-cell relabellings | Customer × activity band | Confirmed | OV |
| Handover effect | Treated-weighted average over cells (event quarter × segment × size third) of mean log growth of customers whose main salesperson changed − mean of those who kept theirs | Event quarter cohort | Confirmed | HO |
| Pre-trend effect | The handover effect estimator applied to growth from the first to the second half of the year before the change | Event quarter cohort | Confirmed | HO |
| Industry swing | Monthly revenue of an industry − its own least-squares straight-line trend | Industry × month | Confirmed | VD |
| Risk contribution | Cov(industry swing, company swing) ÷ Var(company swing); shares add up to 100 % | Industry | Confirmed | VD |
| Diversification ratio | Σ industry swing standard deviations ÷ company swing standard deviation | Company | Confirmed | VD |
| Pull-forward relative change | (Customer's base revenue W days after ÷ W days before a ₹5 lakh+ order) ÷ (the same ratio for all other customers over the same days), pooled over events | Window | Confirmed | LO |
| Placebo p-value (event study) | Share of 400 sets of random dates for the same customers with a relative change at or below the actual one | Window | Confirmed | LO |
| Quiet spell | An established pair (bought in 3+ of the prior 4 quarters, including the last) not bought for 3 quarters while the customer kept ordering | Customer × category × quarter | Confirmed | QC |
| Chance quiet rate | (1 − p)³, p = share of the customer's active quarters in which the pair bought the category | Customer × category | Confirmed | QC |
| BG/NBD dropout profile | Best log-likelihood with the mean dropout chance per purchase m = a ÷ (a + b) held fixed, against m = 0 (NBD); gamma ratios as sums of logs over k | Model | Confirmed | BT |
| NBD chance of a purchase | 1 − ((α + T) ÷ (α + T + t))^(r + x); expected purchases = (r + x) ÷ (α + T) × t | Customer × window | Confirmed | BT |

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
| Late payment (60-day) | Order not fully paid within 60 days of final delivery | Order | Confirmed | LP |
| Weight of evidence | ln(share of on-time in bin ÷ share of late in bin), 0.5 added to counts; points = ROUND(28.85 × WoE) | Characteristic bin | Confirmed | LP |
| Information value | Σ (share on-time − share late) × WoE; < 0.02 not useful, 0.02–0.10 weak, 0.10–0.30 medium, > 0.30 strong | Characteristic | Confirmed | LP |
| Fully paid date | Date of the payment that takes cumulative receipts to the order value (within ₹0.05) | Order | Confirmed | PM, MC |
| Collected share (h days) | Payments in the next h days ÷ outstanding at the snapshot, capped at 100 % | Open item × month-end | Confirmed | MC |
| Cash application rule | R1 amount = full value of exactly one open invoice; R2 no invoice fits and amount = open balance of exactly one; else ambiguous or no match (tolerance ₹0.05) | Receipt | Confirmed | CA |
| Open balance before a receipt | Order value − payments on the order dated earlier (same date: lower payment id) | Receipt × open invoice | Confirmed | CA |
| Age bucket (calendar months) | Year × 12 + month of the month-end − the same for the delivery date, capped at 6 | Open item × month-end | Confirmed | EC |
| Roll rate | Balance still open one month later ÷ balance in the bucket | Bucket × reporting date | Confirmed | EC |
| Loss rate and ECL provision | Loss rate = product of roll rates from the bucket to bucket 5 (bucket 6+ = 100 %); provision = outstanding × loss rate | Open item × reporting date | Confirmed | EC |
| Credit exposure at an order | Earlier valid orders' value − payments on them up to the order date + the new order | Order | Confirmed | LM |
| Lift vs random (credit rule) | (losses caught ÷ good business blocked) ÷ (all losses ÷ all good business) | Rule | Confirmed | LM |
| Rupee-day cost of credit | (Σ payments × days from final delivery to payment + balance unpaid at 180 days × days to day 180) × 12 % ÷ 365 | Order line | Confirmed | PP |
| Kaplan–Meier time to cash | S(t) = Π over days u ≤ t of (1 − orders settled on day u ÷ orders still waiting); settled = payments reach 99 % of value; open orders censored at the as-of date | Group | Confirmed | TK |
| Restricted mean time to cash | Σ S(t) for t = 0 … 364: average days to cash within the first year, an unpaid order counting 365 | Group | Confirmed | TK |
| Early-payment break-even day | 10 + discount × 365 ÷ cost of money: a switch to day-10 payment gains only for orders otherwise paid after this day | Discount level | Confirmed | EP |
| Break-even uptake | Windfall on orders already paid within 10 days ÷ net gain if every slower settled order switched | Segment × discount | Confirmed | EP |
| Countback DSO | Receivables matched against the most recent months' sales, month by month back; DSO = days of months used up + remainder ÷ that month's sales × its days | Month-end | Confirmed | DF |
| Current-invoice DSO | Countback DSO on receivables up to 90 days old | Month-end | Confirmed | DF |
| Average age of receivables | Open-amount-weighted days since invoice date | Month-end | Confirmed | DF |

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
| Split order | Order with two shipment rows (none has more than two) | Order | Confirmed | SD |
| First / final part late | First or last shipment's delivery after the promised date | Order | Confirmed | SD, LC |
| Extra freight per split | Average freight of split minus single-shipment orders with the same line count | Line-count band | Confirmed | SD |
| Shipments avoided | Shipments − dispatches needed when shipments to a destination are combined by schedule | Schedule | Confirmed | SC |
| Safety stock | z × √(L × s² + d² × σL²), weekly demand mean d and std dev s, lead time L | Product | Confirmed | SS |
| Reorder point | d × L + safety stock | Product | Confirmed | SS |
| p-chart limits | p̄ ± 3 √(p̄ (1 − p̄) ÷ n), with Western Electric rules R1, R2, R4 | Week | Confirmed | PC |
| Dispatch days | First shipment date − order date; held order = 7+ days | Order | Confirmed | DH |
| Inferred rate card | Per destination: freight = fixed charge + variable rate × consignment value, least squares on single-shipment orders up to ₹10 lakh; pooled card for cities with < 30 | City | Confirmed | FA |
| Freight variance % | (charged − card) ÷ card; ±15 % tolerance | Shipment | Confirmed | FA |
| Pick ABC | Products ranked by pick lines (order lines): A first 80 % of picks, B next 15 %, C last 5 % | Product | Confirmed | SL |
| Pick travel | Picks × 2 × zone distance; zones hold the top 20 %, next 30 % and remaining products at 10, 25 and 45 m (parameters) | Product | Confirmed | SL |
| Common service standard | 80th percentile of lead time (order to final delivery) in the destination city, the same for every customer | City | Confirmed | KA |
| Lead time vs city | Lead time − average lead time of all orders to the same city | Order | Confirmed | KA |
| Weekday number | MOD(DATE_DIFF(date, DATE '1900-01-07', DAY), 7): 0 = Sunday … 6 = Saturday | Date | Confirmed | WH |
| Overtaken pair | Two orders placed 1–7 days apart where the earlier is dispatched on a later date; expected if random = P(L₁ − L₂ > gap) | Order pair | Confirmed | FQ |
| FIFO dispatch slot | The k-th earliest order receives the k-th earliest actual dispatch date (never before its order date) | Order | Confirmed | FQ |
| Little's Law stage count | Daily number in a stage = entries to date − exits to date; average over a period = entries per day × average days in stage (up to boundary effects) | Stage × day | Confirmed | LL |
| FIFO cumulative departures | D(t) = MIN over s ≤ t of [A(s) + c × (t − s)]; order k ships on the first day with D(t) ≥ k | Day × capacity | Confirmed | CQ |
| Dispatch deadline | Promised delivery date − median transit to the standardised shipping city (pre-window history, 20+ orders), never before the order date | Order | Confirmed | ED |
| EDF feasibility ratio | Orders arriving on or after day s and due by day t ÷ (t − s + 1); the least capacity meeting every deadline is the largest ratio rounded up | Window of days | Confirmed | ED |
| Haversine distance | 2 × 6,371 × asin(√(sin²(Δlat/2) + cos lat₁ cos lat₂ sin²(Δlon/2))) km between city centres | City pair | Confirmed | HB |
| Transit curve | Average transit days by 250 km band from the inferred origin, made non-decreasing | Distance band | Confirmed | HB |
| Hub transit saving | Curve(km from origin) − curve(km from the nearer of origin and hub) per shipment | Shipment × hub | Confirmed | HB |
| Six-day window capacity | Orders arriving on or after day s and due by day t (Sunday deadlines moved to Saturday) ÷ working days in [s, t] | Window of days | Confirmed | SW |
| Working-day FIFO departures | D(t) = c W(t) + MIN(0, running MIN of A(s) − c W(s)), W = working days to date | Day × capacity | Confirmed | SW |
| Freight value rate | Within-destination slope of freight charge on shipment value (consignments under ₹20 lakh) | Card | Confirmed | FZ |
| Freight zone | Destinations sorted by fixed charge (charge − value rate × value, averaged); a new zone starts at a jump of ₹50 or more | Destination | Confirmed | FZ |
| Freight distance benchmark | Shipment-weighted least squares of destination fixed charge on km from the origin; flagged if 15 % and ₹100 above | Destination | Confirmed | FZ |
| E-way bill required | Consignment value incl. GST (assumed 18 %) above ₹50,000 inter-state or ₹1 lakh within Maharashtra | Shipment | Confirmed | EW |
| E-way bill validity | MAX(1, CEIL(road km ÷ 200)) days, road km = haversine km × road factor; outlived if transit days exceed it | Shipment | Confirmed | EW |

## Product and demand

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Monthly demand | Quantity on in-scope orders by order month, zero-filled | Product × month | Confirmed | AX |
| Coefficient of variation | Standard deviation ÷ mean of monthly demand | Product | Confirmed | AX |
| ABC class | Cumulative revenue share: A first 80 %, B next 15 %, C last 5 % | Product | Confirmed | AX, SR |
| Cancellation rate | Cancelled orders ÷ closed orders (Delivered, Cancelled, Returned) | Any | Confirmed | CL |
| ADI / CV² | Weeks ÷ weeks with demand; squared coefficient of variation of non-zero weekly demand. Pattern cut-offs 1.32 and 0.49 (Syntetos–Boylan) | Product | Confirmed | ID |
| Croston / SBA forecast | Smoothed demand size ÷ smoothed interval, updated only in weeks with demand (α = 0.1); SBA = (1 − α/2) × Croston | Product × week | Confirmed | ID |
| WAPE | Σ \|forecast − actual\| ÷ Σ actual | Method | Confirmed | ID |
| MA6 forecast | Average units of the previous 6 months, zero months included | Product × month | Confirmed | CI |
| Conformal 80 % range | MA6 + [smallest, largest] of the product's previous 12 errors (own), or MA6 + (MA6 + 1) × [10th, 90th percentile] of all products' scaled errors (pooled) | Product × month | Confirmed | CI |
| Product family (ladder) | Products whose names match once numbers are masked, 3+ members; bearing series kept apart | Family | Confirmed | PL |
| Ladder slope | Least-squares slope of ln(list price) on ln(size) within a family | Family | Confirmed | PL |
| Neighbour price | Log-log interpolation of list price between the next smaller and next larger size; out of line if more than 10 % off | Product | Confirmed | PL |

## Revenue recognition and forecasting

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Cut-off difference | Order-date revenue − delivery-date revenue for a period | Month / financial year | Confirmed | RC |
| Month-end exposure | Revenue ordered on or before a date but delivered after it | Date | Confirmed | RC |
| MAPE | Mean of \|forecast − actual\| ÷ actual across test months | Method | Confirmed | FB |
| Forecast bias | Mean of (forecast − actual) ÷ actual; negative = under-forecast | Method | Confirmed | FB |
| Monte Carlo range | P10–P90 of simulated totals; coverage = share of back-tests whose actual falls inside | Forecast | Confirmed | MC |
| Precision@K | Hits among the top K recommendations ÷ K, averaged over customers; hit = bought in the test period | Method | Confirmed | CF |
| Exponential smoothing forecast | F(t) = α y(t−1) + (1 − α) F(t−1), F(2) = y(1); α from 0.1–0.9 chosen on 2024 | Series × month | Confirmed | HF |
| Top-down category forecast | Total forecast × the category's share of the previous 12 months; combined = average of bottom-up and top-down | Category × month | Confirmed | HF |
| Weekday run-rate | Revenue to day N × Σ weekday weights of the month ÷ Σ weights to day N; weight = average revenue on that weekday ÷ average daily revenue, from days before the month | Month × day | Confirmed | NW |
| Nowcast blend | Revenue to day N + prior (average of the previous 3 months) × share of the month's weekday weight still to come | Month × day | Confirmed | NW |
| Weekday weight (calendar) | Average booked revenue on a weekday ÷ average daily revenue, estimated on 2024 | Weekday | Confirmed | WD |
| Trading-day index | Σ weekday weights of a month's days ÷ the average of that sum over all months; adjusted revenue = revenue ÷ index | Month | Confirmed | WD |
| Compound Poisson FY simulation | FY total = FY-to-date + Σ remaining months of N ~ Poisson(same month last year's orders × count growth) orders drawn from that month last year (× size growth in rule B) | Cut-off | Confirmed | FT |
| Back-test percentile | Share of simulated totals at or below the actual total; 10–90 % coverage = share of cut-offs whose actual lies between P10 and P90 | Cut-off | Confirmed | FT |

## Data quality

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Rule pass rate | 1 − records failed ÷ records checked | Rule | Confirmed | DQ |
| Anomaly flag | Line quantity, price or order value beyond a multiple of a robust (median) benchmark | Order line | Confirmed | AN |
| Benford MAD | Mean absolute deviation of leading-digit shares from log₁₀(1 + 1/d), judged on Nigrini thresholds | Population | Confirmed | BF |
| Ship-to match type | Exact, case/spacing only, city alias only, different city same state, different city other state, no billing city | Shipment | Confirmed | ST |
| Recurring destination | Same customer shipped to the same non-billing city 3 or more times | Customer × city | Confirmed | ST |
| MUS sample size and interval | n = ⌈book value × reliability factor ÷ tolerable misstatement⌉ (factor 3.0 at 95 %, no expected error); J = book value ÷ n | Population | Confirmed | MU |
| MUS upper misstatement limit | J × (3.0 + Σ ranked taintings × incremental Poisson factor) + top-stratum misstatement | Sample | Confirmed | MU |
| Bunching ratio | Orders in [0.95 t, t) ÷ orders in [t, 1.05 t); z against log ratios at control points | Threshold | Confirmed | OS |
| Expected same-day pairs | Σ customers C(n, 2) × Σ days (share of orders on day)² | Population | Confirmed | OS |
| Event log / variant | One row per order, dispatch, delivery and payment event; variant = the ordered sequence of an order's activities | Event / order | Confirmed | PM |
| Population stability index (PSI) | Σ (a − e) ln(a ÷ e) over bins, shares smoothed by 0.5 per bin; noise test: n N ÷ (n + N) × PSI ≈ χ²(bins − 1) with n, N in orders | Field × month | Confirmed | DD |
| Calendar-blind expectation | Events × days of a type ÷ all days in the event's first-to-last span; tested with chi-square across weekdays | Event type × weekday | Confirmed | WH |
| Missingness chi-square | Σ (missing − n p)² ÷ (n p (1 − p)) across groups (groups < 30 pooled), against the 1 % Wilson–Hilferty critical value | Field × dimension | Confirmed | NM |
| KPI materiality | Corrected − as-reported KPI under one data rule; material if ≥ 1 % of an amount or count, or ≥ 0.5 points of a rate | KPI | Confirmed | MQ |
| Pack (as-of) on-time rate | On-time orders ÷ orders delivered by the as-of date (month-end + lag), for orders promised in the month | Month × lag | Confirmed | KV |
| Fixed on-time rate | On-time orders ÷ all orders promised in the month; equals the final figure at any date after month-end | Month | Confirmed | KV |
| KPI revision | Final value − value as reported at the as-of date | Month × KPI | Confirmed | KV |

## Statistical testing

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Rate z-score | (group rate − overall rate) ÷ `SQRT(p * (1 - p) / n)`; \|z\| ≥ 2 flagged | Group | Confirmed | CL |
| Expected by chance | Groups tested × 4.55 %, reported beside groups flagged | Dimension | Confirmed | CL |
| Two-sample z-test | (mean₁ − mean₂) ÷ `SQRT(var₁/n₁ + var₂/n₂)` | Two groups | Confirmed | PE |
| Two-proportion z-test | Difference in rates ÷ pooled standard error | Two groups | Confirmed | CL, PE, AN, RA, LC, DH |
| Lift | Outcome rate in the flagged group ÷ outcome rate in the rest | Method | Confirmed | RM, MB, SD |
| Chi-square (2 × 2) | N (ad − bc)² ÷ ((a + b)(c + d)(a + c)(b + d)), with Bonferroni correction | Pair | Confirmed | MB |
| Greenwood interval | Var[S(t)] = S(t)² Σ d ÷ (n (n − d)) | Survival curve | Confirmed | KM |
| Revenue (ramp) index | Joiner's revenue ÷ average of benchmark peers in the same calendar month; 3-month version uses sum ÷ sum | Salesperson × month | Confirmed | RU |
| Product split lift z-score | (split rate of orders with the product − base rate) ÷ √(base (1 − base) ÷ n); \|z\| ≥ 3 for 100+ tests | Product | Confirmed | SD |
| Within-customer (paired) difference | Per customer, late-order mean − on-time-order mean; averaged across customers with paired t = mean ÷ (sd ÷ √n) | Customer | Confirmed | LC |
| Welch t-test | (mean₁ − mean₂) ÷ √(s₁²/n₁ + s₂²/n₂) | Two groups | Confirmed | LC |
| Spearman ρ | `CORR` of `RANK()` values (ties share a rank) | Population | Confirmed | MO |
| Over-dispersion ratio | Σ n (p_g − p)² ÷ Σ p (1 − p) across groups; about 1 = no group singled out | Group set | Confirmed | DH |
| Fixed-effects slope | Σ d′ y′ ÷ Σ d′², with d and y demeaned within customer × product; df = n − pairs − 1 | Model | Confirmed | DV |
| Break-even volume response | m ÷ (m − 0.01) − 1, m = unit margin as a share of pre-discount price | Company | Confirmed | DV |
| Mantel–Haenszel difference | Σ w (p_broad − p_narrow) ÷ Σ w, w = n_b n_n ÷ (n_b + n_n) | Strata | Confirmed | CB |
| AUC | Probability that a randomly chosen good case (retained customer, on-time order) scores above a bad one (Mann–Whitney with average ranks); Gini = 2 × AUC − 1 | Score | Confirmed | HS, LP |
| Bootstrap rank interval | 5th–95th percentile of a rank across cluster-bootstrap replicates; a pair is distinguishable when one is better in 95 %+ of replicates | Salesperson × metric | Confirmed | RS |
| Cosine similarity | Customers who bought both ÷ √(customers of i × customers of j) | Product pair | Confirmed | CF |
| Heterogeneity Q and τ² | Q = Σ n (r − p)² ÷ (p (1 − p)); τ² = max(0, (Q − (K − 1)) ÷ (Σw − Σw² ÷ Σw)), w = n ÷ (p (1 − p)) | Measure | Confirmed | EB |
| Credible (shrunk) rate | B p + (1 − B) r, B = (p (1 − p) ÷ n) ÷ (p (1 − p) ÷ n + τ²) | Member | Confirmed | EB |
| Change-point model BIC | n ln(SSE ÷ n) + p ln(n); p = 1 no change, 2 trend, 3 one shift, 5 two shifts; levels of 3+ months | KPI | Confirmed | CP |
| Shift permutation p-value | (1 + reorderings whose best one-shift R² ≥ observed) ÷ (1 + 500) | KPI | Confirmed | CP |
| Binomial dispersion test | Σ (x − n p̄)² ÷ (n p̄ (1 − p̄)) against the Wilson–Hilferty 95 % critical value for months − 1 df | Rate KPI | Confirmed | CP |
| Minimum detectable effect | (1.96 + 0.84) × SD × √(2 ÷ n per arm) ÷ mean | Pilot design | Confirmed | PD |
| CUPED adjustment | Y − θ (X − mean X), θ = cov(X, Y) ÷ var(X); SD falls by √(1 − ρ²) | Customer | Confirmed | PD |
| A/A false-alarm rate | Share of random no-treatment splits with \|z\| > 1.96 | Pilot design | Confirmed | PD |
| GPD shape and scale (PWM) | Exceedances over u sorted ascending; a0 = mean, a1 = (1/n) Σ (n − i)/(n − 1) y(i); ξ = 2 − a0 ÷ (a0 − 2a1), σ = 2a0a1 ÷ (a0 − 2a1) | Threshold fit | Confirmed | XV |
| Return level | Size exceeded about once every T years: u + σ/ξ × ((λT)^ξ − 1), λ = exceedances per year | Threshold fit | Confirmed | XV |

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
| 2026-10-24 | Added CLV, survival, Markov state, safety stock, control chart, Benford and chi-square metrics. Extended the case study key. |
| 2026-10-25 | Added concentration (HHI, effective customers, Gini), reactivation, ramp index, split shipment, ship-to match, paired difference, Welch t, regression momentum and Spearman definitions. Extended the case study key. |
| 2026-10-26 | Added mix-expected margin, GP return, cost of sales, NRR, GRR, constant-price NRR, category breadth, dispatch days, inferred rate card, freight variance, over-dispersion, fixed-effects slope, break-even response and Mantel–Haenszel definitions. Extended the case study key. |
| 2026-10-26 (second batch) | Added margin bridge effects, activity score, k-means cluster, grouping R², 60-day late payment, weight of evidence, information value, pick ABC, pick travel, ADI / CV², Croston / SBA, WAPE, MUS sample size, interval and upper limit, bunching ratio, expected same-day pairs and AUC definitions. Extended the case study key. |
| 2026-10-27 | Added cross-sell trial, observed ÷ expected, price factor and deviation, bootstrap rank interval, common service standard, lead time vs city, event log and variant, fully paid date, PSI, cosine similarity, precision@K, collected share and Monte Carlo range definitions. Extended the case study key. |
| 2026-10-28 | Added budget-neutral commission rate, annualised quota, log-log persistence slope, logistic churn probability, weekday number, calendar-blind expectation, heterogeneity Q and τ², and credible (shrunk) rate definitions. Extended the case study key. |
| 2026-10-29 | Added driver tree, LMDI-I effect, overtaken pair, FIFO dispatch slot, cash application rule, open balance before a receipt, calendar-month age bucket, roll rate, loss rate and ECL provision, change-point BIC, shift permutation p-value and binomial dispersion test definitions. Extended the case study key. |
| 2026-10-30 | Added revenue identity and variance split, irreducible swing, specialisation index, gateway category, stratified permutation effect, gap CV and random benchmark, random-ordering prediction, credit exposure, lift vs random, Little's Law stage count, exponential smoothing and top-down category forecast definitions. Extended the case study key. |
| 2026-10-31 | Added within-customer size slope, frequency elasticity of order size, price deviation elasticity, FIFO cumulative departures, missingness chi-square, minimum detectable effect, CUPED adjustment, A/A false-alarm rate, smoothed churn probability and revenue at risk definitions. Extended the case study key. |
| 2026-11-01 | Added uplift share, expected March orders, operating contribution, split-half reliability, rupee-day cost of credit, account owner, workload band, known contact, dispatch deadline, EDF feasibility ratio, weekday run-rate, nowcast blend, Kaplan–Meier time to cash and restricted mean definitions. Extended the case study key. |
| 2026-11-02 | Added overdue month, activity-matched within-customer difference, within-customer discount slope, haversine distance, transit curve, hub transit saving, KPI materiality, handover effect, pre-trend effect, MA6 forecast and conformal range definitions. Extended the case study key. |
| 2026-11-05 | Added industry swing, risk contribution, diversification ratio, early-payment break-even day and uptake, six-day window capacity, working-day FIFO departures, calendar weekday weight and trading-day index definitions. Extended the case study key. |
| 2026-11-06 | Added pull-forward relative change, event-study placebo p-value, rate-contract qualifying pair, safe commitment level, freight value rate, freight zone, freight distance benchmark, quiet spell, chance quiet rate, compound Poisson FY simulation, back-test percentile, GPD shape and scale and return level definitions. Extended the case study key. |
| 2026-11-07 | Added as-of and fixed on-time rates, KPI revision, product family, ladder slope, neighbour price, e-way bill requirement and validity, BG/NBD dropout profile, NBD purchase chance, countback DSO, current-invoice DSO and average age of receivables definitions. Extended the case study key. |
