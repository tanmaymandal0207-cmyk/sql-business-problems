# Case Study · Selling Below Cost: Which Orders Lose Money and Why

> **Status: In progress.** Query and 6 validation checks are included. Findings are written as a reading guide and will be replaced with figures once the queries have been run in BigQuery. Covers non-cancelled orders January 2024 – September 2026 with known product cost.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-11 |

## 1. Business problem

Margin reviews average away the worst invoices. Sales needs a guardrail: which lines were priced below product cost, and was the list price already below cost or did the discount push it there?

## 2. Business questions

1. How many lines/orders are sold below cost, and how much margin is lost?
2. Is it list-price-below-cost or discount-driven?
3. Which products, categories and segments concentrate the loss?
4. What floor (list check + discount cap) would have prevented it?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, date, customer |
| `sales_order_items` | One row per product per order | Net price, quantity, discount |
| `products` | One row per product | List price (`selling_price`), `unit_cost` |
| `product_categories`, `customers` | Masters | Category and segment splits |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Line value | `quantity × unit_price × (1 − discount/100)`; NULL discount = 0% |
| Line margin | `quantity × (net unit price − unit_cost)`; NULL-cost lines excluded and counted |
| **Below-cost line** | Net unit price < `unit_cost` |
| **List-below-cost** | `selling_price` < `unit_cost` (price-master error, not a sales decision) |

## 5. Analytical approach

1. **Lines** (`sahyadri_b2b.nm_lines`) with value, margin and both flags.
2. Headline loss and list-caused share.
3. Splits by category and segment; worst products and worst orders.

## 6. SQL techniques used

- Net-price vs cost comparison in one pass; `COUNTIF` for below-cost shares
- Master joins kept at line grain to avoid row inflation
- `HAVING COUNTIF(below_cost) > 0` to isolate loss-makers

## 7. Validation and reconciliation

The 6 checks in `validation.sql` (counts vs source, no nulls, both flags recounted, list-caused ⊆ below-cost, line uniqueness).

## 8. Findings

Run `analysis.sql` top to bottom:

- **Headline**: below-cost line share and margin loss in lakh; list-caused share tells whether to fix the price master or discount authority first.
- **Category / segment**: which category and segment carry the loss and the average discount on below-cost lines.
- **Action lists**: top-15 products and bottom-20 orders by margin for price-master correction and credit/rebill review.

## 9. Business implications and recommendations

1. **Block list-below-cost items** in the price master (the 2 products flagged in schema profiling are the first suspects) — require costing sign-off before any quote.
2. **Cap discounts where net price nears cost**: system warning at cost + 5%, approval above it.
3. **Review the bottom-20 orders** for rebill, return or goodwill justification; log the reason.

## 10. Assumptions and limitations

- Cost is `products.unit_cost` at analysis time, not historical cost; NULL-cost lines excluded.
- Freight, handling and credit costs are excluded (see cost-to-serve study for fully-loaded view).
- Describes this dataset to September 2026 only.
