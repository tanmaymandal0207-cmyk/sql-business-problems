/* =============================================================================
   Case study · Customer momentum — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE min_active_months INT64   DEFAULT 3;
DECLARE t_threshold       FLOAT64 DEFAULT 2.0;

WITH g AS (SELECT * FROM `sahyadri_b2b.customer_monthly_revenue`),
     m AS (SELECT * FROM `sahyadri_b2b.customer_momentum`),

source_lines AS (
    SELECT o.customer_id, o.order_date,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
window_source AS (
    SELECT 'Back-test' AS window_name, customer_id, SUM(revenue) AS revenue
    FROM source_lines WHERE order_date >= DATE '2024-10-01' AND order_date < DATE '2025-10-01'
    GROUP BY customer_id
    UNION ALL
    SELECT 'Current', customer_id, SUM(revenue)
    FROM source_lines WHERE order_date >= DATE '2025-10-01' AND order_date < DATE '2026-10-01'
    GROUP BY customer_id
),
-- slope and t recomputed from first principles: sums of squares and residuals
points AS (
    SELECT IF(g.month_start >= DATE '2025-10-01', 'Current', 'Back-test') AS window_name,
           g.customer_id,
           DATE_DIFF(g.month_start, IF(g.month_start >= DATE '2025-10-01', DATE '2025-10-01', DATE '2024-10-01'), MONTH) + 1 AS x,
           g.revenue AS y
    FROM g
    WHERE g.month_start >= DATE '2024-10-01'
),
means AS (
    SELECT window_name, customer_id, AVG(x) AS mx, AVG(y) AS my, COUNT(*) AS n
    FROM points GROUP BY window_name, customer_id
),
ols AS (
    SELECT p.window_name, p.customer_id,
           SUM((p.x - e.mx) * (p.y - e.my)) / SUM(POW(p.x - e.mx, 2)) AS b,
           ANY_VALUE(e.n) AS n, ANY_VALUE(e.mx) AS mx, ANY_VALUE(e.my) AS my,
           SUM(POW(p.x - e.mx, 2)) AS sxx
    FROM points AS p JOIN means AS e USING (window_name, customer_id)
    GROUP BY p.window_name, p.customer_id
),
residuals AS (
    SELECT o.window_name, o.customer_id, o.b,
           SAFE_DIVIDE(o.b, SQRT(SUM(POW(p.y - (o.my + o.b * (p.x - o.mx)), 2)) / (o.n - 2) / o.sxx)) AS t
    FROM ols AS o JOIN points AS p USING (window_name, customer_id)
    GROUP BY o.window_name, o.customer_id, o.b, o.n, o.sxx
),
quartile_bounds AS (
    SELECT window_name, trend_quartile, MIN(trend_pct) AS lo, MAX(trend_pct) AS hi, COUNT(*) AS n
    FROM m WHERE trend_quartile IS NOT NULL
    GROUP BY window_name, trend_quartile
),

checks AS (
    SELECT '01. Monthly grid: one row per customer and month, 33 months each' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(month_start AS STRING))) FROM g)
         + (SELECT COUNT(*) FROM (SELECT customer_id FROM g GROUP BY customer_id HAVING COUNT(*) != 33)) AS actual
    UNION ALL
    SELECT '02. Monthly grid revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM g) - (SELECT SUM(revenue) FROM source_lines), 0) AS INT64)
    UNION ALL
    SELECT '03. Window customers vs source customers with revenue', 0,
           ABS((SELECT COUNT(*) FROM m) - (SELECT COUNT(*) FROM window_source WHERE revenue > 0))
         + (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(window_name, '|', CAST(customer_id AS STRING))) FROM m)
    UNION ALL
    SELECT '04. Window revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(window_revenue) FROM m) - (SELECT SUM(revenue) FROM window_source WHERE revenue > 0), 0) AS INT64)
    UNION ALL
    SELECT '05. Slope vs sum-of-squares recomputation', 0,
           (SELECT COUNTIF(ABS(m.slope - o.b) > 1e-6 * GREATEST(1, ABS(o.b)))
              FROM m JOIN ols AS o USING (window_name, customer_id))
    UNION ALL
    SELECT '06. t-statistic vs residual-based standard error', 0,
           (SELECT COUNTIF(ABS(m.t_stat - r.t) > 1e-6 * GREATEST(1, ABS(r.t)))
              FROM m JOIN residuals AS r USING (window_name, customer_id)
             WHERE m.t_stat IS NOT NULL)
    UNION ALL
    SELECT '07. Every window has 12 months, halves add to window revenue', 0,
           (SELECT COUNTIF(months != 12 OR ABS(first_half_revenue + second_half_revenue - window_revenue) > 0.01) FROM m)
    UNION ALL
    SELECT '08. Momentum class inconsistent with thresholds', 0,
           (SELECT COUNTIF(momentum_class != CASE WHEN active_months < min_active_months THEN '0. Too few active months'
                                                  WHEN t_stat >=  t_threshold THEN '1. Growing'
                                                  WHEN t_stat <= -t_threshold THEN '3. Declining'
                                                  ELSE '2. No significant trend' END) FROM m)
    UNION ALL
    SELECT '09. Trend quartiles unbalanced or overlapping', 0,
           (SELECT COUNT(*) FROM quartile_bounds AS a JOIN quartile_bounds AS b
              ON b.window_name = a.window_name AND b.trend_quartile = a.trend_quartile + 1
             WHERE a.hi > b.lo OR ABS(a.n - b.n) > 1)
    UNION ALL
    SELECT '10. Active months vs recount of months with revenue', 0,
           (SELECT COUNTIF(m.active_months != x.k) FROM m
              JOIN (SELECT window_name, customer_id, COUNTIF(y > 0) AS k FROM points GROUP BY window_name, customer_id) AS x
             USING (window_name, customer_id))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
