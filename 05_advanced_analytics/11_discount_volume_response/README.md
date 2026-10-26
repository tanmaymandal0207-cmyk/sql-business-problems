# Case Study · Does Discount Buy Volume?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 26,472 order lines; 12,701 lines in 2,217 repeat customer × product pairs for the within-pair estimate.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

Salespeople defend deep discounts by saying they win bigger orders, and the pooled data seems to agree: lines with higher discounts have higher quantities. Earlier studies showed that discounts are set mainly by segment ([discount consistency](../../02_sales_and_profitability/06_discount_consistency/)) and that they cost a large part of margin ([discount and margin erosion](../../02_sales_and_profitability/01_discount_margin_erosion/)). The CFO now asks the causal question: **if we give the same customer a bigger discount on the same product, does it buy more, and enough to pay for the discount?**

## 2. Business questions

1. When the same customer buys the same product with a bigger discount, does it buy more units?
2. How much of the pooled relationship is segment and customer mix?
3. Is the response large enough to pay for the discount?
4. Does the answer differ by segment?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Quantity, price, discount |
| `sales_orders` | One row per order | Customer, status |
| `customers` | One row per customer | Segment |
| `products` | One row per product | Unit cost |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Line | An order line on an order not Cancelled or Returned. Discount d = `discount_percent` (NULL = 0). |
| Response | Slope of LN(quantity) on discount points. × 100 ≈ **% more units per extra discount point**. |
| A. Pooled | Slope across all lines: `COVAR_POP(d, ln q) / VAR_POP(d)` |
| B. Within segment | Discount and quantity demeaned within each segment |
| **C. Within customer × product (fixed effects)** | Discount and quantity demeaned within each customer × product pair with 3+ purchases and some variation in discount. Each pair is compared only with itself, so customer size, product and segment cannot drive the result. |
| t-statistic | r × √df ÷ √(1 − r²), with df = lines − pairs − 1 for model C |
| **Break-even response** | With unit margin m (share of pre-discount price, after the average discount), one more discount point keeps gross profit unchanged only if units rise by m ÷ (m − 0.01) − 1 |

## 5. Analytical approach

1. **Line table** (`sahyadri_b2b.discount_response_lines`). Every valid line with discount, log quantity, and the mean and spread of discount within its customer × product pair.
2. **Estimates table** (`sahyadri_b2b.discount_response_estimates`). Slope, correlation and t-statistic for models A, B and C; and segment averages that explain the pooled result.
3. **Model C by segment**, and units bought when a pair's discount is above or below its own average.
4. **Break-even**: the volume response needed to pay for one more discount point, against the measured response.

## 6. SQL techniques used

- Fixed-effects (within) regression in SQL: demeaning with `AVG() OVER (PARTITION BY customer, product)`
- Comparison of pooled, within-segment and within-pair estimates to expose confounding
- Degrees-of-freedom-corrected t-statistic for the fixed-effects slope
- Break-even analysis combining the estimate with the margin structure
- Validation that recomputes the fixed-effects slope with pair-level sums (Σxy − n·x̄·ȳ), an algebraically different route

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One line per source valid order line |
| 02 | Pooled slope = a sums-of-squares recount |
| 03 | **Fixed-effects slope = a pair-level algebraic recount** |
| 04 | Pair means and counts = a `GROUP BY` recount |
| 05 | Fixed-effects lines = lines in eligible pairs |
| 06 | Fixed-effects pairs = eligible pairs |
| 07 | All quantities positive and logs correct |
| 08 | Demeaned discount sums to zero within every pair |
| 09 | Discounts between 0 and 100 % |
| 10 | Every NULL discount is treated as 0 |

## 8. Findings

**The pooled data says discount buys volume. It is almost entirely mix.**

