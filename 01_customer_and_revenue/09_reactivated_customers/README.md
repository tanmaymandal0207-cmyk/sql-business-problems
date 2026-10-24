# Case Study · Reactivated Customers

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 230 returns by 160 customers, January 2024 – September 2026.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-25 |

---

## 1. Business problem

The [churn early warning](../02_customer_churn_early_warning/) study classes a customer as Lapsed after 180 days without an order. Some of those customers come back, on their own or after a sales call. The commercial head is deciding how much effort to put into win-back, and needs evidence on what a returning customer is worth: how often they come back, how much they buy, whether they stay, and which returns need attention before the customer goes quiet again.

## 2. Business questions

1. How many lapsed customers come back, and after how long?
2. How much do they buy after returning, compared with before they went quiet?
3. Do they stay, or lapse again? How does that compare with regular and new customers?
4. Which returns are most likely to last?
5. How much of the last 12 months' revenue comes from returned customers, and which recent returners need follow-up now?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, salesperson, order date, status |
| `sales_order_items` | One row per product per order | Revenue |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Revenue | Quantity × unit price × (1 − discount %), orders not Cancelled or Returned; NULL discount = 0 % |
| **Return** (reactivation) | An order placed **more than 180 days** after the customer's previous order |
| Gap | Days between the return order and the previous order |
| **Stayed** | The customer ordered again within 180 days of the return order |
| Observed return | A return on or before 3 Apr 2026, so the full 180 days after it can be seen |
| Before / after revenue | Revenue in the 180 days ending on the last order before the silence, and in the 180 days starting on the return date |
| Salesperson change | Whether the return order and the order before the silence were handled by the same salesperson |

The 180-day threshold matches the Lapsed status in the churn study, so the two analyses use the same language.

## 5. Analytical approach

1. **Gap table** (`sahyadri_b2b.customer_order_gaps`). Every valid order with its sequence number, previous and next order dates, gaps and a return flag.
2. **Event table** (`sahyadri_b2b.reactivation_events`). One row per return: gap, history, segment, salesperson change, stayed flag and before / after revenue.
3. **Volume.** Returns against new customers each quarter.
4. **Staying power.** Reorder rates after a return, after a regular repeat order and after a first order, then by gap, history, segment and salesperson.
5. **Value.** Before and after revenue, split by outcome.
6. **Last 12 months** contribution, and a follow-up list of recent returners who have not reordered.

## 6. SQL techniques used

- `LAG` and `LEAD` to place every order between its neighbours, so one pass finds every gap
- Date-range conditional aggregation (`SUM(IF(date BETWEEN …))`) for before and after windows, instead of correlated subqueries
- Censoring rule (`is_observed`) so recent returns are not counted as failures before they have had time to reorder
- Validation that recounts returns with a self-join, and checks that each customer's gaps add up to the span from first to last order

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One gap-table row per source valid order |
| 02 | Gap-table revenue = source revenue |
| 03 | First orders = customers, with no previous order date |
| 04 | **Returns = an independent self-join recount** |
| 05 | One event row per return |
| 06 | Every event has a gap over 180 days and a last order before the return |
| 07 | Stayed flag agrees with the next order date |
| 08 | After-window revenue includes the return order |
| 09 | Observed flag agrees with the as-of cut-off |
| 10 | Each customer's gaps sum to the days from first to last order |

## 8. Findings

**Returning customers now outnumber new customers about two to one.**

| | Returns | Customers | Median gap |
|---|---:|---:|---:|
| All periods | 230 | 160 | 249 days |
| Customers who returned more than once | | 66 | |

| Last 12 months (Oct 2025 – Sep 2026) | Count | Value of the first or return order |
|---|---:|---:|
| New customers (first order) | 59 | ₹52.0 lakh |
| Returns | 112 | ₹61.1 lakh |

- Since early 2025, returns have matched or exceeded new customers in every quarter. Win-back is already a larger source of "new" orders than acquisition.
- 66 of the 160 customers have lapsed and returned more than once. For them, long silences are a buying pattern, not a lost relationship.

**Returned customers buy more than before they went quiet.**

| Outcome (observed returns) | Returns | Revenue 180 days before silence | Revenue 180 days after return | After ÷ before | Orders in 180 days after |
|---|---:|---:|---:|---:|---:|
| Stayed | 132 | ₹2.02 crore | ₹2.82 crore | 1.40 | 3.3 |
| Lapsed again | 42 | ₹43.2 lakh | ₹19.6 lakh | 0.45 | 1.0 |
| **All** | **174** | **₹2.45 crore** | **₹3.02 crore** | **1.23** | 2.7 |

