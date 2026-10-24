# Case Study · Time-to-Reorder Survival Analysis

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 8,916 order spells, January 2024 – September 2026.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-24 |

---

## 1. Business problem

Sales teams treat a customer as "lost" after an arbitrary silence, often 90 days. That rule ignores two facts: segments reorder at very different speeds, and a customer who has been quiet for a while may still be likely to come back. Simple averages of days between orders are also biased, because every customer's most recent gap is still open: we do not yet know when, or whether, they will order again.

**Survival analysis** handles those open gaps properly. The commercial head wants an evidence-based rule for when to start win-back activity and when to treat a customer as lost.

## 2. Business questions

1. After an order, how likely is a customer to order again within 30, 60, 90, 180 and 365 days, by segment?
2. What is the median time to the next order?
3. Given that a customer has been silent for X days, how likely are they to order within the next 180 days? At what silence is a customer more likely lost than not?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Spell | The time from one order date of a customer to their next. Several orders on one day count as one order date. |
| Event | The customer ordered again |
| Censored spell | Still open at 30 Sep 2026. Every customer has exactly one, their latest. |
| **Kaplan–Meier survival** S(t) | Probability of no reorder by day t = ∏ (1 − d/n) over event days ≤ t, where d = spells ending in a reorder that day and n = spells still at risk |
| Greenwood 95 % interval | Var[S(t)] = S(t)² × Σ d / (n (n − d)) |
| Conditional reorder probability | P(reorder within the next h days \| silent for x days) = 1 − S(x + h) ÷ S(x) |

Orders that were Cancelled or Returned are not counted.

## 5. Analytical approach

1. **Spell table** (`sahyadri_b2b.reorder_spells`). One row per customer order date, with the next order date, duration and event flag.
2. **Kaplan–Meier curves** (`sahyadri_b2b.reorder_survival_curve`) for each segment and all customers, with at-risk counts and Greenwood sums. A daily version (`reorder_survival_daily`) fills days 0–1,000.
3. **Reorder probabilities** at 30–365 days and median time to reorder, with a 95 % interval at 90 days.
4. **Conditional return probabilities** after 30–540 days of silence, with the number of spells still at risk.
5. **Comparison** of the naive estimate (ignoring open spells) with Kaplan–Meier.

## 6. SQL techniques used

- `LEAD` to pair each order with the next one, and `IFNULL(next, as_of)` for censoring
- Reverse running sums (`ORDER BY t DESC`) to count spells at risk
- A product of probabilities written as `EXP(SUM(LN(1 − d/n)))` in a running window, with a guard for the case where the curve reaches zero
- A named `WINDOW` clause, `LAST_VALUE(… IGNORE NULLS)` to carry the step function across days, and Greenwood confidence intervals

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One spell per customer and order date |
| 02 | Spells = distinct customer order dates in the source (8,916) |
| 03 | Exactly one open (censored) spell per customer |
| 04 | Every duration matches its dates |
| 05 | At-risk count on the first day = all spells in the curve |
| 06 | Survival stays between 0 and 1 and never increases |
| 07 | **S(30) recomputed** with a join-based product-limit calculation instead of window functions |
| 08 | Events in each curve = reordered spells |
| 09 | The daily table has all 1,001 days for every curve, with S(0) = 1 |
| 10 | Greenwood sums are non-negative and never decrease |

## 8. Findings

**Segments reorder at very different speeds.**

| Segment | Spells | Reorder within 30 days | 90 days (95 % interval) | 180 days | 365 days | Median days to reorder |
|---|---:|---:|---:|---:|---:|---:|
| Enterprise | 2,978 | 84.4 % | 96.9 % (96.2–97.5) | 98.9 % | 99.6 % | **8** |
| Distributor | 1,768 | 73.0 % | 90.8 % (89.5–92.2) | 96.8 % | 98.8 % | 12 |
| Mid-Market | 2,253 | 67.8 % | 89.0 % (87.6–90.3) | 95.2 % | 98.2 % | 15 |
| SMB | 1,917 | 53.6 % | 77.2 % (75.2–79.1) | 88.9 % | 95.9 % | **27** |
| **All customers** | **8,916** | 71.3 % | 89.5 % | 95.4 % | 98.3 % | 13 |

**A 90-day silence does not mean a customer is lost.**

| Days silent | P(reorder in the next 180 days), all customers | SMB | Spells still at risk (all) |
|---:|---:|---:|---:|
| 30 | 87.0 % | 80.2 % | 2,520 |
| 90 | **75.8 %** | 72.2 % | 860 |
| 180 | 61.5 % | 61.9 % | 339 |
| 270 | **45.8 %** | 42.8 % | 169 |
| 365 | 36.4 % | 34.8 % | 98 |
| 540 | 14.5 % | 22.7 % | 44 |

- **After 90 days of silence, three in four customers still come back within six months.** Writing them off at 90 days would abandon customers who are more likely than not to return.
- **The tipping point is about 270 days.** Beyond that, a silent customer is more likely lost than not. After 18 months the chance falls to about 1 in 7.
- **Enterprises are the exception.** A silence over 3 months is rare (3.1 % of spells) and becomes serious quickly. The probability of return falls to about 20 % after 270 days, although few spells remain at that point (11).

**Ignoring open spells understates loyalty.** Counting the latest open gap of each customer as "never reordered" gives a 365-day reorder rate of 90.1 % for SMB, against 95.9 % from Kaplan–Meier. The medians barely change, because only one spell per customer is open.

## 9. Business implications and recommendations

1. **Replace the single 90-day "lost" rule with segment-based stages:**

   | Stage | Enterprise | Distributor and Mid-Market | SMB |
   |---|---|---|---|
   | Check in | 30 days | 45 days | 60 days |
   | Win-back | 90 days | 120 days | 180 days |
   | Treat as lost | 270 days | 365 days | 270 days |

   "Treat as lost" is the first checkpoint where the chance of return within 180 days falls below 50 % for that segment (Enterprise 19 % at 270 days; Distributor 43 % and Mid-Market 43 % at 365 days; SMB 43 % at 270 days). The earlier stages are set while return is still likely.

2. **Prioritise win-back calls at 90–180 days of silence.** The customer is still likely to return (60–76 %), and the call is worth most before the 270-day tipping point.
3. **Feed these thresholds into the [churn early warning](../../01_customer_and_revenue/02_customer_churn_early_warning/) and [Markov customer-state](../08_customer_state_markov/) models**, so that all three use the same evidence-based definition of "lost".
4. **Re-estimate the curves every six months.** As history grows, the tail estimates (after 1 year) will become more reliable.

## 10. Assumptions and limitations

- **History starts in January 2024.** Gaps before then are not observed, so very long-cycle customers are under-represented.
- **Independent spells.** Kaplan–Meier treats spells as independent, but spells from the same customer are related. The intervals are therefore slightly too narrow.
- **Thin tails.** Beyond 365 days, few spells remain at risk (98 overall, 12 or fewer for some segments). Read late-tail percentages as indicative.
- **Order dates only.** The size of the next order is not modelled; a small reorder counts the same as a large one.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Spell and survival tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
