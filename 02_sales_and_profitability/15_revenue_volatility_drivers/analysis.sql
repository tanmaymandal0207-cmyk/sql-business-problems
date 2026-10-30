/* =============================================================================
   Case study · Revenue volatility: how much of a monthly miss is predictable?
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The best monthly revenue forecast misses a typical month by about 17 %
   (see the revenue forecast baseline). The board asks the sales director
   to explain every miss and wants the forecast tightened to +/-5 %. Before
   promising that, the FP&A lead wants to know:
     1. Does monthly volatility come from the number of orders or from the
        size of orders?
     2. How much of it is trend and the March / December peaks, which can
        be planned for?
     3. How much is pure chance - what would remain even with a perfect
        forecast of demand?
     4. How much do a few very large orders contribute?

   METHOD
     - Valid orders (not Cancelled or Returned), January 2024 - September
       2026. Monthly revenue R = orders N x average order value S, so
       ln R = ln N + ln S.
     - Plannable part: a linear trend in ln y fitted by least squares, then
       a March effect and a December effect = the average trend residual in
       those months. What is left is the unexplained month-to-month swing.
     - Irreducible noise: if orders arrive at random (Poisson) at the
       planned rate, ln N varies by about 1 / SQRT(N). Order size noise is
       measured by a bootstrap: 300 times, each month's N orders are redrawn
       at random from all orders of the same calendar year, and the SD of
       ln(average size) across draws is the noise a perfect plan would
       still face.
     - Large orders: net value of Rs 5 lakh or more.
   ============================================================================= */

DECLARE start_month     DATE    DEFAULT DATE '2024-01-01';
DECLARE end_month       DATE    DEFAULT DATE '2026-09-01';
DECLARE large_order     FLOAT64 DEFAULT 500000;
DECLARE bootstrap_reps  INT64   DEFAULT 300;
DECLARE prime           INT64   DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Orders and months
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rv_orders` AS
SELECT
    o.order_id, o.order_date, DATE_TRUNC(o.order_date, MONTH) AS month, EXTRACT(YEAR FROM o.order_date) AS yr,
    SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value,
    SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) >= large_order AS is_large
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
  AND o.order_date >= start_month AND o.order_date < DATE_ADD(end_month, INTERVAL 1 MONTH)
GROUP BY o.order_id, o.order_date;

CREATE OR REPLACE TABLE `sahyadri_b2b.rv_months` AS
SELECT
    month,
    ROW_NUMBER() OVER (ORDER BY month)                                  AS t,
    EXTRACT(MONTH FROM month)                                           AS month_no,
    COUNT(*)                                                            AS orders,
    SUM(order_value)                                                    AS revenue,
    SUM(order_value) / COUNT(*)                                         AS avg_order_value,
    COUNTIF(is_large)                                                   AS large_orders,
    SUM(IF(is_large, order_value, 0))                                   AS large_revenue,
    SUM(IF(is_large, 0, order_value))                                   AS revenue_excl_large,
    MAX(order_value)                                                    AS largest_order
FROM `sahyadri_b2b.rv_orders`
GROUP BY month;

SELECT
    COUNT(*)                                                                  AS orders,
    ROUND(AVG(order_value) / 1e3, 1)                                          AS mean_order_k,
    ROUND(APPROX_QUANTILES(order_value, 100)[OFFSET(50)] / 1e3, 1)            AS median_order_k,
    ROUND(STDDEV_SAMP(order_value) / AVG(order_value), 2)                     AS order_size_cv,
    COUNTIF(is_large)                                                         AS large_orders,
    ROUND(100 * COUNTIF(is_large) / COUNT(*), 1)                              AS large_orders_pct,
    ROUND(100 * SUM(IF(is_large, order_value, 0)) / SUM(order_value), 1)     AS large_revenue_pct,
    ROUND(MAX(order_value) / 1e5, 1)                                          AS largest_order_lakh
FROM `sahyadri_b2b.rv_orders`;

-- -----------------------------------------------------------------------------
-- Step 2 · Trend, March and December, and the unexplained swing
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rv_components` AS
WITH series AS (
    SELECT month, t, month_no, 'Revenue' AS measure, LN(revenue) AS y FROM `sahyadri_b2b.rv_months`
    UNION ALL SELECT month, t, month_no, 'Orders',                     LN(orders)             FROM `sahyadri_b2b.rv_months`
    UNION ALL SELECT month, t, month_no, 'Average order value',        LN(avg_order_value)    FROM `sahyadri_b2b.rv_months`
    UNION ALL SELECT month, t, month_no, 'Revenue excluding large orders', LN(revenue_excl_large) FROM `sahyadri_b2b.rv_months`
),
trend AS (
    SELECT measure,
           SUM((t - t_bar) * (y - y_bar)) / SUM(POW(t - t_bar, 2)) AS slope,
           ANY_VALUE(y_bar) AS y_bar, ANY_VALUE(t_bar) AS t_bar
    FROM (SELECT *, AVG(t) OVER (PARTITION BY measure) AS t_bar, AVG(y) OVER (PARTITION BY measure) AS y_bar FROM series)
    GROUP BY measure
),
detrended AS (
    SELECT s.*, s.y - (tr.y_bar + tr.slope * (s.t - tr.t_bar)) AS trend_resid, tr.slope
    FROM series AS s JOIN trend AS tr ON tr.measure = s.measure
),
peaks AS (
    SELECT measure,
           AVG(IF(month_no = 3,  trend_resid, NULL)) AS march_effect,
           AVG(IF(month_no = 12, trend_resid, NULL)) AS december_effect
    FROM detrended
    GROUP BY measure
)
SELECT
    d.month, d.t, d.month_no, d.measure, d.y, d.slope, d.trend_resid,
    p.march_effect, p.december_effect,
    d.trend_resid - CASE d.month_no WHEN 3 THEN p.march_effect WHEN 12 THEN p.december_effect ELSE 0 END AS unexplained
