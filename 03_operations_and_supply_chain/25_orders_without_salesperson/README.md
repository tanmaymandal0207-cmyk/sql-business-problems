# Case Study · Orders With No Salesperson: Value, Fulfilment and Collection

> **Status: In progress.** Query and 6 validation checks are included. Findings are written as a reading guide and will be replaced with figures once the queries have been run in BigQuery. Covers all 10,000 orders, January 2024 – September 2026.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-11 |

## 1. Business problem

352 orders (3.5%) carry no salesperson. Every study notes them and moves on. Operations suspects they wait longer, deliver later and collect slower — with nobody chasing. Sales suspects they are web/phone reorders that need no one. Both cannot be right without numbers.

## 2. Business questions

1. How much value and open balance sits on unassigned orders?
2. Do they deliver and arrive on time at the same rate?
3. Is it a segment, quarter or weekday pattern (e.g. weekend web orders)?
4. What coverage rule clears the queue?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | Order | Assignment flag, status, promise date |
| `sales_order_items` | Line | Order value |
| `payments` | Receipt | Paid and balance per order |
| `shipments` | Shipment | Delivery date, freight |
| `customers` | Customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Unassigned | `employee_id IS NULL` (352 expected — check 02) |
| Order value | After-discount line sum |
| Balance | Value − lifetime receipts |
| On-time | `delivered_on ≤ promised_delivery_date`; NULL if either date missing |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.un_orders`) with value, paid, balance, delivery and on-time flag.
2. Assigned vs unassigned: count, value, delivered share, on-time share, open balance.
3. Segment, quarter and weekday splits; top-25 unassigned open balances.

## 6. SQL techniques used

- Order-level pre-aggregation of lines, payments and shipments before joining (avoids fan-out)
- Nullable-date logic with explicit `CASE` for on-time
- `DAYOFWEEK` pattern scan for channel/shift effects

## 7. Validation and reconciliation

The 6 checks in `validation.sql`: row count, 352-null tie-out, value and paid tie-outs, balance identity, on-time null logic.

## 8. Findings

Run `analysis.sql`:

- **Headline gap**: compare delivered %, on-time % and open-balance share between assigned and unassigned.
- **Pattern**: segment/quarter/weekday splits show whether it is structural (e.g. weekend) or scattered neglect.
- **Action list**: top-25 unassigned balances for immediate ownership.

## 9. Business implications and recommendations

1. **Auto-assign within 24 hours** by customer owner (fallback: duty roster for genuinely new customers); measure unassigned age as a KPI.
2. **Clear the top-25 balances** first — assign an owner and a collection date each.
3. If the weekday split shows a weekend spike, **staff a weekend cover rota** instead of blaming individuals.

## 10. Assumptions and limitations

- Assignment is as recorded; reassignments over time are not visible.
- NULL promise/delivery excluded from on-time rate and counted.
- Describes this dataset only.
