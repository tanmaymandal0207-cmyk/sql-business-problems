# Case Study · City-wise Delivery Promise Standards

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Standards were set on 2024–2025 deliveries and tested on January–September 2026 deliveries.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Depends on** | `delivery_performance` table from [Late delivery root cause](../01_late_delivery_root_cause/) (run that script first) |
| **Last updated** | 2026-10-21 |

---

## 1. Business problem

Salespeople choose delivery promise dates by judgement. The [Late delivery root cause](../01_late_delivery_root_cause/) study found that promises ignore destination: a salesperson serving distant cities promises the same as one serving nearby cities. The operations and sales heads want a **standard promise table by city**. It should be short enough to stay competitive and long enough to be met. It must also be tested on data it was not built from.

## 2. Business questions

1. How long do deliveries actually take to each city?
2. If 2026 promises had followed a city standard, what on-time rate would that have given, and would promises have been longer or shorter than today?
3. Which service level (80 %, 85 % or 90 % of orders on time) gives the best balance?
4. Where are current promises furthest from what each city needs?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `delivery_performance` (built by the late delivery case study) | One row per delivered order | Standardised delivery city, actual lead time, promised lead time, on-time flag |

Reusing this table means the city name standardisation and the scope rules (Delivered orders with promised and delivery dates) match the late delivery study exactly.

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Actual lead time | Days from order to final delivery |
| City standard at s % | The lead time met by s % of the city's **2024–2025** orders: `PERCENTILE_DISC`, rounded up to whole days |
| Fallback | Cities with fewer than 20 training orders use the company-wide standard (13 days at the 85 % level). 6 cities use it. |
| On-time under a standard | 2026 order delivered within its city's standard |
| Promise gap | Current average promise − recommended standard. Negative means promising faster than the city can reliably deliver. |

**Why test out of sample?** A standard built and judged on the same orders will always look right. Setting standards on 2024–2025 and testing them on 2026 shows how they would have performed in practice.

## 5. Analytical approach

1. **Standards table** (`sahyadri_b2b.city_promise_standards`). Typical (median), 80 %, 85 % and 90 % lead times per city from training orders, with the company fallback.
2. **Out-of-sample test.** On-time rate and average promise in 2026 under actual promises and under each standard.
3. **Promise table** by city at the 85 % standard, against current 2026 practice.
4. **Gap summary.** Cities promising faster or slower than their standard.

## 6. SQL techniques used

- Reuse of an upstream analytical table (`delivery_performance`) as a governed source
- A train/test split by date with a declared cut-off
- `PERCENTILE_DISC … OVER (PARTITION BY city)` with `CEIL`. This gives standards that are real observed lead times, so each covers at least its target share of training orders (validation check 08).
- A fallback for small samples with `IF(training_orders >= min_city_orders, …)`
- `UNION ALL` of alternative scenarios into one comparison table

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per city |
| 02 | Every training city has a standard |
| 03 | Training orders in the table = training orders in the source |
| 04 | Standards are in order: median ≤ 80 % ≤ 85 % ≤ 90 % |
| 05 | Standards are whole days, at least 1 |
| 06 | All fallback cities share the same company standard |
| 07 | The city/fallback flag matches the 20-order rule |
| 08 | Each city's 85 % standard covers at least 85 % of its own training orders |
| 09 | Every 2026 test order has a standard |
| 10 | The dependency table is present and has 2026 orders |

## 8. Findings

**A city standard at the 85 % level would have lifted 2026 on-time delivery by 4 points for less than one extra day on the average promise.**

| Promise rule (tested on 2,785 orders in 2026) | On-time rate | Average promise |
|---|---:|---:|
| City standard at 80 % | 80.8 % | 10.5 days |
| **Actual 2026 promises** | **81.6 %** | **12.5 days** |
| City standard at 85 % | **85.4 %** | 13.4 days |
| City standard at 90 % | 90.1 % | 16.8 days |

- **The 80 % standard matches today's on-time rate with promises two days shorter.** Current promises are not just inaccurate but poorly targeted. They are too long for nearby cities and too short for distant ones.
- **The 90 % standard costs 4.3 extra days per promise** for 8.7 more points of on-time delivery. Each step up costs more, because the slowest deliveries are driven by dispatch delays, not distance.

**Promises are wrong in both directions:**

| Current practice vs 85 % standard | Cities | 2026 orders | Current on-time rate |
|---|---:|---:|---:|
| Promising too fast | 30 | 1,903 | 80.7 % |
| Promising slower than needed | 15 | 843 | 83.2 % |

- **Too fast:** Faridabad (promise 11.0 days vs standard 17), Dhanbad (12.2 vs 18), Noida (12.6 vs 17), New Delhi (11.7 vs 16) and Haridwar (11.2 vs 15, on-time only 71 %).
- **Slower than needed:** Mumbai (13.4 vs 9), Nashik (11.3 vs 8) and Pune (12.4 vs 10). Customers here could be offered dates 2 to 4 days sooner with the same reliability, which is a sales advantage being given away.

## 9. Business implications and recommendations

1. **Adopt the 85 % city standard as the default promise.** Load the Step 3 table into the order system as a lookup by delivery city. It lifts on-time delivery from 81.6 % to about 85 % for less than one extra day on average.
2. **Shorten promises for western cities** such as Mumbai, Nashik and Pune, and use the faster dates in sales conversations.
3. **Lengthen promises for the north and east cities currently promised too fast**, starting with the Delhi region (New Delhi, Noida, Faridabad) and Haridwar.
4. **Allow faster promises only with a stock check.** Reaching 90 % would need either 17-day promises or fixing the slow-dispatch tail identified in the late delivery and dispatch workload studies.
5. **Refresh the standards every six months** on a rolling 24-month window, and track 2027 performance against the standards' own forecast.

## 10. Assumptions and limitations

- **Dependency.** Results depend on the `delivery_performance` table and its scope (Delivered orders with both dates, standardised cities).
- **City only.** Standards ignore product and order size. If some products have longer dispatch times, a product-level adjustment could be added.
- **Small cities.** Cities with fewer than 20 training orders use the company standard. Some (for example Bhilai or Guwahati) may deserve their own value as volume grows.
- **Behaviour change.** The test assumes delivery performance in 2026 would have been the same under different promises. In practice, longer promises may reduce urgency and shorter ones may increase it.
- **Fixed cut-off.** One train/test split (end of 2025) is used. A rolling backtest would give a more stable estimate.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Standards table and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
