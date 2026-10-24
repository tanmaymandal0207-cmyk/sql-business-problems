/* =============================================================================
   Case study · Customer momentum
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Account managers are asked every quarter which customers are "growing"
   and which are "declining", and they answer from memory. The sales head
   wants a statistical answer for every customer, and wants to know whether
   it can be trusted before using it to direct sales effort:
     1. For each customer, is monthly revenue trending up or down over the
        last 12 months, and is the trend statistically distinguishable from
        noise?
     2. Which customers are growing or declining significantly now?
     3. Back-test: did customers classed as growing or declining a year ago
        keep growing or declining in the following 12 months?
     4. Which signal predicts next year's revenue best: the trend, its
        significance, or recent revenue level?

   METHOD
     - Monthly revenue per customer, zero-filled, x = month 1..12 in the window.
     - Least-squares slope   b = COVAR_POP(x, y) / VAR_POP(x)   (Rs per month)
     - Trend % = b * 12 / mean monthly revenue: the change in monthly revenue
       over a year, as a share of the customer's average month.
     - t-statistic of the slope = r * SQRT(n - 2) / SQRT(1 - r^2), r = CORR(x, y),
       n = 12. |t| >= 2 is treated as significant (about 5 % two-sided).
     - Classes: Too few active months (< 3 months with revenue), Growing
       (t >= 2), Declining (t <= -2), No significant trend.
     - Windows: Current = Oct 2025 - Sep 2026; Back-test = Oct 2024 - Sep 2025,
       judged on revenue in the current window.

   KEY RULES
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Only customers with revenue in the window are classified in it.
   ============================================================================= */

DECLARE as_of             DATE    DEFAULT DATE '2026-09-30';
DECLARE min_active_months INT64   DEFAULT 3;
DECLARE t_threshold       FLOAT64 DEFAULT 2.0;

-- -----------------------------------------------------------------------------
-- Step 1 · Zero-filled monthly revenue per customer
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_monthly_revenue` AS
WITH monthly AS (
    SELECT
        o.customer_id,
        DATE_TRUNC(o.order_date, MONTH)                                            AS month_start,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.customer_id, month_start
),
months AS (
    SELECT month_start
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2024-01-01', DATE_TRUNC(as_of, MONTH), INTERVAL 1 MONTH)) AS month_start
),
customers AS (
    SELECT DISTINCT customer_id FROM monthly
)
SELECT
    c.customer_id,
    m.month_start,
    IFNULL(x.revenue, 0) AS revenue
FROM customers AS c
CROSS JOIN months AS m
LEFT JOIN monthly AS x ON x.customer_id = c.customer_id AND x.month_start = m.month_start;

-- -----------------------------------------------------------------------------
-- Step 2 · Trend per customer in two 12-month windows
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_momentum` AS
WITH windows AS (
    SELECT 'Back-test' AS window_name, DATE '2024-10-01' AS window_start UNION ALL
    SELECT 'Current',                  DATE '2025-10-01'
),
points AS (
    SELECT
        w.window_name,
        r.customer_id,
        DATE_DIFF(r.month_start, w.window_start, MONTH) + 1                AS x,
        r.revenue                                                          AS y
    FROM `sahyadri_b2b.customer_monthly_revenue` AS r
    JOIN windows AS w
      ON r.month_start >= w.window_start
     AND r.month_start <  DATE_ADD(w.window_start, INTERVAL 12 MONTH)
),
fitted AS (
    SELECT
        window_name,
        customer_id,
        COUNT(*)                                                           AS months,
        COUNTIF(y > 0)                                                     AS active_months,
        SUM(y)                                                             AS window_revenue,
        AVG(y)                                                             AS mean_monthly_revenue,
        SUM(IF(x <= 6, y, 0))                                              AS first_half_revenue,
        SUM(IF(x > 6, y, 0))                                               AS second_half_revenue,
        COVAR_POP(x, y) / VAR_POP(x)                                       AS slope,
        CORR(x, y)                                                         AS r
    FROM points
    GROUP BY window_name, customer_id
    HAVING SUM(y) > 0
)
SELECT
    f.*,
    f.slope * 12 / f.mean_monthly_revenue                                  AS trend_pct,
    SAFE_DIVIDE(f.r * SQRT(f.months - 2), SQRT(1 - f.r * f.r))             AS t_stat,
    CASE WHEN f.active_months < min_active_months THEN '0. Too few active months'
         WHEN SAFE_DIVIDE(f.r * SQRT(f.months - 2), SQRT(1 - f.r * f.r)) >=  t_threshold THEN '1. Growing'
         WHEN SAFE_DIVIDE(f.r * SQRT(f.months - 2), SQRT(1 - f.r * f.r)) <= -t_threshold THEN '3. Declining'
         ELSE '2. No significant trend' END                                AS momentum_class,
    IF(f.active_months >= min_active_months,
       NTILE(4) OVER (PARTITION BY f.window_name, f.active_months >= min_active_months
                      ORDER BY f.slope * 12 / f.mean_monthly_revenue, f.customer_id), NULL) AS trend_quartile
