# Case Study · Customer State Transitions (Markov Chain Model)

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Quarters 2024 Q1 – 2026 Q3; four-quarter forecast to 2027 Q3; backtest from 2025 Q3.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script with a `WHILE` loop) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-24 |

---

## 1. Business problem

Customers move between states every quarter. Big buyers become small buyers, small buyers go quiet, quiet customers come back or are lost. Revenue forecasts based on totals cannot show these flows. The CFO wants a simple, explainable model of customer movements, to see where the existing base is heading if nothing changes, and to put a value on a win-back programme.

## 2. Business questions

1. How likely is a customer in each state to move to every other state next quarter?
2. If no new customers are won, how many customers will be in each state over the next four quarters, and what revenue will the existing base generate?
3. Is the model accurate? Fitted only on data to September 2025, how well does it predict the September 2026 state mix?
4. Where does the base settle in the long run, and what would a win-back programme be worth?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Quarterly revenue |

## 4. Method and metric definitions

| State (per customer per quarter) | Definition |
|---|---|
| 1. High | Quarter revenue ≥ ₹2 lakh |
| 2. Low | Quarter revenue above zero but under ₹2 lakh |
| 3–5. Silent 1, 2 or 3 quarters | No order this quarter; last order 1, 2 or 3 quarters ago |
| 6. Lost | No order for 4 or more quarters |

| Term | Definition |
|---|---|
| Transition probability P(i → j) | Transitions from state i to state j ÷ all transitions from i, over consecutive quarters |
| Projection | Customers in j next quarter = Σᵢ customers in i × P(i → j), repeated in a `WHILE` loop |
| Expected revenue | Customers in each state × average quarterly revenue of that state over the last four quarters (silent and lost customers earn nothing) |
| Win-back scenario | 10 more points of every silent state move back to Low each quarter, instead of staying silent |

The model covers the **existing base only**. New customers are not added.

**Why silence is split by duration.** A Markov chain assumes the next state depends only on the current one. A single "Dormant" state breaks that: a customer silent for one quarter is far more likely to return than one silent for three. During design, a 4-state version with one Dormant state was backtested the same way. It over-predicted dormant customers by 50 % and under-predicted lost customers by 34 %. Splitting silence by duration cut the total backtest error by about a fifth (see Findings).

## 5. Analytical approach

1. **State table** (`sahyadri_b2b.customer_quarter_state`). One row per customer per quarter from their first order, with revenue and state.
2. **Transition matrices** (`sahyadri_b2b.state_transitions`). Three are fitted: full history, history to the backtest date only, and the win-back scenario.
3. **Projection loop** (`sahyadri_b2b.markov_projection`). A BigQuery `WHILE` loop applies the matrix quarter by quarter for three runs: forecast, backtest and win-back.
4. **Backtest:** predicted against actual state mix in 2026 Q3.
5. **Long run** (40 quarters) and the value of the win-back scenario.

## 6. SQL techniques used

