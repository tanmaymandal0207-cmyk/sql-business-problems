# Case Study · Do Overdue Balances Slow a Customer's Ordering?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study covers 10,223 customer-months, from April 2024 to September 2026. It sets the raw comparison (customers who owe money order more) against a comparison within each customer at the same level of recent activity, and tests the difference with 500 random relabellings.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-02 |

---

## 1. Business problem

Finance wants salespeople to chase overdue invoices before they take new orders. Sales argues that customers who owe money order *more*, not less, so pressing them puts revenue at risk. Both sides quote the same report: in months with an overdue balance, customers place more than three times as many orders. The commercial director wants to know whether an overdue balance actually changes how a customer orders, before deciding whose rule to adopt.

## 2. Business questions

1. Do customers order less in months when they have an overdue balance?
2. Is the raw comparison fair, or does it compare different customers?
3. Does a bigger overdue balance make a difference?
4. Does the answer differ by segment?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Order value |
| `shipments` | One row per shipment | Final delivery date |
| `payments` | One row per payment | Balance at the start of each month |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Customer-month | Every month from April 2024 to September 2026 after the month of the customer's first order |
| **Overdue** | At the start of the month the customer has a valid (not Cancelled or Returned), fully delivered order that was delivered more than 90 days earlier and has received less than 99 % of its value. 90 days is beyond the usual payment time of every segment. |
| Overdue amount | Unpaid balance on those orders |
| Outcome | Orders placed in the month (all statuses) and valid revenue |
| Raw comparison | Average orders in overdue months against other months, all customers pooled |
| Within-customer | Each month compared with the same customer's average; customers with both kinds of month |
| **Same customer, same activity** | Each month compared only with that customer's months that had similar ordering in the previous six months (none, 1–2, 3–5, 6+ orders). An overdue balance needs earlier orders, so busy spells and overdue months go together; this comparison removes that link. |
| Permutation test | 500 random relabellings of the overdue flag among each customer's months in the same activity band |

## 5. Analytical approach

1. **Customer-months** (`sahyadri_b2b.ob_months`): overdue status and amount at the start of each month, orders and revenue in the month, and orders in the previous six months.
2. **Raw comparison**, and which customers carry overdue balances.
3. **Within-customer comparisons** (`sahyadri_b2b.ob_within`) and the **permutation test** (`sahyadri_b2b.ob_permutations`).
4. **Dose and segments**: overdue amount bands, segments, and a check that leaves out months after a customer's last order.

## 6. SQL techniques used

- A month-by-customer grid with balances rebuilt as at the start of each month from payments dated before it
- Fixed-effects style comparisons: deviations from each customer's own average with `AVG() OVER (PARTITION BY customer, band)`
- Prior activity as a running window: `SUM() OVER (ORDER BY month ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING)`
- A within-cell permutation test: an integer hash shuffles the month order inside each customer × band cell, and the flag is re-joined by position

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer per month after the first order |
| 02 | Orders per month add up to the orders placed in scope |
| 03 | Revenue = valid order value in scope |
| 04 | **Overdue customers in January 2026 = an independent recount** |
| 05 | Overdue flag, overdue orders and overdue amount agree |
| 06 | Orders in the previous six months = recount |
| 07 | Every comparison cell has both kinds of month; deviations sum to zero |
| 08 | 500 random relabellings, centred on zero |
| 09 | Active month = on or before the customer's last order |
| 10 | Within-cell rows are a subset of all customer-months |

## 8. Findings

**The raw report is right about the numbers but wrong about the cause.**

| Months | Customer-months | Customers | Orders a month | Revenue a month | Months with an order |
|---|---:|---:|---:|---:|---:|
| Overdue balance | 4,231 | 240 | **1.49** | ₹1.45 lakh | 58.7 % |
| No overdue balance | 5,992 | 427 | 0.43 | ₹0.34 lakh | 27.9 % |

| Customers | Number | Orders a month |
|---|---:|---:|
| Never overdue | 187 | 0.21 |
| Overdue in under half their months | 70 | 0.54 |
| Overdue in half their months or more | 170 | **1.50** |

Customers who order often almost always have an invoice more than 90 days old somewhere. The raw comparison sets frequent buyers against occasional ones; it does not compare the same customer with and without a debt.

**For the same customer at the same level of activity, an overdue balance makes no difference.**

| Comparison | Customers | Customer-months | Overdue months vs other months |
|---|---:|---:|---:|
| Raw (different customers) | 427 | 10,223 | **+1.06 orders** |
| Same customer | 240 | 6,538 | +0.044 orders |
| **Same customer, same recent activity** | 209 | 3,776 | **+0.011 orders (+1.0 %)** |
| … excluding months after the last order | 194 | 3,351 | +0.055 orders |

- The difference of +0.011 orders a month sits well inside the range chance produces (95 % of 500 relabellings fall between −0.055 and +0.054; p = 0.71). In revenue it is −₹800 a month.
- Customer by customer, 80 ordered less in their overdue months, 115 ordered more and 14 the same.

**The size of the balance and the segment do not change the answer.**

| Overdue balance | Customer-months | Orders vs the customer's own average |
|---|---:|---:|
| None | 1,537 | −0.006 |
| Under one month of revenue | 1,122 | +0.001 |
| One to three months | 651 | +0.015 |
| Over three months | 466 | −0.003 |

| Segment | Customers | Months overdue | Overdue vs other months |
|---|---:|---:|---:|
| Distributor | 38 | 63.2 % | −0.068 |
| Enterprise | 47 | 61.4 % | +0.021 |
| Mid-Market | 55 | 57.1 % | +0.036 |
| SMB | 69 | 57.4 % | +0.027 |

The segment differences are small (under 0.07 orders a month) and point both ways; none was tested separately.

## 9. Business implications and recommendations

1. **Retire the "overdue customers order more" argument.** They order more because they are bigger, not because they owe money. Using it to resist collections is not supported.
2. **Collections can be firm without costing orders.** On this evidence, customers do not slow down while they owe money, so chasing an overdue invoice does not need to wait for the next order.
3. **Do not use ordering as a sign of financial health.** A customer still ordering is not a customer about to pay. The [customer credit limits](../17_customer_credit_limits/) study found that holds on overdue customers block most good business; collection follow-up, rather than order blocking, is the lever.
4. **If a hold is introduced, measure it as an experiment.** Today's data shows no voluntary slowdown, so any fall in orders after a hold would be the hold's own cost. Pilot it on a random group of accounts (see [pilot design](../../05_advanced_analytics/23_pilot_design_power_cuped/)).

## 10. Assumptions and limitations

- **Observational.** No customer was put on hold; the study shows how customers behave with an overdue balance, not how they would react to a stop on supply.
- **One definition of overdue.** More than 90 days after delivery and under 99 % paid. Shorter definitions would mark almost every Enterprise month as overdue.
- **Activity bands are coarse.** Four bands of orders in the previous six months; finer control would use fewer months per cell.
- **Customer-months start after the first order** and run to September 2026, including months after a customer's last order (checked separately).

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer-month, within-cell and permutation tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
