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
| 05 | [Receivables roll-forward reconciliation](05_receivables_rollforward/) — does the receivables balance roll forward every month and agree with the ageing? | Complete |
| 06 | [Order anomaly screen](06_order_anomaly_screen/) — which order lines are unusual, and are they errors or genuine large orders? | Complete |
| 07 | [Benford's law forensic test](07_benford_forensic_test/) — do payment and order amounts behave like genuine data, and where do they not? | Complete |
| 08 | [Ship-to vs bill-to reconciliation](08_ship_to_bill_to_reconciliation/) — which delivery-city mismatches are naming only, and which cross a state border? | Complete |
| 09 | [Freight invoice audit](09_freight_invoice_audit/) — are carriers charging consistently against a rate card inferred from the charges? | Complete |
| 10 | [Monetary unit sampling](10_monetary_unit_sampling/) — what will the auditors' sample of payment statuses find, and how often is MUS right? | Complete |
| 11 | [Order splitting test](11_order_splitting_test/) — is there any sign of orders split or sized to stay under approval limits? | Complete |
| 12 | [Order-to-cash process mining](12_order_to_cash_process_mining/) — which paths do orders really take from order to cash, where does the time go, and which deviations are errors? | Complete |
| 13 | [Data drift monitoring](13_data_drift_monitoring/) — which monthly shifts in the data are real, which are expected, and what alert rule should the refresh use? | Complete |
| 14 | [Weekend and holiday postings test](14_weekend_holiday_postings/) — which transaction dates follow the business calendar, and which cheques are dated on non-banking days? | Complete |
