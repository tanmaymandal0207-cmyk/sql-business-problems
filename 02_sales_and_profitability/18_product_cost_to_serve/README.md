# Case Study · Product Profitability After Cost to Serve

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Every order line of the financial year April 2025 – March 2026 is charged with freight, order handling, sales effort, the cost of credit and credit losses. The result is a product P&L, a product whale curve, the drivers of loss-making products, and a test of which costs really belong to the product.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-01 |

---

## 1. Business problem

The [SKU rationalisation](../05_sku_rationalisation/) review ranked products on gross profit and noted its own limitation: freight, handling and selling costs were not allocated. The finance controller wants that gap closed before the next range review. A ₹1,000 order line for fasteners takes as much picking, paperwork and sales follow-up as a ₹3 lakh pump, and gross profit treats the two lines as if the cost of serving them were the same.

## 2. Business questions

1. What does each product earn after freight, order handling, sales effort, the cost of waiting for payment and credit losses?
2. How many products lose money once those costs are charged, and how much do they give back?
3. What makes a product lose money: low margin, small lines, or bad debts?
4. How far does the ranking move from the gross-profit ranking?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Date, customer, salesperson, status |
| `sales_order_items` | One row per product per order | Line revenue |
| `products`, `product_categories` | One row per product / category | Unit cost, list price, category |
| `shipments` | One row per shipment | Freight and final delivery date |
| `payments` | One row per payment | Payment timing and amounts |
| `employees` | One row per employee | Salary pools for handling and sales effort |

## 4. Method and metric definitions

| Cost line | How it is charged to each order line |
|---|---|
| Scope | Lines of valid orders (not Cancelled or Returned) placed between 1 Apr 2025 and 31 Mar 2026, so that every order's 180-day payment outcome is known by 30 Sep 2026 |
| Gross profit | Revenue − quantity × unit cost |
| Freight | The order's shipping cost, split by line value |
| Order handling | Operations and Supply Chain & Logistics salaries for the year ÷ all orders placed = **₹1,736 per order**, split equally across the order's lines |
| Sales effort | Each salesperson's salary for the year ÷ the orders they booked (₹2,173–11,053 per order), split equally across lines. The Head of Sales is not charged. |
| Cost of credit | Rupees outstanding × days from final delivery to each payment × 12 % a year. A balance still unpaid at day 180 accrues until then. Split by line value. |
| Credit loss | The order's balance still unpaid 180 days after the order date, split by line value. Receivables that old are never collected (see [collections forecast](../../05_advanced_analytics/17_monte_carlo_collections_forecast/)). |
| **Operating contribution** | Gross profit − freight − handling − sales effort − cost of credit |
| **Contribution** | Operating contribution − credit loss |

Salaries are prorated for anyone who joined during the year. The handling and sales-effort rates use the same method as the [customer whale curve](../../05_advanced_analytics/05_customer_profitability_whale_curve/), which shows the same costs by customer.

## 5. Analytical approach

1. **Rates** (`sahyadri_b2b.pc_rates`): handling per order and sales effort per order for each salesperson.
2. **Lines** (`sahyadri_b2b.pc_lines`): every line with revenue, gross profit and the five costs.
3. **Products** (`sahyadri_b2b.pc_products`): the product P&L. Three products without a unit cost (₹26.2 lakh of revenue) are listed and left out.
4. **Bridge** from gross profit to contribution, and the **whale curve** on both contribution measures.
5. **Drivers**: line size, margin, margin × line size, and a half-year persistence test of each measure.
6. **Ranking shift** against gross profit, and the largest loss-makers.

## 6. SQL techniques used