FROM detrended AS d
JOIN peaks AS p ON p.measure = d.measure;

SELECT
    measure,
    ROUND(100 * (EXP(12 * ANY_VALUE(slope)) - 1), 1)                            AS trend_growth_per_year_pct,
    ROUND(100 * (EXP(ANY_VALUE(march_effect)) - 1), 1)                          AS march_vs_trend_pct,
    ROUND(100 * (EXP(ANY_VALUE(december_effect)) - 1), 1)                       AS december_vs_trend_pct,
    ROUND(100 * STDDEV_POP(y), 1)                                               AS sd_total_pct,
    ROUND(100 * STDDEV_POP(trend_resid), 1)                                     AS sd_after_trend_pct,
    ROUND(100 * STDDEV_POP(unexplained), 1)                                     AS sd_unexplained_pct,
    ROUND(100 * (1 - VAR_POP(unexplained) / VAR_POP(y)), 1)                     AS variance_planned_pct
FROM `sahyadri_b2b.rv_components`
GROUP BY measure
ORDER BY measure;

-- Split the unexplained revenue swing: ln R = ln N + ln S, so var(R) = var(N) + var(S) + 2 cov(N, S)
WITH u AS (
    SELECT month,
           MAX(IF(measure = 'Revenue', unexplained, NULL))             AS u_r,
           MAX(IF(measure = 'Orders', unexplained, NULL))              AS u_n,
           MAX(IF(measure = 'Average order value', unexplained, NULL)) AS u_s
    FROM `sahyadri_b2b.rv_components`
    GROUP BY month
)
SELECT
    ROUND(10000 * VAR_POP(u_r), 1)                                              AS var_revenue_x1e4,
    ROUND(10000 * VAR_POP(u_n), 1)                                              AS var_orders_x1e4,
    ROUND(10000 * VAR_POP(u_s), 1)                                              AS var_order_value_x1e4,
    ROUND(10000 * 2 * COVAR_POP(u_n, u_s), 1)                                   AS two_cov_x1e4,
    ROUND(100 * VAR_POP(u_n) / VAR_POP(u_r), 1)                                 AS orders_share_pct,
    ROUND(100 * VAR_POP(u_s) / VAR_POP(u_r), 1)                                 AS order_value_share_pct,
    ROUND(100 * 2 * COVAR_POP(u_n, u_s) / VAR_POP(u_r), 1)                      AS covariance_share_pct,
    ROUND(CORR(u_n, u_s), 2)                                                    AS corr_orders_order_value
FROM u;

