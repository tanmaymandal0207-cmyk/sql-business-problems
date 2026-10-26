/* =============================================================================
   Case study · Order splitting test — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE band FLOAT64 DEFAULT 0.05;

WITH o AS (SELECT * FROM `sahyadri_b2b.split_test_orders`),
     b AS (SELECT * FROM `sahyadri_b2b.split_test_bunching`),

source_values AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id
),
groups AS (
    SELECT customer_id, order_date, COUNT(*) AS n, SUM(order_value) AS total
    FROM o GROUP BY customer_id, order_date
),
day_shares AS (
    SELECT COUNT(*) / SUM(COUNT(*)) OVER () AS p FROM o GROUP BY order_date
),

checks AS (
    SELECT '01. Orders vs source sales orders, one row each' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM o) - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders`)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM o) AS actual
    UNION ALL
    SELECT '02. Order values vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(order_value) FROM o) - (SELECT SUM(v) FROM source_values), 0) AS INT64)
    UNION ALL
    SELECT '03. Same-day order counts vs GROUP BY recount', 0,
           (SELECT COUNTIF(o.orders_same_day != g.n) FROM o JOIN groups AS g USING (customer_id, order_date))
    UNION ALL
    SELECT '04. Same-day totals vs GROUP BY recount (rupees, rounded)', 0,
           (SELECT COUNTIF(ABS(o.value_same_day - g.total) > 0.01) FROM o JOIN groups AS g USING (customer_id, order_date))
    UNION ALL
    SELECT '05. Same-day groups with 2+ orders', 506,
           (SELECT COUNTIF(n > 1) FROM groups)
    UNION ALL
    SELECT '06. Rs 1 lakh bunching counts vs independent recount', 0,
           (SELECT ABS(b.just_below - x.below) + ABS(b.just_above - x.above) FROM b
              CROSS JOIN (SELECT COUNTIF(order_value >= 95000 AND order_value < 100000) AS below,
                                 COUNTIF(order_value >= 100000 AND order_value < 105000) AS above FROM o) AS x
             WHERE b.point_type = 'Threshold' AND b.t = 100000)
    UNION ALL
    SELECT '07. Control points within 10 % of a threshold', 0,
           (SELECT COUNT(*) FROM b AS c
              CROSS JOIN UNNEST([25000.0, 50000.0, 100000.0, 200000.0, 500000.0]) AS h
             WHERE c.point_type = 'Control' AND ABS(c.t / h - 1) < 0.10)
    UNION ALL
    SELECT '08. Daily order shares sum to 1 (x 1,000,000, rounded)', 0,
           CAST(ROUND(1e6 * ((SELECT SUM(p) FROM day_shares) - 1)) AS INT64)
    UNION ALL
    SELECT '09. Five thresholds tested', 5,
           (SELECT COUNTIF(point_type = 'Threshold') FROM b)
    UNION ALL
    SELECT '10. Bunching ratios positive and log ratio consistent', 0,
           (SELECT COUNTIF(just_below <= 0 OR just_above <= 0 OR ABS(log_ratio - LN(just_below / just_above)) > 1e-12) FROM b)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
