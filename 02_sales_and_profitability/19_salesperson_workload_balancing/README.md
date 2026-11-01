# Case Study · Salesperson Workload Balancing with the Fewest Account Moves

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Account ownership and workload for the 15 field salespeople between October 2025 and September 2026. The study tests whether busy months hurt order outcomes, then builds a rebalancing plan that moves the fewest accounts, each one to a salesperson the customer already knows. It also lists the moves that would close the remaining gaps.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-01 |

---

## 1. Business problem

The Head of Sales hears two complaints. Some salespeople say they are drowning in orders, while others have time to spare. He wants to rebalance account ownership before the new financial year. He does not want to reshuffle the whole book or hand customers to strangers.

## 2. Business questions

1. How uneven is the workload, and does a heavy month hurt order outcomes?
2. Which accounts should move, and to whom, so that every salesperson ends up within 15 % of the average?
3. How few moves does that take, and can every receiver be someone the customer already knows?
4. What is still left to fix after the plan?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, salesperson, date, status |
| `sales_order_items` | One row per product per order | Account revenue |
| `employees` | One row per employee | Sales team, designation |
| `customers` | One row per customer | Segment, state |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Window | Orders placed 1 Oct 2025 – 30 Sep 2026 by the 15 field salespeople. The Head of Sales (53 orders) and unassigned orders (148) are left out. |
| **Account owner** | The salesperson with the most orders on the account in the window. Ties go to the latest order, then the lowest ID. |
| **Workload** | All orders on the accounts a salesperson owns, with one owner per account |
| Band | Average workload ± 15 % (228–309 orders) |
| **Known contact** | A salesperson who has booked at least one order for the customer since 1 Oct 2024 |
| Load and outcomes | For each salesperson and month: orders against the cancelled-or-returned rate, both measured against that person's own average |
| **Rebalancing (greedy)** | **Candidates** are accounts of salespeople above the band that meet three conditions: the account is no bigger than the band width (80 orders); it goes to a known contact below the average; and the receiver stays within the band. The receiver is the known contact with the lightest load. **Senders** shed their largest candidates first until their excess is covered. **Receivers** accept moves, largest first, while they stay within the band. |

## 5. Analytical approach

1. **Accounts** (`sahyadri_b2b.wb_accounts`): owner, orders and revenue for each of the 371 accounts.
2. **Salespeople** (`sahyadri_b2b.wb_reps`): workload, band and status, plus the load-and-outcomes test.
3. **Candidates** (`sahyadri_b2b.wb_candidates`): eligible moves to known contacts.
4. **Moves** (`sahyadri_b2b.wb_moves`): the greedy selection.
5. **After** (`sahyadri_b2b.wb_after`): the rebalanced book, and the closing moves still available for anyone outside the band.

## 6. SQL techniques used

- Ownership by `ROW_NUMBER()` with explicit tie-breaks, and account totals as window sums rather than correlated subqueries
- A within-person (fixed-effects) comparison, which centres each salesperson's months on their own average before correlating
- A set-based greedy allocation: running sums with `ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING` on the sender side, and a second running sum on the receiver side that enforces capacity
- A residual search for the smallest move that closes each remaining gap without pushing the other salesperson out of the band

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One owner per account; accounts = customers with field orders in the window |
| 02 | Account orders add up to all field orders in the window |
| 03 | **No salesperson has more orders on an account than its owner** |
| 04 | Workloads add up to all account orders; band = average ± 15 % |
| 05 | Status labels follow the band |
| 06 | **Every candidate: sender over the band, receiver below average and a known contact, account fits** |
| 07 | Each account moves at most once, and only as a candidate |
| 08 | **No receiver ends above the band, no sender below it** |
| 09 | Orders and accounts are conserved; nobody both gives and receives |
| 10 | 15 salespeople; Head of Sales and unassigned orders left out |

## 8. Findings

**Workloads differ almost six-fold.**

| Salesperson | Role | Accounts | Workload (orders) | Index | Status |
|---|---|---:|---:|---:|---|
| Rohan Shah | Regional Sales Manager | 25 | 451 | 1.68 | Over |
| Deepak Chatterjee | Key Account Manager | 39 | 429 | 1.60 | Over |
| Prakash Sharma | Regional Sales Manager | 25 | 374 | 1.39 | Over |
| Manoj Verma | Regional Sales Manager | 11 | 356 | 1.33 | Over |
| Deepika Jadhav | Key Account Manager | 30 | 351 | 1.31 | Over |
| Ritu Mishra | Senior Sales Executive | 35 | 325 | 1.21 | Over |
| *4 others* | | | 230–279 | 0.86–1.04 | In band |
| Vikram Gupta | Sales Executive | 23 | 225 | 0.84 | Under |
| Tushar Gill | Sales Executive | 24 | 191 | 0.71 | Under |
| Harish Tiwari | Sales Executive | 19 | 131 | 0.49 | Under |
| Deepak Patil | Sales Executive | 16 | 111 | 0.41 | Under |
| Ramesh Patil | Senior Sales Executive | 13 | **77** | **0.29** | Under |

