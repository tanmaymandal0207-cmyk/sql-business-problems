# Case Study · A Quarterly Volume Rebate: What It Would Cost at Today's Volumes, How Much Extra Volume It Must Buy, and How Easily It Is Gamed

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study applies a proposed quarterly volume rebate to every customer's purchases over 11 quarters (January 2024 – September 2026). It measures what the rebate would have cost on volume customers bought anyway, and how much extra volume it would need to pay for itself. It then tests how much of it customers could earn by moving orders between quarters, and compares cheaper designs.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-08 |

---

## 1. Business problem

The sales head wants a quarterly volume rebate, open to every customer, to win more business from the larger accounts. A customer whose purchases in a calendar quarter reach ₹10 lakh earns 1 % back on the whole quarter. At ₹20 lakh it earns 2 %, and at ₹40 lakh 3 %. Before agreeing, the CFO wants to know what it would cost, what it must achieve to pay for itself, and whether customers could earn it without buying more.

## 2. Business questions

1. What would the scheme have cost on the volumes customers already bought, and how much of the gross profit is that?
2. How much extra volume must it bring in just to pay for itself?
3. How easily can customers earn it by moving orders between quarters rather than buying more?
4. Is there a cheaper design that rewards the same customers?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, status |
| `sales_order_items` | One row per product per order | Purchases (after discount), quantity |
| `products` | One row per product | Unit cost |
| `shipments` | One row per shipment | Invoice date (first shipment) |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Invoice | A valid order (not Cancelled or Returned) with a shipment; invoice date = first shipment date; dated 1 January 2024 – 30 September 2026 (11 calendar quarters) |
| Purchases / gross profit | Order value after discount / purchases − quantity × product unit cost (freight and other costs to serve not deducted) |
| Tiers | ₹10 lakh → 1 %, ₹20 lakh → 2 %, ₹40 lakh → 3 % of the quarter's purchases |
| **Retroactive rebate** (proposed) | Purchases × the rate of the highest tier reached in the quarter |
| **Incremental rebate** (alternative) | 1 % of purchases above ₹10 lakh + 1 % above ₹20 lakh + 1 % above ₹40 lakh. Same rate on each extra rupee, paid only above each threshold. |
| **Break-even extra purchases** | Rebate ÷ (gross margin − rebate rate): the extra sales whose gross profit, after the rebate on them, pays back the rebate |
| Near miss | A customer-quarter within 15 % below a threshold |
| Timing tests | (a) the first month of the next quarter's invoices pulled into the quarter; (b) each half-year's purchases placed in one of its two quarters |
| Annual alternative | The same tiers × 4 (₹40 lakh, ₹80 lakh, ₹1.6 crore) over a financial year (April – March) |

## 5. Analytical approach

1. **Invoices** (`sahyadri_b2b.qr_invoices`) and **customer-quarters** (`qr_quarters`) with purchases, gross profit, tier, both rebates, the gap to the next threshold and next month's purchases. The tiers are a table (`qr_tiers`), so other thresholds can be tested by editing three rows.
2. **Cost** on actual volumes, by tier, segment and customer.
3. **Break-even**: extra purchases needed per tier, and what crossing would earn for the near misses.
4. **Timing**: pull-forward and concentration tests; whether a tier earned once is earned again.
5. **Designs**: quarterly or annual, retroactive or incremental.

## 6. SQL techniques used

- Tier lookup by joining a tiers table: `MAX(IF(threshold <= purchases, rate, NULL))` for the tier reached, `MIN(IF(threshold > purchases, threshold, NULL))` for the next one
- Incremental (marginal) rebate in one aggregate: `SUM(step × GREATEST(0, purchases − threshold))`
- The same tiers reused for annual and half-year tests by scaling the threshold (`4 × threshold`) inside the join
- Tier persistence with `LEAD()` over each customer's quarters, treating a missing quarter as no rebate
- The cliff at each threshold from `LAG(rate)` over the tiers

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Invoices = valid shipped orders invoiced in the window; purchases and cost = source |
| 02 | Quarter = calendar quarter of the invoice; 11 quarters; customer-quarters add up to invoices |
| 03 | **Rate = highest tier reached** (recount with a CASE) |
| 04 | Retroactive = purchases × rate; incremental = 1 % above each threshold (recount) |
| 05 | Incremental never above retroactive; zero below ₹10 lakh |
| 06 | Next threshold = the lowest tier above purchases; gap = threshold − purchases |
| 07 | Next-month purchases = recount; none for the last quarter |
| 08 | Rate if pulled forward = tier of purchases + next month; never below the actual rate |
| 09 | Financial year runs April – March |
| 10 | **Break-even: gross profit on the extra purchases, less the rebate on them, repays the rebate** |

