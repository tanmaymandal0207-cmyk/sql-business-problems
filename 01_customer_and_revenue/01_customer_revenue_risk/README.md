# Case Study 01 · Customer Revenue Risk

> **Status: In preparation.** Sections marked _Pending_ will be completed once the analysis query is added, run in BigQuery and its results verified. No findings are reported until then.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL |
| **Last updated** | _Pending_ |

---

## 1. Business problem

_Pending._

<!-- One short paragraph: what the business is concerned about, who needs the answer, and what decision the analysis supports. -->

## 2. Business questions

_Pending._

<!-- 3–5 specific, answerable questions. Example format:
1. Which customers ...?
2. How much revenue ...?
-->

## 3. Dataset and relevant tables

_Pending — to be confirmed against the final query._

| Table | Grain | Used for |
|---|---|---|
| _Pending_ | | |

Join path and grain notes: _Pending._

Full schema: [`datasets_and_documentation/schema.md`](../../datasets_and_documentation/schema.md)

## 4. Metric definitions

_Pending._

| Metric | Definition | Grain | Notes |
|---|---|---|---|
| _Pending_ | | | |

Shared definitions are maintained in [`metric_definitions.md`](../../datasets_and_documentation/metric_definitions.md). Any case-specific deviation is stated here.

## 5. Analytical approach

_Pending._

<!-- Numbered steps that mirror the CTE sequence in analysis.sql, e.g.
1. Build order-level revenue from line items.
2. Aggregate to customer by period.
3. ...
-->

## 6. SQL techniques used

_Pending — listed only for techniques actually used in the final query._

<!-- e.g. CTEs, window functions, conditional aggregation, date functions -->

## 7. Validation and reconciliation

_Pending._

| Check | Method | Expected | Result |
|---|---|---|---|
| _Pending_ | | | |

<!-- Typical checks: source vs. output revenue totals reconcile; row counts before/after each join; no duplicate customer rows in output; null and status handling confirmed. -->

## 8. Findings

_Pending — to be written only after results have been run and validated._

## 9. Business implications and recommendations

_Pending — each recommendation will reference the finding it is based on._

## 10. Assumptions and limitations

_Pending._

<!-- e.g. treatment of cancelled/returned orders, null discounts, partial payments, analysis cut-off date. -->

---

## Files

| File | Purpose | Status |
|---|---|---|
| `README.md` | Case study documentation (this file) | Template |
| `analysis.sql` | Primary analysis query | To be added |

Additional files (for example, validation queries or result extracts) will be listed here only when they are added.
