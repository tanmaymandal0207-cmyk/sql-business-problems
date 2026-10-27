<p align="center">
  <img src="images/banner.svg" alt="SQL Business Problems — business questions answered with SQL in Google BigQuery" width="100%">
</p>

Business problems analysed and answered with SQL — each case study starts from a business question, not from a query.

> **New here?** The [Getting Started Guide](GUIDE.md) explains how the repository is organised, how to read a case study and how to run the SQL in BigQuery.

<p align="center">
  <img src="https://img.shields.io/badge/SQL-BigQuery%20Standard%20SQL-DCE6F2?labelColor=17283B" alt="SQL: BigQuery Standard SQL">
  <img src="https://img.shields.io/badge/Categories-5-DCE6F2?labelColor=17283B" alt="Categories: 5">
  <img src="https://img.shields.io/badge/Case%20studies-74%20complete-DCE6F2?labelColor=17283B" alt="Case studies: 74 complete">
  <img src="https://img.shields.io/badge/Validation-before%20reporting-E1F0E7?labelColor=17283B" alt="Validation: before reporting">
</p>

---

## 1. Project overview

This repository documents business problems solved using SQL. Each case study follows the same structure: a clearly stated business problem, the data and metrics used to address it, the SQL solution, the checks used to validate the numbers, and the business interpretation of the results.

The focus is on decision support for commercial and operational teams — customer and revenue risk, sales and profitability, operations and supply chain, and data quality — rather than on isolated SQL exercises.

## 2. Objective

The repository is intended to demonstrate:

- **Analytical thinking** — translating an ambiguous business concern into specific, answerable questions and measurable metrics.
- **SQL proficiency** — structured, readable queries using CTEs, joins, aggregations, window functions and conditional logic.
- **Data validation** — reconciling totals, testing joins for row inflation, and checking assumptions before results are reported.
- **Business decision support** — converting verified results into findings and recommendations that a manager can act on.

## 3. Analytical approach

Every case study follows the same workflow:

| Step | Activity | Output |
|---|---|---|
| 1 | **Define the business problem** | Problem statement and the decision it supports |
| 2 | **Identify relevant data and metrics** | Tables, grain, joins and metric definitions |
| 3 | **Analyse the data using SQL** | Documented, reproducible queries |
| 4 | **Validate calculations and assumptions** | Reconciliation checks, row counts, null and duplicate tests |
| 5 | **Interpret findings** | Results stated with their context and limits |
| 6 | **Develop evidence-based recommendations** | Actions tied directly to verified findings |

## 4. Repository structure

| Category | Focus |
|---|---|
| [`01_customer_and_revenue`](01_customer_and_revenue/) | Customer value, revenue concentration, churn and revenue-at-risk |
| [`02_sales_and_profitability`](02_sales_and_profitability/) | Product, category and salesperson performance; discounts and margin |
| [`03_operations_and_supply_chain`](03_operations_and_supply_chain/) | Order fulfilment, delivery performance, shipping cost and returns |
| [`04_data_quality_and_reconciliation`](04_data_quality_and_reconciliation/) | Referential integrity, duplicates, standardisation and order-to-cash reconciliation |
| [`05_advanced_analytics`](05_advanced_analytics/) | Cohorts, segmentation, time-series patterns and other multi-step analyses |
| [`datasets_and_documentation`](datasets_and_documentation/) | Dataset schema and shared metric definitions |

