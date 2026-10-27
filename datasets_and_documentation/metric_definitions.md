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
| Mix-expected margin | Σ segment costed revenue × company margin % of that segment; margin vs mix = actual − expected | Industry | Confirmed | IV |
| GP return | Gross profit ÷ salary cost (salary pro-rated from hire date) | Salesperson | Confirmed | SE |
| Cost of sales | Salary cost ÷ revenue | Salesperson / role | Confirmed | SE |
| Margin bridge effects | Product × segment cells, m = P (1 − d) − c: volume = Δ total units × prior margin per unit; mix = Σ Δq × m₀ − volume; price = Σ q₁ (P₁ − P₀)(1 − d₀); discount = Σ q₁ P₁ (d₀ − d₁); new and lost cells separate. Effects sum exactly to the continuing-cell margin change; both periods use current unit cost | Product × segment | Confirmed | MG |

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

## Revenue recognition and forecasting

| Metric | Definition | Grain | Status | Used in |
|---|---|---|---|---|
| Cut-off difference | Order-date revenue − delivery-date revenue for a period | Month / financial year | Confirmed | RC |
| Month-end exposure | Revenue ordered on or before a date but delivered after it | Date | Confirmed | RC |
| MAPE | Mean of \|forecast − actual\| ÷ actual across test months | Method | Confirmed | FB |
| Forecast bias | Mean of (forecast − actual) ÷ actual; negative = under-forecast | Method | Confirmed | FB |
| Monte Carlo range | P10–P90 of simulated totals; coverage = share of back-tests whose actual falls inside | Forecast | Confirmed | MC |
| Precision@K | Hits among the top K recommendations ÷ K, averaged over customers; hit = bought in the test period | Method | Confirmed | CF |

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
