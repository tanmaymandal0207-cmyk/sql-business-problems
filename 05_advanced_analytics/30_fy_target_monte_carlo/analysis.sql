/* =============================================================================
   Case study · Will we hit the full-year target? A Monte Carlo of the
   rest of the financial year
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Half of FY 2026-27 (April - September 2026) is booked. The board will
   set the year's revenue target at its next meeting, and the CFO wants
   to tell it how likely each candidate target is, not just give one
   number. She asks:
     1. What does the rest of the year (October 2026 - March 2027) look
        like as a range, given the first half?
     2. How likely is each candidate target: Rs 40, 45, 50 or 55 crore?
     3. Would the same method have told the truth a year ago, month by
        month through FY 2025-26?
     4. Should growth in order size be projected, or only growth in the
        number of orders?

   METHOD (compound Poisson simulation, built from orders)
     - Valid orders (not Cancelled or Returned), January 2024 -
       September 2026. FY = April - March.
     - At a cut-off (the end of a month), for each remaining month m of
       the FY:
         orders N  ~ Poisson(mean), mean = orders in the same month
                     last year x count growth; count growth = FY-to-date
                     orders / orders in the same months last year
         each order: a random order drawn from the same month last year
     - Two size rules:
         A. Count growth only: drawn orders keep last year's value
         B. Count and size growth: drawn orders are scaled by size growth
            = FY-to-date average order value / same months last year
     - FY total = FY-to-date actual + simulated rest of year. 1,000
       simulations; Poisson counts by the normal approximation; uniform
       random numbers from an integer hash, so every run gives the same
       result.
     - Back-test: cut-offs at the end of every month April 2025 -
       February 2026, each predicting FY 2025-26. Score: where the actual
       FY total falls in the simulated distribution (its percentile) and
       whether it lies inside the 10-90 % range.
   ============================================================================= */

DECLARE sims       INT64 DEFAULT 1000;
DECLARE live_month DATE  DEFAULT DATE '2026-09-01';

