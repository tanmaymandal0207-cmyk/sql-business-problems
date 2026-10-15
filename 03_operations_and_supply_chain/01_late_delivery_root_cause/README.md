# Case Study · Late Delivery Root Cause

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Data covers orders dated 1 Jan 2024 to 30 Sep 2026.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-15 |

---

## 1. Business problem

Customers are complaining about late deliveries. Operations has three competing explanations and a limited budget:

| Explanation | Where the fix would go |
|---|---|
| The warehouse is slow to dispatch | Stock availability, picking and packing capacity |
| Transporters are slow | Change carriers or routes |
| Sales promises dates the business cannot meet | Promise-date rules |

The analysis measures how much each stage contributes to lateness, so that money goes to the stage that actually causes it.

## 2. Business questions

1. What share of delivered orders arrive by the promised date, and how late are the late ones?
2. For each late order, how many days of lateness come from dispatch, from transit, and from a promise date shorter than the normal lead time?
3. Do split shipments and short promise windows predict lateness?
4. After standardising city names, which destinations and which salespeople are associated with late deliveries?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date, promised delivery date, status, salesperson |
| `shipments` | One row per shipment | Shipment and delivery dates, destination city |
| `employees` | One row per employee | Salesperson name and designation |

An order can have up to two shipments. `shipments` is aggregated to one row per order before it is joined to `sales_orders`.

**City standardisation.** Raw `shipping_city` contains 79 distinct strings with mixed case, trailing spaces and historic names (Bombay, Calcutta, Madras, Gurgaon and others). The script builds a small mapping table, `city_name_map`, for alternate names and applies `INITCAP(TRIM(...))` to the rest. This leaves **51 standard city names**. Validation checks 03–05 confirm that the mapping is complete and unambiguous.

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Promised lead | Promised delivery date − order date |
| Dispatch days | Last shipment date − order date. An order counts as dispatched only when its last part leaves. |
| Transit days | Final delivery date − last shipment date |
| Actual lead | Dispatch days + transit days (= final delivery date − order date) |
| Late | Final delivery date after promised delivery date |
| Days late | Actual lead − promised lead |
| Standard dispatch | Median dispatch days of single-shipment orders: **3 days** |
| Standard transit | Median transit days for the destination city. Cities with fewer than 20 orders use the company median. |
| Expected lead | Standard dispatch + standard transit for the city |

**Days-late decomposition.** Every order's days late splits exactly into three parts:

```
days late = (dispatch days − standard dispatch)        → dispatch_excess
          + (transit days  − standard transit for city) → transit_excess
          + (expected lead − promised lead)             → promise_shortfall
```

A negative component means that stage absorbed delay. For example, a generous promise date gives a negative promise_shortfall. Each late order is assigned the component that contributes the most days as its **primary cause**. Validation check 06 confirms that the three parts add up to days late on every order.

## 5. Analytical approach

`analysis.sql` runs nine steps:

0. **City name mapping.** Builds the alternate-name → standard-name table.
1. **Delivery performance table.** Creates one row per in-scope order with lead times, standards, the three components and the primary cause. It is saved as `sahyadri_b2b.delivery_performance`.
2. **Headline on-time rate** and the standards used.
3. **Days-late bridge.** Splits total days late into dispatch, transit and promise components.
4. **Primary cause** of late orders.
5. **Dispatch bands.** Late rate by how far beyond standard the order was dispatched.
6. **Shipment pattern × promise window.** Late rates.
7. **Destinations.** Transit-driven lateness by standard city.
8. **Salespeople.** Promise windows, transit mix and promise-driven lateness.

**Scope.** All 9,288 Delivered orders were considered, and 9,121 are in scope. Excluded: 151 with no promised date, 8 with no delivery date, 3 with no shipment record and 5 shipped before the order date (a data error). These 167 exclusions reconcile exactly in validation check 02.

## 6. SQL techniques used

- BigQuery scripting with `DECLARE` and `CREATE OR REPLACE TABLE`
- A mapping table built with `UNNEST([STRUCT(...)])` and applied with a `LEFT JOIN` plus `COALESCE` fallback
- Text standardisation: `LOWER`, `TRIM`, `INITCAP`
- Pre-aggregation of a one-to-many table before joining
- Medians with `PERCENTILE_CONT(...) OVER (PARTITION BY ...)`, with a fallback for small groups
- An additive decomposition of a metric into components, plus rule-based attribution
- Window shares with `SUM(COUNT(*)) OVER ()` and conditional aggregation with `COUNTIF`

## 7. Validation and reconciliation

`validation.sql` returns PASS for all 10 checks.