FROM fitted AS f;

-- -----------------------------------------------------------------------------
-- Step 3 · Current momentum classes
-- -----------------------------------------------------------------------------
SELECT
    momentum_class,
    COUNT(*)                                                               AS customers,
    ROUND(SUM(window_revenue), 0)                                          AS revenue_12m,
    ROUND(100 * SUM(window_revenue) / SUM(SUM(window_revenue)) OVER (), 1) AS revenue_pct,
    ROUND(100 * APPROX_QUANTILES(trend_pct, 2)[OFFSET(1)], 1)              AS median_trend_pct
FROM `sahyadri_b2b.customer_momentum`
WHERE window_name = 'Current'
GROUP BY momentum_class
ORDER BY momentum_class;

-- How often is a trend significant? Distribution of t among eligible customers
SELECT
    CASE WHEN t_stat <= -2 THEN '1. t <= -2'
         WHEN t_stat <  -1 THEN '2. -2 < t < -1'
         WHEN t_stat <=  1 THEN '3. -1 <= t <= 1'
         WHEN t_stat <   2 THEN '4. 1 < t < 2'
         ELSE                   '5. t >= 2' END                            AS t_band,
    COUNT(*)                                                               AS customers,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                       AS customers_pct
FROM `sahyadri_b2b.customer_momentum`
WHERE window_name = 'Current' AND active_months >= min_active_months
GROUP BY t_band
ORDER BY t_band;

-- -----------------------------------------------------------------------------
-- Step 4 · Current lists: significant growers and decliners
-- -----------------------------------------------------------------------------
SELECT
    m.momentum_class,
    m.customer_id,
    c.customer_name,
    c.customer_segment,
    m.active_months,
    ROUND(m.window_revenue, 0)                                             AS revenue_12m,
    ROUND(m.first_half_revenue, 0)                                         AS oct_mar_revenue,
    ROUND(m.second_half_revenue, 0)                                        AS apr_sep_revenue,
    ROUND(m.slope, 0)                                                      AS slope_rs_per_month,
    ROUND(100 * m.trend_pct, 0)                                            AS trend_pct,
    ROUND(m.t_stat, 2)                                                     AS t_stat
FROM `sahyadri_b2b.customer_momentum` AS m
JOIN `sahyadri_b2b.customers`         AS c ON c.customer_id = m.customer_id
WHERE m.window_name = 'Current'
  AND m.momentum_class IN ('1. Growing', '3. Declining')