## 8. Findings

**On the volumes customers already bought, the scheme would cost ₹33.7 lakh a year, 8.5 % of all gross profit.**

| Tier reached | Customer-quarters | Customers | Purchases | Gross margin | Rebate | Rebate as % of their gross profit |
|---|---:|---:|---:|---:|---:|---:|
| None | 2,339 | 418 | ₹42.91 crore | 13.2 % | – | – |
| 1 % | 125 | 52 | ₹17.11 crore | 12.1 % | ₹17.11 lakh | 8.3 % |
| 2 % | 60 | 21 | ₹16.85 crore | 10.9 % | ₹33.69 lakh | 18.3 % |
| **3 %** | 21 | 8 | ₹13.98 crore | **9.8 %** | ₹41.93 lakh | **30.5 %** |
| **Total** | 2,545 | | ₹90.84 crore | | **₹92.73 lakh** (₹33.72 lakh a year) | 8.5 % of all |

- Only 206 customer-quarters (8 %) would earn a rebate, but they carry 52.8 % of purchases.
- The customers who earn the most already have the thinnest margins. A 3 % rebate takes almost a third of their gross profit.
- In 17 customer-quarters, gross profit was no more than the rebate: the company would have paid to make those sales.

| Segment | Customer-quarters earning | Customers | Rebate | Share |
|---|---:|---:|---:|---:|
| Distributor | 91 | 26 | ₹49.69 lakh | 53.6 % |
| Enterprise | 105 | 28 | ₹41.12 lakh | 44.3 % |
| Mid-Market | 10 | 2 | ₹1.92 lakh | 2.1 % |
| SMB | 0 | 0 | – | – |

| Largest recipients | Segment | Quarters earning (of 11) | Purchases | Rebate | Gross margin | After rebate |
|---|---|---:|---:|---:|---:|---:|
| Siddhivinayak Mishra Trading Co. | Distributor | 11 | ₹681.4 lakh | ₹19.54 lakh | 11.0 % | 8.1 % |
| Krishna Castings Ltd | Enterprise | 11 | ₹488.7 lakh | ₹12.78 lakh | 9.2 % | 6.6 % |
| Maa Joshi Industrial Suppliers | Distributor | 11 | ₹384.5 lakh | ₹9.20 lakh | 9.8 % | 7.4 % |
| Mahavir Pillai Spinning Mills Pvt Ltd | Enterprise | 10 | ₹330.8 lakh | ₹7.06 lakh | 12.1 % | 10.0 % |
| Banerjee Sales Corporation Pvt Ltd | Distributor | 7 | ₹248.8 lakh | ₹5.01 lakh | 11.9 % | 9.9 % |

The three largest recipients take 45 % of the rebate. They already buy over ₹10 lakh every quarter, so most of what they would be paid is for volume the company has today.

**To pay for itself, the scheme must raise these customers' purchases by about a quarter.**

| Tier | Gross margin | Extra purchases needed to repay the rebate | In rupees, over 11 quarters |
|---|---:|---:|---:|
| 1 % | 12.1 % | 9.0 % | ₹1.54 crore |
| 2 % | 10.9 % | 22.4 % | ₹3.78 crore |
| **3 %** | 9.8 % | **44.0 %** | ₹6.15 crore |
| **All tiers** | 11.0 % | **23.9 %** | **₹11.47 crore** |

On a 9.8 % margin, a 3 % rebate needs 44 % more volume from the customer just to break even.

**Even when the rebate works, pushing a near miss over the line loses money.**

| Threshold | Customer-quarters within 15 % below | Customers | Extra purchases to cross | Extra rebate if they cross | Gross profit on the extra purchases |
|---|---:|---:|---:|---:|---:|
| ₹10 lakh | 49 | 37 | ₹35.8 lakh | ₹4.90 lakh | ₹3.78 lakh |
| ₹20 lakh | 24 | 17 | ₹33.1 lakh | ₹5.13 lakh | ₹4.18 lakh |
| ₹40 lakh | 11 | 9 | ₹32.4 lakh | ₹5.05 lakh | ₹4.69 lakh |
| **Total** | **84** | | ₹101.3 lakh | **₹15.08 lakh** | **₹12.65 lakh** |

