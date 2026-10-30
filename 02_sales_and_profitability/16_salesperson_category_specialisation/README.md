# Case Study · Salesperson Category Specialisation: Generalists or Specialists?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 16 salespeople's category mix (January 2024 – September 2026) compared with 200 random reallocations of their orders under two benchmarks, a test of whether focus buys better prices, and the customer coverage a product-line split would create.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-30 |

---

## 1. Business problem

The Head of Sales is considering splitting the team by product line: fluid power (pneumatic, hydraulic, valves, pumps), mechanical and electrical (bearings, power transmission, motors, fasteners) and MRO consumables (cutting tools, safety equipment). The argument is that salespeople already specialise, and that specialists sell their categories at better prices. Before redrawing territories she wants evidence that specialisation exists, that it pays, and an estimate of what the split would do to customers.

## 2. Business questions

1. Does any salesperson's category mix differ from the company mix by more than random allocation of orders would produce?
2. Is any difference down to the customers they serve, or to the salesperson?
3. Do salespeople give smaller discounts in the categories they sell most?
4. How many customers would a product-line split hand to several salespeople?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Salesperson, customer, date, status |
| `sales_order_items` | One row per product per order | Line value, discount |
| `products`, `product_categories` | One row per product / category | Category |
| `employees` | One row per employee | Designation |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Lines used | Valid orders (not Cancelled or Returned) with a salesperson, Jan 2024 – Sep 2026 (orders without a salesperson are excluded) |
| **Specialisation index D** | 0.5 × Σ \|salesperson's revenue share in a category − company share\|: 0 = the company mix exactly, 1 = entirely different |
| Focus index | Salesperson's share of a category ÷ the company share (1.0 = average) |
| **"Any order" benchmark** | Salesperson labels shuffled across all orders, 200 times, keeping each salesperson's number of orders |
| **"Same customer" benchmark** | Labels shuffled only among each customer's own orders: keeps who serves whom, removes any influence of the salesperson on what is bought |
| p-value | Share of shuffles with an index at least as large as observed; with 16 salespeople, p < 0.003 is needed (Bonferroni) |
| Discount gap | A salesperson's average discount % in a category − the category average (cells with 30+ lines) |
| Product lines | Fluid power; mechanical and electrical; MRO consumables (as above) |

## 5. Analytical approach

1. **Lines** (`sahyadri_b2b.sp_lines`) and **order × category values** (`sahyadri_b2b.sp_order_categories`).
2. **Shuffles** (`sahyadri_b2b.sp_shuffles`) for both benchmarks and the **index** (`sahyadri_b2b.sp_index`) for every salesperson and shuffle; team-level test.
3. **Discount and focus**: weighted correlation across salesperson × category cells.
4. **Coverage**: customers by number of product lines bought in the last 12 months.

## 6. SQL techniques used

- A dissimilarity index between two distributions, computed on a complete salesperson × category grid (`CROSS JOIN` plus `LEFT JOIN`)
- Two permutation designs in one table: a global shuffle and a shuffle within customer, both by integer hash and `ROW_NUMBER()`
- A weighted correlation and slope written from sums, with an approximate t statistic
- Validation that every shuffle is a true permutation: each order once, each salesperson's order count kept, and each customer's salespeople kept in the within-customer design

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Lines = valid order lines with a salesperson in the period (count and value) |
| 02 | Order × category values add up to the lines |
| 03 | Every order appears once in every shuffle |
| 04 | **Every shuffle keeps each salesperson's number of orders** |
| 05 | **Same-customer shuffles keep each customer's salespeople and their order counts** |
| 06 | b = 0 keeps the real salesperson on every order |
| 07 | Observed index = a rebuild from order lines |
| 08 | Index in 0–1; salesperson revenues add to the total in every shuffle |
| 09 | Ten categories mapped to three product lines, one line each |
| 10 | Recent customers by product lines add up to all recent customers |

## 8. Findings

**Nobody specialises.** Every salesperson sells close to the company mix: indices range from 0.029 to 0.150, where 0 is identical and 1 entirely different.

