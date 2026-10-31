# Case Study · Order Frequency vs Order Size: Do Customers Batch Their Orders?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 282 customers with six or more valid orders: frequency against order size between customers, within each customer's own order history (with a 500-shuffle permutation test), and year on year.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-31 |

---

## 1. Business problem

The [revenue driver tree](../15_revenue_driver_tree/) showed that orders per customer is the steadiest growth driver, and sales wants to push it further with reorder calls and reminders. Finance objects: if customers simply split the same need into more, smaller orders, frequency rises but revenue does not, while freight and handling costs go up. Before funding the programme the commercial head wants to know whether more frequent ordering means smaller orders.

## 2. Business questions

1. Do customers who order more often place smaller orders?
2. Within the same customer, is an order placed soon after the last one smaller, and one after a long gap bigger?
3. When a customer orders more often from one year to the next, do its orders shrink?
4. Would more frequent ordering add revenue, or just more orders?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Order value |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Customers analysed | 282 customers with 6 or more valid orders (not Cancelled or Returned) |
| Ordering rate | Orders × 365 ÷ days from the first order to 30 Sep 2026 (at least 90) |
| Typical order value | Geometric mean of the customer's order values, EXP(AVG(ln value)) |
| Gap before an order | Days since the customer's previous valid order |
| Size vs typical | The order's ln value − the customer's average ln value, shown as a percentage |
| **Within-customer slope** | Pooled slope of size vs typical on ln(1 + gap), both centred within each customer |
| **Permutation test** | Each customer's order values shuffled among its own orders 500 times, gaps fixed; p = share of shuffles with a slope at least as far from zero |
| Year-on-year response | Across customers, slope of Δ ln(average order size) on Δ ln(orders) from 2024 to 2025 |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.fs_orders`): every order of the qualifying customers with its gap and size against the customer's typical order.
2. **Customers** (`sahyadri_b2b.fs_customers`): rate, typical size and revenue; the relation between them overall and within segment.
3. **Within-customer test** by gap band, and the **permutation slopes** (`sahyadri_b2b.fs_permutation_slopes`).
4. **Year on year**: does a rise in orders come with smaller orders?

## 6. SQL techniques used

- Within-customer centring with `AVG() OVER (PARTITION BY customer_id)`, so only each customer's own variation is compared
- `GROUP BY ROLLUP` to show overall and within-segment relations side by side
- A permutation test in SQL: values moved between a customer's own orders by hashed rank, 500 times
- Validation of the gap logic and the slope by independent recounts

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders of every customer with 6+ valid orders; value = source |
| 02 | **Gap = days since the previous order** (recounted with a self-join) |
| 03 | Size vs own average sums to zero for every customer |
| 04 | One row per customer; orders and revenue add up |
| 05 | Ordering rate recomputed |
| 06 | Typical order value lies between the customer's smallest and largest order |
| 07 | 501 slope rows, each over the same orders |
| 08 | **Real within-customer slope = a direct recount** |
| 09 | Shuffled slopes differ from the real one |
| 10 | Segments add up to all customers |

## 8. Findings

**Frequent buyers place bigger orders, not smaller ones.**

| Orders a year | Customers | Enterprise share | Typical order | Average revenue (33 months) |
|---|---:|---:|---:|---:|
| Under 6 | 107 | 6 % | ₹25.6k | ₹5.8 lakh |
| 6–12 | 77 | 21 % | ₹34.1k | ₹17.7 lakh |
| 12–24 | 64 | 33 % | ₹41.2k | ₹32.5 lakh |
| 24–52 | 25 | 36 % | ₹47.8k | ₹91.9 lakh |
| 52 or more | 9 | 56 % | ₹60.1k | ₹288.9 lakh |

| Scope | Customers | Correlation (ln rate, ln typical order) | Size elasticity to frequency |
|---|---:|---:|---:|
| All customers | 282 | **+0.29** | +0.28 |
| Distributor | 54 | −0.04 | −0.01 |
| Enterprise | 57 | +0.26 | +0.06 |
| Mid-Market | 79 | +0.12 | +0.04 |
| SMB | 92 | +0.00 | +0.00 |

- The positive relation is mostly segment: Enterprise customers order both more often and in bigger amounts. Within each segment frequency and size are close to unrelated, and nowhere negative by a meaningful amount.

**A quick re-order is not a smaller order.**

| Gap before the order | Orders | Size vs the customer's typical order |
|---|---:|---:|
| Same day | 474 | +7.3 % |
| 1–3 days | 1,767 | −2.2 % |
| 4–7 days | 1,471 | −0.8 % |
| 8–30 days | 3,017 | +2.1 % |
| 31–90 days | 1,486 | −1.6 % |
| Over 90 days | 589 | +0.4 % |

- Within customers, doubling the gap changes order size by **−0.1 %**. The slope (−0.0016) sits in the middle of the shuffled range (−0.025 to +0.024) and **p = 0.89**. Customers do not save up a need and place it as one big order after a long gap.

**When customers order more often, nearly all of it is extra revenue.** Across 249 customers active in both 2024 and 2025, a 10 % rise in orders came with order sizes about 1.1 % smaller (slope −0.114, t = −1.8, not significant at 5 %). Customers who ordered more often in 2025 saw their order size fall 6.4 %, against +1.5 % for those who ordered less often; part of that gap is the company-wide fall in basket value in 2025.

## 9. Business implications and recommendations

1. **Fund the frequency programme.** On every measure, more orders are mostly additional business: roughly nine-tenths of extra frequency reaches revenue.
2. **Do not plan on cannibalisation, but watch the cost side.** If extra orders are small add-ons, freight and handling per rupee rise; set a minimum order value or free-freight threshold using the [cost-to-serve](../../03_operations_and_supply_chain/02_freight_cost_to_serve/) study.
3. **Target frequency where it is lowest.** 107 customers order fewer than six times a year with typical orders of ₹25.6k; their frequency, not their basket, is the gap.
4. **Base reminders on rate, not on "due" dates.** Timing within a customer's cycle is random (see [order timing](../../05_advanced_analytics/22_order_timing_regularity/)), and gaps do not change order size.
5. **Re-test after the programme starts.** If the within-customer slope turns clearly negative, customers are splitting orders rather than buying more.

## 10. Assumptions and limitations

- **Observational.** No customer was asked to order more often; the relations describe behaviour, not the effect of a campaign.
- **Six orders or more.** Occasional buyers are excluded; for them frequency and size cannot be separated.
- **Order value includes price and mix changes**, which move all orders in a year together; year-on-year results carry the 2025 basket fall.
- **Same-day orders** (+7.3 %) are within two standard errors of zero; they may be separate requisitions from one site.
- **Ordering rate from first order**, so customers who stopped ordering keep a rate from their active period plus the silence since.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, customer and permutation tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