- The average is 268 orders; the coefficient of variation is 0.41. Only 4 of 15 salespeople are within the band, and the six above it carry 435 orders over its upper edge.
- **Accounts are well defined.** Owners book 88 % of their accounts' orders, and 188 of 371 accounts deal with one salesperson only.

**Busy months do not hurt order outcomes.**

| Months, by orders against the person's own average | Salesperson-months | Average vs own | Cancelled or returned |
|---|---:|---:|---:|
| Quietest quarter | 85 | −7.9 | 6.6 % |
| Second | 85 | −2.3 | 6.8 % |
| Third | 84 | +1.8 | 5.6 % |
| Busiest quarter | 84 | +8.6 | **5.5 %** |

The within-person correlation is −0.07. The case for rebalancing is capacity and fairness, not service quality: the heaviest salespeople have no room to grow their books, and the lightest are under-used.

**Fourteen moves bring 11 of 15 salespeople into the band.**

| | Before | After 14 moves |
|---|---:|---:|
| Coefficient of variation | 0.41 | **0.15** |
| Lightest / heaviest | 77 / 451 | 179 / 318 |
| Salespeople within ±15 % | 4 | **11** |
| Orders moved | | 516 (13 % of 4,024) |
| Revenue of accounts moved | | ₹4.87 crore (13 % of ₹38.74 crore) |

| From | To | Accounts | Orders |
|---|---|---:|---:|
| Deepak Chatterjee (KAM) | Harish Tiwari | 5 | 130 |
| Rohan Shah (RSM) | Deepak Patil | 4 | 133 |
| Prakash Sharma (RSM) | Ramesh Patil | 2 | 102 |
| Deepika Jadhav (KAM) | Vikram Gupta | 1 | 76 |
| Manoj Verma (RSM) | Anjali Jadhav | 1 | 42 |
| Ritu Mishra (SSE) | Harish Tiwari | 1 | 33 |

- **Every receiver already knows the customer.** However, the relationship is often thin: on average the receiver booked 6.8 % of the customer's orders in the last two years, and for National Dairy and Om Agro Foods just one order.
- The largest single move is Jai Consumer Care India (76 orders, ₹84.9 lakh) from Deepika Jadhav to Vikram Gupta.

**What is left.**

| Salesperson | After the plan | Outside the band by | Closing move available |
|---|---:|---:|---|
| Rohan Shah | 318 | 9.5 orders over | Yes: 3 accounts, the smallest 12 orders (to Deepak Patil) |
| Manoj Verma | 314 | 5.5 orders over | Yes: 2 accounts, the smallest 6 orders (to Anjali Jadhav) |
| Tushar Gill | 191 | 37 orders under | Yes: 1 account of 40 orders (from Prakash Sharma) |
| Ramesh Patil | 179 | 49 orders under | **None**: no known contact on a movable account |

These three closing moves do not conflict with each other; together they would put 14 of 15 salespeople within the band. Ramesh Patil cannot reach the band through relationships alone. Manoj Verma's book also shows why one salesperson can be over the band with only 11 accounts: a single customer brings 149 orders, 42 % of his load, and is too big to move.

## 9. Business implications and recommendations

1. **Approve the 14 moves plus the three closing moves.** Together they move 17 accounts and bring 14 of 15 salespeople within ±15 % of the average.
2. **Hand over in person.** Most receivers know the customer only lightly. Plan a joint visit and one shared quarter for each moved account, starting with the largest, such as Jai Consumer Care India (₹84.9 lakh) and Saraswati Mehta Flexipack (₹54.2 lakh).
3. **Give Ramesh Patil new accounts, not transferred ones.** He has no known contacts to take over. Assign him new or reactivated customers (see [reactivated customers](../../01_customer_and_revenue/09_reactivated_customers/)) and inbound unassigned orders, which numbered 148 last year.
4. **Use the freed capacity for growth.** Busy months did not raise cancellations, so the senior salespeople can use the time they gain on large accounts and new business rather than on service fixes.
5. **Re-run before each financial year.** Ownership drifts as accounts grow; the same script gives the next plan.
6. **Watch key-person risk.** Large single-owner accounts such as Manoj Verma's 149-order customer should have a named backup (see [salesperson relationship risk](../../01_customer_and_revenue/04_salesperson_relationship_risk/)).

## 10. Assumptions and limitations

- **Workload = orders.** Large, complex orders and travel time are not weighted. Revenue per salesperson differs much more than order counts (from ₹24.9 lakh to ₹5.15 crore).
- **One band for every role.** Key Account Managers and Sales Executives are held to the same order count. A role-specific target would give different moves.
- **Past orders stand in for future load.** Accounts that grow or shrink next year will shift the balance.
- **Greedy, not optimal.** A single pass does not guarantee the fewest possible moves; the residual search shows the gaps it leaves.
- **Region is not a constraint.** Moves are limited to known contacts, but the plan does not check territory or travel.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Account, salesperson, candidate, move and after tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