| Model | Lines | Pairs | % more units per discount point | Correlation | t |
|---|---:|---:|---:|---:|---:|
| A. Pooled | 26,472 | | **5.90 %** | 0.244 | 40.9 |
| B. Within segment | 26,472 | | 0.70 % | 0.023 | 3.7 |
| **C. Within customer × product** | 12,701 | 2,217 | **0.97 %** | 0.050 | 5.1 |

| Segment | Average discount | Typical line (geometric mean units) |
|---|---:|---:|
| Distributor | 10.88 % | 13.2 |
| Enterprise | 8.12 % | 9.8 |
| Mid-Market | 4.07 % | 6.1 |
| SMB | 1.38 % | 3.9 |

- Distributors buy larger quantities **and** get larger discounts, so the pooled data links the two. Within a segment, the effect falls from 5.9 % to 0.7 % per point.
- **When the same customer buys the same product, one more discount point goes with about 1 % more units.** The effect is statistically real (t = 5.1) but small.

| Discount compared with the pair's own average | Lines | Average gap | Units compared with own average |
|---|---:|---:|---:|
| 2+ points below | 3,445 | −4.2 pts | −3.7 % |
| 0–2 points below | 2,740 | −1.1 pts | −1.5 % |
| 0–2 points above | 2,888 | +0.9 pts | −0.1 % |
| 2+ points above | 3,628 | +4.1 pts | +4.9 % |

A discount about 8 points higher than the customer's usual level on a product (from 4 below to 4 above) goes with about 9 % more units.

**By segment, the response is small everywhere and absent for SMB.**

| Segment | Lines | Pairs | % more units per point | Typical within-pair discount variation |
|---|---:|---:|---:|---:|
| Distributor | 4,245 | 701 | 0.48 % | 3.4 pts |
| Enterprise | 5,743 | 966 | 1.29 % | 3.8 pts |
| Mid-Market | 2,040 | 401 | 0.95 % | 3.0 pts |
| SMB | 673 | 149 | −0.08 % | 1.7 pts |

**Discount does not pay for itself.**

| | Value |
|---|---:|
| Average discount | 8.76 % |
| Gross margin as % of pre-discount price | 10.5 % |
| Margin after one more discount point | 9.5 % |
| **Extra units needed to keep gross profit unchanged** | **10.5 %** |
| Extra units measured (model C) | 0.97 % |
| **Gross profit change per extra discount point** | **−8.6 %** |

- Because margins are thin, each extra discount point removes about a tenth of the gross profit on the line. Customers would need to buy 10.5 % more to compensate; they buy about 1 % more.

## 9. Business implications and recommendations

1. **Stop using discount to win volume from existing customers.** Each extra point costs about 8.6 % of gross profit on the line and brings about 1 % more units.
2. **Retire the "bigger discount, bigger order" argument in deal reviews.** The pooled correlation that supports it is segment mix: distributors are both large buyers and highly discounted.
3. **If discounts are needed, tie them to quantity explicitly** (price breaks at stated quantities) so the volume is committed before the discount is given, rather than hoped for after.
4. **Test reductions on SMB and distributors first.** SMB shows no measurable response, and distributors 0.5 % per point; a one-point reduction there would recover margin with little volume at risk. Run it as a controlled pilot.
5. **Combine with the discount band** from the [discount consistency](../../02_sales_and_profitability/06_discount_consistency/) study, so deviations from the band need a stated reason.

## 10. Assumptions and limitations

- **Observational, not experimental.** Model C removes everything stable about a customer and product, but not changes over time (for example a customer winning a project and negotiating a one-off deal). If salespeople give bigger discounts on bigger orders, the 0.97 % is an **upper bound** on the effect of discount on volume.
- **Units only.** The analysis measures the size of each line, not whether a discount wins orders that would otherwise go to a competitor, or brings forward future purchases.
- **Pairs with 3+ purchases and varying discount** are used for model C (12,701 of 26,472 lines). Customers who buy a product rarely may respond differently.
- **Current unit cost** is used for margin, as elsewhere in the repository.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Line and estimate tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
