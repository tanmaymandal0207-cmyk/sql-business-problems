# Case Study · ABC-XYZ Product Classification for Inventory Policy

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Period: 12 months, October 2025 to September 2026.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-16 |

---

## 1. Business problem

The purchasing team applies the same stocking rule to all 200 products. As a result, working capital is tied up in slow-moving items while important items run short. The supply chain head wants every product placed in an inventory policy class using the standard **ABC-XYZ** method, which combines two questions:

- **ABC:** how much does the product contribute to revenue?
- **XYZ:** how predictable is its monthly demand?

The combination decides how each product should be stocked.

## 2. Business questions

1. How many products, and how much revenue, fall in each ABC-XYZ cell?
2. What stocking policy should each cell follow, and how much revenue does each policy cover?
3. Which high-value products have erratic demand and need close review?
4. Which products had no demand at all in the last 12 months?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Quantity and revenue |
| `sales_orders` | One row per order | Order month and status |
| `products` | One row per product | The full product list (including products with no sales) |
| `product_categories` | One row per category | Category name |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Demand | Quantity on orders not Cancelled or Returned, by order month |
| Revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)` |
| ABC class | Products ranked by 12-month revenue, highest first. **A** = products making up the first 80 % of revenue · **B** = the next 15 % · **C** = the last 5 % |
| Coefficient of variation (CV) | Standard deviation ÷ mean of monthly quantity, with months of no demand counted as zero |
| XYZ class | **X** = CV ≤ 0.5 (stable) · **Y** = 0.5–1.0 (variable) · **Z** > 1.0 (erratic) |
| N class | No demand in the 12 months |

**Stocking policy by cell** (standard ABC-XYZ practice):

| Policy | Cells | Rationale |
|---|---|---|
| 1. Keep in stock, high service level | AX, AY, BX | Valuable and predictable enough to forecast reliably |
| 2. Keep in stock, standard service level | BY, CX | Moderate value or low value with stable demand |
| 3. Stock on forecast, review monthly | AZ, BZ | Valuable but erratic. Holding safety stock for all of them is expensive, and running out is costly. |
| 4. Make or buy to order, minimal stock | CY, CZ | Low value and unpredictable, so stock rarely pays for itself |
| 5. Review for discontinuation | N | No demand in 12 months |

## 5. Analytical approach

1. **Classification table** (`sahyadri_b2b.product_abc_xyz`).
   - Builds a full **product × month grid** with `GENERATE_DATE_ARRAY`, so a month with no sales counts as zero demand instead of disappearing.
   - Calculates 12-month revenue, CV, cumulative revenue share, class and policy for every product.
2. **ABC-XYZ matrix.** Products and revenue share in each cell.
3. **Policy summary.** Products and revenue covered by each stocking policy.
4. **AZ review list.** High-value products with erratic demand.
5. **No-demand list.** Products with no orders in the period, with their last order date.

## 6. SQL techniques used

- Date spine with `UNNEST(GENERATE_DATE_ARRAY(...))` and `CROSS JOIN` to fill months with no sales
- `DATE_TRUNC(..., MONTH)` for monthly demand
- `STDDEV_SAMP` / `AVG` for the coefficient of variation, with `SAFE_DIVIDE`
- Running total with `SUM(...) OVER (ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)` for the Pareto (ABC) split
- `STRING_AGG(DISTINCT ...)` in the summary

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per product |
| 02 | Every product in the master is classified (200), including products with no sales |
| 03 | 12-month revenue = source line total for the period, within rounding |
| 04 | 12-month quantity = source quantity for the period |
| 05 | Classes do not overlap: every A product out-earns every B, and every B out-earns every C |
| 06 | A class reaches 80 % of cumulative revenue, and B reaches 95 % |
| 07 | Every X, Y and Z class matches its CV threshold |
| 08 | N class applies exactly to products with zero demand |
| 09 | Months with demand stay within 0–12 |
| 10 | Every product has a stocking policy |

## 8. Findings

12-month revenue in the period is **₹40.36 crore** across 200 products.

**31 % of products generate 80 % of revenue.**

| Class | X (stable) | Y (variable) | Z (erratic) | No demand | Products | Share of revenue |
|---|---:|---:|---:|---:|---:|---:|
| A | 17 | 37 | 8 | – | 62 | 80.0 % |
| B | 10 | 41 | 17 | – | 68 | 15.1 % |
| C | 1 | 36 | 19 | – | 56 | 4.9 % |
| N | – | – | – | 14 | 14 | 0 % |

- **The 17 AX products are the core range.** They earn ₹12.50 crore (31.0 % of revenue) with stable monthly demand. Stock-outs here do the most damage and are the easiest to prevent with a forecast.
- **Most demand is variable, not stable.** Only 28 of the 186 products with demand are class X. Most fall in Y, which is typical for B2B industrial distribution, where demand comes from customer projects and maintenance cycles.

**Five policies cover the range.**

| Policy | Cells | Products | Share of revenue |
|---|---|---:|---:|
| 1. Keep in stock, high service level | AX, AY, BX | 64 | 78.7 % |
| 2. Keep in stock, standard service level | BY, CX | 42 | 8.8 % |
| 3. Stock on forecast, review monthly | AZ, BZ | 25 | 7.7 % |
| 4. Make or buy to order, minimal stock | CY, CZ | 55 | 4.8 % |
| 5. Review for discontinuation | N | 14 | 0 % |

- **55 products (4.8 % of revenue) do not justify routine stock.** Moving them to order-based supply frees working capital with little revenue risk.
- **8 AZ products need individual attention.** They earn ₹1.59 crore together but have erratic demand. Examples:
  - The double-lanyard safety harness (₹31.0 lakh) sells every month, but in uneven volumes.
  - The 5 HP induction motor (₹22.4 lakh) sold in only 7 of 12 months.
  - Three of the eight are electric motors or soft starters.
- **14 products on the product master have never been ordered** in the dataset's history (January 2024 onwards). They span 8 of the 10 categories.

## 9. Business implications and recommendations

1. **Set service levels by policy, not one rule for all.** Hold safety stock for the 64 policy-1 products (78.7 % of revenue). Use standard stock for policy 2. Hold minimal or no stock for the 55 policy-4 products.
2. **Manage AZ and BZ products through a monthly review with sales.** Their demand is driven by a few large orders. Ask account managers for upcoming project requirements instead of relying on history alone.
3. **Move CY and CZ products to order-based supply** where suppliers' lead times allow, and agree those lead times with customers upfront.
4. **Review the 14 never-ordered products for discontinuation.** Check stock on hand and supplier commitments first. Any stock held is a clearance candidate.
5. **Re-run the classification quarterly.** Products move between classes as demand changes, and a policy that is not refreshed becomes the same one-size-fits-all rule again.

## 10. Assumptions and limitations

- **No inventory data.** The dataset has no stock-on-hand, lead time or purchase data. The analysis decides the policy each product **should** follow, not how much stock to hold today.
- **Demand = orders.** Cancelled and returned orders are excluded, and order date is used as the demand date.
- **Thresholds.** The 80/95 % ABC cut-offs and the 0.5 / 1.0 CV thresholds are common conventions. Different cut-offs would move borderline products between classes.
- **CV and zeros.** Counting months with no demand as zero is the standard treatment. It classes intermittent products as erratic, which is the intended effect.
- **12-month window.** A product launched or delisted part-way through the year is classified on part-year data.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Classification table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
