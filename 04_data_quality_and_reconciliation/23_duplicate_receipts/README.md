# Case Study · Duplicate Receipts: How Much Was Collected Twice

> **Status: In progress.** Query and 5 validation checks are included. Findings are written as a reading guide and will be replaced with figures once the queries have been run in BigQuery. Covers all 10,568 payment receipts.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-11 |

## 1. Business problem

Schema profiling found 7 receipts repeating an earlier receipt for the same order, date and amount. Order-to-cash excludes them from performance — but the money may still be with us. Finance needs the refund list and a control that stops the next double-entry.

## 2. Business questions

1. Which receipts are exact duplicates (same order, date, amount)?
2. How much double-collected value is at stake?
3. Do duplicates cluster by method, customer or timing?
4. What matching rule flags them at entry?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `payments` | Receipt | Duplicate grouping |
| `sales_orders`, `sales_order_items` | Order / line | Order value for overpayment test |
| `customers` | Customer | Name and segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Duplicate group | `(order_id, payment_date, amount)` with >1 receipt |
| Original | Lowest `payment_id` in the group; the rest are duplicates |
| **Refund exposure** | Duplicate amount on an order whose lifetime receipts exceed its value (`overpaid = paid − value > 0`) |

## 5. Analytical approach

1. **Ranked receipts** (`sahyadri_b2b.dr_receipts`) with group size, original/duplicate flags.
2. Headline duplicate count and value; group listing with payment IDs.
3. Method breakdown; per-duplicate overpayment vs order value.

## 6. SQL techniques used

- Duplicate detection with `COUNT(*) OVER (PARTITION BY ...)` + `ROW_NUMBER()`
- `STRING_AGG` of payment IDs per group for the audit trail
- Overpayment test via order-value vs lifetime-paid join

## 7. Validation and reconciliation

The 5 checks in `validation.sql`: row count, group key integrity, one original per group, duplicate-amount identity, payment uniqueness.

## 8. Findings

Run `analysis.sql`:

- **Headline**: duplicate receipt count and lakh exposure (expect ~7 duplicates per profiling notes).
- **Groups**: the order/date/amount clusters with IDs for the refund file.
- **Method**: whether a method (or the one missing-method receipt) dominates.
- **Exposure**: per-duplicate overpayment — positive means refund or adjust; zero/negative means the duplicate merely reduced an underpayment.

## 9. Business implications and recommendations

1. **Refund or adjust** every duplicate with positive overpayment; write to the customer with both receipt IDs.
2. **Add an entry control**: block `(order_id, date, amount)` repeats unless a supervisor overrides with a reason code.
3. **Fix the missing-method receipt** as part of the same pass (see payment-rails audit for method rules).

## 10. Assumptions and limitations

- Exact-match rule only; near-duplicates (off-by-a-day or fees) are out of scope.
- Original = earliest `payment_id`; operational truth may differ if the first entry was the error.
