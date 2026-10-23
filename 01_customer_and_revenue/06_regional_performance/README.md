# Case Study · Regional Performance and Market Coverage

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 12-month window 1 Oct 2025 – 30 Sep 2026; growth compares January–September 2026 with January–September 2025.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-23 |

---

## 1. Business problem

The company sells to customers in 22 states with one sales team. The managing director is deciding **where to add the next regional salesperson** and whether a regional stocking point would pay off. That needs a like-for-like view of every state: how much it earns, how fast it is growing, how well its registered customers are converted into buyers, how dependent it is on one account, and how well it is served.

## 2. Business questions

1. Where does revenue come from, and where is it growing or shrinking?
2. How well is each state's registered customer base converted into active buyers?
3. Which states depend on one or two customers?
4. Is delivery service worse in some regions?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `customers` | One row per customer | State (bill-to location) |
| `sales_orders` | One row per order | Dates, status, promised date |
| `sales_order_items` | One row per product per order | Revenue |
| `shipments` | One row per shipment | Final delivery date |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)`, orders not Cancelled or Returned |
| Region | State grouped into West, North, South, East and Central with a mapping table |
| YTD growth | Jan–Sep 2026 revenue ÷ Jan–Sep 2025 revenue − 1 (same basis as the [Revenue growth bridge](../03_revenue_growth_bridge/)) |
| Active customer | At least one in-scope order in the 12-month window |
| Activation rate | Active customers ÷ registered customers |
| Largest customer share | The state's largest customer ÷ state 12-month revenue |
| On-time rate | Delivered orders in the window delivered on or before the promised date |
| Portfolio quadrant | States with ₹50 lakh+ revenue: **Invest** (above-median size, above-company growth), **Defend** (above-median size, lower growth), **Develop** (smaller, faster growth), **Review** (smaller, slower growth) |

## 5. Analytical approach

1. **Region mapping table** (`sahyadri_b2b.state_region_map`).
2. **State table** (`sahyadri_b2b.state_performance`). One row per state with registered and active customers, revenue, growth, concentration and on-time rate.
3. **Region summary.**
4. **Portfolio quadrant** for each state.
5. **Concentration risk:** states where one customer exceeds 40 % of revenue.
6. **Dormant base:** registered customers not buying, by state.

## 6. SQL techniques used

- A small mapping table built with `UNION ALL` and joined like a dimension
- Conditional aggregation to build three revenue periods in one pass
- `PERCENTILE_CONT … OVER ()` for a median benchmark, cross-joined to classify every row
- `ROW_NUMBER() OVER (PARTITION BY state …)` to name the largest customer in each state
- Weighted averages (on-time rate × deliveries) when rolling states up to regions

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per state |
| 02 | States = distinct states in the customer master (22) |
| 03 | Registered customers = customer master (500) |
| 04 | Active customers = source (367) |
| 05 | 12-month revenue = source (₹40.36 crore, matching other case studies) |
| 06 | YTD revenue for both years = source |
| 07 | Every state maps to a region |
| 08 | Largest-customer share = an independent self-join recount |
| 09 | Measured and on-time deliveries = source |
| 10 | Activation rate between 0 and 1, and never more active than registered customers |

## 8. Findings

**The West earns 31 % of revenue and delivered 46 % of this year's growth.** Company revenue grew 38.7 % (₹8.71 crore) year to date.

| Region | States | Active / registered | 12-month revenue | Share | YTD growth | On-time |
|---|---:|---:|---:|---:|---:|---:|
| West | 3 | 116 / 158 | ₹12.39 crore | 30.7 % | **+68.6 %** | **85.6 %** |
| North | 7 | 92 / 127 | ₹9.44 crore | 23.4 % | +32.4 % | 78.6 % |
| South | 5 | 88 / 117 | ₹7.46 crore | 18.5 % | +31.8 % | 82.8 % |
| East | 5 | 43 / 57 | ₹6.79 crore | 16.8 % | +41.3 % | **77.5 %** |
| Central | 2 | 28 / 41 | ₹4.28 crore | 10.6 % | **+0.1 %** | 80.8 % |

- **Western growth rests on two accounts.** In Gujarat, one customer (Banerjee Sales Corporation, including its ₹1.19 crore order) supplied ₹1.23 crore of the state's ₹1.40 crore growth. Without that customer, Gujarat grew 9.6 %. In Maharashtra, Siddhivinayak Mishra Trading supplied about half of the ₹2.59 crore increase.
- **Central has stalled.** Chhattisgarh grew 10.9 %, and Madhya Pradesh fell 24.5 %.
- **East and North are served worst.** Their on-time rates are 77.5 % and 78.6 %, against 85.6 % in the West. This matches the [promise standards](../../03_operations_and_supply_chain/05_promise_date_standards/) finding that northern and eastern cities are promised too fast.

**State portfolio (states with ₹50 lakh or more revenue):**

| Quadrant | States |
|---|---|
| **Invest** | Maharashtra, Gujarat, Haryana, West Bengal, Uttar Pradesh |
| **Defend** | Tamil Nadu (growth 38.2 %, just under the company rate), Chhattisgarh, Karnataka |
| **Develop** | Jharkhand (+92.8 %), Odisha (+156.7 %), Punjab (+79.9 %) |
| **Review** | Madhya Pradesh (−24.5 %), Bihar (−22.0 %), Uttarakhand, Telangana, Delhi |

Six states shrank: Madhya Pradesh, Bihar, Rajasthan, Himachal Pradesh, Andhra Pradesh and Assam, losing ₹93.4 lakh between them. **Assam has 5 registered customers and no sales in the last 12 months.**

**In 12 states, one customer is more than 40 % of revenue.** Examples:

| State | 12-month revenue | Largest customer | Share |
|---|---:|---|---:|
| West Bengal | ₹3.10 crore | Krishna Castings | 62.8 % |
| Uttarakhand | ₹96.1 lakh | Ganesh Precision Engineering | 74.4 % |
| Himachal Pradesh | ₹48.0 lakh | Jyoti Engineering Works | 94.2 % |
| Chhattisgarh | ₹3.02 crore | Maa Joshi Industrial Suppliers | 47.5 % |

Losing one account would remove most of the business in these states.

**133 registered customers (27 %) are not buying.** The largest dormant pool is Maharashtra (29 customers). The lowest activation rates are Rajasthan (53 %), Telangana (60 %) and Madhya Pradesh (65 %).

## 9. Business implications and recommendations

1. **Put the next salesperson in the East (Jharkhand, Odisha, West Bengal).** It is growing faster than the company, its revenue per active customer is the highest (₹15.8 lakh), and three states are in Develop or Invest. A local presence would also cut the region's dependence on Krishna Castings.
2. **Fix service before adding sales in the North and East.** On-time delivery there is 7–8 points below the West. Test a stocking point or a regional carrier before pushing more volume.
3. **Run a Central recovery review.** Find out why Madhya Pradesh fell 24.5 % and Chhattisgarh slowed. Check for lost accounts with the [churn early warning](../02_customer_churn_early_warning/) list.
4. **Do not read Gujarat and Maharashtra growth as market growth.** Plan these states on their underlying growth, excluding the two large accounts.
5. **Reactivate the dormant base in Maharashtra, Rajasthan and Telangana** before prospecting for new names. Close out the Assam accounts or hand them to a distributor.

## 10. Assumptions and limitations

- **Bill-to state.** Location is the customer's registered state. Customers with sites in several states are counted in one.
- **Growth is lumpy.** A single large order can swing a small state's growth rate, so the quadrant is a prompt for review, not a verdict.
- **Service by state** uses the customer's state, not the shipping city.
- **No market size data.** The analysis shows where the company is strong, not where the market is largest. Industry data per state would be needed to size the opportunity.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Region mapping and state tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
