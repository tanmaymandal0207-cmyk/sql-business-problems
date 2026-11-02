# Case Study · Discount Creep: Do Customers Get Bigger Discounts the Longer They Buy?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 9,391 valid orders from January 2024 to September 2026. The study compares the cross-section ("first orders get 5 %, regulars get 7 %") with each customer's own discount over time, tests the within-customer trend against 500 shuffles, and works out what a "no creep" rule would recover.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-02 |

---

## 1. Business problem

The pricing manager's monthly report shows that a customer's first order carries a discount of about 5 %, while orders after a customer's 30th carry about 7 %. She reads this as "discount creep": loyal customers negotiate a little more each year, and margin leaks away. Before she asks sales for a discount freeze on long-standing accounts, she wants to know whether the same customers really are getting more over time.

## 2. Business questions

1. Does the same customer's discount rise from order to order and from year to year?
2. If not, why do frequent customers get bigger discounts?
3. Is there creep in any segment?
4. What would a "no creep" rule actually recover?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, date, status |
| `sales_order_items` | One row per product per order | List value and discount |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Orders | Valid orders (not Cancelled or Returned), January 2024 – September 2026 |
| **Order discount** | Discount given ÷ list-price value of the order's lines |
| Order number | 1 for the customer's first order in the data, 2 for the next, and so on |
| **Within-customer slope** | Each order's discount and its years since the customer's first order are centred on the customer's own averages; the pooled slope is the change in discount per year for the same customer (customers with 2+ orders) |
| Shuffle test | 500 shuffles of each customer's discounts across its own orders: the slopes that arise with no trend at all |
| "No creep" rule | Each customer's orders after its first 365 days are compared with its own first-year average discount; rupees above and below that level |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.dc_orders`) with order number, years since first order and within-customer deviations.
2. **Cross-section**: discount by order number and by customer size.
3. **Within customer**: pooled slope with the shuffle test (`sahyadri_b2b.dc_shuffles`), the same customers early and late, and year by year.
4. **Segments**, and what drives discount between customers.
5. **The "no creep" rule** simulated.

## 6. SQL techniques used

- A fixed-effects slope in SQL: deviations from each customer's mean with `AVG() OVER (PARTITION BY customer)` and Σxy ÷ Σx²
- A within-customer permutation test: an integer hash reorders each customer's orders, and the discount is re-joined by position
- Equal-weight comparisons (customer averages first, then their average), so heavy buyers do not dominate a band
- A symmetric counterfactual: rupees above and below each customer's own baseline, netted

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Orders = valid orders; list and discount value = source |
| 02 | Order numbers run 1..n within each customer |
| 03 | Discount rate = discount ÷ list value, between 0 and 20 % |
| 04 | **Deviations sum to zero within each customer** |
| 05 | Time since first order starts at zero, never negative |
| 06 | 500 shuffled slopes, centred on zero |
| 07 | **Pooled within slope = covariance ÷ variance of the centred values** |
| 08 | Order-number bands add up to all orders |
| 09 | First-year and later orders split every order of each customer |
| 10 | Segments add up to the customers with two or more orders |

## 8. Findings

**The report's pattern is real: later orders carry bigger discounts.**

| Order number | Orders | Customers | Discount (order average) | Discount (by value) |
|---|---:|---:|---:|---:|
| First order | 426 | 426 | 4.92 % | 7.37 % |
| Orders 2–3 | 676 | 348 | 4.95 % | 7.77 % |
| Orders 4–10 | 1,806 | 314 | 5.34 % | 8.14 % |
| Orders 11–30 | 2,715 | 196 | 6.23 % | 8.47 % |
| Order 31+ | 3,768 | 90 | **7.03 %** | 9.31 % |

**But the same customer's discount does not rise.**

