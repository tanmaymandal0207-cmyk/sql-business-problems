/* =============================================================================
   Case study · KPI change-point detection: which monthly moves are real?
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Every month the management pack shows ten KPIs with red and green
   arrows, and every month someone is asked to explain a move. The CEO
   wants to know which KPIs have actually changed level in the last 33
   months, when, and by how much, and which are just noise around a stable
   level:
     1. Does a change-point method find the two January price increases,
        which are known to have happened?
     2. Which other KPIs shifted, which grew gradually, and which never
        changed?
     3. Are the monthly swings in the rate KPIs larger than chance?
     4. What should the monthly pack report instead of arrows?

   METHOD
     - Ten monthly KPIs, January 2024 - September 2026 (33 months). Counts
       and rupee values are analysed as natural logs, so shifts and trends
       are in percent; rates and prices are analysed as they are.
     - Four models per KPI, each fitted by least squares:
         M0 one constant level
         T  a linear trend
         M1 one shift: two levels, with the best break month
         M2 two shifts: three levels, with the best pair of break months
       Breaks are searched exhaustively; every level lasts at least
       3 months. Segment sums of squares come from prefix sums.
     - Model choice by the Bayesian information criterion
       BIC = n ln(SSE / n) + p ln(n), with p = 1, 2, 3 and 5 parameters.
       A BIC lower by 2-6 is positive evidence, 6-10 strong, over 10 very
       strong.
     - Permutation test for "any shift at all": the share of 500 random
       reorderings of the months whose best single shift explains as much
       of the variance as the real order does.
     - Rate KPIs: chi-square dispersion test of the monthly counts against
       a constant rate (binomial noise only).
   ============================================================================= */

