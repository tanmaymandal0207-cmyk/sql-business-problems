# Case Study · Small-Order Economics: Do Small Orders Pay After Freight?

> **Status: In progress.** Query and 6 validation checks are included. Findings are written as a reading guide and will be replaced with figures once the queries have been run in BigQuery. Covers valid orders (not Cancelled/Returned), January 2024 – September 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-11 |

## 1. Business problem

The sales team celebrates every order; the warehouse sees every small pick, pack and despatch. With freight largely fixed per shipment, small orders can lose money on a healthy product margin. Finance wants a defensible minimum order value (MOV) or small-order fee.

## 2. Business questions

1. What share of orders and value sits below ₹25k / ₹10k / ₹5k?
2. What is product margin vs freight vs handling by size band?
3. Below what size does the average order go below zero contribution?
4. What MOV or fee recovers the loss?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders`, `sales_order_items` | Order / line | Value and product margin |
| `products` | Product | Unit cost |
| `shipments` | Shipment | Freight per order (summed; 316 nulls → 0, counted) |
| `customers` | Customer | Segment split |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Order value | After-discount line sum; NULL discount = 0% |
| Product margin | `quantity × (net price − unit_cost)` |
| Freight | `SUM(shipping_cost)` per order; NULL → 0 |
| Handling | ₹350/order + ₹45/line (stated assumption; test ±50%) |
| **Contribution** | Product margin − freight − handling |
| Size bands | Under ₹5k / ₹5–10k / ₹10–25k / ₹25k–1L / ₹1L+ |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.sm_orders`) with value, margin, freight, handling, contribution and band.
2. Band economics: share, average margin/freight/handling/contribution, loss-making share.
3. Segment × band split; MOV/fee simulation (₹500 fee under ₹10k); 25 worst contributors.

## 6. SQL techniques used

- Order-level aggregation before joining freight (avoids fan-out)
- `IFNULL` freight handling with explicit null-shipment counter
- Banded analysis with `CASE` + window share (`SUM(COUNT(*)) OVER ()`)

## 7. Validation and reconciliation

The 6 checks in `validation.sql`: order count, value tie-out, contribution identity, band coverage, order uniqueness, freight tie-out.

## 8. Findings

Run `analysis.sql`:

- **Concentration**: order/value share in each band — expect a long tail of sub-₹25k orders carrying a small share of value.
- **Break-even band**: the band where average contribution turns negative (test with handling ±50% by editing the two DECLAREs).
- **Segment view**: which segments place the loss-making small orders.
- **Fee maths**: loss under ₹10k vs ₹500-fee recovery; bottom-25 list for consolidation offers.

## 9. Business implications and recommendations

1. **Set an MOV (e.g. ₹10k) or a ₹500 small-order fee**, waived on consolidated monthly schedules.
2. **Offer consolidation**: prompt repeat small-order customers with a standing monthly slot.
3. **Exempt genuine spares/emergency SKUs** by category rather than blanket-pressuring all small orders.

## 10. Assumptions and limitations

- Handling rates are stated estimates; re-run sensitivity before pricing.
- NULL freight treated as 0 (own-collection assumption); flagged per order.
- Cost is current `unit_cost`; excludes credit cost and losses.
