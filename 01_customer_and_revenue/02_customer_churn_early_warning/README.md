# Case Study · Customer Churn Early Warning

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. As-of date: 30 Sep 2026.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-16 |

---

## 1. Business problem

In B2B distribution, customers rarely announce that they are leaving. They simply stop ordering. By the time the annual review shows the drop, the account has often moved to a competitor. The sales head wants a monthly early-warning view that tells account managers whom to call **before** an account is lost.

## 2. Business questions

1. How many customers are active, at risk, lapsed or lost?
2. How much annual revenue sits with customers who have gone quiet?
3. Which customers still count as active are overdue against **their own** usual ordering cycle?
4. Which lapsed or lost accounts are worth a win-back effort?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order dates, status, customer |
| `sales_order_items` | One row per product per order | Order revenue |
| `customers` | One row per customer | Name and segment |

Line items are aggregated to order level before any customer-level calculation.

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)` on orders that are not Cancelled or Returned |
| Days since last order | As-of date − last order date |
| Activity status | **Active** ≤ 90 days · **At risk** 91–180 · **Lapsed** 181–365 · **Lost** > 365 |
| Annual run-rate | Revenue in the 365 days up to and including the customer's last order: what the account was worth per year when it was last active |
| Usual ordering cycle | Median gap in days between consecutive orders (customers with 3 or more orders) |
| Overdue vs cycle | Days since last order is more than **2 ×** the usual cycle and more than 30 days |

The fixed status bands follow common B2B recency practice. The cycle-based flag adds a customer-specific signal: a customer who normally orders every week is a concern after a month of silence, even though a 90-day rule still calls them active.

## 5. Analytical approach

1. **Customer activity table.** One row per customer with order count, first and last order, lifetime revenue, annual run-rate, usual cycle, status and the overdue flag. It is saved as `sahyadri_b2b.customer_activity_status`.
2. **Status summary.** Customers and run-rate in each status.
3. **Segment view.** The share of each segment's run-rate held by quiet customers.
4. **Early-warning call list.** The 15 largest accounts that are still Active or At risk but overdue against their own cycle.
5. **Win-back list.** The 10 largest Lapsed or Lost accounts.

## 6. SQL techniques used

- CTEs that move from order level to customer level
- `LAG()` to find the previous order date, and `PERCENTILE_CONT` for each customer's median gap
- `DATE_DIFF` with a declared as-of date, so the analysis can be re-run for any month-end
- `CASE` banding and a boolean flag column
- Window shares with `SUM(SUM(...)) OVER ()`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer |
| 02 | Every customer with an in-scope order is in the table (426) |
| 03 | Total orders = in-scope orders in the source |
| 04 | Lifetime revenue = in-scope line-item total, within rounding |
| 05 | No run-rate exceeds lifetime revenue |
| 06 | Last order date matches the source on every row |
| 07 | Status agrees with the day bands on every row |
| 08 | Days since last order recomputed independently |
| 09 | No overdue flag on customers with fewer than 3 orders |
| 10 | No order dated after the as-of date |

## 8. Findings

**38 % of customers have gone quiet, but they hold only 6.6 % of revenue.**

| Status | Customers | Share | Annual run-rate | Share |
|---|---:|---:|---:|---:|
| Active | 264 | 62.0 % | ₹39.80 crore | 93.4 % |
| At risk | 56 | 13.1 % | ₹1.34 crore | 3.1 % |
| Lapsed | 47 | 11.0 % | ₹1.03 crore | 2.4 % |
| Lost | 59 | 13.8 % | ₹0.47 crore | 1.1 % |
| **Total** | **426** | | **₹42.64 crore** | |

Customers who have gone quiet placed an average of 1.6 to 6.8 orders. Active customers placed an average of 32.9. Churn is concentrated among small, occasional buyers.

**SMB customers are the most exposed segment.**

| Segment | Customers | Quiet customers | Share of run-rate gone quiet |
|---|---:|---:|---:|
| SMB | 170 | 86 | 19.3 % |
| Mid-Market | 117 | 40 | 12.1 % |
| Distributor | 71 | 24 | 8.1 % |
| Enterprise | 68 | 12 | 1.2 % |

**The bigger risk sits inside the "Active" group.** 39 customers who are still Active or At risk have gone silent for more than twice their usual ordering cycle. Together they are worth **₹4.59 crore a year**, which is 10.8 % of total run-rate and more than all quiet customers combined (₹2.84 crore). For example, customer 1375 normally orders every 7.5 days and is worth ₹51.9 lakh a year, but had not ordered for 34 days at the as-of date. A 90-day rule would not flag this account for another two months.

**The win-back list is led by mid-sized distributors.** The largest lapsed account (customer 1008) was worth ₹18.3 lakh a year and last ordered on 1 Jan 2026. Eight of the top ten win-back accounts are distributors.

## 9. Business implications and recommendations

1. **Use the cycle-based flag as the primary early warning.** The 39 overdue accounts (₹4.59 crore run-rate) should be called this month. A 90-day rule alone would miss most of them.
2. **Assign the top 15 overdue accounts to named account managers**, with a follow-up date recorded in the CRM.
3. **Run a structured win-back for the 10 largest lapsed and lost accounts.** Start by asking why they left (price, service, delivery), because the answer determines whether the account can be recovered.
4. **Treat SMB churn as a coverage problem rather than an account-management one.** With 86 quiet SMB customers and a small value per account, a low-cost channel such as inside sales, reorder reminders or a distributor partner is more economical than field visits.
5. **Re-run the analysis every month-end** by changing the as-of date, and track how many flagged accounts reorder within 30 days to measure whether the calls work.

## 10. Assumptions and limitations

- **Customer behaviour.** A customer that stops ordering may have reduced demand rather than switched supplier. The data cannot distinguish the two.
- **Run-rate** describes the account's value when last active, not a forecast.
- **Fixed thresholds.** The status bands (90/180/365 days) and the 2× cycle rule are business conventions. Different thresholds would move customers between groups.
- **Short histories.** Customers with fewer than 3 orders have no usual cycle and are judged on the status bands only.
- **Cancelled and returned orders** are excluded, so a customer whose only recent order was cancelled is shown as inactive.
- **Period.** Order history starts in January 2024, so "Lost" customers may have been declining before the data begins.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer activity table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
