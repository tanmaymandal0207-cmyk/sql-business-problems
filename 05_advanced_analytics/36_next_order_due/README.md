# Case Study · Next Order Due: Whose Ordering Rhythm Has Slipped

> **Status: In progress.** Query and 6 validation checks are included. Findings are written as a reading guide and will be replaced with figures once the queries have been run in BigQuery. Covers reordering customers (3+ orders) to 30 September 2026, with a June-2026 back-test for July reorders.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-11 |

## 1. Business problem

Reorder reminders fire on fixed category clocks; field reps work alphabetically. Every reordering customer has its own rhythm — and a slip against that rhythm is the earliest demand signal. Management wants a ranked due-list, proven to predict reorders, not another static segment.

## 2. Business questions

1. What is each customer's typical gap and spread between orders?
2. Who is overdue today against their own rhythm, and by how much?
3. Does overdue-against-own-rhythm actually predict who reorders next month?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | Order | Consecutive-order gaps, last date, July reorder label |
| `customers` | Customer | Name, segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Gap | Days between consecutive non-cancelled orders of the same customer |
| **Rhythm (median gap)** | p50 of a customer's gaps; spread = p90 − p50 |
| **Due date** | Last order date + median gap (as of 30 Sep 2026) |
| **Overdue / far overdue** | Days since last order > median / > p90 |
| Back-test | Score as of 30 Jun 2026, label = reorder in next 31 days; AUC by Mann–Whitney rank; no look-ahead (only orders ≤ as-of used for rhythm) |

## 5. Analytical approach

1. **Gaps and rhythms** (`sahyadri_b2b.no_gaps`, 3+ orders only).
2. **Due list** (`no_due`) with days overdue and both flags.
3. **Back-test AUC** for July-2026 reorders; top-25 overdue list.

## 6. SQL techniques used

- Consecutive gaps via `LAG()` / self-join on `ROW_NUMBER()`
- `APPROX_QUANTILES(...,100)[OFFSET(50/90)]` for median and p90 in SQL
- Point-in-time back-test with an as-of cut-off; AUC from `RANK()` (Mann–Whitney)

## 7. Validation and reconciliation

The 6 checks in `validation.sql`: scored-customer count, gaps = orders − 1, due-date identity, flag logic, no nulls, customer uniqueness.

## 8. Findings

Run `analysis.sql`:

- **Headline**: scored customers, overdue and far-overdue counts and share.
- **Due list**: top-25 by days overdue with rhythm and last date for the call plan.
- **Proof**: back-test AUC — above 0.5 means overdue rank predicts July reorders; report alongside the reorder base rate.

## 9. Business implications and recommendations

1. **Work the far-overdue list first**, then plain overdue sorted by days overdue — not alphabetically.
2. **Trigger at due date + 25% of median gap** for routine SKUs; escalate at p90.
3. **Keep fixed-clock reminders only for 1–2 order customers**; rhythm needs 3+ orders.

## 10. Assumptions and limitations

- Needs 3+ orders; newer customers are unscored by design.
- Cancelled orders excluded; returns kept as demand.
- Single-month back-test (July 2026); re-run across months before automating.