-- -----------------------------------------------------------------------------
-- Step 1 · Orders, months and cut-offs
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ft_orders` AS
SELECT o.order_id, o.order_date, DATE_TRUNC(o.order_date, MONTH) AS month,
       SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))     AS value
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
GROUP BY o.order_id, o.order_date;

-- Draw pool: every order numbered within its month
CREATE OR REPLACE TABLE `sahyadri_b2b.ft_pool` AS
SELECT month, ROW_NUMBER() OVER (PARTITION BY month ORDER BY order_id) AS rn, value
FROM `sahyadri_b2b.ft_orders`;

CREATE OR REPLACE TABLE `sahyadri_b2b.ft_months` AS
SELECT month, COUNT(*) AS orders, SUM(value) AS revenue
FROM `sahyadri_b2b.ft_orders`
GROUP BY month;

-- Cut-offs: end of each month April 2025 - February 2026 (back-test of FY 2025-26) and September 2026 (live)
CREATE OR REPLACE TABLE `sahyadri_b2b.ft_cutoffs` AS
WITH cut AS (
    SELECT c, DATE_ADD(DATE '2025-04-01', INTERVAL c MONTH) AS cutoff_month FROM UNNEST(GENERATE_ARRAY(0, 10)) AS c
    UNION ALL
    SELECT 11, live_month
),
fy AS (
    SELECT c, cutoff_month,
           DATE(EXTRACT(YEAR FROM DATE_SUB(cutoff_month, INTERVAL 3 MONTH)), 4, 1)     AS fy_start
    FROM cut
)
SELECT
    f.c, f.cutoff_month, f.fy_start,
    DATE_ADD(f.fy_start, INTERVAL 11 MONTH)                                           AS fy_last_month,
    IF(f.c = 11, 'FY 2026-27 (live)', 'FY 2025-26 (back-test)')                        AS fy,
    SUM(IF(m.month BETWEEN f.fy_start AND f.cutoff_month, m.revenue, 0))              AS ytd_revenue,
    SUM(IF(m.month BETWEEN f.fy_start AND f.cutoff_month, m.orders, 0))               AS ytd_orders,
    SUM(IF(m.month BETWEEN DATE_SUB(f.fy_start, INTERVAL 12 MONTH) AND DATE_SUB(f.cutoff_month, INTERVAL 12 MONTH), m.orders, 0))  AS ly_ytd_orders,
    SUM(IF(m.month BETWEEN DATE_SUB(f.fy_start, INTERVAL 12 MONTH) AND DATE_SUB(f.cutoff_month, INTERVAL 12 MONTH), m.revenue, 0)) AS ly_ytd_revenue,
    SUM(IF(m.month BETWEEN f.fy_start AND DATE_ADD(f.fy_start, INTERVAL 11 MONTH), m.revenue, 0)) AS fy_actual_so_far
FROM fy AS f CROSS JOIN `sahyadri_b2b.ft_months` AS m
GROUP BY f.c, f.cutoff_month, f.fy_start;

CREATE OR REPLACE TABLE `sahyadri_b2b.ft_growth` AS
SELECT c, cutoff_month, fy, ytd_revenue, ytd_orders, ly_ytd_orders,
       ytd_orders / ly_ytd_orders                                                     AS count_growth,
       (ytd_revenue / ytd_orders) / (ly_ytd_revenue / ly_ytd_orders)                  AS size_growth,
       fy_actual_so_far, fy_start, fy_last_month
FROM `sahyadri_b2b.ft_cutoffs`;

-- Remaining months of each FY, with last year's orders as the base
CREATE OR REPLACE TABLE `sahyadri_b2b.ft_plan` AS
WITH months AS (
    SELECT g.c, k, g.count_growth, g.fy_last_month,
           DATE_ADD(g.cutoff_month, INTERVAL k MONTH)                                 AS month,
           DATE_ADD(g.cutoff_month, INTERVAL (k - 12) MONTH)                            AS ly_month
    FROM `sahyadri_b2b.ft_growth` AS g
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, 11)) AS k
)
SELECT mo.c, mo.k, mo.month, mo.ly_month,
       ly.orders AS ly_orders, ly.revenue AS ly_revenue,
       ly.orders * mo.count_growth                                                    AS mean_orders
FROM months AS mo
JOIN `sahyadri_b2b.ft_months` AS ly ON ly.month = mo.ly_month
WHERE mo.month <= mo.fy_last_month;

SELECT c, cutoff_month, fy, ytd_orders, ly_ytd_orders,
       ROUND(count_growth, 3) AS count_growth, ROUND(size_growth, 3) AS size_growth,
       ROUND(ytd_revenue / 1e7, 2) AS ytd_revenue_crore
FROM `sahyadri_b2b.ft_growth`
ORDER BY c;

-- -----------------------------------------------------------------------------
-- Step 2 · Simulate the rest of each FY
-- -----------------------------------------------------------------------------
-- Integer-hash uniforms: x = MOD(seed, p); u = (MOD(x * x + 12345, p) + 1) / (p + 1), p = 2147483647
CREATE OR REPLACE TABLE `sahyadri_b2b.ft_counts` AS
WITH seeds AS (
    SELECT pl.c, pl.k, pl.month, pl.ly_month, pl.ly_orders, pl.mean_orders, s,
           MOD(pl.c * 7919 + s * 104729 + pl.k * 1299709 + 11, 2147483647)            AS x1,
           MOD(pl.c * 7919 + s * 104729 + pl.k * 1299709 + 15485863, 2147483647)      AS x2
    FROM `sahyadri_b2b.ft_plan` AS pl
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, sims)) AS s
),
u AS (
    SELECT *, (MOD(x1 * x1 + 12345, 2147483647) + 1) / 2147483648 AS u1,
              (MOD(x2 * x2 + 12345, 2147483647) + 1) / 2147483648 AS u2
    FROM seeds
)
SELECT c, k, month, ly_month, ly_orders, mean_orders, s,
       SQRT(-2 * LN(u1)) * COS(2 * ACOS(-1) * u2)                                     AS z,
       CAST(GREATEST(0, ROUND(mean_orders + SQRT(mean_orders) * SQRT(-2 * LN(u1)) * COS(2 * ACOS(-1) * u2))) AS INT64) AS n
FROM u;

-- Each simulated order is a random order of the same month last year
CREATE OR REPLACE TABLE `sahyadri_b2b.ft_sims` AS
WITH draws AS (
    SELECT ct.c, ct.s, ct.k, ct.ly_month, ct.ly_orders,
           1 + MOD(MOD(MOD(ct.c * 7919 + ct.s * 104729 + ct.k * 1299709 + j * 179424673, 2147483647)
                       * MOD(ct.c * 7919 + ct.s * 104729 + ct.k * 1299709 + j * 179424673, 2147483647) + 12345, 2147483647),
                   ct.ly_orders)                                                      AS rn
    FROM `sahyadri_b2b.ft_counts` AS ct
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, ct.n)) AS j
),
rest AS (
    SELECT d.c, d.s, SUM(p.value) AS rest_value, COUNT(*) AS rest_orders
    FROM draws AS d JOIN `sahyadri_b2b.ft_pool` AS p ON p.month = d.ly_month AND p.rn = d.rn
    GROUP BY d.c, d.s
)
SELECT g.c, g.fy, sm AS s,
       g.ytd_revenue,
       IFNULL(r.rest_value, 0)                                                        AS rest_last_year_prices,
       IFNULL(r.rest_orders, 0)                                                       AS rest_orders,
       g.ytd_revenue + IFNULL(r.rest_value, 0)                                        AS fy_total_a,
       g.ytd_revenue + IFNULL(r.rest_value, 0) * g.size_growth                        AS fy_total_b
FROM `sahyadri_b2b.ft_growth` AS g
CROSS JOIN UNNEST(GENERATE_ARRAY(1, sims)) AS sm
LEFT JOIN rest AS r ON r.c = g.c AND r.s = sm;

-- -----------------------------------------------------------------------------
-- Step 3 · Back-test: FY 2025-26 seen from the end of each month
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ft_backtest` AS
WITH actual AS (
    SELECT fy_actual_so_far AS fy_actual FROM `sahyadri_b2b.ft_growth` WHERE c = 0
),
long_form AS (
    SELECT c, 'A. Count growth only' AS rule, fy_total_a AS fy_total FROM `sahyadri_b2b.ft_sims` WHERE c <= 10
    UNION ALL
    SELECT c, 'B. Count and size growth', fy_total_b FROM `sahyadri_b2b.ft_sims` WHERE c <= 10
)
SELECT
    lf.c, lf.rule, ANY_VALUE(a.fy_actual) AS fy_actual,
    APPROX_QUANTILES(lf.fy_total, 100)[OFFSET(10)]                                    AS p10,
    APPROX_QUANTILES(lf.fy_total, 100)[OFFSET(50)]                                    AS p50,
    APPROX_QUANTILES(lf.fy_total, 100)[OFFSET(90)]                                    AS p90,
    COUNTIF(lf.fy_total <= a.fy_actual) / COUNT(*)                                    AS actual_percentile
