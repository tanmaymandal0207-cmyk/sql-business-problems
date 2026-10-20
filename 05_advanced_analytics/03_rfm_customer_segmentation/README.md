# Case Study · RFM Customer Segmentation

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. As-of date 30 Sep 2026; 12-month window October 2025 – September 2026.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-20 |

---

## 1. Business problem

Sales and marketing treat all customers the same way: the same visit schedule, the same offers. The commercial director wants customers grouped by **behaviour**, so each group gets a different plan: retain, grow, win back, or serve at low cost. The standard tool for this is **RFM** segmentation:

- **Recency:** how recently did the customer order?
- **Frequency:** how often do they order?
- **Monetary:** how much do they spend?

## 2. Business questions

1. How many customers, and how much revenue, fall in each RFM segment?
2. How do RFM segments line up with the existing customer segments (Enterprise, Distributor, Mid-Market, SMB)?
3. Which high-value customers are slipping away?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order dates, status, customer |
| `sales_order_items` | One row per product per order | Order revenue |
| `customers` | One row per customer | Name and customer segment |

**Population:** 426 customers with at least one order (not Cancelled or Returned) at any time.

## 4. Metric definitions

| Metric | Definition |
|---|---|
| R (recency) | Days since the last order, all time |
| F (frequency) | Orders in the last 12 months |
| M (monetary) | Revenue in the last 12 months (NULL discount = 0 %) |
| Scores | Each of R, F and M scored 1–5 with `NTILE(5)` (5 = most recent / most frequent / highest spend). Customers with no orders in the window get F = 1 and M = 1. |

**Segments** (first matching rule wins):

| Segment | Rule | Typical action |
|---|---|---|
| Champions | R ≥ 4, F ≥ 4, M ≥ 4 | Retain: key account management, priority service |
| Cannot lose | R ≤ 2, M ≥ 4 | Senior-level call now; find out what changed |
| Loyal | R ≥ 3, F ≥ 4 | Grow: cross-sell other categories |
| At risk | R ≤ 2, F ≥ 3 | Re-engage with an account review |
| Potential loyalists | R ≥ 4, F ≥ 2 | Encourage repeat orders (contracts, reorder reminders) |
| New or returning | R ≥ 4, F = 1 | Onboard; second-order follow-up |
| Hibernating | R ≤ 2 | Low-cost reactivation; no field visits |
| Need attention | Everything else | Review individually |

## 5. Analytical approach

1. **RFM table** (`sahyadri_b2b.customer_rfm`). Recency, frequency, monetary value, the three scores, RFM code and segment for each customer.
2. **Segment summary.** Customers, 12-month revenue, average recency and frequency.
3. **RFM segments × customer segments.**
4. **Priority list** of the largest Cannot-lose and At-risk customers.

## 6. SQL techniques used

- Order-level revenue, then customer-level `MAX`, `COUNTIF` and conditional `SUM` for R, F and M
- Quintile scoring with `NTILE(5) OVER (ORDER BY …)`, with deterministic tie-breaking on `customer_id`
- A rule-based `CASE` segmentation in priority order
- An RFM code built with `CONCAT` and `CAST`
- Conditional pivot with `COUNTIF` for the segment cross-tab

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer |
| 02 | Every customer with an in-scope order is included (426) |
| 03 | 12-month revenue = source total for the window |
| 04 | 12-month orders = source count for the window |
| 05 | Every score is between 1 and 5 |
| 06 | Recency quintiles are balanced (group sizes differ by at most 1) |
| 07 | Customers with no orders in the window are scored F = 1, M = 1 |
| 08 | Recency recomputed from the last order date on every row |
| 09 | Every customer has a segment |
| 10 | Every Champion meets the Champion rule |

The 12-month revenue (₹40.36 crore) also matches the 12-month revenue in the [ABC-XYZ classification](../01_abc_xyz_product_classification/), which covers the same window from the product side.

## 8. Findings

**A quarter of customers generate nearly four-fifths of revenue.**

| RFM segment | Customers | Share | 12-month revenue | Share | Avg days since last order |
|---|---:|---:|---:|---:|---:|
| Champions | 103 | 24.2 % | ₹31.64 crore | **78.4 %** | 10 |
| Cannot lose | 17 | 4.0 % | ₹1.55 crore | 3.8 % | 126 |
| Loyal | 59 | 13.8 % | ₹4.63 crore | 11.5 % | 39 |
| At risk | 29 | 6.8 % | ₹0.37 crore | 0.9 % | 140 |
| Potential loyalists | 48 | 11.3 % | ₹1.02 crore | 2.5 % | 11 |
| New or returning | 4 | 0.9 % | ₹0.04 crore | 0.1 % | 18 |
| Hibernating | 125 | **29.3 %** | ₹0.36 crore | 0.9 % | 398 |
| Need attention | 41 | 9.6 % | ₹0.76 crore | 1.9 % | 51 |

- **17 "Cannot lose" customers (₹1.55 crore a year) have gone quiet.** They spent heavily in the last year but have not ordered for 84 to 302 days. Ten of the 17 are distributors. The largest (customer 1301, ₹31.2 lakh) has not ordered for 85 days after 12 orders in the year. Four of the top five also appear on the cycle-based early-warning list in [Customer churn early warning](../../01_customer_and_revenue/02_customer_churn_early_warning/), so two different methods identify the same accounts.
- **Champions are concentrated in larger accounts.** 39 Enterprise, 24 Distributor and 28 Mid-Market customers are Champions, against only 12 SMBs.
- **Hibernating customers are mainly SMBs.** 71 of the 125 are SMB customers, last active more than a year ago on average and worth under 1 % of revenue. This matches the SMB churn pattern in the churn study.
- **48 Potential loyalists** ordered recently but less often (3.4 orders in the year on average, ₹1.02 crore in total). They are the most realistic source of new Champions. 28 of them are SMBs.

## 9. Business implications and recommendations

1. **Call the 17 "Cannot lose" customers this month**, starting with the largest distributors. Assign each to a senior salesperson and find out whether the cause is price, service, delivery or a competitor.
2. **Protect the 103 Champions** with named account managers, priority dispatch and early warning of stock-outs. They carry 78 % of revenue.
3. **Run a structured repeat-order programme for Potential loyalists**, such as annual rate contracts or reorder reminders, to move them up to Loyal or Champion.
4. **Serve Hibernating customers through low-cost channels**, such as email offers, inside sales or a distributor partner, rather than field visits. 125 customers at under 1 % of revenue do not justify visits.
5. **Refresh the RFM scores monthly** and track movement between segments. A customer moving from Champion to Cannot lose is the most important signal in this model.

## 10. Assumptions and limitations

- **Relative scores.** NTILE ranks customers against each other, so a score of 5 means "top 20 % of this customer base", not an absolute threshold. As the base changes, the cut-offs move.
- **12-month window.** Frequency and monetary value cover the last 12 months only. Seasonal buyers may be scored differently depending on the as-of date.
- **Equal weight.** R, F and M are treated equally in the segment rules. A business that values margin over revenue may prefer a margin-based M.
- **Segment rules are conventions.** The names and thresholds follow common RFM practice but are business choices, and should be agreed with sales leadership.
- **Overlap with churn analysis.** RFM recency uses a ranking. The churn study uses fixed day bands and each customer's own cycle. The two are complementary and largely agree on the accounts at risk.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | RFM table and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