- **BigQuery scripting:** `DECLARE`, `SET` and a `WHILE … DO … END WHILE` loop with `INSERT INTO` to iterate a matrix multiplication
- Matrix multiplication in SQL: a join on `from_state` and `SUM(customers × probability)` grouped by `to_state`
- A customer × quarter grid with `GENERATE_DATE_ARRAY(… INTERVAL 3 MONTH)` so that quarters with no orders become explicit silent states
- `MAX(IF(revenue > 0, quarter, NULL)) OVER (… ROWS UNBOUNDED PRECEDING)` to count quarters since the last order
- An out-of-time backtest with a separately fitted matrix

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer and quarter |
| 02 | Rows = quarters from each customer's first order quarter to 2026 Q3, counted independently |
| 03 | Revenue = source |
| 04 | Every state matches revenue and an independent self-join check of the previous three quarters |
| 05 | Each matrix row sums to 1, with all probabilities between 0 and 1 |
| 06 | Full-history transitions = rows − customers (every row except each customer's last has a successor) |
| 07 | **Customers are conserved:** every projection step has the same total as its start |
| 08 | **No look-ahead:** the backtest matrix uses only transitions up to 2025 Q3 |
| 09 | The scenario matrix differs from the full-history matrix only in the silent rows |
| 10 | Forecast step 1 = an independent manual matrix multiplication |

## 8. Findings

**Quarterly transition matrix (full history):**

| From \ To | High | Low | Silent | Lost | Transitions |
|---|---:|---:|---:|---:|---:|
| High | **63.3 %** | 26.6 % | 10.1 % | – | 858 |
| Low | 16.0 % | **51.8 %** | 32.2 % | – | 1,424 |
| Silent 1 quarter | 9.8 % | 37.2 % | 53.0 % | – | 489 |
| Silent 2 quarters | 5.7 % | 35.2 % | 59.0 % | – | 227 |
| Silent 3 quarters | 1.7 % | 27.5 % | – | **70.8 %** | 120 |
| Lost | 1.1 % | 12.7 % | – | 86.2 % | 189 |

- **High-value customers are sticky.** 63 % stay High the next quarter, and only 10 % go silent.
- **The chance of return falls with every silent quarter**: 47 % after one quarter, 41 % after two, 29 % after three. This is why silence must be split by duration.
- **Lost is not final.** 14 % of lost customers buy again in any quarter, almost always as Low.

**Without new customers, the base slowly erodes.**

| Quarters ahead | High | Low | Silent | Lost | Expected quarterly revenue |
|---:|---:|---:|---:|---:|---:|
| 0 (2026 Q3) | 94 | 171 | 102 | 59 | ₹9.53 crore |
| 1 | 95.1 | 157.1 | 113.1 | 60.8 | ₹9.54 crore |
| 2 | 94.3 | 154.0 | 111.8 | 65.8 | ₹9.46 crore |
| 4 | 92.1 | 151.4 | 108.6 | 73.9 | ₹9.24 crore |

The existing base is projected to generate **₹37.6 crore over the next four quarters**, with lost customers rising from 59 to 74. In the long run (40 quarters), the base settles at 55 % active (20 % High, 34 % Low), 24 % silent and 21 % lost.

**Backtest: fitted on data to September 2025, predicting September 2026.**

| State | Predicted | Actual | Error |
|---|---:|---:|---:|
| High | 75.6 | 85 | −11.0 % |
| Low | 137.5 | 149 | −7.7 % |
| Silent (1–3 quarters) | 102.9 | 74 | +39.1 % |
| Lost | 51.0 | 59 | −13.5 % |

- The model gets the active base within about 10 %, but **under-predicts activity**: 2026 was a stronger year than the history it was fitted on (revenue grew 38.7 %). Customers left the silent states faster than before, both upwards (back to buying) and downwards (to Lost).
- Treat the forecast as a "no change" baseline, not a prediction of a growth year.

**A win-back programme is worth about ₹1 crore a year.** Moving 10 more points of silent customers back to buying each quarter raises four-quarter revenue from ₹37.59 crore to ₹38.60 crore (**+₹1.01 crore, +2.7 %**) and ends the year with 19 more active customers (263 against 243).

## 9. Business implications and recommendations

1. **Target win-back at customers silent for 1–2 quarters.** They return at 41–47 % on their own, and a call can tip more of them. By the third silent quarter, 71 % move to Lost.
2. **Fund the win-back programme against its value.** About ₹1 crore of revenue a year (at roughly 16 % gross margin, about ₹16 lakh of gross profit) justifies an inside-sales role dedicated to silent accounts.
3. **Protect the High state.** High customers stay High 63 % of the time. A High customer averages ₹9.0 lakh a quarter against ₹0.6 lakh for Low, so each drop from High to Low loses over 90 % of that customer's revenue, and key-account cover (see [Salesperson relationship risk](../../01_customer_and_revenue/04_salesperson_relationship_risk/)) protects the most valuable transition.
4. **Add new-customer inflow to the model** using the activation rates from [New customer onboarding](../../01_customer_and_revenue/05_new_customer_activation/), to turn the base projection into a full customer forecast.
5. **Refit the matrix every quarter** and track backtest error. A rising error is an early sign that customer behaviour is changing.

## 10. Assumptions and limitations

- **Stationarity.** The model assumes transition rates stay as they were. The backtest shows 2026 differed from 2024–2025.
- **No new customers.** The projection describes the existing base only.
- **State revenue is an average.** Revenue per state is the last-four-quarter average. Within High, customers vary widely, so revenue forecasts for small groups are less reliable than counts.
- **The ₹2 lakh threshold** separating High from Low is declared at the top of the script and can be changed.
- **Scenario effect is assumed.** The 10-point win-back uplift is an assumption for sizing, not a measured effect. A test-and-control pilot would measure it.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | State, transition and projection tables, the projection loop, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
