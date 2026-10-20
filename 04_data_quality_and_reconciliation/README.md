# 04 · Data Quality and Reconciliation

Case studies that test whether the data can be trusted before it is used for reporting — integrity, consistency and order-to-cash reconciliation.

## Typical business questions

- Do order, line-item, payment and shipment records reconcile with each other?
- Does each order's payment status agree with the payments actually recorded against it?
- Where are keys missing, values null or text values inconsistently formatted?
- Are there potential duplicate customers or transactions?

## Primary tables

All tables — see [schema](../datasets_and_documentation/schema.md), including the profiling notes on known data characteristics.

## Case studies

| # | Case study | Status |
|---|---|---|
| 01 | [Order-to-cash reconciliation](01_order_to_cash_reconciliation/) — does the order payment flag agree with payments received, and how old are open receivables? | Complete |
| 02 | [Data quality scorecard](02_data_quality_scorecard/) — a 29-rule, repeatable scorecard across all tables, ranked by business impact | Complete |
| 03 | [Customer master de-duplication](03_customer_master_deduplication/) — which customer records are duplicates, and which record should survive? | Complete |
| 04 | [Revenue cut-off reconciliation](04_revenue_cutoff_reconciliation/) — how much does order-date reporting misstate monthly and financial-year revenue? | Complete |
