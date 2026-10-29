# 01 · Customer and Revenue

Case studies on how revenue is distributed across customers, how it changes over time, and where it is at risk.

## Typical business questions

- How concentrated is revenue across customers and segments?
- Which customers are reducing their order activity or have stopped ordering?
- How much revenue is exposed to customers showing risk signals?
- How do customer segments differ in value, order frequency and payment behaviour?

## Primary tables

`customers`, `sales_orders`, `sales_order_items`, `payments` — see [schema](../datasets_and_documentation/schema.md).

## Case studies

| # | Case study | Status |
|---|---|---|
| 01 | [Customer revenue risk](01_customer_revenue_risk/) — which customers depend on a single order, and how concentrated is revenue? | Complete (version 2) |
| 02 | [Customer churn early warning](02_customer_churn_early_warning/) — which customers have gone quiet, and which active accounts are overdue against their own ordering cycle? | Complete |
| 03 | [Revenue growth bridge](03_revenue_growth_bridge/) — where did year-to-date growth come from: new customers, existing accounts, more orders or bigger orders? | Complete |
| 04 | [Salesperson relationship risk](04_salesperson_relationship_risk/) — how much revenue depends on one salesperson, and what happens when an account changes hands? | Complete |
| 05 | [New customer onboarding and activation](05_new_customer_activation/) — do new registrations turn into repeat buyers, and where does onboarding stall? | Complete |
| 06 | [Regional performance and market coverage](06_regional_performance/) — which states and regions to invest in, defend, develop or review? | Complete |
| 07 | [Customer lifetime value](07_customer_lifetime_value/) — what is each customer's expected future margin, and what is a second order worth? | Complete |
| 08 | [Revenue concentration trend](08_revenue_concentration_trend/) — is the business becoming more or less dependent on a few customers, by HHI, effective customers and Gini? | Complete |
| 09 | [Reactivated customers](09_reactivated_customers/) — how many lapsed customers come back, what are they worth, and do they stay? | Complete |
| 10 | [Industry vertical scorecard](10_industry_vertical_scorecard/) — which industries grow, earn margin and keep customers, once single-customer growth and segment mix are removed? | Complete |
| 11 | [Net and gross revenue retention](11_net_revenue_retention/) — how much of last year's customer revenue is kept, and how much of NRR is price and a few accounts? | Complete |
| 12 | [Customer health score](12_customer_health_score/) — which churn signals actually work, tested with a point-in-time back-test and AUC? | Complete |
| 13 | [Cross-sell stickiness](13_cross_sell_stickiness/) — which categories, once tried, are bought again, after allowing for how often the customer orders? | Complete |
| 14 | [Key-account selection and regression to the mean](14_key_account_regression_to_mean/) — how stable is the top of the customer list, and why do big accounts miss uniform growth targets? | Complete |
| 15 | [Revenue driver tree](15_revenue_driver_tree/) — which of five drivers (customers, frequency, lines, units, revenue per unit) explain growth in 2025 and 2026, by an exact LMDI decomposition? | Complete |
