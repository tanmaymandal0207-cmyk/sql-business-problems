/* =============================================================================
   Case study · Revenue volatility — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE start_month     DATE    DEFAULT DATE '2024-01-01';
DECLARE end_month       DATE    DEFAULT DATE '2026-09-01';
DECLARE large_order     FLOAT64 DEFAULT 500000;
DECLARE bootstrap_reps  INT64   DEFAULT 300;

WITH o AS (SELECT * FROM `sahyadri_b2b.rv_orders`),
     m AS (SELECT * FROM `sahyadri_b2b.rv_months`),
     c AS (SELECT * FROM `sahyadri_b2b.rv_components`),
     b AS (SELECT * FROM `sahyadri_b2b.rv_bootstrap`),

src AS (
    SELECT x.order_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned')
      AND x.order_date >= start_month AND x.order_date < DATE_ADD(end_month, INTERVAL 1 MONTH)
    GROUP BY x.order_id
),
month_recount AS (
    SELECT month, COUNT(*) AS n, SUM(order_value) AS r, COUNTIF(is_large) AS nl, SUM(IF(is_large, order_value, 0)) AS rl
    FROM o GROUP BY month
),
wide AS (
    SELECT month,
           MAX(IF(measure = 'Revenue', y, NULL)) AS y_r, MAX(IF(measure = 'Orders', y, NULL)) AS y_n,
           MAX(IF(measure = 'Average order value', y, NULL)) AS y_s,
           MAX(IF(measure = 'Revenue', unexplained, NULL)) AS u_r, MAX(IF(measure = 'Orders', unexplained, NULL)) AS u_n,
           MAX(IF(measure = 'Average order value', unexplained, NULL)) AS u_s
    FROM c GROUP BY month
),
slopes AS (
    SELECT measure, ANY_VALUE(slope) AS slope, COVAR_POP(t, y) / VAR_POP(t) AS slope_recount FROM c GROUP BY measure
),
year_range AS (
    SELECT yr, MIN(order_value) AS lo, MAX(order_value) AS hi FROM o GROUP BY yr
),

checks AS (
    SELECT '01. One row per valid order in range, order value = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT COUNT(*) FROM src))
         + (SELECT COUNTIF(ABS(o.order_value - s.v) > 0.01) FROM o JOIN src AS s USING (order_id)) AS actual
    UNION ALL
    SELECT '02. 33 months, totals = order recount, large + other = revenue', 0,
           ABS(33 - (SELECT COUNT(*) FROM m))
         + (SELECT COUNTIF(m.orders != r.n OR ABS(m.revenue - r.r) > 0.01 OR m.large_orders != r.nl
                           OR ABS(m.large_revenue + m.revenue_excl_large - m.revenue) > 0.01)
              FROM m JOIN month_recount AS r USING (month))
    UNION ALL
    SELECT '03. ln revenue = ln orders + ln order value, before and after the plan', 0,
           (SELECT COUNTIF(ABS(y_r - y_n - y_s) > 1e-9 OR ABS(u_r - u_n - u_s) > 1e-9) FROM wide)
    UNION ALL
    SELECT '04. Trend slope = COVAR_POP(t, y) / VAR_POP(t)', 0,
           (SELECT COUNTIF(ABS(slope - slope_recount) > 1e-12) FROM slopes) + ABS(4 - (SELECT COUNT(*) FROM slopes))
    UNION ALL
    SELECT '05. Trend residuals average zero for every measure', 0,
           (SELECT COUNTIF(ABS(avg_resid) > 1e-9) FROM (SELECT measure, AVG(trend_resid) AS avg_resid FROM c GROUP BY measure))
    UNION ALL
    SELECT '06. March and December effects = average trend residual, unexplained averages zero there', 0,
           (SELECT COUNTIF(ABS(eff - period_effect) > 1e-12 OR ABS(avg_u) > 1e-9)
              FROM (SELECT measure, month_no, AVG(trend_resid) AS eff, AVG(unexplained) AS avg_u,
                           IF(month_no = 3, ANY_VALUE(march_effect), ANY_VALUE(december_effect)) AS period_effect
                      FROM c WHERE month_no IN (3, 12) GROUP BY measure, month_no))
    UNION ALL
    SELECT '07. 300 bootstrap draws per month, each with the real number of orders', 0,
           (SELECT COUNTIF(reps != bootstrap_reps) FROM (SELECT month, COUNT(DISTINCT b) AS reps FROM b GROUP BY month))
         + (SELECT COUNT(*) FROM b JOIN m USING (month) WHERE b.orders != m.orders)
         + ABS(33 - (SELECT COUNT(DISTINCT month) FROM b))
    UNION ALL
    SELECT '08. Bootstrap averages lie within the same year''s order values', 0,
           (SELECT COUNTIF(b.avg_order_value < y.lo - 0.01 OR b.avg_order_value > y.hi + 0.01)
              FROM b JOIN year_range AS y ON y.yr = EXTRACT(YEAR FROM b.month))
    UNION ALL
    SELECT '09. Large-order flag = order value of Rs 5 lakh or more', 0,
           (SELECT COUNTIF(is_large != (order_value >= large_order)) FROM o)
    UNION ALL
    SELECT '10. Revenue swing variance = orders + order value + 2 x covariance', 0,
           (SELECT IF(ABS(VAR_POP(u_r) - (VAR_POP(u_n) + VAR_POP(u_s) + 2 * COVAR_POP(u_n, u_s))) > 1e-12, 1, 0) FROM wide)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
