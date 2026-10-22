# Case Study · New Customer Onboarding and Activation

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Customers registered 1 Jan 2024 – 30 Sep 2026; as of 30 Sep 2026.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-22 |

---

## 1. Business problem

Sales reports count new customer registrations, but a registration earns nothing until the customer orders, and then orders again. The commercial head wants to know whether accounts opened since January 2024 are turning into real buyers, how quickly, and where onboarding stalls, so that follow-up effort goes to accounts that can still be activated.

## 2. Business questions

1. How many registered customers place a first order, and how quickly?
2. How many come back for a second order?
3. How valuable are new customers in their first year, compared with established customers in the same segment?
4. Which new accounts have stalled and need follow-up?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `customers` | One row per customer | Registration date and segment |
| `sales_orders` | One row per order | Order dates and status |
| `sales_order_items` | One row per product per order | Revenue |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| New customer | `registration_date` from 1 Jan 2024 to 30 Sep 2026 (82 customers). The 6 customers with no registration date are excluded. |
| Valid order | Order not Cancelled or Returned |
| Activation stage | Not yet ordered · Only cancelled or returned orders · One order only · Repeat buyer |
| First order within 90 days | Among customers registered at least 90 days before the as-of date |
| Repeat within 90 days | Second valid order within 90 days of the first, among first orders at least 90 days old |
| First-year revenue | Revenue in the 365 days from the first order, for customers whose first order is at least a year old |
| Established benchmark | Median last-12-month revenue of customers registered before 2024 in the same segment, among those who bought |

**Why the fair-window rule?** A customer who registered last month has not had 90 days to order. Counting them would make recent onboarding look worse than it is.

## 5. Analytical approach

1. **Activation table** (`sahyadri_b2b.new_customer_activation`). One row per new customer with first, second and last order dates, days between milestones, revenue, first-year revenue and activation stage.
2. **Funnel by registration year** with fair-window rates.
3. **Current stage and speed by segment** (median days to first and second order).
4. **First-year value** against established customers in the same segment.
5. **Follow-up list** of stalled accounts.

## 6. SQL techniques used

- `ROW_NUMBER()` to number each customer's valid orders, then conditional `MIN(IF(order_seq = n, …))` to pick milestones
- Fair-window rates using `SAFE_DIVIDE` with matching eligibility conditions in numerator and denominator
- `GROUP BY ROLLUP` for a total row
- `PERCENTILE_CONT … OVER (PARTITION BY segment)` for medians, as averages are distorted by a few large accounts

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer |
| 02 | Rows = customers registered in the period |
| 03 | Revenue to date = source revenue for these customers |
| 04 | Valid order count = source count |
| 05 | First order date = independent minimum order date |
| 06 | A second order date exists only for customers with 2+ valid orders |
| 07 | No order before registration, and no second order before the first |
| 08 | Every activation stage obeys its rule |
| 09 | First-year revenue only for customers with a full year, and never above revenue to date |
| 10 | First-year revenue = independent recount |

## 8. Findings

**Three in four new customers have bought, and most who buy come back. But only half buy within 90 days.**

| Registration year | Registered | Placed a first order | Placed a second order | First order within 90 days | Repeat within 90 days |
|---|---:|---:|---:|---:|---:|
| 2024 | 27 | 20 | 16 | 37.0 % | 55.0 % |
| 2025 | 35 | 29 | 24 | 62.9 % | 74.1 % |
| 2026 (Jan–Sep) | 20 | 12 | 9 | 53.8 % | 71.4 % |
| **Total** | **82** | **61 (74.4 %)** | **49** | **52.0 %** | **66.7 %** |

- **Onboarding improved from 2024 to 2025.** The share ordering within 90 days rose from 37 % to 63 %, and 90-day repeat from 55 % to 74 %.
- **New customers are already material.** They generated ₹5.59 crore in the last 12 months, **13.8 % of company revenue**. Three accounts make up 44 % of their revenue to date: Laxmi Enterprises (₹1.12 crore), Jai Consumer Care (₹1.03 crore) and Unique Industrial Suppliers (₹1.01 crore).

**SMB is where activation stalls.**

| Segment | Registered | Not yet ordered | Only cancelled/returned | One order only | Repeat buyers | Median days to first order |
|---|---:|---:|---:|---:|---:|---:|
| SMB | 39 | **14** | 0 | 4 | 21 | 61 |
| Mid-Market | 22 | 2 | 0 | 6 | 14 | 37 |
| Enterprise | 11 | 1 | 1 | 1 | 8 | 15 |
| Distributor | 10 | 0 | **3** | 1 | 6 | 24 |

- **14 of 39 SMB registrations (36 %) have never ordered**, 7 of them registered in 2024. SMB customers also take four times as long as enterprises to place a first order.
- **4 new accounts have only cancelled or returned orders**, 3 of them distributors. Their first experience failed, and none has bought since.

**New customers who do buy are worth as much as established ones, except SMB:**

| Segment | New customers measured | Median first-year revenue | Established median (12 months) | New as % of established |
|---|---:|---:|---:|---:|
| Distributor | 3 | ₹34.0 lakh | ₹10.0 lakh | 340 % |
| Mid-Market | 6 | ₹5.6 lakh | ₹3.3 lakh | 168 % |
| Enterprise | 6 | ₹16.9 lakh | ₹16.6 lakh | 102 % |
| SMB | 16 | ₹0.5 lakh | ₹0.7 lakh | 77 % |

Step 5 lists 26 stalled accounts: 14 that never ordered (30+ days after registering), 8 with one order and nothing for 90+ days, and the 4 whose only orders were cancelled or returned. The largest one-order account is Classic Traders (₹1.69 lakh, quiet for 210 days).

## 9. Business implications and recommendations

1. **Set a 90-day activation target for every new account**, owned by the salesperson who opened it, and report it monthly beside registrations.
2. **Call the 4 accounts whose first orders failed.** Find out why each order was cancelled or returned before trying to sell again. A failed first order is the cheapest churn to prevent.
3. **Run an SMB onboarding sequence**: a welcome call within a week, a starter order offer and a reminder at 30 days. Mark accounts still without an order after 12 months as dormant, so they stop inflating the customer count.
4. **Follow up one-order accounts at 60 days**, before they go quiet. Repeat within 90 days is the strongest sign a new account will last.
5. **Give the large new accounts key-account cover early.** Laxmi Enterprises and Jai Consumer Care, both registered in July 2025, already rank 7th and 8th of 367 active customers by 12-month revenue (see [Salesperson relationship risk](../04_salesperson_relationship_risk/)).

## 10. Assumptions and limitations

- **Small numbers.** 82 new customers in total, and only 3–16 per segment have a full first year. Treat segment medians as indicative.
- **Registration date as start.** The analysis assumes registration marks the start of the relationship. If accounts are sometimes created long before first contact, days to first order will be overstated.
- **No acquisition source.** The data has no lead source or campaign, so activation cannot be compared by channel.
- **Cancelled and returned orders** are not counted as purchases, but are tracked separately because they reveal failed first experiences.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Activation table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
