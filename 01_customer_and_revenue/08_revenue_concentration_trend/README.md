# Case Study · Revenue Concentration Trend

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 11 quarters (2024 Q1 – 2026 Q3) and 8 rolling 12-month windows (Dec 2024 – Sep 2026).

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-25 |

---

## 1. Business problem

The [customer revenue risk](../01_customer_revenue_risk/) study measured concentration at one point in time. The board now asks a different question: **is the business becoming more or less dependent on a few customers?** Lenders and investors read rising concentration as rising risk. The CFO wants concentration tracked over time with standard measures, and wants to know whether the latest quarter's movement is a trend or a one-off.

## 2. Business questions

1. Is revenue becoming more or less concentrated, quarter by quarter and on a rolling 12-month basis?
2. How many "equally sized" customers is the business effectively relying on?
3. Which customers drive the changes, and is the latest movement a trend or a one-off?
4. Which segments are most concentrated?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Revenue |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

All measures use each customer's revenue share sᵢ within the period.

| Term | Definition |
|---|---|
| Revenue | Quantity × unit price × (1 − discount %), orders not Cancelled or Returned; NULL discount = 0 % |
| Top-1 / top-5 / top-10 share | Share of period revenue from the largest 1, 5 and 10 customers |
| **HHI** | Herfindahl-Hirschman Index = Σ sᵢ². Reported in points (× 10,000). Higher = more concentrated. |
| **Effective customers** | 1 ÷ HHI: the number of equal-sized customers that would give the same concentration |
| **Gini** | 2 Σ(i · xᵢ) ÷ (n Σxᵢ) − (n + 1) ÷ n, customers sorted smallest to largest. 0 = all equal. |
| Rolling 12 months | The quarter and the three before it |
| Period customers | Customers with revenue in the period only |

HHI is sensitive to the largest customers; Gini describes inequality across the whole customer base. Using both separates "one customer got big" from "the base became more unequal".

## 5. Analytical approach

1. **Period table** (`sahyadri_b2b.concentration_periods`). Revenue per customer per quarter, and per rolling 12-month window built by joining four quarters.
2. **Measures table** (`sahyadri_b2b.concentration_measures`). Top-N shares, HHI, effective customers and Gini for every period.
3. **Largest customer each quarter**, with the second-largest share for comparison.
4. **One-off test.** HHI recomputed for each quarter without its single largest order.
5. **Segment concentration** for the latest 12 months.

## 6. SQL techniques used

- Rolling windows built with a range join between quarters, so each window is the exact sum of its quarters
- HHI and Gini as single-pass aggregates over window-function shares and ranks
- `WHERE TRUE QUALIFY ROW_NUMBER() …` to drop each quarter's largest order
- Validation that recomputes Gini with a different formula (mean absolute difference over all customer pairs)

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | No duplicate customer-period rows |
| 02 | Quarterly revenue = source revenue |
| 03 | Latest 12-month revenue = source revenue for those 12 months |
| 04 | Latest 12-month customer count = source |
| 05 | HHI between 1/n and 1; effective customers ≤ customers |
| 06 | Top-1 ≤ top-5 ≤ top-10 ≤ 100 % |
| 07 | **Gini = an independent mean-absolute-difference calculation** |
| 08 | Gini between 0 and 1 |
| 09 | 11 quarters and 8 rolling windows |
| 10 | Every rolling window = the sum of its four quarters, per customer |

## 8. Findings

**On a 12-month view, concentration fell through 2025 and has risen since March 2026.**

| 12 months to | Customers | HHI points | Effective customers | Top-1 share | Top-10 share | Gini |
|---|---:|---:|---:|---:|---:|---:|
| Dec 2024 | 318 | 217 | 46.2 | 7.0 % | 38.6 % | 0.747 |
| Mar 2025 | 323 | 197 | 50.7 | 7.4 % | 35.8 % | 0.747 |
| Jun 2025 | 331 | 189 | 53.0 | 7.0 % | 34.6 % | 0.747 |
| Sep 2025 | 340 | 184 | 54.3 | 7.0 % | 34.4 % | 0.741 |
| Dec 2025 | 347 | 170 | 58.7 | 6.5 % | 32.8 % | 0.737 |
| Mar 2026 | 350 | **162** | **61.7** | 5.0 % | 32.6 % | 0.736 |
| Jun 2026 | 360 | 170 | 59.0 | 5.0 % | 33.9 % | 0.744 |
| Sep 2026 | 367 | 200 | 49.9 | 8.2 % | 35.8 % | 0.753 |

- The customer base grew from 318 to 367. Effective customers rose to 61.7 by March 2026, then fell to 49.9 in two quarters. **Growth has come with more reliance on the largest accounts.**
- **All values are low by any standard.** An HHI of 200 points (0.02) is the equivalent of about 50 equal customers. Concentration is a watch item, not a crisis.
- Gini is stable at 0.74–0.75 on a 12-month basis: the inequality of the whole base has not changed; the movement comes from the very top.

