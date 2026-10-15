<p align="center">
  <img src="images/banner.svg" alt="SQL Business Problems — business questions answered with SQL in Google BigQuery" width="100%">
</p>

Business problems analysed and answered with SQL — each case study starts from a business question, not from a query.

<p align="center">
  <img src="https://img.shields.io/badge/SQL-BigQuery%20Standard%20SQL-DCE6F2?labelColor=17283B" alt="SQL: BigQuery Standard SQL">
  <img src="https://img.shields.io/badge/Categories-5-DCE6F2?labelColor=17283B" alt="Categories: 5">
  <img src="https://img.shields.io/badge/Case%20studies-1%20complete%20%C2%B7%201%20in%20progress-DCE6F2?labelColor=17283B" alt="Case studies: 1 complete, 1 in progress">
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
├── 01_customer_and_revenue/
│   └── 01_customer_revenue_risk/
├── 02_sales_and_profitability/
├── 03_operations_and_supply_chain/
├── 04_data_quality_and_reconciliation/
├── 05_advanced_analytics/
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
| 1 | [Customer revenue risk](01_customer_and_revenue/01_customer_revenue_risk/) | Customer and revenue | Version 1 query added · findings pending revision |
| 2 | [Order-to-cash reconciliation](04_data_quality_and_reconciliation/01_order_to_cash_reconciliation/) | Data quality and reconciliation | Complete |

Case studies are listed as complete only once their SQL, validation and findings have been added to the repository.

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
