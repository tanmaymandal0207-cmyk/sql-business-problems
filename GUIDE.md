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
3. [Customer revenue risk](01_customer_and_revenue/01_customer_revenue_risk/): an example of a version 1 query with its known issues documented openly.

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
| Customer revenue risk | None (single query) |
| Order-to-cash reconciliation | `order_payment_reconciliation` |
| Late delivery root cause | `city_name_map`, `delivery_performance` |
| Customer churn early warning | `customer_activity_status` |
| Discount and margin erosion | `sales_line_margin` |
| Freight cost-to-serve | `order_cost_to_serve` |
| Data quality scorecard | `data_quality_results` |
| ABC-XYZ product classification | `product_abc_xyz` |

### 5.4 If something does not match

| Symptom | Likely cause |
|---|---|
| `Not found: Table ...` | The table name differs from the script (check spelling and case), or the dataset is not named `sahyadri_b2b` |
| `Not found: Table sahyadri_b2b.Sales_Orders` in Customer revenue risk | Version 1 of that query uses `Sales_Orders`; change it to `sales_orders`. This is listed as a known issue in its README. |
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