```
sql-business-problems/
├── README.md
├── GUIDE.md
├── CHANGELOG.md
├── 01_customer_and_revenue/
│   ├── 01_customer_revenue_risk/
│   ├── 02_customer_churn_early_warning/
│   ├── 03_revenue_growth_bridge/
│   ├── 04_salesperson_relationship_risk/
│   ├── 05_new_customer_activation/
│   ├── 06_regional_performance/
│   ├── 07_customer_lifetime_value/
│   ├── 08_revenue_concentration_trend/
│   ├── 09_reactivated_customers/
│   ├── 10_industry_vertical_scorecard/
│   ├── 11_net_revenue_retention/
│   ├── 12_customer_health_score/
│   ├── 13_cross_sell_stickiness/
│   └── 14_key_account_regression_to_mean/
├── 02_sales_and_profitability/
│   ├── 01_discount_margin_erosion/
│   ├── 02_salesperson_scorecard/
│   ├── 03_price_volume_mix/
│   ├── 04_cross_sell_white_space/
│   ├── 05_sku_rationalisation/
│   ├── 06_discount_consistency/
│   ├── 07_period_end_sales_push/
│   ├── 08_market_basket_affinity/
│   ├── 09_salesperson_ramp_up/
│   ├── 10_sales_force_cost_efficiency/
│   ├── 11_gross_margin_bridge/
│   ├── 12_price_increase_and_price_discipline/
│   ├── 13_salesperson_ranking_stability/
│   └── 14_commission_plan_simulation/
├── 03_operations_and_supply_chain/
│   ├── 01_late_delivery_root_cause/
│   ├── 02_freight_cost_to_serve/
│   ├── 03_open_order_backlog_review/
│   ├── 04_dispatch_workload_planning/
│   ├── 05_promise_date_standards/
│   ├── 06_cancellation_return_leakage/
│   ├── 07_shipment_consolidation/
│   ├── 08_safety_stock_reorder_points/
│   ├── 09_statistical_process_control/
│   ├── 10_split_shipment_drivers/
│   ├── 11_dispatch_holds/
│   ├── 12_warehouse_slotting/
│   ├── 13_key_account_service_equity/
│   └── 14_empirical_bayes_rates/
├── 04_data_quality_and_reconciliation/
│   ├── 01_order_to_cash_reconciliation/
│   ├── 02_data_quality_scorecard/
│   ├── 03_customer_master_deduplication/
│   ├── 04_revenue_cutoff_reconciliation/
│   ├── 05_receivables_rollforward/
│   ├── 06_order_anomaly_screen/
│   ├── 07_benford_forensic_test/
│   ├── 08_ship_to_bill_to_reconciliation/
│   ├── 09_freight_invoice_audit/
│   ├── 10_monetary_unit_sampling/
│   ├── 11_order_splitting_test/
│   ├── 12_order_to_cash_process_mining/
│   ├── 13_data_drift_monitoring/
│   └── 14_weekend_holiday_postings/
├── 05_advanced_analytics/
│   ├── 01_abc_xyz_product_classification/
│   ├── 02_customer_payment_behaviour/
│   ├── 03_rfm_customer_segmentation/
│   ├── 04_revenue_forecast_baseline/
│   ├── 05_customer_profitability_whale_curve/
│   ├── 06_reorder_reminders/
│   ├── 07_time_to_reorder_survival/
│   ├── 08_customer_state_markov/
│   ├── 09_cost_of_late_delivery/
│   ├── 10_customer_momentum/
│   ├── 11_discount_volume_response/
│   ├── 12_category_breadth_retention/
│   ├── 13_kmeans_customer_segmentation/
│   ├── 14_intermittent_demand_forecasting/
│   ├── 15_late_payment_scorecard/
│   ├── 16_collaborative_filtering_recommender/
│   ├── 17_monte_carlo_collections_forecast/
│   └── 18_logistic_regression_churn/
├── datasets_and_documentation/
│   ├── schema.md
│   └── metric_definitions.md
└── images/
```

## 5. Technical stack

- **Google BigQuery** — Standard SQL

Additional tools will be listed here only when they are used in a published case study.

## 6. Case studies

