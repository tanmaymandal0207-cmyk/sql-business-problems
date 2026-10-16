# Case Study · Discount and Margin Erosion

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Period: orders dated 1 Jan 2024 to 30 Sep 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-16 |

---

## 1. Business problem

Revenue is growing, but finance reports that gross margin is thin. Salespeople can give line discounts of up to 18 % and there is no formal approval rule. Before introducing a discount policy, the commercial director needs evidence: how much discounting costs, where it happens, and what a limit would recover.

## 2. Business questions

1. How much revenue is given away in discounts, and what gross margin is left?
2. How does gross margin change as the discount gets deeper?
3. Which categories, customer segments and salespeople discount most, and at what margin?
4. How many order lines were sold below cost, and was that caused by the discount or by the price?
5. What would a 10 % discount cap have recovered?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Quantity, price, discount |
| `sales_orders` | One row per order | Status, salesperson, customer |
| `products` | One row per product | Unit cost |
| `product_categories` | One row per category | Category name |
| `customers` | One row per customer | Segment |
| `employees` | One row per employee | Salesperson name |

Every join is many-to-one from the order line, so the line count does not change (validation checks 01 and 02).

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Gross value | `quantity * unit_price` (price before the line discount) |
| Net revenue | Gross value × (1 − discount % / 100). A missing discount is treated as 0 %. |
| Discount given | Gross value − net revenue |
| Discount % of gross | Discount given ÷ gross value |
| Line cost | `quantity * products.unit_cost` |
| Gross margin % | (Net revenue − line cost) ÷ net revenue, for lines whose product has a unit cost |
| Below cost | Net revenue < line cost |

**Discount bands:** No discount · Up to 5 % · Above 5 % to 10 % · Above 10 % to 15 % · Above 15 %.

## 5. Analytical approach

1. **Line-level margin table** (`sahyadri_b2b.sales_line_margin`). One row per in-scope order line with gross value, discount, net revenue, cost and band.
2. **Headline:** discount given and gross margin left.
3. **Margin by discount band.**
4. **Category view.**
5. **Customer segment view.**
6. **Salesperson view**, including the share of lines discounted above 10 % and the loss on below-cost lines.
7. **Below-cost lines**, split by whether the price was already below cost or the discount pushed it below.
8. **Scenario:** gross margin if discounts had been capped at 10 %.

## 6. SQL techniques used

- A single line-level fact table that every later step reads from
- `CASE` banding and boolean flags (`cost_known`)
- Conditional aggregation with `SUM(IF(...))` and `COUNTIF`, so lines without a cost are kept in revenue but left out of margin
- Window shares with `SUM(SUM(...)) OVER ()`
- A what-if scenario using `LEAST()`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order line |
| 02 | Row count = in-scope source lines (26,472) |
| 03 | Gross value = source total, to the paisa |
| 04 | Gross value − discount = net revenue on every row |
| 05 | Every line has a category and customer segment |
| 06 | No discount outside 0–100 % |
| 07 | The cost-known flag matches the presence of a line cost |
| 08 | Lines without cost = lines for products with no unit cost (292) |
| 09 | Discount band revenues add up to total revenue |
| 10 | Every line sits in the correct discount band |

## 8. Findings

**₹8.76 crore (8.76 %) of gross value was given away in discounts. Gross margin after discount is 11.51 %.**

**Margin falls steadily as the discount deepens.**

| Discount band | Lines | Share of revenue | Gross margin | Lines below cost |
|---|---:|---:|---:|---:|
| No discount | 4,460 | 12.0 % | 18.70 % | 56 |
| Up to 5 % | 7,085 | 21.0 % | 15.70 % | 259 |
| Above 5 % to 10 % | 9,306 | 36.8 % | 11.32 % | 868 |
| Above 10 % to 15 % | 5,102 | 27.9 % | 6.19 % | 1,082 |
| Above 15 % | 519 | 2.2 % | 3.32 % | 167 |

30.1 % of revenue is sold at more than 10 % discount, where margin is 6.19 % or less.

**2,432 lines were sold below cost, losing ₹87.09 lakh.** In 2,095 of them (₹70.94 lakh, 81.5 % of the loss), the price was above cost and **the discount pushed it below**. The other 337 lines (₹16.15 lakh) were priced below cost before any discount.

**Distributors and Enterprise accounts get the deepest discounts.**

| Segment | Net revenue | Discount % | Gross margin |
|---|---:|---:|---:|
| Distributor | ₹36.37 crore | 11.28 % | 9.54 % |
| Enterprise | ₹37.03 crore | 8.69 % | 10.97 % |
| Mid-Market | ₹12.75 crore | 4.02 % | 16.26 % |
| SMB | ₹5.09 crore | 1.39 % | 17.56 % |

**Category margins differ because of pricing, not discounting.** Every category is discounted at between 8.3 % and 9.2 % of gross. Margin, however, ranges from 5.77 % (Electric Motors & Drives, the second-largest category at ₹17.95 crore) to 17.82 % (Fasteners). Bearings has the most below-cost lines (490).

**Discounting varies widely between salespeople.** Discount as a share of gross ranges from 4.89 % (employee 112, gross margin 16.36 %) to 11.13 % (employee 114). Employee 102 discounts more than 10 % on 29.2 % of their lines and has the largest below-cost loss (₹17.40 lakh). Orders with **no salesperson recorded** carry an 11.20 % discount and a 7.85 % margin, among the weakest of any group.

**A 10 % discount cap would have recovered up to ₹1.36 crore** across 5,621 lines and raised gross margin from 11.51 % to 12.81 %. This is an upper bound, because it assumes no sales would have been lost at the lower discount.

## 9. Business implications and recommendations

1. **Introduce a discount authority matrix.** A typical structure: up to 5 % at the salesperson's discretion, 5–10 % with sales manager approval, above 10 % with commercial head approval and a margin check. Lines above 10 % carry 30.1 % of revenue at 6 % margin or less.
2. **Block below-cost quotes in the ERP.** Add a margin-floor check at quotation. 81.5 % of the below-cost loss came from discounts that a floor would have stopped.
3. **Replace ad hoc distributor discounts with a structured trade price list.** Distributors average 11.3 % off; a published trade discount makes the margin predictable and easier to negotiate.
4. **Review pricing for Electric Motors & Drives and Bearings.** Their low margins exist before discounting. List prices or purchase costs need renegotiating.
5. **Coach the highest-discounting salespeople using this report**, and make discount % and gross margin part of sales targets, not revenue alone.
6. **Require a salesperson on every order.** Unassigned orders have one of the highest discount rates and no one accountable for it.
7. **Track discount % and margin by band every month** to measure whether the policy is working.

## 10. Assumptions and limitations

- **Cost basis.** `products.unit_cost` is a single current cost per product, not the cost at the time of sale. If costs have changed over the period, historical margins are approximate.
- **Missing costs.** 292 lines (products with no unit cost) are included in revenue and discount figures but excluded from margin.
- **Discount scenario.** The 10 % cap assumes all volume would still have been sold. Some customers may have bought less or gone elsewhere, so treat ₹1.36 crore as the maximum recoverable.
- **Hidden deductions.** Only line discounts are recorded. Rebates, freight absorbed and payment-term costs are not in the data, so net margin is lower than gross margin.
- **Salesperson.** The salesperson on the order is assumed to be the person who set the discount.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Line-level margin table and 7 analysis steps |
| `validation.sql` | 10 pass/fail checks |
