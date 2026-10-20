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
