# Case Study · Customer Credit Limits: Which Rule Would Have Stopped the Losses?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Credit exposure at every one of 9,391 valid orders, limits set on a training year (October 2024 – September 2025), and five credit rules back-tested on the 2,100 orders placed October 2025 – March 2026 against what was still unpaid 180 days later.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-30 |

---

## 1. Business problem

Orders are accepted without any credit check. The [expected credit loss](../../05_advanced_analytics/19_expected_credit_loss_provision/) study showed that a balance still unpaid six months after delivery is never collected, and the CFO wants credit control at order entry before the new ERP goes live. Two kinds of rule are proposed: a credit limit for each customer, and a hold on customers with old unpaid balances. Before configuring either, she wants to know which rule would have stopped the orders that were never paid, and how much good business it would have turned away.

## 2. Business questions

1. How much credit does each customer actually use?
2. How many orders are accepted from customers who already owe money on old orders?
3. What do the losses look like: whole invoices unpaid, or remainders?
4. Which rule would have blocked the losses without blocking good business?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Order value |
| `payments` | One row per receipt | Payments to each date |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Valid order | Not Cancelled or Returned |
| **Exposure** at an order | Value of the customer's earlier valid orders − payments on them up to the order date, plus the new order. Credit balances (advances, duplicate receipts) on other orders are netted. |
| Peak exposure | The largest exposure at any order in a period (exposure only rises when an order is placed) |
| **Old unpaid balance** | Amount unpaid on the customer's orders placed more than 90 days before the new order |
| **Lost** | Order value still unpaid 180 days after the order date |
| Training year / test period | Orders Oct 2024 – Sep 2025 / orders Oct 2025 – Mar 2026 |
| Rule A History limit | Block if exposure > 1.25 × the customer's training-year peak |
| Rule B Sales limit | Block if exposure > 90 days of the customer's training-year sales |
| Rule C Overdue hold | Block if the customer has an old unpaid balance |
| Rule D | A or C |
| Rule E Past-loss hold | Block customers that left more than 20 % of their order value unpaid after 180 days, on orders whose outcome was known before the test period |
| New customers | No training-year orders: the median limit of their segment |
| **Lift vs random** | (losses caught ÷ good business blocked) ÷ (all losses ÷ all good business). 1.0 = no better than blocking orders at random. |

## 5. Analytical approach

1. **Order table** (`sahyadri_b2b.cl_orders`): exposure before and after every valid order, the old unpaid balance and the 180-day outcome.
2. **Old balances**: how often orders were accepted from customers with old unpaid balances, and what the losses look like.
3. **Limits** (`sahyadri_b2b.cl_limits`) from the training year, and the **back-test** (`sahyadri_b2b.cl_backtest`) of five rules on every test order.

## 6. SQL techniques used

- Point-in-time exposure with a self-join to each customer's earlier orders (date, then id) and payments up to the order date
- A train/test split in time, with the past-loss rule using only outcomes known before the test period
- Rule back-testing with a `CROSS JOIN` of rules and orders, scored on losses caught and good business blocked
- A lift measure against random blocking, so a rule that blocks a lot is not mistaken for a rule that discriminates
- Validation that recomputes exposure a second way (running order value minus a separate payment join)

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per valid order |
| 02 | Order value = source recount |
| 03 | **Exposure before the order = running order value − earlier payments** (computed a second way) |
| 04 | Old unpaid balance = recount, and no more than the sum of positive balances |
| 05 | Unpaid after 180 days = recount; the not-fully-paid flag agrees |
| 06 | One limit per test customer; history and sales limits recomputed |
| 07 | New customers get a limit within their segment's range |
| 08 | Five rules for every test order; every block flag recomputed |
| 09 | **The past-loss rule uses only outcomes known before the test period** |
| 10 | Every rule sees the same test losses and catches no more than all of them |

## 8. Findings

**Customers carry six to nine months of sales as exposure, because old balances never clear.**

| Segment | Customers | Median peak exposure | Largest peak | Median peak in days of sales |
|---|---:|---:|---:|---:|
| Distributor | 58 | ₹5.12 lakh | ₹76.7 lakh | 187 |
| Enterprise | 59 | ₹7.31 lakh | ₹55.8 lakh | 232 |
| Mid-Market | 91 | ₹1.51 lakh | ₹19.5 lakh | 257 |
| SMB | 132 | ₹0.46 lakh | ₹4.5 lakh | 263 |

