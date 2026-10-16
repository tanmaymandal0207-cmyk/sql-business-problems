# Case Study · Data Quality Scorecard

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Snapshot of the dataset as loaded (transactions to 30 Sep 2026).

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-16 |

---

## 1. Business problem

The company is about to build management dashboards on its order data. Earlier analyses in this repository kept hitting the same gaps: missing product costs, missing freight, inconsistent city names and duplicate payment receipts. Each one was handled case by case. The data owner now wants a **repeatable scorecard** that measures data quality across every table, ranks the issues by business impact, and can be re-run to track whether the fixes work.

## 2. Business questions

1. Which data quality rules fail, on which tables, and for how many records?
2. Which failures are serious enough to distort financial reporting?
3. Which table and which quality dimension need attention first?

## 3. Dataset and relevant tables

All seven transactional and master tables are checked: `customers`, `products`, `employees`, `sales_orders`, `sales_order_items`, `payments` and `shipments`.

## 4. Metric definitions

**Quality dimensions** (standard data management framework):

| Dimension | Question it answers | Rules |
|---|---|---:|
| Completeness | Is the value there? | 11 |
| Validity | Is the value allowed (range, sign, date order)? | 6 |
| Uniqueness | Is the record recorded only once? | 3 |
| Consistency | Does the value agree with related data and formats? | 5 |
| Referential integrity | Does every reference point to a real record? | 4 |

**Severity** reflects business impact, not the number of failures:

| Severity | Meaning |
|---|---|
| High | Distorts revenue, margin, cash or receivables reporting |
| Medium | Distorts operational reporting (delivery performance, sales attribution) |
| Low | Descriptive attributes; limits segmentation only |

**Pass rate** = 1 − records failed ÷ records checked. Some rules check only the relevant records. For example, delivery date completeness checks only shipments marked Delivered.

## 5. Analytical approach

1. **Rule register.** 29 rules, each written as one `SELECT` that returns records checked and records failed. They are combined with `UNION ALL` and saved as `sahyadri_b2b.data_quality_results`.
2. **Full scorecard**, ordered by severity, then by the number of failed records.
3. **Summary by table.**
4. **Summary by dimension.**

New rules are added by appending one more `SELECT` to the register. The output table keeps the same shape, so results from different runs can be compared.

## 6. SQL techniques used

- A rule register built from `UNION ALL` blocks that share one output shape
- `COUNTIF` for rule failures and `COUNT(*) - COUNT(DISTINCT ...)` for duplicates
- `LEFT JOIN … IS NULL` for referential integrity and consistency checks
- Text normalisation with `LOWER`, `TRIM`, `REGEXP_REPLACE` and `INITCAP`
- `SAFE_DIVIDE` for pass rates, and severity-based ordering with `CASE`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**. Checks 05–10 count the same rule a **second way, with different SQL**, so they test the logic rather than repeat it.

| # | Check |
|---|---|
| 01 | Every rule ID is unique |
| 02 | All 29 rules are present |
| 03 | No rule reports more failures than records checked, and no counts are NULL |
| 04 | Whole-table completeness rules checked exactly the table's row count |
| 05 | Missing discounts recounted with `COUNT(column)` |
| 06 | Missing freight recounted with `COUNT(column)` |
| 07 | Duplicate payments recounted with `ROW_NUMBER()` |
| 08 | Unpaid orders with payments recounted with `EXISTS` |
| 09 | Duplicate customer IDs recounted with `GROUP BY … HAVING` |
| 10 | Delivered orders without a shipment recounted with `NOT EXISTS` |

## 8. Findings

**19 of 29 rules fail, but the structure of the data is sound.** All 4 referential-integrity rules pass, and 5 of 6 validity rules pass. The problems are almost entirely **missing values** and **inconsistent statuses or formats**.

| Dimension | Rules | Failing | Records failed |
|---|---:|---:|---:|
| Completeness | 11 | 11 | 1,405 |
| Consistency | 5 | 5 | 174 |
| Uniqueness | 3 | 2 | 9 |
| Validity | 6 | 1 | 2 |
| Referential integrity | 4 | 0 | 0 |

**Six high-severity failures affect financial reporting:**

| Rule | Issue | Records | Impact |
|---|---|---:|---|
| C02 | Order lines with no discount value | 336 | Revenue becomes NULL and drops out of totals unless handled |
| C03 | Shipments with no freight cost | 316 | Freight and cost-to-serve are understated |
| C01 | Products with no unit cost | 4 | Margin cannot be calculated on their sales |
| V01 | Products with a list price below unit cost | 2 | Every sale at list price loses money |
| U03 | Payments recorded twice | 7 | Cash received and customer balances are overstated |
| K04 | Orders marked Unpaid that have been paid | 4 | Receivables are overstated |

**The worst medium-severity issues limit operational reporting:**

- 352 orders (3.5 %) have no salesperson, so sales performance cannot be attributed.
- 166 orders (1.7 %) have no promised delivery date, so on-time delivery cannot be measured for them.
- 154 shipments (1.5 %) have untrimmed or wrongly cased city names.
- 7 of the 58 orders still marked Shipped already have a delivered shipment, so the order status was not updated.
- 5 shipments are dated before their order, which is impossible.

**By table**, every failing rule on `products` and `sales_order_items` is high severity. `sales_orders` has the most failing rules (5 of 8).

## 9. Business implications and recommendations

1. **Fix the six high-severity rules before the dashboards go live.** Together they affect fewer than 700 records, so the effort is small and the reporting impact is large.
2. **Make key fields mandatory at entry** in the ERP: discount (default 0), freight cost on dispatch, unit cost on product creation, salesperson and promised date on every order.
3. **Block duplicate receipts at posting.** Warn when a payment matches an existing one on order, date and amount (the cause found in [Order-to-cash reconciliation](../01_order_to_cash_reconciliation/)).
4. **Derive statuses from transactions** instead of maintaining them by hand. Payment status should come from payments, and order status should follow shipment status.
5. **Use a city master list.** Format rules catch case and spacing, but not historic names such as Bombay or Calcutta. The mapping table built in [Late delivery root cause](../../03_operations_and_supply_chain/01_late_delivery_root_cause/) can serve as the starting master.
6. **Run the scorecard monthly** and keep each run's results with a run date, so the trend in failed records becomes a data-quality KPI with a named owner for each table.

## 10. Assumptions and limitations

- **Rule coverage.** 29 rules cover the issues known from this repository's analyses and standard checks. They do not prove the data is free of other errors.
- **Format, not meaning.** K01 checks city name formatting only. Alternate city names (for example Bombay vs Mumbai) need a mapping table.
- **Business rules are assumptions.** For example, the rule that an Unpaid order should have no payments assumes the status is meant to reflect receipts.
- **Severity is a judgement** based on how each field is used in this repository's analyses. Another business might rank the rules differently.
- **Pass rates** are not weighted by monetary value. A single missing cost on a high-volume product may matter more than many missing industry codes.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | 29-rule register and 3 summary views |
| `validation.sql` | 10 pass/fail checks, including independent recounts |