| Test | Result |
|---|---|
| Within-customer slope, 348 customers, 9,313 orders | **+0.059 points a year** |
| Range from 500 shuffles (95 %) | −0.089 to +0.091 points |
| p-value | 0.22 |
| Same 90 customers (31+ orders), each weighted equally: orders 1–10 / 11–30 / 31+ | 6.31 % / 6.29 % / 6.38 % |
| Same 263 customers buying in every year: 2024 / 2025 / 2026 | 5.17 % / 5.26 % / 5.17 % |

- A customer's discount today is what it was in its first year, within a few hundredths of a point.
- Bigger orders from the same customer do not get bigger discounts either (+0.014 points per doubling of order size).

**Bigger discounts go to different customers, not to older ones.**

| Customer places | Customers | Discount | Discount on its first order | Average order (list) |
|---|---:|---:|---:|---:|
| 1–3 orders | 112 | 3.89 % | 4.02 % | ₹58,200 |
| 4–10 | 118 | 3.96 % | 4.43 % | ₹63,100 |
| 11–30 | 106 | 5.70 % | 5.55 % | ₹92,500 |
| 31+ | 90 | 6.72 % | **5.94 %** | ₹1,17,200 |

| Segment | Customers | Discount | Within-customer slope |
|---|---:|---:|---:|
| Distributor | 61 | **10.94 %** | −0.045 points a year |
| Enterprise | 59 | 8.01 % | +0.203 |
| Mid-Market | 93 | 4.04 % | +0.015 |
| SMB | 135 | 1.36 % | −0.026 |

- Frequent buyers already had bigger discounts on their first order (5.94 % against 4.02 %). 50 of the 90 are Distributors or Enterprise accounts, whose discounts are higher from the start; among the 112 occasional buyers it is 25, and 59 are SMB customers (1.4 % average discount).
- Across customers, discount correlates with customer value (+0.52), but within a segment the correlation is −0.07. **Segment sets the discount.** Late orders look expensive only because frequent buyers come from the high-discount segments.
- Enterprise shows the largest within-customer drift, +0.2 points a year: about one point over five years if it continued. It is the one segment worth watching.

**A "no creep" rule would recover nothing.**

| Orders after each customer's first year (307 customers, 5,513 orders, ₹59.94 crore at list) | Amount |
|---|---:|
| Discount above the customer's own first-year average | ₹89.9 lakh |
| Discount below it | ₹91.7 lakh |
| **Net** | **−₹1.8 lakh (−0.03 %)** |

A cap at each customer's first-year level would appear to save ₹89.9 lakh, but customers sit as often below their own level as above it. The variation is order-to-order noise around a stable level, not creep. Capping only the high side would mean renegotiating ₹90 lakh of discounts with no evidence that they crept.

## 9. Business implications and recommendations

1. **Do not freeze discounts for long-standing accounts.** There is no creep to stop. The report's pattern comes from mixing segments.
2. **Report discount by segment and against each customer's own history,** not by order number. A customer moving more than one point above its own level is worth a question; a long-standing customer with a high discount is not.
3. **Review discount levels where they are set: by segment.** Distributors average 10.9 % and Enterprise 8.0 %. Whether those levels are right is a pricing question for the [discount consistency](../06_discount_consistency/) and [discount and margin](../01_discount_margin_erosion/) studies, not a loyalty problem.
4. **Watch Enterprise drift.** Re-run the within-customer slope for Enterprise each year; +0.2 points a year is small today but would add up.

## 10. Assumptions and limitations

- **Discounts as recorded.** Customer-specific net prices outside the discount field (special list prices) are not visible.
- **Up to 33 months per customer.** Customers registered years before 2024 enter the data mid-relationship; their "first order" is their first in the data. Creep from earlier years cannot be seen.
- **Segment slopes are not separately tested.** Only the pooled slope has a shuffle test.
- **Order average and value-weighted rates differ.** Large orders carry bigger discounts across customers, so value-weighted figures are higher. The within-customer tests use the order-average rate.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order and shuffle tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
