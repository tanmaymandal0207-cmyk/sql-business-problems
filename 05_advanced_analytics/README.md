# 05 · Advanced Analytics

Case studies that need multi-step SQL — cohort analysis, segmentation, time-series patterns and similar techniques — applied to a specific business question.

## Typical business questions

- How do customer cohorts retain and grow over time?
- How can customers be segmented by recency, frequency and value?
- What seasonal or trend patterns appear in order volume and revenue?

## Primary tables

Depends on the case study — see [schema](../datasets_and_documentation/schema.md).

## Case studies

| # | Case study | Status |
|---|---|---|
| 01 | [ABC-XYZ product classification](01_abc_xyz_product_classification/) — which stocking policy should each product follow, based on revenue and demand predictability? | Complete |
| 02 | [Customer payment behaviour and credit terms](02_customer_payment_behaviour/) — how fast does each segment pay, and what would formal credit terms release in cash? | Complete |
| 03 | [RFM customer segmentation](03_rfm_customer_segmentation/) — which customers are Champions, which are slipping away, and what should each group get? | Complete |
| 04 | [Baseline revenue forecast with backtesting](04_revenue_forecast_baseline/) — which simple method forecasts best, and what is the Q4 2026 outlook? | Complete |
| 05 | [Customer profitability and the whale curve](05_customer_profitability_whale_curve/) — which customers make money after the full cost to serve? | Complete |
| 06 | [Replenishment reorder reminders](06_reorder_reminders/) — which customers are overdue to reorder a product, and does the method work in a backtest? | Complete |
| 07 | [Time-to-reorder survival analysis](07_time_to_reorder_survival/) — how likely is a silent customer to return, and when is a customer really lost? | Complete |
| 08 | [Customer state transitions (Markov chain)](08_customer_state_markov/) — where is the customer base heading, and what is a win-back programme worth? | Complete |
| 09 | [Cost of a late delivery](09_cost_of_late_delivery/) — does lateness slow payment or lose repeat business, within the same customer? | Complete |
| 10 | [Customer momentum](10_customer_momentum/) — which customers have a statistically significant revenue trend, and does it predict next year? | Complete |
| 11 | [Does discount buy volume?](11_discount_volume_response/) — within the same customer and product, does a bigger discount bring enough extra units to pay for itself? | Complete |
| 12 | [Category breadth and retention](12_category_breadth_retention/) — do customers who buy more categories stay longer once purchase frequency is held constant? | Complete |
| 13 | [k-means customer segmentation](13_kmeans_customer_segmentation/) — what behaviour groups does k-means (written in SQL) find, and do the official segments match? | Complete |
| 14 | [Intermittent demand forecasting](14_intermittent_demand_forecasting/) — do Croston and SBA forecast lumpy weekly demand better than moving averages? | Complete |
| 15 | [Late payment scorecard](15_late_payment_scorecard/) — which characteristics predict late payment, and does a points scorecard beat the segment rule? | Complete |
| 16 | [Collaborative filtering recommender](16_collaborative_filtering_recommender/) — does a "customers like you" recommender beat a best-seller list in a back-test? | Complete |
| 17 | [Monte Carlo collections forecast](17_monte_carlo_collections_forecast/) — how much of the open book will be collected in 30, 60 and 90 days, as a tested range? | Complete |
| 18 | [Logistic regression churn model](18_logistic_regression_churn/) — can a churn model be trained in BigQuery, and does it beat the activity score? | Complete |
| 19 | [Expected credit loss provision](19_expected_credit_loss_provision/) — what roll-rate provision matrix does the payment history support, and would it have predicted the losses that followed? | Complete |
| 20 | [KPI change-point detection](20_kpi_change_point_detection/) — which monthly KPI moves are real shifts, which are steady trends, and which are noise? | Complete |
| 21 | [Hierarchical forecast reconciliation](21_hierarchical_forecast_reconciliation/) — should category forecasts be built bottom-up, top-down or combined so they add up to the total? | Complete |
| 22 | [Order timing regularity](22_order_timing_regularity/) — do customers order on a cycle or at random, and does being "due" make an order more likely? | Complete |
