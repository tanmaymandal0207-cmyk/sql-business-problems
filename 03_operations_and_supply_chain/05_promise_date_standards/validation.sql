/* =============================================================================
   Case study · City-wise delivery promise standards — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE train_end       DATE  DEFAULT DATE '2025-12-31';
DECLARE min_city_orders INT64 DEFAULT 20;

WITH s AS (SELECT * FROM `sahyadri_b2b.city_promise_standards`),
     dp AS (SELECT * FROM `sahyadri_b2b.delivery_performance`),
     training AS (SELECT * FROM dp WHERE order_date <= train_end),
     test AS (SELECT * FROM dp WHERE order_date > train_end),

checks AS (
    SELECT '01. Duplicate cities in the standards table' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT delivery_city) FROM s) AS actual
    UNION ALL
    SELECT '02. Training cities missing from the standards table', 0,
           (SELECT COUNT(DISTINCT delivery_city) FROM training) - (SELECT COUNT(*) FROM s)
    UNION ALL
    SELECT '03. Training orders vs source', 0,
           (SELECT SUM(training_orders) FROM s) - (SELECT COUNT(*) FROM training)
    UNION ALL
    SELECT '04. Standards out of order (p50 <= p80 <= p85 <= p90)', 0,
           (SELECT COUNTIF(NOT (lead_p50 <= standard_p80 AND standard_p80 <= standard_p85
                                AND standard_p85 <= standard_p90)) FROM s)
    UNION ALL
    SELECT '05. Standards that are not whole days or below 1', 0,
           (SELECT COUNTIF(standard_p85 <> TRUNC(standard_p85) OR standard_p85 < 1) FROM s)
    UNION ALL
    SELECT '06. Fallback cities with differing standards', 0,
           (SELECT COUNT(DISTINCT standard_p85) - 1 FROM s WHERE NOT uses_city_standard)
    UNION ALL
    SELECT '07. Flag inconsistent with training order count', 0,
           (SELECT COUNTIF(uses_city_standard <> (training_orders >= min_city_orders)) FROM s)
    UNION ALL
    -- by construction, each city standard covers at least 85 % of its own training orders
    SELECT '08. City standards covering under 85 % of their training orders', 0,
           (SELECT COUNT(*) FROM (
                SELECT t.delivery_city
                FROM training AS t
                JOIN s ON s.delivery_city = t.delivery_city
                WHERE s.uses_city_standard
                GROUP BY t.delivery_city, s.standard_p85
                HAVING COUNTIF(t.actual_lead_days <= s.standard_p85) / COUNT(*) < 0.85))
    UNION ALL
    SELECT '09. Test orders without a standard', 0,
           (SELECT COUNT(*) FROM test AS t
             WHERE NOT EXISTS (SELECT 1 FROM s WHERE s.delivery_city = t.delivery_city))
    UNION ALL
    SELECT '10. Test period has orders (dependency table present)', 1,
           (SELECT IF(COUNT(*) > 0, 1, 0) FROM test)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