| Salesperson | Designation | Revenue | Index | Random: any order (p) | Random: same customer (p) | Most over-sold category |
|---|---|---:|---:|---:|---:|---|
| 114 | Sales Executive | ₹2.97 crore | **0.150** | 0.087 (0.06) | 0.145 (0.56) | Pumps (1.48 ×) |
| 112 | Senior Sales Executive | ₹0.80 crore | 0.084 | 0.092 (0.51) | 0.110 (0.76) | Power Transmission (2.08 ×) |
| 106 | Key Account Manager | ₹12.77 crore | 0.082 | 0.039 (**0.02**) | 0.055 (0.12) | Pumps (1.31 ×) |
| 103 | Regional Sales Manager | ₹7.72 crore | 0.074 | 0.050 (0.11) | 0.074 (0.55) | Electric Motors & Drives (1.35 ×) |
| 102 | Regional Sales Manager | ₹10.33 crore | 0.038 | 0.043 (0.56) | 0.047 (0.79) | Cutting Tools & Abrasives (1.19 ×) |
| 104 | Regional Sales Manager | ₹8.97 crore | **0.029** | 0.042 (0.79) | 0.027 (0.40) | Pneumatic Components (1.14 ×) |

| Team (revenue-weighted index) | Observed | Random mean | Random 95th percentile | p-value |
|---|---:|---:|---:|---:|
| Any order | 0.059 | 0.056 | 0.065 | 0.26 |
| Same customer | 0.059 | 0.060 | 0.066 | 0.65 |

- **The team's mix is what random allocation of orders produces** (p = 0.26). Random allocation alone gives small portfolios higher indices (about 0.09 for the smallest sellers against 0.04 for the largest), so a high index on its own means little.
- **The unusual mixes are explained by the customers.** Key Account Manager 106 sells more pumps than random allocation predicts (p = 0.02, not significant after 16 tests), and Sales Executive 114 has the highest index (0.150, p = 0.06). Shuffling only within their own customers' orders produces the same mixes (p = 0.12 and 0.56): it is what their customers buy, not how they sell.

**Focus does not buy price.** Across 153 salesperson × category cells, the correlation between focus and discount gap is 0.065 (t ≈ 0.8). Where it has any direction, salespeople give slightly *more* discount in their stronger categories.

**A product-line split would hand most customers to three salespeople.**

| Product lines bought (Oct 2025 – Sep 2026) | Customers | Share | Share of revenue | Salespeople today (average) | Served by one today |
|---|---:|---:|---:|---:|---:|
| 1 | 33 | 9.0 % | 0.2 % | 1.00 | 100 % |
| 2 | 58 | 15.8 % | 1.5 % | 1.16 | 86.2 % |
| 3 | **275** | **75.1 %** | **98.3 %** | 2.03 | 37.1 % |

Three customers in four, carrying 98.3 % of revenue, buy from all three product lines. Under a split each of them would need three salespeople; today they deal with two on average.

## 9. Business implications and recommendations

1. **Do not reorganise by product line on the grounds of existing specialisation.** There is none to build on, and focus has not produced better prices.
2. **Keep account ownership by customer.** A product-line split would add a third salesperson to the accounts that carry almost all revenue. If anything, reduce the two salespeople those customers already deal with (see [salesperson relationship risk](../../01_customer_and_revenue/04_salesperson_relationship_risk/)).
3. **If product expertise is the goal, add specialists as support, not owners.** A pumps or motors specialist joining the account owner on technical sales keeps one point of contact.
4. **Measure specialists against random, not against each other.** Small portfolios always look specialised; use the shuffled benchmark before rewarding or reorganising around an apparent niche.

## 10. Assumptions and limitations

- **Revenue mix only.** Specialisation in technical knowledge or in winning first orders would not show up in category shares.
- **352 orders without a salesperson** are excluded.
- **Discount is the only price measure.** Invoice prices vary within ±3 % of the list with no salesperson pattern (see [price discipline](../12_price_increase_and_price_discipline/)), so discount is where focus would show.
- **Product-line groups are a proposal.** A different grouping would change the coverage figures.
- **200 shuffles** give p-values to within about ±0.035.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Line, shuffle and index tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
