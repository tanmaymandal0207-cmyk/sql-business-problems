# 03 · Operations and Supply Chain

Case studies on order fulfilment — whether orders ship and arrive on time, what delivery costs, and where returns occur.

## Typical business questions

- What share of orders is delivered by the promised delivery date?
- Where and for which products do delivery delays concentrate?
- How does shipping cost vary by destination and order size?
- Which customers, products or routes account for returns?

## Primary tables

`sales_orders`, `shipments`, `sales_order_items`, `products`, `customers` — see [schema](../datasets_and_documentation/schema.md).

## Case studies

| # | Case study | Status |
|---|---|---|
| 01 | [Late delivery root cause](01_late_delivery_root_cause/) — is lateness caused by dispatch, transit or promise-setting? | Complete |
| 02 | [Freight cost-to-serve and minimum order value](02_freight_cost_to_serve/) — do small orders cost more to ship than they earn? | Complete |
| 03 | [Open order backlog review](03_open_order_backlog_review/) — which open orders at month-end are overdue, stuck in transit, or delivered but never closed? | Complete |
| 04 | [Dispatch workload and capacity planning](04_dispatch_workload_planning/) — when does dispatch work peak, how much capacity is needed, and does load slow dispatch? | Complete |
| 05 | [City-wise delivery promise standards](05_promise_date_standards/) — what promise date should each city get, tested on 2026 orders? | Complete |
| 06 | [Cancellation and return leakage](06_cancellation_return_leakage/) — how much do cancellations and returns cost, and is any group responsible beyond chance? | Complete |
| 07 | [Shipment consolidation opportunity](07_shipment_consolidation/) — what would fixed dispatch schedules save in freight, and how long would goods wait? | Complete |
| 08 | [Safety stock and reorder points](08_safety_stock_reorder_points/) — what safety stock, reorder point and order quantity should each product have, and would it have worked? | Complete |
| 09 | [Statistical process control](09_statistical_process_control/) — which weekly swings in late delivery and cancellations are real, and which are noise? | Complete |
| 10 | [Split shipment drivers](10_split_shipment_drivers/) — what causes split shipments, and how much lateness and freight do they add? | Complete |
| 11 | [Dispatch holds](11_dispatch_holds/) — why does one order in nine wait 1–3 weeks before dispatch, and what does it cost in lateness? | Complete |
| 12 | [Warehouse slotting by pick frequency](12_warehouse_slotting/) — which products belong nearest the dispatch bay, and how much walking would it save? | Complete |
| 13 | [Key-account service equity](13_key_account_service_equity/) — do Enterprise customers get faster delivery, or just longer promises? | Complete |
| 14 | [Empirical Bayes for operational rates](14_empirical_bayes_rates/) — which cancellation, return and late-delivery rankings show real differences, and which are noise? | Complete |
| 15 | [Dispatch queue discipline](15_dispatch_queue_discipline/) — are orders dispatched first come, first served, and what would strict FIFO change for waits and on-time delivery? | Complete |
| 16 | [Little's Law backlog planning](16_littles_law_backlog_planning/) — how many orders wait for dispatch and travel at once, does Little's Law hold, and what does 2027 need? | Complete |
| 17 | [Dispatch capacity simulation](17_dispatch_capacity_simulation/) — what daily dispatch capacity does a first-in-first-out queue need today and in 2027, and is capacity the real constraint? | Complete |
