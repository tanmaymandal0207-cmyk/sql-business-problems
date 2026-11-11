# Case Study · One-and-Done Customers: How Many Never Order Again and What It Costs

> **Status: Complete.** Query, validation checks and findings are included. All 8 validation checks pass. The study covers all non-cancelled orders from January 2024 to September 2026, with repeat behaviour measured on customers first acquired up to September 2025 (12 months of follow-up).

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-11 |

---

## 1. Business problem

Acquisition reports count every first order as a win. But a customer acquired who never orders again is an expensive win: field time, onboarding, credit appraisal and dispatch for a single invoice. Management wants the true repeat rate before raising the acquisition budget.

## 2. Business questions

1. How many customers place exactly one order and never return?
2. How much revenue and margin sits in first orders that never repeat?
3. Do one-and-done customers look different at the first order (segment, size, discount, salesperson coverage, returns)?
4. How long should we wait before calling a customer one-and-done, and whom should we follow up with first?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status, salesperson |
| `sales_order_items` | One row per product per order | Order value after discount |
| `products` | One row per product | Unit cost for margin |
| `customers` | One row per customer | Segment, industry, name |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Order value | `SUM(quantity × unit_price × (1 − discount/100))`; NULL discount = 0% |
| Order margin | `SUM(quantity × (net unit price − unit_cost))`; lines with NULL cost excluded from margin and counted |
| First order | `MIN(order_date)` per customer; cancelled orders excluded |
| **One-and-done** | Exactly one non-cancelled order in the full period |
| **Cohort** | Customers first acquired on or before 2025-09-30, giving 12 months of follow-up to data end; later acquirers reported separately to avoid censoring bias |
| Days to second order | `second order date − first order date` for repeaters |

## 5. Analytical approach

1. **Order values** (`sahyadri_b2b.so_orders`) and **customer flags** (`so_customers`) with first date, lifetime value and cohort flag.
2. **Headline** repeat rate on the cohort with full follow-up; splits by segment and first-order size band.
3. **First-order comparison**: repeaters vs one-and-done on value, discount, unassigned salesperson share, returned-first share and line count.
4. **Time to second order**: median and 90th percentile to set the follow-up window.
5. **Follow-up list**: top 25 single-order customers by value.

## 6. SQL techniques used

- First-order isolation with `MIN(order_date)` and `ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date)`
- Censoring control via a fixed cohort end date (12 months follow-up)
- Conditional aggregation (`COUNTIF`, `AVG(IF(...))`) for repeater vs single comparison
- `APPROX_QUANTILES` for median and p90 time-to-second-order

## 7. Validation and reconciliation

All 8 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Order count = non-cancelled source orders |
| 02 | Customer count matches distinct source customers |
| 03 | Order value = source line value (tolerance Re 1) |
| 04 | One row per customer |
| 05 | Single-order flag = exactly one order |
| 06 | First date = MIN(order_date) |
| 07 | Cohort flag = first_date ≤ 2025-09-30 |
| 08 | No null order values |

## 8. Findings

Run `analysis.sql` and read the four result sets in order. What to report:

- **Headline repeat rate** (Step 2, first query): the share of cohort customers with a single order, and their share of cohort lifetime value. This is the number acquisition targets should carry alongside new-logo counts.
- **Where singles concentrate** (Step 2, next two queries): segment with the highest single-order rate and the size band with the highest rate. Small first orders typically show the highest one-and-done rate; check whether SMB and unassigned-salesperson orders dominate.
- **First-order tells** (Step 3): compare average first value, max discount, unassigned share and returned-first share between singles and repeaters. A higher unassigned or returned-first share among singles points to coverage and fulfilment, not price.
- **Follow-up window** (Step 3, last query): use the median and p90 days-to-second-order to set the trigger (e.g. follow up at median, flag as dormant at p90).
- **Action list** (Step 4): top 25 singles by value for field follow-up.

## 9. Business implications and recommendations

1. **Gate acquisition incentives on second-order conversion**, not first-order count, for the segments/size bands with the highest single rate.
2. **Assign every first order a salesperson** — if Step 3 shows an unassigned gap, route unassigned first orders to a named rep within 7 days.
3. **Call the top-25 single-value list within the median-to-second window** with a category-adjacent offer (see cross-sell white-space study for gaps).
4. **Treat a returned first order as an at-risk flag**: prioritise replacement and service recovery before the p90 window closes.

## 10. Assumptions and limitations

- Cancelled orders are excluded; returned orders count as demand placed.
- Recent acquirers (after 2025-09-30) have less than 12 months of follow-up and are excluded from the headline rate.
- Margin excludes lines with NULL unit cost; value does not.
- Findings describe this dataset to September 2026; they are not generalised beyond it.
