# Getting Started Guide

This guide explains how the repository is organised, how to read a case study, how to run the SQL yourself in Google BigQuery, and how new case studies are added.

**Contents**

1. [Who this guide is for](#1-who-this-guide-is-for)
2. [How the repository is organised](#2-how-the-repository-is-organised)
3. [How to read a case study](#3-how-to-read-a-case-study)
4. [Suggested reading order](#4-suggested-reading-order)
5. [Running the SQL in BigQuery](#5-running-the-sql-in-bigquery)
6. [Conventions used across the repository](#6-conventions-used-across-the-repository)
7. [How a new case study is added](#7-how-a-new-case-study-is-added)
8. [Glossary](#8-glossary)

---

## 1. Who this guide is for

| If you are… | Start with |
|---|---|
| **A recruiter or hiring manager** with five minutes | Section 4, path A: one case study README, top to bottom |
| **An analyst** who wants to check the logic | Section 3, then any `analysis.sql` alongside its README |
| **A learner** who wants to run the queries | Section 5, then section 4, path C |

You do not need to run any SQL to follow a case study. Each README states the problem, the method, the validation results and the findings in plain language.

## 2. How the repository is organised

Case studies are grouped by the kind of business problem they solve, not by SQL technique.

```
sql-business-problems/
├── README.md                          Project overview and case study index
├── GUIDE.md                           This guide
├── CHANGELOG.md                       Dated record of additions and changes
├── 01_customer_and_revenue/           Customer value, concentration, revenue risk
├── 02_sales_and_profitability/        Products, pricing, discounts, margin
├── 03_operations_and_supply_chain/    Fulfilment, delivery, logistics
├── 04_data_quality_and_reconciliation/  Integrity checks, matching, reconciliation
├── 05_advanced_analytics/             Cohorts, segmentation, time series
├── datasets_and_documentation/
│   ├── schema.md                      Tables, keys, relationships, known data issues
│   └── metric_definitions.md          Shared metric formulas
└── images/                            README banner
```

Each category folder has its own `README.md` that lists its case studies and their status. Each case study sits in its own numbered folder inside its category:

```
03_operations_and_supply_chain/
└── 01_late_delivery_root_cause/
    ├── README.md        The write-up: problem, method, validation, findings
    ├── analysis.sql     The analysis, run first
    └── validation.sql   Pass/fail checks on the analysis output, run second
```

## 3. How to read a case study

Every case study README uses the same ten sections, so you can move between them easily.

| Section | What it tells you |
|---|---|
| 1. Business problem | The decision someone needs to make and why the data matters to it |
| 2. Business questions | The specific questions the SQL must answer |
| 3. Dataset and relevant tables | Which tables are used, their grain, and how they are joined |
| 4. Metric definitions | The exact formula behind every number reported |
| 5. Analytical approach | The steps in `analysis.sql`, in order |
| 6. SQL techniques used | The SQL features the solution relies on |
| 7. Validation and reconciliation | The checks that prove the numbers are right, and their results |
| 8. Findings | What the data shows, with figures |
| 9. Business implications and recommendations | What to do about it, each point tied to a finding |
| 10. Assumptions and limitations | What the analysis cannot tell you |

**Status labels** at the top of each README:

| Label | Meaning |
|---|---|
| **Complete** | SQL, validation and findings are all in place. All validation checks pass. |
| **Version 1 — revision planned** | The query is published, but known issues are listed and findings are held back until the next version is validated |
| **In preparation** | The folder is reserved; no analysis has been published yet |

Findings are written only after validation passes. If a case study shows *Pending* in its findings section, the numbers have not been signed off yet.

## 4. Suggested reading order

**Path A — a quick review (about 5 minutes)**

1. [Late delivery root cause](03_operations_and_supply_chain/01_late_delivery_root_cause/): read sections 1, 7 and 8.
2. Look at the days-late decomposition in section 4 of that README. It shows how the analysis turns a vague complaint into a measurable split.

**Path B — reviewing the analytical approach**

1. [`schema.md`](datasets_and_documentation/schema.md): the tables and the known data issues every case study has to handle.
2. [Order-to-cash reconciliation](04_data_quality_and_reconciliation/01_order_to_cash_reconciliation/): the README first, then `analysis.sql` and `validation.sql` side by side.
3. [Customer revenue risk](01_customer_and_revenue/01_customer_revenue_risk/): an example of how a flawed first version was diagnosed, kept for reference and corrected in version 2.

**Path C — learning by running the queries**

1. Set up the dataset (section 5).
2. Run the order-to-cash case study. It uses straightforward joins and `CASE` logic.
3. Then run the late delivery case study. It adds a mapping table, medians and a decomposition.
4. Compare your output with the figures in each README.

## 5. Running the SQL in BigQuery

### 5.1 What you need

- A Google Cloud project with BigQuery enabled. The free BigQuery sandbox is enough for this data volume; note that tables in a sandbox project expire automatically after 60 days.
- The nine `sahyadri_b2b` CSV files: `customers`, `products`, `product_categories`, `sales_orders`, `sales_order_items`, `payments`, `shipments`, `employees` and `departments`.

> **Data availability:** the CSV files are not currently published in this repository. The table structure is documented in full in [`schema.md`](datasets_and_documentation/schema.md).

### 5.2 Create the dataset and tables

1. In the BigQuery console, create a dataset named **`sahyadri_b2b`** in your project.
2. Load each CSV file as a table:
   - **Create table from:** Upload, then select the CSV file
   - **Table name:** the file name without `.csv`, in lowercase (for example `sales_orders`)
   - **Schema:** Auto detect
   - **Header rows to skip:** 1
3. Check the row counts against [`schema.md`](datasets_and_documentation/schema.md) (for example, `sales_orders` should have 10,000 rows).

If you prefer the command line, the same load can be done with the `bq` tool, one command per file:

```bash
bq load --autodetect --skip_leading_rows=1 --source_format=CSV \
  sahyadri_b2b.sales_orders ./sales_orders.csv
```

**Table names are case-sensitive in BigQuery.** The scripts refer to tables in lowercase (`sahyadri_b2b.sales_orders`). If you name a table differently, the script will not find it.

### 5.3 Run a case study

1. Open the case study's `analysis.sql`, paste it into the BigQuery editor and click **Run**.
   - Scripts that start with `DECLARE` are multi-statement scripts. BigQuery runs every step and shows each result separately; use **View results** on each step to see its output.
   - Some scripts save a table to your dataset with `CREATE OR REPLACE TABLE` so that later steps and the validation script can read from it. Running the script again simply replaces that table.
2. Then run `validation.sql` from the same folder. Every row should show **PASS**.
3. Compare your results with the findings section of the README.

| Case study | Tables created by `analysis.sql` |
|---|---|
| Customer revenue risk | None (single query; run `analysis_v2.sql`) |
| Order-to-cash reconciliation | `order_payment_reconciliation` |
| Late delivery root cause | `city_name_map`, `delivery_performance` |
| Customer churn early warning | `customer_activity_status` |
| Discount and margin erosion | `sales_line_margin` |
| Freight cost-to-serve | `order_cost_to_serve` |
| Data quality scorecard | `data_quality_results` |
| ABC-XYZ product classification | `product_abc_xyz` |
| Revenue growth bridge | `ytd_revenue_lines` |
| Salesperson performance scorecard | `salesperson_scorecard` |
| Customer payment behaviour | `paid_order_timing` |
| Open order backlog review | `open_order_review` |
| Customer master de-duplication | `customer_name_keys`, `customer_duplicate_candidates`, `customer_master_map` |
| Price-volume-mix analysis | `product_price_volume` |
| Dispatch workload and capacity planning | `daily_dispatch_workload` |
| RFM customer segmentation | `customer_rfm` |
| Cross-sell white-space analysis | `customer_category_spend`, `cross_sell_gaps` |
| City-wise delivery promise standards | `city_promise_standards` (needs `delivery_performance` from Late delivery root cause) |
| Revenue cut-off reconciliation | `revenue_recognition_basis` |
| Baseline revenue forecast | `monthly_revenue`, `monthly_forecasts` |
| Salesperson relationship risk | `customer_relationship_coverage`, `salesperson_handover` |
| New customer onboarding and activation | `new_customer_activation` |
| SKU rationalisation | `sku_profitability` |
| Cancellation and return leakage | `order_outcomes`, `cancellation_driver_screen` |
| Receivables roll-forward reconciliation | `receivables_ledger`, `receivables_month_end` (the tie-out step needs `order_payment_reconciliation` from Order-to-cash reconciliation) |
| Customer profitability and the whale curve | `customer_profitability` |
| Regional performance and market coverage | `state_region_map`, `state_performance` |
| Discount consistency and price leakage | `customer_discount_band` |
| Period-end sales push | `order_period_position` |
| Shipment consolidation opportunity | `freight_cost_model`, `shipment_consolidation_base`, `consolidation_scenarios` |
| Order anomaly screen | `order_line_anomalies`, `order_anomaly_review` |
| Replenishment reorder reminders | `customer_product_purchases`, `reorder_status`, `reorder_backtest` |
| Customer lifetime value | `clv_retention_bands`, `customer_lifetime_value` |
| Market basket affinity | `basket_items`, `basket_pair_stats`, `basket_pair_results` |
| Safety stock and reorder points | `weekly_product_demand`, `safety_stock_policy`, `safety_stock_backtest` |
| Statistical process control | `spc_weekly`, `spc_chart`, `spc_signals` |
| Benford's law forensic test | `benford_values`, `benford_first_digit`, `benford_first_two` |
| Time-to-reorder survival analysis | `reorder_spells`, `reorder_survival_curve`, `reorder_survival_daily` |
| Customer state transitions (Markov chain) | `customer_quarter_state`, `state_transitions`, `markov_projection` (the script uses a `WHILE` loop, so run it as one script) |
| Revenue concentration trend | `concentration_periods`, `concentration_measures` |
| Reactivated customers | `customer_order_gaps`, `reactivation_events` |
| Salesperson ramp-up | `rep_monthly`, `rep_ramp` |
| Split shipment drivers | `order_fulfilment`, `split_product_lift` |
| Ship-to vs bill-to reconciliation | `city_alias_map`, `city_state_lookup`, `ship_bill_reconciliation` |
| Cost of a late delivery | `delivery_outcomes`, `late_delivery_paired` |
| Customer momentum | `customer_monthly_revenue`, `customer_momentum` |

### 5.4 If something does not match

| Symptom | Likely cause |
|---|---|
| `Not found: Table ...` | The table name differs from the script (check spelling and case), or the dataset is not named `sahyadri_b2b` |
| `Not found: Table sahyadri_b2b.Sales_Orders` in Customer revenue risk | You ran the version 1 query (`analysis.sql`), which uses `Sales_Orders`. Run `analysis_v2.sql` instead. |
| A validation check shows FAIL | `analysis.sql` was not run first, or it was run against a different version of the data |
| Totals differ slightly from the README | A column was loaded with a different type; check that dates are `DATE` and amounts are numeric |

## 6. Conventions used across the repository

**SQL style**

- Google BigQuery Standard SQL.
- Logic is built in named CTEs, one step per CTE, with a comment explaining each one.
- One-to-many tables (line items, payments, shipments) are always aggregated to order level **before** joining, so totals are not inflated by duplicate rows.
- Business rules (thresholds, tolerances, as-of dates) are declared once at the top of a script, not repeated inside the logic.
- Every script starts with a header block stating the business problem, the outputs and the key rules.

**Data handling**

- Every exclusion is counted and reconciled. Records are never silently dropped.
- Missing values are handled explicitly and the treatment is stated with its evidence. For example, a missing discount is treated as 0 % because every paid order with a missing discount was paid at exactly the undiscounted value.
- Text values such as city names are standardised through a visible mapping table rather than one-off edits.

**Numbers**

- Amounts are in Indian rupees (₹) and use the Indian digit grouping: **₹1 lakh = ₹1,00,000 (100,000)** and **₹1 crore = ₹1,00,00,000 (10 million)**.
- Dates are written as `YYYY-MM-DD` in SQL and in day-month-year form in the text.
- Each case study states its as-of date or period. Results describe that period only.

## 7. How a new case study is added

1. **Choose the category** that matches the business problem, not the SQL technique.
2. **Create a numbered folder** inside it, for example `02_sales_and_profitability/01_discount_leakage/`. Use lowercase with underscores.
3. **Write the business problem and questions first**, before any SQL.
4. **Write `analysis.sql`** with a header block and one commented step per output.
5. **Write `validation.sql`** with pass/fail checks. As a minimum, include:
   - one row per expected key (no duplicates from joins)
   - totals that reconcile back to the source tables
   - every excluded record accounted for
   - any identity the method relies on (for example, components adding up to the total)
6. **Run both scripts** and confirm every check passes.
7. **Write the README** using the ten-section structure. Findings come from the validated output only, and each recommendation refers to a finding.
8. **Update the indexes**: the category `README.md` and the case study table in the root `README.md`.
9. If the case study reveals something new about the data, **update [`schema.md`](datasets_and_documentation/schema.md)**.

## 8. Glossary

| Term | Meaning in this repository |
|---|---|
| **Grain** | What one row represents (for example, one row per order) |
| **CTE** | Common table expression: a named step inside a query, written with `WITH` |
| **Reconciliation** | Showing that two independent totals agree, or explaining exactly why they differ |
| **Validation check** | A query that returns PASS or FAIL against an expected value |
| **As-of date** | The date the analysis is measured at; later transactions are not included |
| **Mapping table** | A table that converts variant values (such as `Bombay`) to a standard value (`Mumbai`) |
| **Receivable** | Money owed by customers for goods already delivered |
| **On-time delivery** | Delivered on or before the promised delivery date |
| **Split shipment** | An order sent in more than one shipment |
| **Days-late decomposition** | Splitting how late an order was into the days added by dispatch, transit and the promise date |
| **Roll-forward** | Opening balance + additions − reductions = closing balance, proved for each period |
| **Cost to serve** | Costs caused by serving a customer beyond the product itself: freight, order handling, sales time and credit |
| **Whale curve** | Cumulative profit by customer, ranked from most to least profitable; it peaks above 100 % when some customers lose money |
| **z-score** | How many standard errors a group's rate is from the overall rate; used to judge whether a difference could be chance |
| **Backtest** | Testing a method on past data it was not built from, to see how it would have performed |
| **Median property** | A validation test that at least half the values sit on each side of a reported median |
| **Censoring** | An observation that has not ended yet (a customer who has not reordered by the as-of date); survival analysis uses it instead of dropping it |
| **Control limits** | The range a stable process stays within about 99.7 % of the time; points outside suggest a real change |
| **Bonferroni correction** | Dividing the significance level by the number of tests, so that testing many pairs does not create false findings |
| **HHI (Herfindahl-Hirschman Index)** | The sum of squared revenue shares; higher means revenue depends on fewer customers |
| **Effective customers** | 1 ÷ HHI: how many equal-sized customers would give the same concentration |
| **Reactivation** | An order from a customer who had been silent for more than 180 days |
| **Within-customer (paired) comparison** | Comparing each customer with itself (for example its late orders against its on-time orders), so that differences between customers cannot explain the result |
| **Customer mix effect** | A difference between groups that comes from which customers are in each group, not from the factor being studied |
| **t-statistic of a slope** | The trend divided by its standard error; around 2 or more suggests a trend that is unlikely to be noise |
| **Mean reversion** | The tendency of unusually high or low values to move back towards normal in the next period |