**Quarterly concentration is volatile, and the latest quarter is the highest in the period.**

| Quarter | HHI points | Effective customers | Largest customer | Largest share | Second-largest share |
|---|---:|---:|---|---:|---:|
| 2024 Q1 | 383 | 26.1 | Krishna Castings Ltd | 13.8 % | 7.5 % |
| 2024 Q2 | 265 | 37.8 | Siddhivinayak Mishra Trading Co. | 8.5 % | 6.2 % |
| 2024 Q3 | 237 | 42.1 | Annapurna Precision Engineering Ltd | 8.5 % | 6.3 % |
| 2024 Q4 | 239 | 41.8 | Siddhivinayak Mishra Trading Co. | 6.9 % | 6.7 % |
| 2025 Q1 | 253 | 39.5 | Siddhivinayak Mishra Trading Co. | 9.3 % | 6.4 % |
| 2025 Q2 | 208 | 48.1 | Siddhivinayak Mishra Trading Co. | 6.8 % | 5.6 % |
| 2025 Q3 | 167 | 60.0 | Krishna Castings Ltd | 4.6 % | 4.2 % |
| 2025 Q4 | 178 | 56.3 | Siddhivinayak Mishra Trading Co. | 5.1 % | 4.6 % |
| 2026 Q1 | 269 | 37.2 | Banerjee Sales Corporation Pvt Ltd | 11.6 % | 4.8 % |
| 2026 Q2 | 225 | 44.5 | Krishna Castings Ltd | 8.1 % | 5.6 % |
| 2026 Q3 | **439** | **22.8** | Siddhivinayak Mishra Trading Co. | **18.4 %** | 4.1 % |

- In 2026 Q3 Siddhivinayak Mishra Trading bought ₹1.87 crore, **18.4 % of the quarter**. The second-largest customer had 4.1 %.
- Only four customers have been the largest in any quarter. They change places, so no single customer has a permanent hold.

**The 2026 Q3 spike is mostly one order, not a trend.**

| Quarter | HHI points | Without the quarter's largest order | Effective customers without it |
|---|---:|---:|---:|
| 2024 Q1 | 383 | 256 | 39.0 |
| 2026 Q1 | 269 | 168 | 59.6 |
| 2026 Q3 | 439 | **199** | **50.4** |
| Other 8 quarters | 167–265 | 165–253 | 39.5–60.4 |

- Removing the single largest order of 2026 Q3 more than halves its HHI, back to a normal level. The 2026 Q1 rise was also one order: Banerjee Sales Corporation's ₹1.19 crore order.
- **Large one-off orders, not a narrowing customer base, drive the quarterly peaks.** They still matter: lumpy revenue makes quarterly results and cash harder to forecast.

**Distributors are by far the most concentrated segment.**

| Segment (last 12 months) | HHI points | Effective customers | Largest customer's share of segment |
|---|---:|---:|---:|
| Distributor | **753** | **13.3** | 20.3 % |
| Enterprise | 443 | 22.6 | 12.3 % |
| Mid-Market | 311 | 32.1 | 11.7 % |
| SMB | 259 | 38.6 | 9.3 % |

## 9. Business implications and recommendations

1. **Report the 12-month HHI and effective customers to the board quarterly**, with the "without largest order" figure next to it. This shows lenders the underlying trend instead of a single order's effect.
2. **Set an alert threshold**, for example any customer above 15 % of a quarter or effective customers below 40 on a 12-month basis. The latest quarter would have triggered the first.
3. **Manage the large-order customers as key accounts.** Siddhivinayak Mishra Trading, Krishna Castings, Banerjee Sales Corporation and Annapurna Precision Engineering are the only customers that have been largest in any quarter. Agree order forecasts and credit terms with them, and watch their balances in the [receivables roll-forward](../../04_data_quality_and_reconciliation/05_receivables_rollforward/).
4. **Reduce distributor dependence.** With only about 13 effective distributors, losing one large distributor would move the whole segment. Widen the distributor base in the regions the largest one serves.
5. **Plan for lumpy quarters.** A ₹1–2 crore order can swing a quarter. Budget and cash forecasts should be built on the 12-month run rate, with large orders treated separately.

## 10. Assumptions and limitations

- **Customer, not group.** Related companies under common ownership are measured separately. If any of the large customers belong to one group, true concentration is higher.
- **Order date, not invoice or payment date.** A large order counts in the quarter it was placed.
- **Only customers with revenue in the period are counted.** Inactive customers do not dilute the measures.
- **HHI thresholds from competition policy** (for example 1,500 and 2,500 points) describe market structure, not customer risk. They are not used here; the trend matters more than the level.
- 2026 Q3 is the last complete quarter. Orders placed after 30 Sep 2026 are excluded.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Period and measure tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