- A return is not a small order to test the water: on average returned customers buy 23 % more in the next six months than in the six months before the silence.
- The 42 that lapse again place a single order and stop. That first return order is the moment to secure the next one.

**But a returned customer is fragile, closer to a new customer than to a regular one.**

| After this kind of order | Orders observed | Next order within 90 days | Within 180 days |
|---|---:|---:|---:|
| Regular repeat order | 6,994 | 92.8 % | **97.5 %** |
| Return order | 174 | 54.0 % | **75.9 %** |
| First order of a new customer | 398 | 56.8 % | 70.4 % |

- One return in four lapses again within six months, against one regular order in forty (z = −16.5).
- **A returned customer should be handled like a new one**, with onboarding-style follow-up, not handed straight back to routine account management.

**The longer the silence, the less likely the return lasts.**

| Dimension | Group | Returns observed | Stayed |
|---|---|---:|---:|
| Gap length | 181–270 days | 115 | 79.1 % |
| | 271–365 days | 37 | 75.7 % |
| | Over 365 days | 22 | **59.1 %** |
| Orders before the silence | 1 | 56 | **67.9 %** |
| | 2–3 | 64 | 79.7 % |
| | 4–9 | 47 | 76.6 % |
| | 10+ | 7 | 100.0 % |
| Salesperson on the return order | Same as before | 124 | 72.6 % |
| | Different | 42 | 83.3 % |
| | Not recorded | 8 | 87.5 % |
| Segment | Distributor / Enterprise / Mid-Market / SMB | 24 / 15 / 46 / 89 | 79.2 / 73.3 / 76.1 / 75.3 % |

- **Returns after more than a year are the weakest** (59.1 % against 78.3 % for shorter gaps, z = −2.0, just significant at 5 %).
- One-order customers are less likely to stay (67.9 % against 79.7 % for the rest, z = −1.7, not significant at 5 %).
- Returns handled by a different salesperson stayed more often (83.3 % against 72.6 %), but the difference is not significant (z = 1.4) and should not drive reassignment on its own.
- Segment makes no material difference.

**Returned customers are worth ₹2.02 crore in the last 12 months.** 104 customers returned in the last 12 months. Their revenue from the return onwards was ₹2.02 crore, **5.0 % of the ₹40.36 crore** total.

**Ten recent returners have not reordered yet.** The largest: Kaveri Enterprises (Distributor, ₹4.38 lakh return order on 30 Sep 2026 after 350 days), Ambica Kulkarni Autoparts (₹1.24 lakh, 12 earlier orders), Parikh Packaging (₹1.22 lakh) and Precision Kapoor Alloys (₹1.09 lakh). Four returns from May–July 2026 are already 77–133 days without a follow-up order: Om Bhatia Auto Industries (returned after 730 days), Classic Mittal Trading (₹10.0 lakh of earlier revenue), Ganga Forgings and Apex Bansal Life Sciences.

## 9. Business implications and recommendations

1. **Treat every return as a new start.** Trigger a follow-up call within 30 days of a return order and a reorder reminder at 60 days, the same treatment a new customer gets. The [reorder reminders](../../05_advanced_analytics/06_reorder_reminders/) list can include returned customers automatically.
2. **Work the follow-up list now.** Call the 10 recent returners who have not reordered, starting with the four that returned in May–July 2026.
3. **Prioritise win-back before the one-year mark.** Returns after more than 365 days last least. This supports the [time-to-reorder](../../05_advanced_analytics/07_time_to_reorder_survival/) recommendation to call at 90–180 days of silence.
4. **Report returns separately from new customers.** Counting both as "new business" hides that win-back produces more orders than acquisition. Track returns, stay rate and 180-day value as win-back KPIs.
5. **Ask lapsed-and-returned customers why they paused.** With 66 customers lapsing more than once, the cause may be project-based buying, a second supplier or service issues. The answer decides whether to chase them or simply plan for their cycle.

## 10. Assumptions and limitations

- **Threshold.** A 180-day silence defines a lapse. A different threshold would change the counts, though the comparison between return and repeat orders holds for nearby values.
- **Recent returns are censored.** Returns after 3 Apr 2026 are excluded from staying-power and value analysis, because their 180-day outcome is not yet known.
- **No record of win-back activity.** The data cannot separate customers who came back on their own from those who responded to a sales call, so the effect of win-back effort is not measured here.
- **Small groups.** Several bands have fewer than 30 returns. Only the gap-length difference is near statistical significance.
- Cancelled and Returned orders do not count as activity: a customer whose only orders in a period were cancelled is treated as silent.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Gap and event tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