DECLARE start_month   DATE   DEFAULT DATE '2024-01-01';
DECLARE end_month     DATE   DEFAULT DATE '2026-09-01';
DECLARE min_segment   INT64  DEFAULT 3;
DECLARE permutations  INT64  DEFAULT 500;
DECLARE prime         INT64  DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Monthly KPI series
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.chp_series` AS
WITH months AS (
    SELECT m AS month, ROW_NUMBER() OVER (ORDER BY m) AS t
    FROM UNNEST(GENERATE_DATE_ARRAY(start_month, end_month, INTERVAL 1 MONTH)) AS m
),
lines AS (
    SELECT i.order_id,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS net_value,
           SUM(i.quantity * i.unit_price)                                             AS gross_value,
           SUM(i.quantity * p.selling_price)                                          AS list_value
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    GROUP BY i.order_id
),
ship AS (
    SELECT order_id, MIN(shipment_date) AS dispatch_date, MAX(delivery_date) AS final_delivery_date,
           COUNT(delivery_date) = COUNT(*) AS all_delivered
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
orders AS (
    SELECT DATE_TRUNC(o.order_date, MONTH) AS month, o.order_id, o.customer_id, o.order_date, o.order_status,
           o.promised_delivery_date, l.net_value, l.gross_value, l.list_value,
           s.dispatch_date, s.final_delivery_date, IFNULL(s.all_delivered, FALSE) AS all_delivered,
           o.order_status NOT IN ('Cancelled', 'Returned') AS is_sale
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN lines AS l ON l.order_id = o.order_id
    LEFT JOIN ship AS s ON s.order_id = o.order_id
),
agg AS (
    SELECT
        m.month, m.t,
        COUNT(*)                                                                         AS orders,
        SUM(IF(o.order_status = 'Cancelled', 1, 0))                                      AS cancelled,
        SUM(IF(o.order_status = 'Returned', 1, 0))                                       AS returned,
        SUM(IF(o.is_sale, 1, 0))                                                         AS sales,
        COUNT(DISTINCT IF(o.is_sale, o.customer_id, NULL))                               AS active_customers,
        SUM(IF(o.is_sale, o.net_value, 0))                                               AS revenue,
        SUM(IF(o.is_sale, o.gross_value, 0))                                             AS gross_value,
        SUM(IF(o.is_sale, o.list_value, 0))                                              AS list_value,
        SUM(IF(o.order_status = 'Delivered' AND o.all_delivered AND o.promised_delivery_date IS NOT NULL, 1, 0)) AS delivered,
        SUM(IF(o.order_status = 'Delivered' AND o.all_delivered AND o.promised_delivery_date IS NOT NULL
               AND o.final_delivery_date > o.promised_delivery_date, 1, 0))              AS late,
        AVG(IF(o.dispatch_date >= o.order_date, DATE_DIFF(o.dispatch_date, o.order_date, DAY), NULL)) AS dispatch_lag
    FROM months AS m
    JOIN orders AS o ON o.month = m.month
    GROUP BY m.month, m.t
)
SELECT 1 AS kpi_no, 'Price factor (invoice / list)' AS kpi, 'level' AS scale, month, t, gross_value / list_value AS value,
       gross_value / list_value AS y, CAST(NULL AS INT64) AS events, CAST(NULL AS INT64) AS trials FROM agg
UNION ALL SELECT 2,  'Orders',                   'log',   month, t, orders,                    LN(orders),                 NULL, NULL FROM agg
UNION ALL SELECT 3,  'Active customers',         'log',   month, t, active_customers,          LN(active_customers),       NULL, NULL FROM agg
UNION ALL SELECT 4,  'Net revenue',              'log',   month, t, revenue,                   LN(revenue),                NULL, NULL FROM agg
UNION ALL SELECT 5,  'Average order value',      'log',   month, t, revenue / sales,           LN(revenue / sales),        NULL, NULL FROM agg
UNION ALL SELECT 6,  'Discount rate',            'level', month, t, 1 - revenue / gross_value, 1 - revenue / gross_value, NULL, NULL FROM agg
UNION ALL SELECT 7,  'Cancellation rate',        'level', month, t, cancelled / orders,        cancelled / orders,         cancelled, orders FROM agg
UNION ALL SELECT 8,  'Return rate',              'level', month, t, returned / orders,         returned / orders,          returned, orders FROM agg
UNION ALL SELECT 9,  'Late delivery rate',       'level', month, t, late / delivered,          late / delivered,           late, delivered FROM agg
UNION ALL SELECT 10, 'Dispatch lag (days)',      'level', month, t, dispatch_lag,              dispatch_lag,               NULL, NULL FROM agg;

SELECT kpi_no, kpi, COUNT(*) AS months, ROUND(MIN(value), 4) AS min_value, ROUND(AVG(value), 4) AS mean_value,
       ROUND(MAX(value), 4) AS max_value
FROM `sahyadri_b2b.chp_series`
GROUP BY kpi_no, kpi
ORDER BY kpi_no;

-- -----------------------------------------------------------------------------
-- Step 2 · Fit the four models to every KPI
-- -----------------------------------------------------------------------------
-- Prefix sums: S1(t) = sum of y up to t, S2(t) = sum of y squared up to t (t = 0 row = 0)
CREATE OR REPLACE TABLE `sahyadri_b2b.chp_prefix` AS
SELECT kpi_no, t,
       SUM(y)     OVER (PARTITION BY kpi_no ORDER BY t ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS s1,
       SUM(y * y) OVER (PARTITION BY kpi_no ORDER BY t ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS s2
FROM `sahyadri_b2b.chp_series`
UNION ALL
SELECT DISTINCT kpi_no, 0, 0.0, 0.0 FROM `sahyadri_b2b.chp_series`;

-- Every segment [first_t, last_t] with its mean and sum of squared deviations
CREATE OR REPLACE TABLE `sahyadri_b2b.chp_segments` AS
SELECT a.kpi_no, a.t + 1 AS first_t, b.t AS last_t, b.t - a.t AS months,
       (b.s1 - a.s1) / (b.t - a.t)                                           AS mean_y,
       GREATEST((b.s2 - a.s2) - POW(b.s1 - a.s1, 2) / (b.t - a.t), 0)        AS sse
FROM `sahyadri_b2b.chp_prefix` AS a
JOIN `sahyadri_b2b.chp_prefix` AS b
  ON b.kpi_no = a.kpi_no AND b.t - a.t >= min_segment;

CREATE OR REPLACE TABLE `sahyadri_b2b.chp_models` AS
WITH n AS (
    SELECT kpi_no, COUNT(*) AS n, AVG(t) AS t_bar, AVG(y) AS y_bar FROM `sahyadri_b2b.chp_series` GROUP BY kpi_no
),
m0 AS (
    SELECT s.kpi_no, 'M0 No change' AS model, 1 AS params, s.sse, CAST(NULL AS INT64) AS break_1, CAST(NULL AS INT64) AS break_2
    FROM `sahyadri_b2b.chp_segments` AS s JOIN n ON n.kpi_no = s.kpi_no
    WHERE s.first_t = 1 AND s.last_t = n.n
),
trend AS (
    SELECT c.kpi_no, 'T Linear trend' AS model, 2 AS params,
           SUM(POW(c.y - n.y_bar, 2)) - POW(SUM((c.t - n.t_bar) * (c.y - n.y_bar)), 2) / SUM(POW(c.t - n.t_bar, 2)) AS sse,
           CAST(NULL AS INT64) AS break_1, CAST(NULL AS INT64) AS break_2
    FROM `sahyadri_b2b.chp_series` AS c JOIN n ON n.kpi_no = c.kpi_no
    GROUP BY c.kpi_no
),
m1_all AS (
    SELECT s1.kpi_no, s1.sse + s2.sse AS sse, s2.first_t AS break_1,
           ROW_NUMBER() OVER (PARTITION BY s1.kpi_no ORDER BY s1.sse + s2.sse, s2.first_t) AS rk
    FROM `sahyadri_b2b.chp_segments` AS s1
    JOIN n ON n.kpi_no = s1.kpi_no
    JOIN `sahyadri_b2b.chp_segments` AS s2 ON s2.kpi_no = s1.kpi_no AND s2.first_t = s1.last_t + 1 AND s2.last_t = n.n
    WHERE s1.first_t = 1
),
m2_all AS (
    SELECT s1.kpi_no, s1.sse + s2.sse + s3.sse AS sse, s2.first_t AS break_1, s3.first_t AS break_2,
           ROW_NUMBER() OVER (PARTITION BY s1.kpi_no ORDER BY s1.sse + s2.sse + s3.sse, s2.first_t, s3.first_t) AS rk
    FROM `sahyadri_b2b.chp_segments` AS s1
    JOIN n ON n.kpi_no = s1.kpi_no
    JOIN `sahyadri_b2b.chp_segments` AS s2 ON s2.kpi_no = s1.kpi_no AND s2.first_t = s1.last_t + 1
    JOIN `sahyadri_b2b.chp_segments` AS s3 ON s3.kpi_no = s1.kpi_no AND s3.first_t = s2.last_t + 1 AND s3.last_t = n.n
    WHERE s1.first_t = 1
),
fits AS (
    SELECT * FROM m0
    UNION ALL SELECT * FROM trend
    UNION ALL SELECT kpi_no, 'M1 One shift', 3, sse, break_1, CAST(NULL AS INT64) FROM m1_all WHERE rk = 1
    UNION ALL SELECT kpi_no, 'M2 Two shifts', 5, sse, break_1, break_2 FROM m2_all WHERE rk = 1
)
SELECT f.*, n.n,
       n.n * LN(f.sse / n.n) + f.params * LN(n.n)                                       AS bic,
       RANK() OVER (PARTITION BY f.kpi_no ORDER BY n.n * LN(f.sse / n.n) + f.params * LN(n.n)) AS bic_rank
FROM fits AS f
JOIN n ON n.kpi_no = f.kpi_no;

-- BIC of every model (lower is better), and the chosen model
SELECT
    s.kpi_no, s.kpi,
    ROUND(MAX(IF(m.model LIKE 'M0%', m.bic, NULL)), 1)   AS bic_no_change,
    ROUND(MAX(IF(m.model LIKE 'T%',  m.bic, NULL)), 1)   AS bic_trend,
    ROUND(MAX(IF(m.model LIKE 'M1%', m.bic, NULL)), 1)   AS bic_one_shift,
    ROUND(MAX(IF(m.model LIKE 'M2%', m.bic, NULL)), 1)   AS bic_two_shifts,
    MAX(IF(m.bic_rank = 1, m.model, NULL))               AS chosen_model,
    ROUND(MAX(IF(m.bic_rank = 2, m.bic, NULL)) - MAX(IF(m.bic_rank = 1, m.bic, NULL)), 1) AS bic_margin_over_next
FROM (SELECT DISTINCT kpi_no, kpi FROM `sahyadri_b2b.chp_series`) AS s
JOIN `sahyadri_b2b.chp_models` AS m ON m.kpi_no = s.kpi_no
GROUP BY s.kpi_no, s.kpi
ORDER BY s.kpi_no;

-- -----------------------------------------------------------------------------
-- Step 3 · What changed, when and by how much
-- -----------------------------------------------------------------------------
-- Levels of the best one-shift and two-shift fits (log KPIs shown as values)
WITH n_months AS (
    SELECT kpi_no, COUNT(*) AS n FROM `sahyadri_b2b.chp_series` GROUP BY kpi_no
),
best AS (
    SELECT m.kpi_no, m.model, m.break_1, m.break_2, m.bic_rank
    FROM `sahyadri_b2b.chp_models` AS m
    WHERE m.model LIKE 'M%' AND m.model NOT LIKE 'M0%'
),
levels AS (
    SELECT b.kpi_no, b.model, b.bic_rank, b.break_1, b.break_2,
           ss.first_t, ss.last_t, ss.mean_y
    FROM best AS b
    JOIN n_months AS nm ON nm.kpi_no = b.kpi_no
    JOIN `sahyadri_b2b.chp_segments` AS ss
      ON ss.kpi_no = b.kpi_no
     AND (   (ss.first_t = 1 AND ss.last_t = b.break_1 - 1)
          OR (b.break_2 IS NULL AND ss.first_t = b.break_1 AND ss.last_t = nm.n)
          OR (b.break_2 IS NOT NULL AND ss.first_t = b.break_1 AND ss.last_t = b.break_2 - 1)
          OR (b.break_2 IS NOT NULL AND ss.first_t = b.break_2 AND ss.last_t = nm.n))
)
SELECT
    l.kpi_no, s.kpi, l.model, l.bic_rank AS rank_among_4_models,
    MIN(IF(s.t = l.break_1, s.month, NULL))                                               AS break_1_month,
    MIN(IF(s.t = l.break_2, s.month, NULL))                                               AS break_2_month,
    STRING_AGG(CAST(ROUND(IF(s.scale = 'log', EXP(l.mean_y), l.mean_y), 4) AS STRING), ' -> ' ORDER BY l.first_t) AS levels
FROM levels AS l
JOIN (SELECT DISTINCT kpi_no, kpi, scale, t, month FROM `sahyadri_b2b.chp_series`) AS s
  ON s.kpi_no = l.kpi_no AND s.t = l.first_t
GROUP BY l.kpi_no, s.kpi, l.model, l.bic_rank
ORDER BY l.kpi_no, l.model;

-- The trend models: growth per year (log KPIs) or change per year (level KPIs)
SELECT
    c.kpi_no, c.kpi,
    ROUND(SUM((c.t - x.t_bar) * (c.y - x.y_bar)) / SUM(POW(c.t - x.t_bar, 2)) * 12, 4)           AS slope_per_year,
    ROUND(100 * (EXP(SUM((c.t - x.t_bar) * (c.y - x.y_bar)) / SUM(POW(c.t - x.t_bar, 2)) * 12) - 1), 1) AS growth_per_year_pct_if_log
FROM `sahyadri_b2b.chp_series` AS c
JOIN (SELECT kpi_no, AVG(t) AS t_bar, AVG(y) AS y_bar FROM `sahyadri_b2b.chp_series` GROUP BY kpi_no) AS x
  ON x.kpi_no = c.kpi_no
GROUP BY c.kpi_no, c.kpi
ORDER BY c.kpi_no;

-- -----------------------------------------------------------------------------
-- Step 4 · Permutation test: is there any shift at all?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.chp_permutation_stats` AS
WITH reps AS (
    SELECT b FROM UNNEST(GENERATE_ARRAY(1, permutations)) AS b
),
hashed AS (
    SELECT r.b, c.kpi_no, c.t, c.y,
           MOD(MOD(r.b * 7919 + c.t * 104729 + c.kpi_no * 1299709, prime) * MOD(r.b * 7919 + c.t * 104729 + c.kpi_no * 1299709, prime) + 12345, prime) AS h
    FROM reps AS r
    CROSS JOIN `sahyadri_b2b.chp_series` AS c
),
shuffled AS (
    SELECT b, kpi_no, y, ROW_NUMBER() OVER (PARTITION BY b, kpi_no ORDER BY h, t) AS t
    FROM hashed
),
prefix AS (
    SELECT b, kpi_no, t,
           SUM(y)     OVER (PARTITION BY b, kpi_no ORDER BY t ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS s1,
           SUM(y * y) OVER (PARTITION BY b, kpi_no ORDER BY t ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS s2,
           COUNT(*)   OVER (PARTITION BY b, kpi_no) AS n,
           SUM(y)     OVER (PARTITION BY b, kpi_no) AS s1_all,
           SUM(y * y) OVER (PARTITION BY b, kpi_no) AS s2_all
    FROM shuffled
)
SELECT b, kpi_no,
       -- share of the variance explained by the best single shift
       MAX(1 - ((s2 - POW(s1, 2) / t) + ((s2_all - s2) - POW(s1_all - s1, 2) / (n - t)))
               / (s2_all - POW(s1_all, 2) / n))                                   AS r2_best_shift
FROM prefix
WHERE t >= min_segment AND n - t >= min_segment
GROUP BY b, kpi_no;

WITH observed AS (
    SELECT m1.kpi_no, m1.n, 1 - m1.sse / m0.sse AS r2_best_shift
    FROM `sahyadri_b2b.chp_models` AS m1
    JOIN `sahyadri_b2b.chp_models` AS m0 ON m0.kpi_no = m1.kpi_no AND m0.model LIKE 'M0%'
    WHERE m1.model LIKE 'M1%'
)
SELECT
    o.kpi_no, s.kpi,
    ROUND(o.r2_best_shift, 3)                                                            AS r2_observed,
    ROUND(APPROX_QUANTILES(p.r2_best_shift, 100)[OFFSET(95)], 3)                         AS r2_95th_pct_if_random,
    ROUND((1 + COUNTIF(p.r2_best_shift >= o.r2_best_shift - 1e-12)) / (1 + COUNT(*)), 4) AS p_value,
    -- how often pure noise would make BIC prefer one shift over no change:
    -- BIC(M1) < BIC(M0)  <=>  R2 > 1 - n^(-2/n)
    ROUND(100 * AVG(IF(p.r2_best_shift > 1 - POW(o.n, -2 / o.n), 1, 0)), 1)            AS noise_flagged_as_shift_pct
FROM observed AS o
JOIN `sahyadri_b2b.chp_permutation_stats` AS p ON p.kpi_no = o.kpi_no
JOIN (SELECT DISTINCT kpi_no, kpi FROM `sahyadri_b2b.chp_series`) AS s ON s.kpi_no = o.kpi_no
GROUP BY o.kpi_no, s.kpi, o.n, o.r2_best_shift
ORDER BY o.kpi_no;

-- -----------------------------------------------------------------------------
-- Step 5 · Rate KPIs: are the monthly swings larger than chance?
-- -----------------------------------------------------------------------------
WITH rates AS (
    SELECT kpi_no, kpi, t, events, trials,
           SUM(events) OVER (PARTITION BY kpi_no) / SUM(trials) OVER (PARTITION BY kpi_no) AS p_bar
    FROM `sahyadri_b2b.chp_series`
    WHERE trials IS NOT NULL
),
moves AS (
    SELECT kpi_no, MAX(move) AS largest_move
    FROM (SELECT kpi_no, ABS(value - LAG(value) OVER (PARTITION BY kpi_no ORDER BY t)) AS move
          FROM `sahyadri_b2b.chp_series`)
    GROUP BY kpi_no
)
SELECT
    r.kpi_no, r.kpi,
    ROUND(100 * ANY_VALUE(r.p_bar), 2)                                                     AS overall_rate_pct,
    ROUND(100 * ANY_VALUE(mv.largest_move), 1)                                             AS largest_monthly_move_pp,
    ROUND(SUM(POW(r.events - r.trials * r.p_bar, 2) / (r.trials * r.p_bar * (1 - r.p_bar))), 1) AS chi_square,
    COUNT(*) - 1                                                                           AS degrees_of_freedom,
    -- 95 % critical value, Wilson-Hilferty approximation
    ROUND((COUNT(*) - 1) * POW(1 - 2 / (9 * (COUNT(*) - 1)) + 1.6449 * SQRT(2 / (9 * (COUNT(*) - 1))), 3), 1) AS critical_value_95,
    ROUND(SUM(POW(r.events - r.trials * r.p_bar, 2) / (r.trials * r.p_bar * (1 - r.p_bar))) / (COUNT(*) - 1), 2) AS dispersion_ratio
FROM rates AS r
JOIN moves AS mv ON mv.kpi_no = r.kpi_no
GROUP BY r.kpi_no, r.kpi
ORDER BY r.kpi_no;