The retroactive rebate is paid on the whole quarter, not just on the extra purchases. A customer 15 % short of a tier who buys the difference earns more rebate than the company makes on the extra sale. Each threshold is a cliff: the rupee that crosses ₹10 lakh earns ₹10,000, the one that crosses ₹20 lakh another ₹20,000, and the one that crosses ₹40 lakh another ₹40,000.

**Much of the rebate could be earned by moving orders, not buying more.**

| Timing test (quarters to June 2026) | Result |
|---|---|
| Pull the next month's invoices into the quarter | 110 customer-quarters (48 customers) reach a higher tier; **₹38.28 lakh** extra rebate |
| Place each half-year's purchases in one quarter | Rebate up **44.5 %** (₹80.70 lakh to ₹116.64 lakh); 185 of 1,432 customer half-years gain |

Purchases are lumpy, so tiers are not stable:

| Tier earned in a quarter | Customer-quarters | Next quarter: none | Lower | Same | Higher |
|---|---:|---:|---:|---:|---:|
| 1 % | 112 | **62** | – | 30 | 20 |
| 2 % | 52 | 6 | 17 | 19 | 10 |
| 3 % | 20 | 3 | 11 | 6 | 0 |

- More than half of the quarters that earn 1 % are followed by a quarter that earns nothing.
- 24 of the 56 customers who would ever earn a rebate earn it in only one quarter of 11. For them, the rebate rewards a lumpy quarter, not loyalty.

**An annual, incremental design costs 60–65 % less and keeps the same reward on extra purchases.**

| Financial year | Quarterly, retroactive (proposed) | Quarterly, incremental | Annual, retroactive | **Annual, incremental** | Customers earning, quarterly / annual |
|---|---:|---:|---:|---:|---:|
| 2024-25 | ₹33.02 lakh | ₹16.72 lakh | ₹28.29 lakh | **₹13.09 lakh** | 32 / 16 |
| 2025-26 | ₹27.43 lakh | ₹12.13 lakh | ₹22.26 lakh | **₹9.46 lakh** | 38 / 18 |

- Over the 11 quarters, the incremental design costs ₹47.53 lakh against ₹92.73 lakh, 51.3 % of the proposed scheme.
- It pays the same rate on each extra rupee above a threshold, so a customer deciding whether to buy more faces the same reward. The difference is that it does not pay again for the base the customer was buying anyway, and it has no cliff.
- An annual period removes most of the timing game, because moving orders between quarters no longer changes the tier. It also concentrates the reward on the 16–18 customers who buy at scale all year.

## 9. Business implications and recommendations

1. **Do not launch the scheme as proposed.** It would cost about ₹34 lakh a year, 8.5 % of gross profit. Most of that would go to customers already buying at those levels, and it needs about 24 % more volume from them to break even.
2. **If a rebate is wanted, make it annual and incremental.** The same tiers × 4, paid only on purchases above each threshold, would have cost ₹9–13 lakh a year. The incentive on extra purchases is unchanged, and there is no cliff and much less timing game.
3. **Exclude or cap low-margin accounts.** Krishna Castings Ltd (9.2 % gross margin), Sudarshan Autoparts Pvt Ltd (7.4 %) and Annapurna Precision Engineering Ltd (6.7 %) would keep under 7 % after the rebate. Set the rebate as a share of the margin, or make it conditional on a minimum margin.
4. **Reward growth, not size.** For the three largest recipients, which buy above ₹10 lakh in every quarter, a rebate on purchases above last year's level would pay only for new volume.
5. **Track the result once it runs.** Compare each customer's purchases against its pre-scheme trend and against the break-even uplift above. Check for pull-forward by watching the first month after each period-end (see [period-end sales push](../07_period_end_sales_push/)).

## 10. Assumptions and limitations

- **Gross margin before costs to serve.** Freight and other costs to serve (see [product cost to serve](../18_product_cost_to_serve/)) would make the margins thinner and the break-even higher.
- **Historical volumes are taken as what customers would buy without the scheme.** If volumes would have fallen without it, part of the rebate defends existing business; the study cannot measure that.
- **Invoice date = first shipment date.** A scheme on order date or full delivery would move some purchases between quarters.
- **The timing tests are upper bounds.** Not every customer can or will move a month of orders; they show the exposure, not a forecast.
- **2026-27 is not in the annual comparison**, as it is only half a year.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Tier, invoice and customer-quarter tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