| # | Case study | Category | Status |
|---|---|---|---|
| 1 | [Customer revenue risk](01_customer_and_revenue/01_customer_revenue_risk/) | Customer and revenue | Complete (version 2) |
| 2 | [Order-to-cash reconciliation](04_data_quality_and_reconciliation/01_order_to_cash_reconciliation/) | Data quality and reconciliation | Complete |
| 3 | [Late delivery root cause](03_operations_and_supply_chain/01_late_delivery_root_cause/) | Operations and supply chain | Complete |
| 4 | [Customer churn early warning](01_customer_and_revenue/02_customer_churn_early_warning/) | Customer and revenue | Complete |
| 5 | [Discount and margin erosion](02_sales_and_profitability/01_discount_margin_erosion/) | Sales and profitability | Complete |
| 6 | [Freight cost-to-serve and minimum order value](03_operations_and_supply_chain/02_freight_cost_to_serve/) | Operations and supply chain | Complete |
| 7 | [Data quality scorecard](04_data_quality_and_reconciliation/02_data_quality_scorecard/) | Data quality and reconciliation | Complete |
| 8 | [ABC-XYZ product classification](05_advanced_analytics/01_abc_xyz_product_classification/) | Advanced analytics | Complete |
| 9 | [Revenue growth bridge](01_customer_and_revenue/03_revenue_growth_bridge/) | Customer and revenue | Complete |
| 10 | [Salesperson performance scorecard](02_sales_and_profitability/02_salesperson_scorecard/) | Sales and profitability | Complete |
| 11 | [Customer payment behaviour and credit terms](05_advanced_analytics/02_customer_payment_behaviour/) | Advanced analytics | Complete |
| 12 | [Open order backlog review](03_operations_and_supply_chain/03_open_order_backlog_review/) | Operations and supply chain | Complete |
| 13 | [Customer master de-duplication](04_data_quality_and_reconciliation/03_customer_master_deduplication/) | Data quality and reconciliation | Complete |
| 14 | [Price-volume-mix analysis](02_sales_and_profitability/03_price_volume_mix/) | Sales and profitability | Complete |
| 15 | [Dispatch workload and capacity planning](03_operations_and_supply_chain/04_dispatch_workload_planning/) | Operations and supply chain | Complete |
| 16 | [RFM customer segmentation](05_advanced_analytics/03_rfm_customer_segmentation/) | Advanced analytics | Complete |
| 17 | [Cross-sell white-space analysis](02_sales_and_profitability/04_cross_sell_white_space/) | Sales and profitability | Complete |
| 18 | [City-wise delivery promise standards](03_operations_and_supply_chain/05_promise_date_standards/) | Operations and supply chain | Complete |
| 19 | [Revenue cut-off reconciliation](04_data_quality_and_reconciliation/04_revenue_cutoff_reconciliation/) | Data quality and reconciliation | Complete |
| 20 | [Baseline revenue forecast with backtesting](05_advanced_analytics/04_revenue_forecast_baseline/) | Advanced analytics | Complete |
| 21 | [Salesperson relationship risk](01_customer_and_revenue/04_salesperson_relationship_risk/) | Customer and revenue | Complete |
| 22 | [New customer onboarding and activation](01_customer_and_revenue/05_new_customer_activation/) | Customer and revenue | Complete |
| 23 | [SKU rationalisation](02_sales_and_profitability/05_sku_rationalisation/) | Sales and profitability | Complete |
| 24 | [Cancellation and return leakage](03_operations_and_supply_chain/06_cancellation_return_leakage/) | Operations and supply chain | Complete |
| 25 | [Receivables roll-forward reconciliation](04_data_quality_and_reconciliation/05_receivables_rollforward/) | Data quality and reconciliation | Complete |
| 26 | [Customer profitability and the whale curve](05_advanced_analytics/05_customer_profitability_whale_curve/) | Advanced analytics | Complete |
| 27 | [Regional performance and market coverage](01_customer_and_revenue/06_regional_performance/) | Customer and revenue | Complete |
| 28 | [Discount consistency and price leakage](02_sales_and_profitability/06_discount_consistency/) | Sales and profitability | Complete |
| 29 | [Period-end sales push](02_sales_and_profitability/07_period_end_sales_push/) | Sales and profitability | Complete |
| 30 | [Shipment consolidation opportunity](03_operations_and_supply_chain/07_shipment_consolidation/) | Operations and supply chain | Complete |
| 31 | [Order anomaly screen](04_data_quality_and_reconciliation/06_order_anomaly_screen/) | Data quality and reconciliation | Complete |
| 32 | [Replenishment reorder reminders](05_advanced_analytics/06_reorder_reminders/) | Advanced analytics | Complete |
| 33 | [Customer lifetime value](01_customer_and_revenue/07_customer_lifetime_value/) | Customer and revenue | Complete |
| 34 | [Market basket affinity with significance testing](02_sales_and_profitability/08_market_basket_affinity/) | Sales and profitability | Complete |
| 35 | [Safety stock and reorder points](03_operations_and_supply_chain/08_safety_stock_reorder_points/) | Operations and supply chain | Complete |
| 36 | [Statistical process control](03_operations_and_supply_chain/09_statistical_process_control/) | Operations and supply chain | Complete |
| 37 | [Benford's law forensic test](04_data_quality_and_reconciliation/07_benford_forensic_test/) | Data quality and reconciliation | Complete |
| 38 | [Time-to-reorder survival analysis](05_advanced_analytics/07_time_to_reorder_survival/) | Advanced analytics | Complete |
| 39 | [Customer state transitions (Markov chain)](05_advanced_analytics/08_customer_state_markov/) | Advanced analytics | Complete |
| 40 | [Revenue concentration trend](01_customer_and_revenue/08_revenue_concentration_trend/) | Customer and revenue | Complete |
| 41 | [Reactivated customers](01_customer_and_revenue/09_reactivated_customers/) | Customer and revenue | Complete |
| 42 | [Salesperson ramp-up](02_sales_and_profitability/09_salesperson_ramp_up/) | Sales and profitability | Complete |
| 43 | [Split shipment drivers](03_operations_and_supply_chain/10_split_shipment_drivers/) | Operations and supply chain | Complete |
| 44 | [Ship-to vs bill-to reconciliation](04_data_quality_and_reconciliation/08_ship_to_bill_to_reconciliation/) | Data quality and reconciliation | Complete |
| 45 | [Cost of a late delivery](05_advanced_analytics/09_cost_of_late_delivery/) | Advanced analytics | Complete |
| 46 | [Customer momentum](05_advanced_analytics/10_customer_momentum/) | Advanced analytics | Complete |
| 47 | [Industry vertical scorecard](01_customer_and_revenue/10_industry_vertical_scorecard/) | Customer and revenue | Complete |
| 48 | [Net and gross revenue retention](01_customer_and_revenue/11_net_revenue_retention/) | Customer and revenue | Complete |
| 49 | [Sales force cost efficiency](02_sales_and_profitability/10_sales_force_cost_efficiency/) | Sales and profitability | Complete |
| 50 | [Dispatch holds](03_operations_and_supply_chain/11_dispatch_holds/) | Operations and supply chain | Complete |
| 51 | [Freight invoice audit](04_data_quality_and_reconciliation/09_freight_invoice_audit/) | Data quality and reconciliation | Complete |
| 52 | [Does discount buy volume?](05_advanced_analytics/11_discount_volume_response/) | Advanced analytics | Complete |
| 53 | [Category breadth and retention](05_advanced_analytics/12_category_breadth_retention/) | Advanced analytics | Complete |
| 54 | [Customer health score](01_customer_and_revenue/12_customer_health_score/) | Customer and revenue | Complete |
| 55 | [Gross margin bridge](02_sales_and_profitability/11_gross_margin_bridge/) | Sales and profitability | Complete |
| 56 | [Warehouse slotting by pick frequency](03_operations_and_supply_chain/12_warehouse_slotting/) | Operations and supply chain | Complete |
| 57 | [Monetary unit sampling for the receivables audit](04_data_quality_and_reconciliation/10_monetary_unit_sampling/) | Data quality and reconciliation | Complete |
| 58 | [Order splitting test](04_data_quality_and_reconciliation/11_order_splitting_test/) | Data quality and reconciliation | Complete |
| 59 | [k-means customer segmentation](05_advanced_analytics/13_kmeans_customer_segmentation/) | Advanced analytics | Complete |
| 60 | [Intermittent demand forecasting (Croston and SBA)](05_advanced_analytics/14_intermittent_demand_forecasting/) | Advanced analytics | Complete |
| 61 | [Late payment scorecard](05_advanced_analytics/15_late_payment_scorecard/) | Advanced analytics | Complete |
| 62 | [Cross-sell stickiness](01_customer_and_revenue/13_cross_sell_stickiness/) | Customer and revenue | Complete |
| 63 | [January price increase and price discipline](02_sales_and_profitability/12_price_increase_and_price_discipline/) | Sales and profitability | Complete |
| 64 | [Salesperson ranking stability (bootstrap)](02_sales_and_profitability/13_salesperson_ranking_stability/) | Sales and profitability | Complete |
| 65 | [Key-account service: better service or easier promises?](03_operations_and_supply_chain/13_key_account_service_equity/) | Operations and supply chain | Complete |
| 66 | [Order-to-cash process mining](04_data_quality_and_reconciliation/12_order_to_cash_process_mining/) | Data quality and reconciliation | Complete |
| 67 | [Data drift monitoring (PSI)](04_data_quality_and_reconciliation/13_data_drift_monitoring/) | Data quality and reconciliation | Complete |
| 68 | [Collaborative filtering vs best sellers](05_advanced_analytics/16_collaborative_filtering_recommender/) | Advanced analytics | Complete |
| 69 | [Monte Carlo collections forecast](05_advanced_analytics/17_monte_carlo_collections_forecast/) | Advanced analytics | Complete |
| 70 | [Key-account selection and regression to the mean](01_customer_and_revenue/14_key_account_regression_to_mean/) | Customer and revenue | Complete |
| 71 | [Sales commission plan simulation](02_sales_and_profitability/14_commission_plan_simulation/) | Sales and profitability | Complete |
| 72 | [Weekend and holiday postings test](04_data_quality_and_reconciliation/14_weekend_holiday_postings/) | Data quality and reconciliation | Complete |
| 73 | [Logistic regression churn model, trained in SQL](05_advanced_analytics/18_logistic_regression_churn/) | Advanced analytics | Complete |
| 74 | [Real differences or noise? Empirical Bayes for operational rates](03_operations_and_supply_chain/14_empirical_bayes_rates/) | Operations and supply chain | Complete |

Case studies are listed as complete only once their SQL, validation and findings have been added to the repository. A dated record of every addition and change is kept in [`CHANGELOG.md`](CHANGELOG.md).

## 7. Data and methodology

Case studies initially use the **`sahyadri_b2b`** dataset — transactional data for a B2B industrial products distributor covering customers, products, sales orders, order line items, payments, shipments and employees. The table structure, keys and known data characteristics are documented in [`datasets_and_documentation/schema.md`](datasets_and_documentation/schema.md).

For each analysis, the following are documented alongside the SQL:

- **Assumptions** — how statuses, nulls, partial payments and edge cases are treated.
- **Metric definitions** — the exact formula and grain of every reported metric, referencing [`metric_definitions.md`](datasets_and_documentation/metric_definitions.md).
- **Validation methods** — the checks used to confirm that totals reconcile and joins do not duplicate or drop records.

## 8. Limitations

- Results depend on the completeness and accuracy of the underlying data. Known data quality issues are documented and their treatment is stated in each analysis.
- Findings describe the dataset analysed; they are not generalised beyond it.
- Recommendations are grounded only in verified findings. Where the data cannot support a conclusion, that is stated rather than inferred.

---

**Author:** Tanmay Mandal — Business Analysis, Operations & ERP