-- -----------------------------------------------------------------------------
-- Step 3 · How much swing would remain with a perfect plan? (bootstrap)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rv_bootstrap` AS
WITH pool AS (
    SELECT yr, order_value, ROW_NUMBER() OVER (PARTITION BY yr ORDER BY order_id) AS k,
           COUNT(*) OVER (PARTITION BY yr) AS pool_size
    FROM `sahyadri_b2b.rv_orders`
),
slots AS (
    -- one slot per real order: month, calendar year and position j within the month
    SELECT month, yr, ROW_NUMBER() OVER (PARTITION BY month ORDER BY order_id) AS j
    FROM `sahyadri_b2b.rv_orders`
),
draws AS (
    SELECT b, s.month, s.yr,
           1 + MOD(MOD(MOD(b * 7919 + s.j * 104729 + (EXTRACT(YEAR FROM s.month) * 12 + EXTRACT(MONTH FROM s.month)) * 1299709, prime)
                       * MOD(b * 7919 + s.j * 104729 + (EXTRACT(YEAR FROM s.month) * 12 + EXTRACT(MONTH FROM s.month)) * 1299709, prime) + 12345, prime),
                   z.pool_size) AS k
    FROM slots AS s
    JOIN (SELECT DISTINCT yr, pool_size FROM pool) AS z ON z.yr = s.yr
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, bootstrap_reps)) AS b
)
SELECT d.b, d.month, COUNT(*) AS orders, AVG(p.order_value) AS avg_order_value
FROM draws AS d
JOIN pool AS p ON p.yr = d.yr AND p.k = d.k
GROUP BY d.b, d.month;

WITH per_month AS (
    SELECT b.month, m.orders, STDDEV_POP(LN(b.avg_order_value)) AS sd_size_noise
    FROM `sahyadri_b2b.rv_bootstrap` AS b
    JOIN `sahyadri_b2b.rv_months` AS m ON m.month = b.month
    GROUP BY b.month, m.orders
),
noise AS (
    SELECT SQRT(AVG(POW(sd_size_noise, 2)))  AS size_noise,
           SQRT(AVG(1 / orders))             AS count_noise
    FROM per_month
),
observed AS (
    SELECT measure, STDDEV_POP(unexplained) AS sd FROM `sahyadri_b2b.rv_components` GROUP BY measure
)
SELECT
    ROUND(100 * (SELECT sd FROM observed WHERE measure = 'Orders'), 1)               AS orders_unexplained_sd_pct,
    ROUND(100 * n.count_noise, 1)                                                    AS orders_random_arrival_sd_pct,
    ROUND(100 * (SELECT sd FROM observed WHERE measure = 'Average order value'), 1)  AS order_value_unexplained_sd_pct,
    ROUND(100 * n.size_noise, 1)                                                     AS order_value_random_draw_sd_pct,
    ROUND(100 * (SELECT sd FROM observed WHERE measure = 'Revenue'), 1)              AS revenue_unexplained_sd_pct,
    ROUND(100 * SQRT(POW(n.count_noise, 2) + POW(n.size_noise, 2)), 1)               AS revenue_irreducible_sd_pct
FROM noise AS n;

-- -----------------------------------------------------------------------------
-- Step 4 · The contribution of large orders
-- -----------------------------------------------------------------------------
SELECT
    m.month,
    m.orders,
    ROUND(m.revenue / 1e5, 1)                                               AS revenue_lakh,
    m.large_orders,
    ROUND(m.large_revenue / 1e5, 1)                                         AS large_revenue_lakh,
    ROUND(m.largest_order / 1e5, 1)                                         AS largest_order_lakh,
    ROUND(100 * (EXP(c.unexplained) - 1), 1)                                AS revenue_vs_plan_pct,
    ROUND(100 * (EXP(x.unexplained) - 1), 1)                                AS excl_large_vs_plan_pct
FROM `sahyadri_b2b.rv_months` AS m
JOIN `sahyadri_b2b.rv_components` AS c ON c.month = m.month AND c.measure = 'Revenue'
JOIN `sahyadri_b2b.rv_components` AS x ON x.month = m.month AND x.measure = 'Revenue excluding large orders'
ORDER BY ABS(c.unexplained) DESC
LIMIT 8;

-- How often a month's miss is mostly its large orders
WITH m AS (
    SELECT r.month,
           r.unexplained                                AS u_all,
           x.unexplained                                AS u_excl,
           mo.large_revenue / mo.revenue                AS large_share
    FROM `sahyadri_b2b.rv_components` AS r
    JOIN `sahyadri_b2b.rv_components` AS x ON x.month = r.month AND x.measure = 'Revenue excluding large orders'
    JOIN `sahyadri_b2b.rv_months` AS mo ON mo.month = r.month
    WHERE r.measure = 'Revenue'
)
SELECT
    COUNT(*)                                                                    AS months,
    ROUND(100 * MIN(large_share), 1)                                            AS min_large_share_pct,
    ROUND(100 * MAX(large_share), 1)                                            AS max_large_share_pct,
    ROUND(CORR(u_all, large_share), 2)                                          AS corr_miss_with_large_share,
    COUNTIF(ABS(u_all) > 0.15)                                                  AS months_missed_by_15pct_plus,
    COUNTIF(ABS(u_all) > 0.15 AND ABS(u_excl) <= 0.15)                          AS of_which_within_15pct_without_large
FROM m;