FROM long_form AS lf CROSS JOIN actual AS a
GROUP BY lf.c, lf.rule;

SELECT
    b.rule, g.cutoff_month AS data_to_end_of,
    12 - (b.c + 1)                                                                    AS months_simulated,
    ROUND(g.count_growth, 3) AS count_growth, ROUND(g.size_growth, 3) AS size_growth,
    ROUND(b.p10 / 1e7, 2) AS p10_crore, ROUND(b.p50 / 1e7, 2) AS p50_crore, ROUND(b.p90 / 1e7, 2) AS p90_crore,
    ROUND(b.fy_actual / 1e7, 2)                                                       AS actual_crore,
    ROUND(100 * (b.p50 / b.fy_actual - 1), 1)                                         AS median_error_pct,
    ROUND(100 * b.actual_percentile, 0)                                               AS actual_percentile,
    b.fy_actual BETWEEN b.p10 AND b.p90                                               AS inside_10_90
FROM `sahyadri_b2b.ft_backtest` AS b JOIN `sahyadri_b2b.ft_growth` AS g USING (c)
ORDER BY b.rule, b.c;

SELECT
    rule,
    COUNT(*)                                                                          AS cut_offs,
    COUNTIF(fy_actual BETWEEN p10 AND p90)                                            AS inside_10_90,
    COUNTIF(fy_actual > p90)                                                          AS above_p90,
    COUNTIF(fy_actual < p10)                                                          AS below_p10,
    ROUND(100 * AVG(ABS(p50 / fy_actual - 1)), 1)                                     AS mean_abs_median_error_pct,
    ROUND(100 * AVG(p50 / fy_actual - 1), 1)                                          AS mean_median_error_pct
FROM `sahyadri_b2b.ft_backtest`
GROUP BY rule
ORDER BY rule;

