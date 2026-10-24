# Case Study · Safety Stock and Reorder Points

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Training year: weeks from 30 Sep 2024; review year: weeks from 29 Sep 2025 to 21 Sep 2026.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-24 |

---

## 1. Business problem

Purchasing reorders by experience: "keep about a month of stock". That holds too much of slow, predictable items and too little of fast, erratic ones. The supply chain manager wants a **reorder policy for every product**: a safety stock, a reorder point and an order quantity, with service levels set by importance. Before adopting it, the manager wants proof that the policy would have delivered the promised service levels.

This study turns the stocking policies of the [ABC-XYZ classification](../../05_advanced_analytics/01_abc_xyz_product_classification/) into numbers.

## 2. Business questions

1. How much safety stock does each product need, and what reorder point and order quantity follow?
2. What does the policy cost in stock, and how much does differentiating service levels by ABC class save against a uniform high service level?
3. Backtest: with parameters set on one year of demand, how often would the next year's demand during the lead time have been covered?
4. For which products does the method not fit?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Units and revenue |
| `sales_orders` | One row per order | Order week and status |
| `products`, `product_categories` | One row per product / category | Unit cost, names |

The dataset has no stock, purchase order or supplier tables. Lead time and costs are therefore **declared assumptions** at the top of the script.

## 4. Method and metric definitions

| Formula | Definition |
|---|---|
| d, s | Mean and standard deviation of weekly demand (units), zero-filled over 52 weeks |
| **Safety stock** | SS = z × √(L × s² + d² × σL²), where L = 3 weeks lead time and σL = 1 week |
| **Reorder point** | ROP = d × L + SS |
| **Order quantity** | EOQ = √(2 × annual demand × ₹1,500 per order ÷ (24 % × unit cost)) |
| Average stock | SS + EOQ ÷ 2, valued at unit cost |
| Service level (cycle) | A 98 % (z = 2.054), B 95 % (z = 1.645), C 90 % (z = 1.282), with classes on review-year revenue |
| Lumpy demand | More than half the weeks with no demand, or a coefficient of variation above 1.5 |
| Backtest coverage | Share of rolling 3-week windows in the review year whose demand did not exceed the reorder point set from the training year |

The safety stock formula includes lead-time variability, not just demand variability. This matters for fast movers, where a one-week delay is worth a full week of demand.

## 5. Analytical approach

1. **Weekly demand** (`sahyadri_b2b.weekly_product_demand`). Every product × 104 weeks, zero-filled.
2. **Policy table** (`sahyadri_b2b.safety_stock_policy`). Class, demand statistics, pattern, service level, safety stock, reorder point and EOQ, plus a uniform-98 % alternative.
3. **Stock investment** by class, and the saving from differentiated service levels.
4. **Backtest** (`sahyadri_b2b.safety_stock_backtest`). Training-year parameters against review-year demand, plus a growth-adjusted diagnostic.
5. **Reorder table** for the top regular products.

## 6. SQL techniques used

- A product × week grid (`CROSS JOIN` with `GENERATE_DATE_ARRAY(… INTERVAL 1 WEEK)`) so that zero-demand weeks count in the variance
- Inventory formulas (safety stock with lead-time variance, reorder point, EOQ) in SQL with `SQRT`, `POW` and `CEIL`
- Forward-looking rolling windows (`ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING`) for lead-time demand
- An out-of-sample backtest of a statistical policy
- Validation that recomputes variance from sums of squares instead of `STDDEV_SAMP`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Weekly rows = 200 products × 104 weeks |
| 02 | Weekly units = source units |
| 03 | One policy row per product in the master |
| 04 | Class A is the smallest set reaching 80 % of revenue |
| 05 | **Safety stock recomputed** from independently calculated moments (sums of squares) |
| 06 | Reorder point = lead-time demand + safety stock (within rounding) |
| 07 | EOQ recomputed |
| 08 | Service level and z match the class |
| 09 | Every backtest product has 50 full 3-week windows |
| 10 | Every demand pattern follows its rule |

## 8. Findings

**The policy needs ₹3.25 crore of safety stock, ₹4.40 crore of average stock in total.**

| Class | Products | Lumpy | Service level | Safety stock | Average stock (SS + EOQ/2) | Uniform 98 % safety stock | Saving |
|---|---:|---:|---:|---:|---:|---:|---:|
| A | 62 | 24 | 98 % | ₹2.60 crore | ₹3.27 crore | ₹2.60 crore | – |
| B | 65 | 46 | 95 % | ₹50.4 lakh | ₹82.1 lakh | ₹62.5 lakh | ₹12.0 lakh |
| C | 56 | 50 | 90 % | ₹14.9 lakh | ₹31.7 lakh | ₹23.7 lakh | ₹8.7 lakh |

- **Differentiated service levels save ₹20.8 lakh of safety stock** (6 % of the uniform requirement), about **₹5 lakh a year** in holding cost at 24 %.
- **Class A takes 80 % of safety stock investment.** The top two items, the 50 HP induction motor (₹21.3 lakh) and the 5 HP dewatering pump (₹13.6 lakh), hold more than all class C products together.

**Most products do not have demand regular enough for a statistical policy.** 122 of the 186 products with demand (66 %) are lumpy: they sell in fewer than half the weeks, or in very uneven amounts.

**Backtest: the policy fell short in a growth year, but the method is sound.**

| Class | Pattern | Products | Target | Achieved | Growth-adjusted |
|---|---|---:|---:|---:|---:|
| A | Regular | 38 | 98 % | 94.5 % | **97.8 %** |
| B | Regular | 20 | 95 % | 90.8 % | **95.6 %** |
| C | Regular | 6 | 90 % | 84.0 % | **90.7 %** |
| A | Lumpy | 24 | 98 % | 88.5 % | 91.8 % |
| B | Lumpy | 47 | 95 % | 88.1 % | 92.3 % |
| C | Lumpy | 51 | 90 % | 83.3 % | 88.8 % |

- **Units sold grew 22.7 % between the two years**, so parameters set on last year's demand were too low. When the training parameters are scaled by that growth, **regular products hit their targets almost exactly**. The formula works when the demand level is right.
- **Lumpy products miss even after adjustment.** The normal-distribution assumption behind the formula does not fit products that sell in occasional large orders.

## 9. Business implications and recommendations

1. **Adopt the policy for the 64 regular products**, with reorder points loaded into the ERP. Recalculate monthly on a rolling 52-week window, and **apply a demand trend factor**: in a growing business, last year's average understates next year's demand.
2. **Do not use statistical safety stock for the 122 lumpy products.** Move them to make- or buy-to-order with confirmed lead times, or hold a fixed minimum for the few class A lumpy items. This matches policy 4 of the ABC-XYZ study.
3. **Use differentiated service levels** (98 / 95 / 90 %). They release ₹20.8 lakh of stock against a uniform 98 % with no change for class A.
4. **Replace the lead-time assumption with real supplier data.** Lead time drives safety stock for every item. Recording purchase order and receipt dates would let the script use measured supplier lead times by product.

## 10. Assumptions and limitations

- **No inventory or supplier data.** The 3-week lead time, 1-week lead-time variation, ₹1,500 order cost and 24 % holding rate are assumptions. Changing them changes every result, and they are declared at the top of the script.
- **Orders as demand.** Order dates are used as the demand date. Large project orders inflate variance.
- **Coverage, not fill rate.** The backtest measures the share of lead-time windows covered (cycle service level), not the share of units supplied from stock.
- **No stock check.** Whether current stock levels are above or below these reorder points cannot be assessed without stock data.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Weekly demand, policy and backtest tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
