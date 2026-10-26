# Case Study · Order Splitting Test

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 10,000 orders tested against five candidate approval limits and against what chance alone would produce.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

The company is introducing a delegation-of-authority policy: sales orders above set values, for example ₹50,000, ₹1 lakh or ₹2 lakh, will need a manager's approval, mainly to control discounts and credit. Internal audit knows the classic way around such limits: split one large order into several smaller orders placed the same day, each just under the limit. Before the limits go live, audit wants a **baseline**. Is there already any sign of order splitting, or of order values being kept just under round amounts? If the behaviour appears after the policy starts, the baseline shows it is new.

## 2. Business questions

1. Do order values bunch just below round thresholds?
2. Do customers place more same-day orders than chance would produce?
3. Are same-day orders more often just below a threshold than other orders?
4. Is the same product ordered twice on the same day more often than chance?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, salesperson, order date |
| `sales_order_items` | One row per product per order | Order value, products |
| `customers` | One row per customer | Names |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Orders | All orders, any status (an approval would apply at entry) |
| Candidate thresholds | ₹25,000, ₹50,000, ₹1 lakh, ₹2 lakh, ₹5 lakh |
| **Bunching ratio** | Orders in [0.95 t, t) ÷ orders in [t, 1.05 t). Above about 1 means more orders just below t than just above. |
| Control points | 51 points on a log grid from ₹20,000 to about ₹6 lakh, more than 10 % away from any threshold, where no bunching is expected |
| Bunching z | (log ratio at threshold − mean log ratio at controls) ÷ s.d. of controls |
| **Expected same-day pairs** | Σ over customers C(n, 2) × q, where q = Σ (share of all orders on day d)². This is what chance gives if each customer's orders fell on days in proportion to company volume. |
| Same-day vs other orders | Odds ratio of below / above (within 20 % of t) for same-day orders against other orders; z = ln(OR) ÷ √(1/a + 1/b + 1/c + 1/d); \|z\| ≥ 2.58 is significant after a Bonferroni correction for 5 thresholds |

## 5. Analytical approach

1. **Order table** (`sahyadri_b2b.split_test_orders`). Order value, number of orders and total value for the same customer on the same day.
2. **Bunching table** (`sahyadri_b2b.split_test_bunching`). Ratios at thresholds and control points, and z-scores.
3. **Same-day coincidence**: observed against expected same-day pairs, for orders and for the same product.
4. **Same-day orders at thresholds**: odds ratios and z-scores; groups that cross ₹1 lakh only when added together; a review list of same-product, same-day orders.

## 6. SQL techniques used

- Bunching (density discontinuity) test against a control grid generated with `GENERATE_ARRAY` and `POW`
- Coincidence model: expected same-day pairs from daily volume shares, Σ C(n, 2) × Σ p²
- Odds ratios and log-odds z-scores computed in SQL, with a Bonferroni threshold
- `COUNT(*) OVER (PARTITION BY customer, date)` to tag same-day orders without a self-join

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per source order |
| 02 | Order values = source |
| 03 | Same-day order counts = a `GROUP BY` recount |
| 04 | Same-day totals = a `GROUP BY` recount |
| 05 | 506 same-day groups with two or more orders |
| 06 | ₹1 lakh bunching counts = an independent recount |
| 07 | No control point within 10 % of a threshold |
| 08 | Daily order shares sum to 1 |
| 09 | Five thresholds tested |
| 10 | Bunching ratios and log ratios are consistent |

## 8. Findings

**No bunching below round amounts.**

| Threshold | Just below | Just above | Ratio | Typical ratio at controls | z |
|---|---:|---:|---:|---:|---:|
| ₹25,000 | 91 | 130 | 0.70 | 1.07 | −2.78 |
| ₹50,000 | 161 | 139 | 1.16 | 1.07 | 0.54 |
| ₹1 lakh | 139 | 134 | 1.04 | 1.07 | −0.19 |
| ₹2 lakh | 97 | 103 | 0.94 | 1.07 | −0.82 |
| ₹5 lakh | 30 | 21 | 1.43 | 1.07 | 1.92 |

- No threshold shows a significant excess just below it. The only significant result (₹25,000, z = −2.78) is a **shortage** below the threshold, the opposite of avoidance behaviour.

**Customers place fewer same-day orders than chance predicts.**

| | Observed | Expected by chance | Ratio | z |
|---|---:|---:|---:|---:|
| Same-day order pairs (same customer) | 563 | 620 | 0.91 | −2.29 |
| Same product on two orders the same day | 129 | 108 | 1.19 | 2.02 |

- There are 506 customer-days with two or more orders (1,039 orders). That is slightly **fewer** than random timing would give, not more.
- The same product appears on two same-day orders a little more often than chance (z = 2.02), which is worth a look but is not significant once the several tests in this study are allowed for.

**Same-day orders are not concentrated just below thresholds.**

| Threshold | Same-day below / above | Other orders below / above | Odds ratio | z |
|---|---|---|---:|---:|
| ₹25,000 | 47 / 50 | 401 / 418 | 0.98 | −0.09 |
| ₹50,000 | 61 / 68 | 609 / 473 | 0.70 | −1.94 |
| ₹1 lakh | 89 / 52 | 539 / 427 | 1.36 | 1.64 |
| ₹2 lakh | 53 / 46 | 381 / 297 | 0.90 | −0.50 |
| ₹5 lakh | 19 / 7 | 102 / 54 | 1.44 | 0.77 |

- The strongest signal is at ₹1 lakh (odds ratio 1.36, z = 1.64), below the Bonferroni level of 2.58. It is the threshold to watch once the policy is live.
- 66 same-day groups (31 customers) have every order under ₹1 lakh but a day total above it, averaging ₹1.36 lakh. These would need approval if they had been one order; today they are consistent with normal ordering.

**One same-day pair stands out for review.** Banerjee Sales Corporation placed two orders for the same product (2196) on 30 March 2026, the day before the financial year end, worth ₹77.7 lakh together. It is the largest same-product, same-day pair by far, and falls in the quarter of the large Banerjee order noted in the [revenue concentration](../../01_customer_and_revenue/08_revenue_concentration_trend/) study.

## 9. Business implications and recommendations

1. **Record this as the pre-policy baseline.** Today there is no bunching below round amounts and no excess of same-day orders. Any change after the approval limits start can be attributed to the policy.
2. **Re-run the test quarterly after go-live**, with the actual approval limits in the threshold list. Watch ₹1 lakh first, where same-day orders already lean slightly below the limit.
3. **Aggregate same-day orders for approval.** Configure the approval check on the customer's total for the day (or a rolling 3 days), not only on each order. The 66 groups above would then be caught automatically.
4. **Review the Banerjee Sales Corporation year-end pair** (orders 107989 and 107995): confirm why one requirement was entered as two orders on the last day of the year.
5. **Block same-product duplicates at entry.** A warning when the same product is ordered twice for one customer on one day prevents both splitting and accidental double entry.

## 10. Assumptions and limitations

- **Candidate thresholds.** The company has no approval limits yet; the test uses common round amounts. The real limits should be added once set.
- **Chance model.** Expected same-day pairs assume each customer orders on days in proportion to company volume. Customers with regular ordering days would produce more same-day pairs by habit, which would make the observed count look high; it is low, so the conclusion holds.
- **Several tests.** Five thresholds and several statistics are tested. Isolated results near z = 2 are expected by chance.
- **Order value after discount.** If approvals are set on gross (list) value, the thresholds would move accordingly.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order and bunching tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