| # | Check | Result |
|---|---|---|
| 01 | One row per order | PASS |
| 02 | Delivered orders = in scope + each exclusion reason (9,288 = 9,121 + 167) | PASS |
| 03 | No two standard city names differ only by case or spacing | PASS |
| 04 | No order is shipped to more than one standard city | PASS |
| 05 | Every row in the mapping table matches real shipment data | PASS |
| 06 | Dispatch + transit + promise components = days late, on every order | PASS |
| 07 | Days late = final delivery date − promised date, recomputed from dates | PASS |
| 08 | Every late order has a primary cause, and no on-time order has one | PASS |
| 09 | No negative dispatch or transit days in scope | PASS |
| 10 | The primary cause is always the largest component | PASS |

## 8. Findings

**On-time delivery is 81.7 %.** 7,448 of 9,121 delivered orders arrived by the promised date. The 1,673 late orders were an average of 6.6 days late (maximum 32).

**Promises are not the problem. Dispatch is.** A typical order takes 7 days to arrive (3 days to dispatch plus about 4 days in transit), but the average promise is 12.6 days. Promise dates therefore already carry a buffer of about 5 days. Splitting the 10,987 total days late:

| Component | Days | What it means |
|---|---:|---|
| Dispatch beyond standard | +15,060 | The main source of delay |
| Transit beyond standard | +1,973 | A small contributor |
| Promise shorter than normal lead | −6,046 | Generous promises absorbed part of the delay |
| **Total days late** | **10,987** | |

| Primary cause | Late orders | Share |
|---|---:|---:|
| Dispatch delay | 1,340 | 80.1 % |
| Transit delay | 278 | 16.6 % |
| Promise shorter than normal lead time | 55 | 3.3 % |

**A small group of slow-dispatch orders causes most of the lateness.** Orders dispatched within the 3-day standard are late only 4.1 % of the time. The 1,322 orders (14.5 %) that left **6 or more days** after the standard were late 84.8 % of the time. They account for **67.0 % of all late deliveries**. Of the 1,121 late orders in that group, 751 were single shipments, meaning the whole order waited rather than just one part.

**Split shipments are late 69.3 % of the time, against 14.8 % for single shipments** (414 of 597). With a promise of 7 days or less, every split shipment was late (44 of 44).

**Short promise windows leave no room for any delay.** Single-shipment orders promised in 7 days or less were late 44.8 % of the time, against 7.0 % for promises of 15 days or more. Only 294 orders (3.2 %) were promised in less than the city's normal lead time, but 61.9 % of those were late.

**Geography is a minor factor.** No city with 20 or more orders has more than 10.0 % of its orders late because of transit (the highest is Ghaziabad). Kolkata has the most transit-driven late orders in absolute terms (37). City late rates range from 6.9 % to 38.1 %, but that spread comes mainly from dispatch delays.

**One salesperson stands out on promise-setting.** Employee 110 has the highest late rate, 29.3 %. They also account for 21 of the 55 promise-driven late orders (38 %). Their orders average 6.4 transit days, among the longest of any salesperson, yet their average promise window (12.1 days) is no longer than their peers'. Employee 105 serves similarly distant destinations (6.3 transit days) but promises 14.5 days on average and is late only 17.4 % of the time. Promise windows that allow for distance work.

## 9. Business implications and recommendations

1. **Put the budget into dispatch, not transport.** Dispatch delay is the primary cause of 80.1 % of late orders. Changing carriers would address at most the 16.6 % caused by transit.
2. **Investigate the 6+ day dispatch tail.** These orders are 14.5 % of volume and 67.0 % of late deliveries. The next step is to join them to stock and purchase data (not in this dataset) to confirm whether they waited for stock, for picking capacity or for credit approval.
3. **Confirm stock before promising split orders.** Split shipments are late 69.3 % of the time. A promise date should be based on when the last part will be available, not the first.
4. **Make promise dates city-aware.** Calculate the minimum promise as standard dispatch + the city's median transit + a buffer. This would stop the 294 promises shorter than normal lead time (61.9 % of which were late). Review distant-city orders with employee 110 first.
5. **Target transport fixes by lane, not network-wide.** Start with Kolkata, which has the most transit-driven late orders, and with Rourkela and Ghaziabad, which have the highest shares.
6. **Fix the data at source.** Adopt the city mapping table as the master list in the order system. Make the promised delivery date mandatory (151 delivered orders had none). Block shipment dates earlier than the order date (5 orders).

## 10. Assumptions and limitations

- **Standards** are medians from the same dataset. They describe normal performance, not a contractual service level.
- **Salesperson.** `employee_id` on the order is assumed to be the person who agreed the promise date. 322 orders have no salesperson recorded.
- **Split shipments** are measured to the last part dispatched, so a partially on-time order still counts as late.
- **No stock, warehouse or carrier data** is available. The analysis shows where delay happens, not why dispatch is slow.
- **City mapping** merges `Delhi` into `New Delhi` and treats historic names as current ones. These are business judgements recorded in `city_name_map`.
- **Timing.** Results cover the full period from 2024 to September 2026. Monthly late rates stayed within roughly 11 % to 23 % with no clear trend, so the period is treated as one.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | City mapping, delivery performance table and 8 analysis steps |
| `validation.sql` | 10 pass/fail checks |
