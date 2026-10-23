# Case Study · Period-end Sales Push

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Period: January 2024 – September 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-23 |

---

## 1. Business problem

Sales targets are monthly, quarterly and annual (financial year to 31 March). A common side effect is the **hockey stick**: orders bunch in the last days of a period, are closed with extra discount, and some are cancelled afterwards. The CFO is redesigning sales incentives and wants evidence, not anecdotes, on whether that happens here and what it costs.

## 2. Business questions

1. Do orders bunch at the end of the month, quarter or financial year?
2. Are period-end orders discounted more deeply, and is the difference larger than chance?
3. Are period-end orders cancelled, returned or delivered late more often?
4. What does any extra period-end discount cost?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, status, promised date |
| `sales_order_items` | One row per product per order | Gross value and discount |
| `shipments` | One row per shipment | Final delivery date |
| `customers` | One row per customer | Names for the year-end order list |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Month position | Last 5 days (final 5 calendar days of the month), First 5 days, or Mid-month |
| Quarter-end months | March, June, September and December. March is also the financial year-end. |
| Orders per day | Orders ÷ calendar days in the bucket over the period, so buckets of different length compare fairly |
| Weighted discount | Discount amount ÷ gross value (`quantity * unit_price`), orders not Cancelled or Returned |
| Discount z-test | (mean₁ − mean₂) ÷ `SQRT(var₁/n₁ + var₂/n₂)` on line-level `discount_percent` |
| Cancellation z-test | Two-proportion test with a pooled rate, on closed orders |
| Extra discount cost | (last-5-day weighted rate − rest-of-month weighted rate) × last-5-day gross value |

## 5. Analytical approach

1. **Order table** (`sahyadri_b2b.order_period_position`). One row per order with its month position, quarter-end and year-end flags, gross value, discount, closed flag and late flag.
2. **Bunching test:** orders and value per calendar day by month position.
3. **Outcomes by position**, separately for ordinary months, quarter-ends and the year-end.
4. **Significance tests** for discount and cancellation, and the largest year-end orders.
5. **Cost** of the extra period-end discount by year.

## 6. SQL techniques used

- `LAST_DAY` and `DATE_DIFF` to place each order within its month
- A daily calendar from `GENERATE_DATE_ARRAY` to normalise counts by calendar days
- Two-sample and two-proportion z-tests in SQL with `AVG`, `VAR_SAMP` and `SQRT`
- `UNION ALL` to run the same test over several scopes (all months, quarter-ends, other months)

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order |
| 02 | Orders = source orders in the period (10,000) |
| 03 | Gross value = source |
| 04 | Discount amount = source |
| 05 | Month position matches an independent day-of-month rule |
| 06 | The calendar has exactly 5 last-5-day days in each of the 33 months |
| 07 | Quarter-end and year-end flags match the month, and every year-end month is a quarter-end |
| 08 | Closed flag matches status |
| 09 | No late flag on orders that are not Delivered |
| 10 | Order line count = source |

## 8. Findings

**There is no general month-end rush.** Orders per day in the last 5 days are only 3 % above mid-month. Orders are bigger at month-end, so value per day is 17 % higher.

| Month position | Calendar days | Orders | Orders per day | Gross value per day | Average order |
|---|---:|---:|---:|---:|---:|
| First 5 days | 165 | 1,633 | 9.90 | ₹9.59 lakh | ₹96,937 |
| Mid-month | 674 | 6,688 | 9.92 | ₹10.37 lakh | ₹1,04,466 |
| Last 5 days | 165 | 1,679 | 10.18 | ₹12.12 lakh | ₹1,19,079 |

**Routine discounting does not change at period-end.** The average line discount is 7.25 % in the last 5 days against 7.20 % in the rest of the month (z = 0.7). The pattern is the same in quarter-end and other months.

**The year-end is different: a few very large deals closed at 15 %.** In the last 5 days of March, the weighted discount was **12.3 %**, against 8.4 % in mid-March.

| Order | Customer | Date | Gross value | Discount | Delivered |
|---|---|---|---:|---:|---|
| 107989 | Banerjee Sales Corporation | 30 Mar 2026 | ₹1.40 crore | 15.0 % (₹21.1 lakh) | 3 Apr 2026 |
| 100772 | Krishna Castings | 27 Mar 2024 | ₹96.3 lakh | 15.0 % (₹14.4 lakh) | 9 Apr 2024 |
| 107992 | Laxmi Petrochem | 30 Mar 2026 | ₹20.3 lakh | 14.8 % (₹3.0 lakh) | 2 Apr 2026 |

- **All three were delivered in the next financial year.** They count towards the year's order-intake target but, on a delivery basis, belong to the following year (see [Revenue cut-off reconciliation](../../04_data_quality_and_reconciliation/04_revenue_cutoff_reconciliation/)).
- Two of the three customers also appear as out-of-band discounts in [Discount consistency](../06_discount_consistency/) (Banerjee Sales Corporation, Laxmi Petrochem).

**Quarter-end orders are cancelled more often.**

| Scope | Cancel rate, last 5 days | Cancel rate, rest of month | z-score |
|---|---:|---:|---:|
| Quarter-end months | **7.09 %** | 4.54 % | **2.46** |
| Other months | 5.97 % | 5.62 % | 0.46 |
| All months | 6.32 % | 5.21 % | 1.80 |

About 13 more orders were cancelled than the rest-of-month rate would predict. These are likely orders booked to make a quarter's number and withdrawn later. The [Cancellation and return leakage](../../03_operations_and_supply_chain/06_cancellation_return_leakage/) screen did not find this because it tested calendar months, not the position within the month.

- Late delivery and returns show no consistent period-end pattern (Step 3).

**Extra period-end discount cost:** ₹1.43 lakh in 2024, ₹0.88 lakh in 2025 and **₹12.8 lakh in 2026** (January–September), driven by the March 2026 year-end deals.

## 9. Business implications and recommendations

1. **Require director approval for year-end deals above ₹10 lakh at 12 % discount or more.** The routine process is disciplined. The risk sits in a handful of large year-end orders.
2. **Measure annual targets on delivered sales, not order intake.** All three large year-end deals were delivered in April. Paying incentives on delivery removes the reason to book them in March.
3. **Track quarter-end cancellations by salesperson** and claw back incentive credit for orders cancelled within 30 days of booking.
4. **Keep monthly targets as they are.** There is no month-end order rush and no month-end discount creep in ordinary months.

## 10. Assumptions and limitations

- **No booking timestamp.** Order date is used as the booking date. Orders entered late in the day on the last day of a period are treated like any other.
- **Few year-end observations.** Only three financial year-ends are in the data, so the year-end finding rests on a small number of large orders. It is a governance point, not a statistical trend.
- **No cancellation date.** The data cannot show how soon after booking the quarter-end orders were cancelled.
- **The 5-day window** is declared at the top of the script and can be changed.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order position table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
