# Case Study · Does a Salesperson Handover Cost Revenue? A Difference-in-Differences Test

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 95 customers whose main salesperson changed in 2025 are compared with 173 customers who kept theirs. The comparison is made within cells of event quarter × segment × size, with a pre-trend test, a permutation test (500 shuffles) and a split by who received the account.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-02 |

---

## 1. Business problem

The [salesperson relationship risk](../../01_customer_and_revenue/04_salesperson_relationship_risk/) study found that customers whose main salesperson changed lost 7.1 % of revenue while other customers grew. It warned that this was an association: accounts may change hands *because* they were already in trouble. The [workload balancing](../../02_sales_and_profitability/19_salesperson_workload_balancing/) study now proposes 17 account moves. Before approving them, the Head of Sales wants a fairer estimate of what a handover costs.

## 2. Business questions

1. Comparing like with like, does a handover cost revenue in the year after it?
2. Were the accounts that changed hands already declining before?
3. Is the raw gap driven by a few large accounts?
4. Do handovers to newly hired salespeople fare differently from moves between existing salespeople?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, salesperson, date, status |
| `sales_order_items` | One row per product per order | Revenue |
| `employees` | One row per employee | Sales team, hire date |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Quarters | 2024 Q1 – 2026 Q3 |
| Main salesperson | The field salesperson (Head of Sales excluded) with the most orders in a window; ties go to the lower ID |
| Event quarter | 2025 Q1, Q2, Q3 or Q4. "Before" = the 4 quarters before it; "after" = the event quarter and the 3 after |
| **Treated** | The main salesperson after differs from the one before (the first such event for the customer) |
| **Control** | Same main salesperson before and after, and never treated; used once per event quarter |
| Growth | ln((revenue after + ₹10,000) ÷ (revenue before + ₹10,000)), valid orders; customers with revenue before |
| **Cell** | Event quarter × segment × third of revenue before |
| **Handover effect** | Average over treated customers of (their growth − the control average in their cell), shown as a % change |
| Pre-trend | The same comparison on growth from the first half of the "before" year to the second half |
| Permutation test | 500 shuffles of the treated label within each cell |
| New-hire receiver | The new main salesperson joined less than a year before the event quarter |

## 5. Analytical approach

1. **Windows** (`sahyadri_b2b.ho_windows`): revenue before and after, main salesperson on each side, for each customer and event quarter.
2. **Panel** (`sahyadri_b2b.ho_panel`): treated and control customers, cells, growth and pre-trend growth.
3. **Effects** (`sahyadri_b2b.ho_effects`) and **permutations** (`sahyadri_b2b.ho_permutations`).
4. **Large accounts and event quarters.**

## 6. SQL techniques used

- A stacked difference-in-differences design: one row per customer and event quarter, built with a cross join to the event list
- Exact matching on cells with `NTILE()` size thirds, and treated-weighted cell differences
- A placebo (pre-trend) test using the same estimator on the year before
- A within-cell permutation test: an integer hash ranks customers inside each cell, and the first k are labelled treated

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One window row per customer and event quarter, all with revenue before |
| 02 | **2025 Q2 windows: revenue before and after = a recount from orders** |
| 03 | 2025 Q2 windows: nobody has more orders than the main salesperson before |
| 04 | Treated once at their first change; controls never change and appear once per event quarter |
| 05 | Every cell has treated and control customers |
| 06 | Growth and pre-trend growth = the log formulas |
| 07 | Size thirds are ordered by revenue before within each event quarter |
| 08 | 500 relabellings, centred near zero |
| 09 | **Effect = average of treated growth minus its cell's control mean** |
| 10 | New-hire flag = receiver hired less than a year before the event quarter |

## 8. Findings

**The raw comparison looks bad for handovers.**

| | Customers | Revenue before | Revenue after | Change | Typical customer |
|---|---:|---:|---:|---:|---:|
| Salesperson changed | 95 | ₹7.33 crore | ₹6.83 crore | **−6.9 %** | −7.0 % |
| Same salesperson | 173 (452 customer-windows) | ₹24.31 crore | ₹28.11 crore | +15.6 % | +10.7 % |

**Matched like with like, the effect is not distinguishable from chance.**

| Test | Result |
|---|---|
| Handover effect (matched within cells) | **−12.3 %** |
| Range from 500 shuffles (95 %) | −21.1 % to +24.5 % |
| p-value | **0.28** |
| Pre-trend: same test on the year before | **+18.5 %** |

- The best estimate is a 12 % loss, but shuffling the labels produces gaps that large 28 % of the time. The data cannot rule out zero.
- **The changed accounts were growing faster than their peers just before the change** (+18.5 %), not declining. Some of the later shortfall is likely a growth spurt fading rather than damage from the handover. A handover effect, if any, is probably smaller than −12 %.

**A few large Distributor accounts drive the raw gap.**

| View | Changed accounts | Same salesperson |
|---|---:|---:|
| All customers | −6.9 % | +15.6 % |
| Without the 5 largest changed accounts | **+1.1 %** | +15.6 % |

The five largest changed accounts are all Distributors. One, customer 1042 (₹191 lakh before), grew under its new salesperson. Customer 1154 fell from ₹39.7 lakh to ₹11.5 lakh, and 1170 from ₹19.2 lakh to ₹7.5 lakh.

**Handovers to new hires held up; moves between existing salespeople did not.**

| Receiver | Accounts | Effect against matched controls |
|---|---:|---:|
| Salesperson hired in the past year | 74 | −2.6 % |
| Existing salesperson | 21 | **−39.5 %** |

Most handovers in 2025 went to the four salespeople hired between November 2024 and June 2025, and those accounts did about as well as accounts that kept their salesperson. The 21 moves between existing salespeople fared much worse. These are few, and they are the moves most likely to have been made because something was already wrong with the account.

## 9. Business implications and recommendations

1. **Approve the workload moves, with handover discipline.** There is no clear evidence that a planned handover costs revenue. Planned moves to new capacity (the closest match to the proposed rebalancing) show −2.6 %.
2. **Treat moves between existing salespeople with care.** The −39.5 % on 21 accounts is not proven, but it is large. Before moving an account between existing salespeople, record why, and give it a joint quarter with both.
3. **Watch the large accounts personally.** The raw loss comes from a handful of Distributor accounts. For any account above ₹20 lakh a year, the Head of Sales should introduce the new salesperson.
4. **Track moved accounts against matched controls,** not against the company average. The company average flatters accounts that kept their salesperson, because they are a different mix.
5. **Record the reason for every reassignment** (new capacity, departure, performance, customer request), so next year's test can separate planned moves from rescue moves.

## 10. Assumptions and limitations

- **Observational, not randomised.** Matching on quarter, segment and size removes the main differences, not all of them. Why an account moved is not recorded.
- **95 treated customers.** Most moved to new hires in early 2025; only 5 changes happened in 2025 Q4.
- **One year after.** Longer effects (two years after a handover) cannot be measured yet.
- **The main salesperson is defined by order count.** An account shared between two salespeople can flip "main" without a real handover.
- **Subgroup estimates are not separately tested.** The new-hire and existing-salesperson effects come from the same matched cells, without their own permutation test.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Window, panel, permutation and effect tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