-- A harder test: the same rules from March 2026 for April - September 2026, when growth accelerated
-- (growth = FY 2025-26 against FY 2024-25; base = April - September 2025)
WITH fy AS (
    SELECT
        SUM(IF(month BETWEEN DATE '2025-04-01' AND DATE '2026-03-01', orders, 0))
          / SUM(IF(month BETWEEN DATE '2024-04-01' AND DATE '2025-03-01', orders, 0))  AS count_growth,
        (SUM(IF(month BETWEEN DATE '2025-04-01' AND DATE '2026-03-01', revenue, 0)) / SUM(IF(month BETWEEN DATE '2025-04-01' AND DATE '2026-03-01', orders, 0)))
          / (SUM(IF(month BETWEEN DATE '2024-04-01' AND DATE '2025-03-01', revenue, 0)) / SUM(IF(month BETWEEN DATE '2024-04-01' AND DATE '2025-03-01', orders, 0))) AS size_growth,
        SUM(IF(month BETWEEN DATE '2025-04-01' AND DATE '2025-09-01', revenue, 0))   AS base,
        SUM(IF(month BETWEEN DATE '2026-04-01' AND DATE '2026-09-01', revenue, 0))   AS actual,
        SUM(IF(month BETWEEN DATE '2026-04-01' AND DATE '2026-09-01', orders, 0))
          / SUM(IF(month BETWEEN DATE '2025-04-01' AND DATE '2025-09-01', orders, 0))  AS actual_count_growth
    FROM `sahyadri_b2b.ft_months`
)
SELECT
    ROUND(count_growth, 3)                                                            AS count_growth_used,
    ROUND(size_growth, 3)                                                             AS size_growth_used,
    ROUND(actual_count_growth, 3)                                                     AS count_growth_that_happened,
    ROUND(base * count_growth / 1e7, 2)                                               AS expected_rule_a_crore,
    ROUND(base * count_growth * size_growth / 1e7, 2)                                 AS expected_rule_b_crore,
    ROUND(actual / 1e7, 2)                                                            AS actual_crore,
    ROUND(100 * (base * count_growth / actual - 1), 1)                                AS rule_a_error_pct
FROM fy;

-- -----------------------------------------------------------------------------
-- Step 4 · FY 2026-27: range and the chance of each target
-- -----------------------------------------------------------------------------
WITH live AS (
    SELECT 'A. Count growth only' AS rule, fy_total_a AS fy_total, ytd_revenue FROM `sahyadri_b2b.ft_sims` WHERE c = 11
    UNION ALL
    SELECT 'B. Count and size growth', fy_total_b, ytd_revenue FROM `sahyadri_b2b.ft_sims` WHERE c = 11
    UNION ALL
    -- both rules pooled: equal weight on "size growth fades" and "size growth holds"
    SELECT 'C. A and B pooled', fy_total_a, ytd_revenue FROM `sahyadri_b2b.ft_sims` WHERE c = 11
    UNION ALL
    SELECT 'C. A and B pooled', fy_total_b, ytd_revenue FROM `sahyadri_b2b.ft_sims` WHERE c = 11
)
SELECT
    rule,
    ROUND(ANY_VALUE(ytd_revenue) / 1e7, 2)                                            AS h1_actual_crore,
    ROUND(APPROX_QUANTILES(fy_total, 100)[OFFSET(10)] / 1e7, 2)                       AS p10_crore,
    ROUND(APPROX_QUANTILES(fy_total, 100)[OFFSET(50)] / 1e7, 2)                       AS p50_crore,
    ROUND(APPROX_QUANTILES(fy_total, 100)[OFFSET(90)] / 1e7, 2)                       AS p90_crore,
    ROUND(100 * COUNTIF(fy_total >= 40e7) / COUNT(*), 1)                              AS p_40_crore_pct,
    ROUND(100 * COUNTIF(fy_total >= 45e7) / COUNT(*), 1)                              AS p_45_crore_pct,
    ROUND(100 * COUNTIF(fy_total >= 50e7) / COUNT(*), 1)                              AS p_50_crore_pct,
    ROUND(100 * COUNTIF(fy_total >= 55e7) / COUNT(*), 1)                              AS p_55_crore_pct
FROM live
GROUP BY rule
ORDER BY rule;

-- The live plan month by month (rule A expected values)
SELECT
    pl.month, pl.ly_orders, ROUND(pl.mean_orders, 0) AS expected_orders,
    ROUND(pl.ly_revenue / 1e7, 2)                                                     AS same_month_last_year_crore,
    ROUND(pl.ly_revenue * g.count_growth / 1e7, 2)                                    AS expected_rule_a_crore,
    ROUND(pl.ly_revenue * g.count_growth * g.size_growth / 1e7, 2)                    AS expected_rule_b_crore
FROM `sahyadri_b2b.ft_plan` AS pl JOIN `sahyadri_b2b.ft_growth` AS g USING (c)
WHERE pl.c = 11
ORDER BY pl.month;