- Activity-based costing: salary pools turned into per-order rates, then charged per line with equal or value-weighted splits
- Rupee-day financing cost built from single payments, with a write-off point at 180 days so that a balance is not both financed and lost
- A whale curve in rupees with `SUM … OVER (ORDER BY … ROWS UNBOUNDED PRECEDING)`, which still works when the total is negative
- A split-half reliability test (`CORR` of each product's first-half and second-half rates), used to tell product properties from noise

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Lines = valid order lines of the financial year; revenue = source |
| 02 | Handling rate = Operations and Supply Chain pay ÷ all orders, charged once per valid order |
| 03 | Sales effort per salesperson = pay × valid ÷ all orders booked; Head of Sales not charged |
| 04 | Freight charged = shipping cost of these orders |
| 05 | Value shares add up to 1 on every order |
| 06 | **Credit loss = order value − payments within 180 days**, recounted |
| 07 | **Cost of credit recounted from single payments**; no negative costs |
| 08 | Every order's 180-day window closes by the as-of date |
| 09 | Product rows = sum of their lines; contribution = gross profit − all costs |
| 10 | Whale curve ranks run 1 to n and end at total contribution |

## 8. Findings

**₹4.49 crore of gross profit becomes ₹1.36 crore after cost to serve, and turns into a loss of ₹1.03 crore once bad debts are charged.**

| Line | Amount | % of revenue |
|---|---:|---:|
| Revenue (183 products) | ₹33.44 crore | 100.0 % |
| Gross profit | ₹448.8 lakh | 13.4 % |
| − Sales effort | ₹143.2 lakh | 4.3 % |
| − Cost of credit | ₹63.2 lakh | 1.9 % |
| − Order handling | ₹62.5 lakh | 1.9 % |
| − Freight | ₹44.4 lakh | 1.3 % |
| **Operating contribution** | **₹135.5 lakh** | **4.1 %** |
| − Credit loss | ₹238.7 lakh | 7.1 % |
| **Contribution** | **−₹103.2 lakh** | **−3.1 %** |

| Products losing money | Count |
|---|---:|
| On gross profit | 6 |
| On operating contribution | **94** |
| After credit loss | 124 |

**Half the range earns more than all of the operating contribution.**

| Products ranked by operating contribution | Cumulative |
|---|---:|
| Top 10 % (19 products) | ₹150.7 lakh (111 % of the total) |
| Top 20 % (37 products) | ₹186.0 lakh |
| Peak: 89 profitable products | **₹211.2 lakh (156 %)** |
| 94 loss-making products give back | −₹75.7 lakh |
| All 183 products | ₹135.5 lakh |

The Fire Fighting Pump Diesel 20 HP alone earns ₹60.1 lakh, 44 % of the total, on 67 lines averaging ₹5.3 lakh.

**Small lines lose money, and order costs explain it.**

| Line value | Lines | Share of revenue | Gross margin | Handling + sales effort | Freight + credit | Operating margin |
|---|---:|---:|---:|---:|---:|---:|
| Under ₹5k | 1,476 | 1.4 % | 17.7 % | **78.2 %** | 8.1 % | **−68.6 %** |
| ₹5–20k | 4,445 | 15.0 % | 16.0 % | 18.6 % | 4.3 % | −6.9 % |
| ₹20–50k | 2,633 | 25.2 % | 14.6 % | 5.8 % | 3.3 % | 5.5 % |
| ₹50k–2 lakh | 1,334 | 35.2 % | 12.2 % | 2.0 % | 2.9 % | 7.3 % |
| ₹2 lakh+ | 191 | 23.2 % | 12.0 % | 0.4 % | 2.6 % | 9.0 % |

- Lines under ₹20k are 59 % of all lines but 16 % of revenue, and lose ₹66.3 lakh. Each order costs about ₹5,700 in handling and sales effort and has 2.8 lines on average.
- Small lines carry the highest gross margins (16–18 %), but those margins do not cover the order costs.

**For products, low margin matters as much as line size.**

| Gross margin | Average line under ₹20k | Average line ₹20k+ |
|---|---|---|
| Under 10 % | 21 of 21 lose money (−₹27.6 lakh) | 27 of 35 lose (−₹21.3 lakh) |
| 10–15 % | 23 of 24 lose (−₹10.4 lakh) | 4 of 21 lose (+₹14.5 lakh) |
| 15 %+ | 18 of 37 lose (+₹3.0 lakh) | **1 of 45 loses (+₹177.2 lakh)** |

- Loss-making products average a **5.3 % gross margin** against 18.2 % for profitable ones, and ₹25,454 per line against ₹40,430. This differs from the customer view, where loss-makers had the same margin as profitable customers.
- **Two products are sold below cost on every line.** The Carbide End Mill 4 Flute 6 mm (list ₹810, unit cost ₹895.54) and 16 mm (list ₹3,469, cost ₹3,860.53) lost ₹6.1 lakh of gross profit between them. Either the list price or the recorded cost is wrong.

**Credit loss is not a product property.**

| Same product, Apr–Sep 2025 against Oct 2025–Mar 2026 | Correlation |
|---|---:|
| Gross margin | 0.961 |
| Operating margin | 0.846 |
| Credit-loss rate | **0.014** |

- Profitable and loss-making products have the same credit-loss rate (7.1 % of revenue). The loss comes from 384 of 3,630 orders, 140 of them wholly unpaid, and lands on whatever products those orders contained. For example, ₹17.3 lakh of the Dewatering Pump 5 HP's revenue went unpaid.
- Charging credit loss to products turns 30 profitable products into "loss-makers" by chance. The range review should use operating contribution.

**The ranking moves substantially.** The rank correlation between gross profit and operating contribution is 0.69. 88 products that make a gross profit lose money after cost to serve, 6 of the 37 top-fifth products on gross profit fall out of the top fifth, and 83 products move 20 places or more.

| Biggest loss-makers (operating) | Lines | Per line | Gross margin | Handling + sales | Operating contribution |
|---|---:|---:|---:|---:|---:|
| Carbide End Mill 4 Flute 6 mm | 89 | ₹18,316 | −28.3 % | ₹2.0 lakh | −₹7.2 lakh |
| Pillow Block Bearing UCP207 | 310 | ₹15,079 | 2.2 % | ₹6.0 lakh | −₹6.7 lakh |
| Pneumatic Gripper Parallel 20 mm | 121 | ₹32,101 | 0.1 % | ₹2.5 lakh | −₹3.8 lakh |
| Ball Valve SS316 2 in Screwed | 283 | ₹28,987 | 7.2 % | ₹6.1 lakh | −₹3.0 lakh |
| Dewatering Pump 5 HP | 250 | ₹82,927 | 4.2 % | ₹5.1 lakh | −₹2.7 lakh |

**By category, only Pumps earns a double-digit operating margin (10.8 %).** Bearings (−6.6 %: 10.2 % gross margin on ₹15,369 lines) and Pneumatic Components (−0.3 %) lose money before credit loss. Fasteners has the highest gross margin (20.1 %) but small lines (₹14,527), which leaves an operating margin of 2.1 %.

## 9. Business implications and recommendations

1. **Run the range review on operating contribution, not gross profit.** Credit loss should be managed through customer credit limits (see [customer credit limits](../../01_customer_and_revenue/17_customer_credit_limits/)), not charged to products.
2. **Fix the two carbide end mills first.** Their list prices are below cost, so either reprice them or correct the cost master.
3. **Reprice or delist low-margin products.** 48 of the 56 products with a gross margin under 10 % lose money, whatever their line size. Start with Pillow Block Bearing UCP207, Pneumatic Gripper 20 mm and VFD 15 HP, whose gross margins are close to zero.
4. **Set a minimum line value or a small-order charge** for lines under ₹5,000. These lines earn 17.7 % gross margin but cost 78 % of their value to process. Bundling fasteners and bearings into kits or boxes, or routing small orders to a counter or distributor channel, also cuts the per-order cost.
5. **Protect the few products that carry the business.** 45 products with gross margins above 15 % and lines of ₹20k or more earn ₹177 lakh, more than the whole range nets. Keep them in stock and price them carefully.
6. **Treat the 7.1 % credit loss as the company's biggest leak.** It is larger than freight, handling and the cost of credit combined (see [expected credit loss](../../05_advanced_analytics/19_expected_credit_loss_provision/)).

## 10. Assumptions and limitations

- **Activity-based allocation.** Handling and sales effort are split equally across an order's lines. A long pump line may take more effort than a box of nuts, so small lines may carry slightly too much cost.
- **Current unit cost.** Gross profit uses `products.unit_cost`, with no history of cost changes.
- **Credit loss at 180 days.** A balance unpaid after 180 days is treated as lost. Later recoveries, if any, are ignored.
- **Overheads are not allocated.** Rent, finance, IT, marketing and the Head of Sales are not charged, so contribution is before fixed overheads.
- **One financial year.** The half-year persistence test uses two six-month periods of that year.
- **Three products without a unit cost** (₹26.2 lakh of revenue) are excluded.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Rate, line and product tables, and 6 analysis steps |
| `validation.sql` | 10 pass/fail checks |