ORDER BY m.momentum_class, ABS(m.slope) DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Back-test: what happened next to last year's classes and quartiles?
-- -----------------------------------------------------------------------------
WITH bt AS (
    SELECT
        b.customer_id,
        b.momentum_class,
        b.trend_quartile,
        b.window_revenue                                                   AS backtest_revenue,
        IFNULL(c.window_revenue, 0)                                        AS next_12m_revenue
    FROM `sahyadri_b2b.customer_momentum` AS b
    LEFT JOIN `sahyadri_b2b.customer_momentum` AS c
      ON c.customer_id = b.customer_id AND c.window_name = 'Current'
    WHERE b.window_name = 'Back-test'
)
SELECT
    'Class' AS grouping, momentum_class AS group_value,
    COUNT(*)                                                               AS customers,
    ROUND(SUM(backtest_revenue), 0)                                        AS revenue_oct24_sep25,
    ROUND(SUM(next_12m_revenue), 0)                                        AS revenue_oct25_sep26,
    ROUND(100 * (SUM(next_12m_revenue) / SUM(backtest_revenue) - 1), 1)    AS change_pct,
    ROUND(100 * AVG(IF(next_12m_revenue < backtest_revenue, 1, 0)), 1)     AS customers_down_pct,
    ROUND(100 * AVG(IF(next_12m_revenue = 0, 1, 0)), 1)                    AS customers_lost_pct
FROM bt
GROUP BY momentum_class
UNION ALL
SELECT
    'Trend quartile', CONCAT('Q', CAST(trend_quartile AS STRING)),
    COUNT(*),
    ROUND(SUM(backtest_revenue), 0),
    ROUND(SUM(next_12m_revenue), 0),
    ROUND(100 * (SUM(next_12m_revenue) / SUM(backtest_revenue) - 1), 1),
    ROUND(100 * AVG(IF(next_12m_revenue < backtest_revenue, 1, 0)), 1),
    ROUND(100 * AVG(IF(next_12m_revenue = 0, 1, 0)), 1)
FROM bt
WHERE trend_quartile IS NOT NULL
GROUP BY trend_quartile
ORDER BY grouping, group_value;

-- -----------------------------------------------------------------------------
-- Step 6 · Which signal predicts next year best? Rank (Spearman) correlations
-- -----------------------------------------------------------------------------
WITH bt AS (
    SELECT
        b.customer_id,
        b.t_stat,
        b.trend_pct,
        b.second_half_revenue / b.window_revenue                           AS second_half_share,
        b.second_half_revenue,
        IFNULL(c.window_revenue, 0)                                        AS next_12m_revenue,
        IFNULL(c.window_revenue, 0) / b.window_revenue                     AS growth_ratio
    FROM `sahyadri_b2b.customer_momentum` AS b
    LEFT JOIN `sahyadri_b2b.customer_momentum` AS c
      ON c.customer_id = b.customer_id AND c.window_name = 'Current'
    WHERE b.window_name = 'Back-test' AND b.active_months >= min_active_months
),
ranked AS (
    SELECT
        RANK() OVER (ORDER BY t_stat)              AS rk_t,
        RANK() OVER (ORDER BY trend_pct)           AS rk_trend,
        RANK() OVER (ORDER BY second_half_share)   AS rk_h2_share,
        RANK() OVER (ORDER BY second_half_revenue) AS rk_h2_revenue,
        RANK() OVER (ORDER BY growth_ratio)        AS rk_growth,
        RANK() OVER (ORDER BY next_12m_revenue)    AS rk_next
    FROM bt
)
SELECT 'Trend t-statistic -> next-year growth'     AS signal_and_target, COUNT(*) AS customers, ROUND(CORR(rk_t, rk_growth), 3)          AS spearman_rho FROM ranked
UNION ALL
SELECT 'Trend % -> next-year growth',              COUNT(*), ROUND(CORR(rk_trend, rk_growth), 3)      FROM ranked
UNION ALL
SELECT 'Second-half share -> next-year growth',    COUNT(*), ROUND(CORR(rk_h2_share, rk_growth), 3)   FROM ranked
UNION ALL
SELECT 'Second-half revenue -> next-year revenue', COUNT(*), ROUND(CORR(rk_h2_revenue, rk_next), 3)   FROM ranked
ORDER BY spearman_rho DESC;
