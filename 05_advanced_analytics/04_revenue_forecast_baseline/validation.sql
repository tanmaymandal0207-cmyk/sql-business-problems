/* =============================================================================
   Case study · Baseline revenue forecast — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE history_start  DATE DEFAULT DATE '2024-01-01';
DECLARE last_actual    DATE DEFAULT DATE '2026-09-01';
DECLARE backtest_start DATE DEFAULT DATE '2026-01-01';

WITH m AS (SELECT * FROM `sahyadri_b2b.monthly_revenue`),
     f AS (SELECT * FROM `sahyadri_b2b.monthly_forecasts`),

checks AS (
    SELECT '01. Duplicate months in the revenue table' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT month_start) FROM m) AS actual
    UNION ALL
    SELECT '02. Months in spine (Jan 2024 - Dec 2026 = 36)', 36,
           (SELECT COUNT(*) FROM m)
    UNION ALL
    SELECT '03. Actual revenue vs in-scope line items (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM m)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i
                         JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
                        WHERE o.order_status NOT IN ('Cancelled', 'Returned')), 0) AS INT64)
    UNION ALL
    SELECT '04. Future months with an actual value', 0,
           (SELECT COUNTIF(month_start > last_actual AND revenue IS NOT NULL) FROM m)
    UNION ALL
    SELECT '05. Historical months without an actual value', 0,
           (SELECT COUNTIF(month_start <= last_actual AND revenue IS NULL) FROM m)
    UNION ALL
    -- no look-ahead: recompute the Jan 2026 12-month average from 2025 actuals only
    SELECT '06. Jan 2026 12-month average vs 2025 actuals (rupees, rounded)', 0,
           CAST(ROUND((SELECT avg_12m FROM f WHERE month_start = DATE '2026-01-01')
                    - (SELECT AVG(revenue) FROM m
                        WHERE month_start BETWEEN DATE '2025-01-01' AND DATE '2025-12-01'), 0) AS INT64)
    UNION ALL
    -- seasonal x growth for Jan 2026 recomputed by hand
    SELECT '07. Jan 2026 seasonal x growth recomputed (rupees, rounded)', 0,
           CAST(ROUND((SELECT seasonal_growth FROM f WHERE month_start = DATE '2026-01-01')
                    - (SELECT revenue FROM m WHERE month_start = DATE '2025-01-01')
                      * (SELECT SUM(revenue) FROM m WHERE month_start BETWEEN DATE '2025-01-01' AND DATE '2025-12-01')
                      / (SELECT SUM(revenue) FROM m WHERE month_start BETWEEN DATE '2024-01-01' AND DATE '2024-12-01'), 0) AS INT64)
    UNION ALL
    SELECT '08. Backtest months with a missing forecast', 0,
           (SELECT COUNTIF(last_month IS NULL OR avg_3m IS NULL OR avg_12m IS NULL
                        OR seasonal_growth IS NULL OR blend IS NULL)
            FROM f WHERE month_start BETWEEN backtest_start AND last_actual)
    UNION ALL
    SELECT '09. Future months forecast (Oct-Dec 2026 = 3)', 3,
           (SELECT COUNTIF(month_start > last_actual AND blend IS NOT NULL) FROM f)
    UNION ALL
    SELECT '10. Blend not equal to average of its two inputs', 0,
           (SELECT COUNTIF(ABS(blend - (avg_12m + seasonal_growth) / 2) > 0.01) FROM f)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