**Almost every order now comes from a customer with an old unpaid balance, and those orders are paid almost as well as the rest.**

| Order year | Orders | From a customer with a balance unpaid > 90 days | Not fully paid after 180 days: with old balance | Others |
|---|---:|---:|---:|---:|
| 2024 | 2,923 | 38.3 % | 12.6 % | 10.4 % |
| 2025 | 3,520 | 74.0 % | 10.8 % | 9.2 % |
| 2026 (orders to Sep; outcomes for Jan–Mar orders) | 2,948 | **83.3 %** | 10.3 % | 7.6 % |

**Losses are thin and spread across most customers.** Of 2,100 test orders, 220 were not fully paid after 180 days (₹149.6 lakh, 7.2 % of value). 143 of them were part-paid and 77 unpaid in full, and they belong to 115 of the 305 customers who ordered.

**No rule blocks losses without blocking far more good business.**

| Rule | Orders blocked | Good business blocked | Losses caught | Share of losses | Lift vs random |
|---|---:|---:|---:|---:|---:|
| A History limit (1.25 × peak) | 14.6 % | ₹537.3 lakh | ₹34.5 lakh | 23.1 % | **0.80** |
| B Sales limit (90 days) | 66.0 % | ₹1,446.9 lakh | ₹110.1 lakh | 73.6 % | 0.95 |
| C Overdue hold (> 90 days) | **81.5 %** | ₹1,579.1 lakh | ₹140.3 lakh | 93.8 % | 1.11 |
| D History limit or hold | 85.0 % | ₹1,683.1 lakh | ₹141.6 lakh | 94.7 % | 1.05 |
| E Past-loss hold (> 20 % unpaid) | 5.7 % | ₹90.9 lakh | ₹10.3 lakh | 6.9 % | **1.40** |

- **The overdue hold would stop four orders in five** to catch 94 % of losses: it is a sales freeze, not a credit control.
- **Limits based on history do worse than random** (lift 0.80): orders that push a customer above its past peak are paid better than the average order.
- **Past behaviour is the only weak signal.** The 18 customers who left more than 20 % unpaid in the training period lost 9.3 % on their test orders, against 7.1 % for everyone else. Blocking them catches only 6.9 % of losses.
- By segment, test losses ran at 6.4 % (Distributor), 7.5 % (Enterprise), 8.9 % (Mid-Market) and 6.4 % (SMB); new customers with no history lost 5.8 %.

## 9. Business implications and recommendations

1. **Do not switch on an overdue hold or history-based limits.** On this history they would block most orders while catching losses no better than chance.
2. **Clean the ledger before setting limits.** The [ECL provision](../../05_advanced_analytics/19_expected_credit_loss_provision/) identified ₹5.08 crore in default; until it is written off or settled, every customer looks overdue and any exposure rule fires constantly. Measure limits on collectible exposure only.
3. **Move credit control from the customer to the invoice.** Two in three lost orders were part-paid: the remainder of an instalment that never came. Chase each open remainder at 30 and 60 days (see [cash application matching](../../04_data_quality_and_reconciliation/15_cash_application_matching/) for how instalments arrive).
4. **Use the past-loss flag as a review list, not a block.** Ask the 18 flagged customers for advance payment or tighter terms, and re-test the flag each quarter.
5. **Find out why remainders go unpaid.** Losses are spread across more than a third of customers in small amounts, which points to disputes, short deliveries or price differences rather than customers who cannot pay.

## 10. Assumptions and limitations

- **Static back-test.** A blocked order stays in later exposure; in practice blocking would change customer behaviour and later balances.
- **Credit balances are netted.** Advances and duplicate receipts on other orders reduce exposure, so 183 orders show an old unpaid balance larger than the net exposure.
- **No credit terms or limits are recorded**, so the rules are illustrations calibrated on history, not the company's policy.
- **180-day outcome.** Payments after 180 days are rare but not impossible; losses could be slightly overstated.
- **Six-month test period.** A longer test would give more losses to separate good rules from bad.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, limit and back-test tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
