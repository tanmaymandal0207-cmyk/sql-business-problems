# Case Study · SKU Rationalisation: Product Profitability Review

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Window: 1 Oct 2025 – 30 Sep 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-22 |

---

## 1. Business problem

The range has 200 products. Every product costs money to list, buy, stock, price and pick, whether it earns or not. The [ABC-XYZ classification](../../05_advanced_analytics/01_abc_xyz_product_classification/) ranks products by revenue, which shows what sells but not what earns. The category managers want a **margin-based review of the range**: which products to protect, which to reprice and which to consider delisting, and who would be affected.

## 2. Business questions

1. How concentrated is gross profit across products?
2. Which products sell well but earn too little per sale (reprice), and which sell little and earn little (delist review)?
3. What would repricing the low-margin sellers be worth?
4. If the delist-review products were dropped, which customers depend on them?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Revenue and units |
| `sales_orders` | One row per order | Order date, status and customer |
| `products` | One row per product | Standard unit cost and list price |
| `product_categories` | One row per category | Category names |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)`, orders not Cancelled or Returned |
| Gross profit (GP) | Revenue − `quantity * unit_cost` |
| GP margin | GP ÷ revenue |
| Revenue class | A = products making the first 80 % of revenue, B = next 15 %, C = last 5 %. Same basis as the ABC-XYZ study, so the classes match it exactly (62 / 68 / 56). |
| GP core | Products earning the first 80 % of GP |
| Low margin | GP margin below 10 % |
| Dependent customer | A customer for whom the product is at least 10 % of their 12-month spend |

**Actions** (first rule that applies):

| # | Rule | Action |
|---|---|---|
| 1 | No sales in 12 months | Delist: no demand |
| 2 | No unit cost in the product master | Fix cost data first |
| 3 | GP below zero | Reprice or stop: loss-making |
| 4 | Class C and low margin | Delist review |
| 5 | Class A or B and low margin | Reprice |
| 6 | GP core | Protect |
| 7 | Otherwise | Maintain |

A low-margin product that sells well is a pricing problem, not a range problem. Only products that both sell little and earn little are put forward for delisting.

## 5. Analytical approach

1. **Product table** (`sahyadri_b2b.sku_profitability`). One row per product in the master with revenue, GP, margin, revenue class, GP rank and action.
2. **GP concentration** and margin by revenue class.
3. **Action summary.**
4. **Repricing value.** The GP gained if each low-margin seller reached a 10 % margin at today's volume, and the price rise that needs.
5. **Delisting impact.** For each delist-review product, customers who depend on it.

## 6. SQL techniques used

- Two independent Pareto rankings (revenue and GP) with `SUM … OVER (ORDER BY … ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)`, so a product is classed by the share earned *before* it
- `LEFT JOIN` from the full product master, so products with no sales are reviewed too
- A first-match `CASE` decision table that turns metrics into actions
- Per-customer share of spend with `SUM … OVER (PARTITION BY customer_id)` to measure dependency

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per product |
| 02 | Rows = products in the master (200) |
| 03 | Revenue = source total (₹40.36 crore, matching other 12-month case studies) |
| 04 | GP = independent recount |
| 05 | GP core is the smallest set of products reaching 80 % of GP |
| 06 | Class A is the smallest set reaching 80 % of revenue, and class C holds no more than 5 % |
| 07 | Every product with sales has a revenue class, and no other does |
| 08 | Every action obeys its rule |
| 09 | No-demand products = an independent count of products with no sales |
| 10 | Every product has an action |

## 8. Findings

**54 of 183 costed, selling products earn 80 % of gross profit.** The company's GP margin over the 12 months is 15.5 %.

**The best sellers earn the least per rupee.**

| Revenue class | Products | Revenue | GP margin | Low-margin products | Their revenue |
|---|---:|---:|---:|---:|---:|
| A | 62 | ₹32.29 crore | **15.2 %** | 18 | ₹10.24 crore |
| B | 68 | ₹6.10 crore | 16.6 % | 12 | ₹1.03 crore |
| C | 56 | ₹1.97 crore | 17.1 % | 12 | ₹0.43 crore |
| No sales | 14 | – | – | – | – |

Almost a third of class A revenue (₹10.24 crore) is earned at under 10 % margin. Class A products start with a slightly lower list-price margin (23.6 % against 24.7 % for class C) and are discounted more deeply (8.9 % against 8.1 % on average). See [Discount and margin erosion](../01_discount_margin_erosion/) for the discount view.

**Action summary:**

| Action | Products | Revenue | GP margin |
|---|---:|---:|---:|
| Protect | 49 | ₹22.53 crore | 20.3 % |
| Maintain | 92 | ₹5.87 crore | 17.7 % |
| **Reprice** | **28** | **₹11.04 crore** | **5.6 %** |
| Reprice or stop: loss-making | 2 | ₹22.6 lakh | −21.8 % |
| Delist review | 12 | ₹42.9 lakh | 6.1 % |
| Fix cost data first | 3 | ₹26.3 lakh | – |
| Delist: no demand | 14 | – | – |

- **Repricing is worth about ₹61.8 lakh a year,** roughly 10 % more gross profit, if the 30 low-margin and loss-making sellers reached a 10 % margin at the same volume. Two products account for ₹23.0 lakh of it: the 50 HP induction motor (5.3 % margin, ₹2.41 crore revenue) and the 5 HP dewatering pump (6.2 %, ₹2.45 crore). Each needs a price rise of about 4–5 %.
- **Two carbide end mills lose money on every sale** (₹4.9 lakh in total), because their list price is below cost. This is the same master-data error flagged as rule V01 in the [Data quality scorecard](../../04_data_quality_and_reconciliation/02_data_quality_scorecard/). They need a price rise of about 35 %.
- **Delisting is a small lever.** The 12 delist-review products earn ₹42.9 lakh (1.1 % of revenue) and ₹2.6 lakh of GP. Nine of them have no customer who depends on them: ₹33.0 lakh of revenue across 194 orders, such as Taper Lock Bush 2012 and the 6 in butterfly valve. The other three (a V-belt and two bearings) are at least 10 % of one customer's spend, so a substitute should be agreed first.
- **14 products had no sales at all**, the same products as the N class in the ABC-XYZ study.
- **3 selling products have no unit cost** (₹26.3 lakh of revenue), so their margin cannot be measured.

## 9. Business implications and recommendations

1. **Reprice before delisting.** Start with the two largest low-margin products and the two loss-making end mills. Together they hold ₹31.0 lakh of the ₹61.8 lakh opportunity.
2. **Set a margin floor for class A products** in the pricing approval process. Discounts that take an A-class line below 10 % should need manager approval.
3. **Delist the 14 no-demand products and the 9 delist candidates** after a final stock and supplier check. Agree substitutes for the 3 products that individual customers depend on.
4. **Correct the product master.** Fix the 2 list prices below cost and add costs for the 3 uncosted products, then re-run the review.
5. **Re-run the review every six months** with the same thresholds, and track GP margin by revenue class as a range-health KPI.

## 10. Assumptions and limitations

- **Standard cost.** GP uses the current `unit_cost` from the product master for all 12 months. If costs changed during the year, margins on older sales are approximate.
- **Product margin only.** Freight, handling, stock-holding and selling costs are not allocated, so true product profitability is lower. Small-volume products may cost more to handle than their GP shows.
- **Static volume.** The repricing value assumes volumes do not fall after a price rise. Price-sensitive lines may lose some volume, so treat ₹61.8 lakh as an upper bound.
- **Thresholds.** The 10 % margin floor and the 10 % dependency test are declared at the top of the script and can be changed.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Product profitability table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
