# Case Study · Who Drives the March Peak?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. March against the surrounding months (January–June, excluding March) in 2024, 2025 and 2026: the uplift split into more customers, more orders per customer and bigger orders, tested by segment and industry, and followed customer by customer across years.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-01 |

---

## 1. Business problem

March, the last month of the Indian financial year, is the biggest month every year: revenue runs about 60 % above trend (see [revenue volatility](../../02_sales_and_profitability/15_revenue_volatility_drivers/)). The sales director wants to plan next March deliberately: pre-book stock and dispatch capacity, and call the customers who will order. Before drawing up a "March list" of budget-flush customers, he wants to know who actually drives the peak.

## 2. Business questions

1. Is the March peak more customers ordering, more orders from each, or bigger orders?
2. Is it a few large accounts, or nearly everyone?
3. Does it come from particular segments or industries?
4. Do the same customers spike every March?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Order value |
| `customers` | One row per customer | Segment, industry |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Orders | Valid orders (not Cancelled or Returned), January–June of 2024, 2025 and 2026 |
| **Baseline month** | The average of January, February, April, May and June of the same year |
| March index / uplift | March ÷ baseline month (− 1 for the uplift) |
| **Uplift shares** | Revenue = active customers × orders per active customer × average order value; each driver's share = its log change ÷ the log change in revenue (shares add to 100 %) |
| Large order | ₹5 lakh or more |
| Group test | Chi-square on orders, March against baseline months, by segment or industry (all years pooled): is March the same share of every group's orders? |
| Excess orders | A customer's March orders − its average baseline-month orders |
| **Spiker** | At least 2 excess orders and at least double its baseline in March |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.mp_orders`) for January–June with period, segment and industry.
2. **Company view** (`sahyadri_b2b.mp_company`): March against baseline each year, the decomposition and the effect of large orders.
3. **Groups** (`sahyadri_b2b.mp_groups`): March index by segment and industry, with the homogeneity test.
4. **Customers** (`sahyadri_b2b.mp_customers`): breadth of the uplift and persistence between 2025 and 2026.

## 6. SQL techniques used

- A multiplicative decomposition (customers × frequency × order value) with log shares that add up exactly
- A 2 × k chi-square homogeneity test with a Wilson–Hilferty critical value, validated against the equivalent binomial form
- Customer-level excess against each customer's own baseline, and year-on-year persistence with `CORR`
- A same-customer repeat-rate test against the base rate for all customers

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders = valid January–June orders; value = source |
| 02 | 2026 March and baseline figures = recount |
| 03 | **Uplift shares add up to 100 %** |
| 04 | Group orders add up to all orders in each dimension |
| 05 | Expected March orders add up to actual March orders |
| 06 | **Chi-square = the binomial form of the same test** |
| 07 | Excess orders and spiker rule recomputed |
| 08 | One customer row per year with January–June orders |
| 09 | Persistence correlation recomputed |
| 10 | Revenue without large orders never exceeds revenue |

## 8. Findings

**The peak is everything at once: more customers, more orders each, bigger orders.**

| Year | March revenue | Baseline month | Uplift | More customers | More orders each | Bigger orders | Uplift without ₹5 lakh+ orders |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2024 | ₹335.4 lakh | ₹208.4 lakh | **+60.9 %** | +17.3 % | +20.3 % | +13.9 % | +39.0 % |
| 2025 | ₹414.5 lakh | ₹233.3 lakh | **+77.6 %** | +24.0 % | +22.4 % | +17.0 % | +55.4 % |
| 2026 | ₹541.7 lakh | ₹312.5 lakh | **+73.4 %** | +25.0 % | +16.1 % | +19.4 % | +30.9 % |

| Share of the uplift | 2024 | 2025 | 2026 |
|---|---:|---:|---:|
| More customers ordering | 33.6 % | 37.5 % | 40.6 % |
| More orders per customer | 38.9 % | 35.2 % | 27.2 % |
| Bigger orders | 27.4 % | 27.3 % | 32.2 % |

- Large deals add a lot in some years (2026: the uplift is 31 % without orders of ₹5 lakh or more, 73 % with them), but even without them March is 30–55 % above the surrounding months.

**Every segment and industry joins in equally.**

| Segment | March orders | Expected if equal | March order index | z |
|---|---:|---:|---:|---:|
| Mid-Market | 302 | 287.3 | 1.56 | +0.99 |
| SMB | 247 | 238.8 | 1.53 | +0.60 |
| Enterprise | 372 | 382.3 | 1.41 | −0.60 |
| Distributor | 226 | 238.6 | 1.36 | −0.93 |

- The share of orders falling in March is the same across segments (chi-square 2.6 against 7.8 needed at 5 %) and across 15 industries (8.8 against 23.7). The industry with the highest index (Agricultural Equipment, 1.96) has 20 March orders in three years.
- Revenue indices vary much more (from 0.98 for Construction to 3.03 for Steel & Metals) because single large orders land in some groups' March and not others.

**Half the customers order more in March, and they are different customers each year.**

| Year | Customers active Jan–Jun | Ordered more in March than usual | Extra orders in March | Spikers |
|---|---:|---:|---:|---:|
| 2024 | 256 | 43.4 % | 89.6 | 20 |
| 2025 | 278 | 50.0 % | 134.6 | 28 |
| 2026 | 313 | 49.5 % | 138.8 | 32 |

- Across 236 customers active in both 2025 and 2026, the correlation of their March excess orders between the two years is **0.07**.
- Of 25 customers that spiked in March 2025, **3 (12.0 %)** spiked again in 2026, the same rate as for customers that had not spiked (10.9 %).

## 9. Business implications and recommendations

1. **Do not build a "budget-flush" customer list.** Who orders extra in March changes from year to year; a list based on last March would be no better than chance.
2. **Plan March as a company-wide surge.** Expect about 40–50 % more orders and 25 % more active customers than the surrounding months, from every segment and industry, and book dispatch capacity accordingly (see [dispatch capacity](../../03_operations_and_supply_chain/17_dispatch_capacity_simulation/)).
3. **Reach every active customer in February.** Since any customer may add March orders, a broad reminder of year-end delivery cut-offs is better targeted than calls to a few accounts.
4. **Track the large March deals separately.** They swing the March revenue figure by up to 40 points and should come from the sales pipeline, not the seasonal plan.
5. **Watch quarter-end cancellations.** The [period-end push](../../02_sales_and_profitability/07_period_end_sales_push/) study found more cancellations on orders placed in the last five days of quarter-end months (7.1 % against 4.5 %); confirm late-March orders before committing stock.

## 10. Assumptions and limitations

- **Baseline months** are January–June excluding March; using a trend line instead gives a similar uplift (about 63 % on revenue).
- **Three Marches only.** The persistence test rests on one pair of years (2025 and 2026).
- **Customers are counted when they order** between January and June; a customer that orders only in March is in the March figures but not in the persistence pairs unless it ordered in both years.
- **Order date, not delivery.** Some late-March orders are delivered in April; on a delivery basis the peak would shift slightly.
- **Unknown industry** (18 customers) is kept as its own group.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, company, group and customer tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
