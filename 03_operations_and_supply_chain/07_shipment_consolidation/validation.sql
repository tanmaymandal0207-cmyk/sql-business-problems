/* =============================================================================
   Case study · Shipment consolidation opportunity — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start DATE DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE DEFAULT DATE '2026-09-30';

WITH b AS (SELECT * FROM `sahyadri_b2b.shipment_consolidation_base`),
     c AS (SELECT * FROM `sahyadri_b2b.consolidation_scenarios`),
     m AS (SELECT * FROM `sahyadri_b2b.freight_cost_model`),

src AS (
    SELECT * FROM `sahyadri_b2b.shipments`
    WHERE shipment_date BETWEEN window_start AND window_end AND shipping_cost IS NOT NULL
),
dispatches AS (
    SELECT schedule, COUNT(*) AS n, SUM(shipments) AS shipments
    FROM c GROUP BY schedule
),
-- least-squares slope recomputed with the sums formula
pairs AS (
    SELECT s.shipping_cost AS y, v.order_value AS x
    FROM (SELECT order_id, ANY_VALUE(shipping_cost) AS shipping_cost
            FROM `sahyadri_b2b.shipments`
           WHERE shipment_date BETWEEN window_start AND window_end
           GROUP BY order_id
          HAVING COUNT(*) = 1 AND COUNT(shipping_cost) = 1) AS s
    JOIN (SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
            FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id) AS v
      ON v.order_id = s.order_id
),
ols AS (
    SELECT
        COUNT(*) AS n,
        (COUNT(*) * SUM(x * y) - SUM(x) * SUM(y)) / (COUNT(*) * SUM(x * x) - SUM(x) * SUM(x)) AS slope,
        AVG(y) AS mean_y,
        AVG(x) AS mean_x
    FROM pairs
),
spans AS (
    SELECT
        MAX(IF(schedule = '2. Every 2 days', span, 0)) AS max_2day,
        MAX(IF(schedule = '3. Twice weekly', span, 0)) AS max_twice,
        MAX(IF(schedule = '4. Weekly',       span, 0)) AS max_weekly
    FROM (
        SELECT '2. Every 2 days' AS schedule, DATE_DIFF(MAX(shipment_date), MIN(shipment_date), DAY) AS span
        FROM b GROUP BY customer_id, city_key, bucket_2day
        UNION ALL
        SELECT '3. Twice weekly', DATE_DIFF(MAX(shipment_date), MIN(shipment_date), DAY)
        FROM b GROUP BY customer_id, city_key, bucket_twice_weekly
        UNION ALL
        SELECT '4. Weekly', DATE_DIFF(MAX(shipment_date), MIN(shipment_date), DAY)
        FROM b GROUP BY customer_id, city_key, bucket_weekly
    )
),

checks AS (
    SELECT '01. Duplicate shipments in base' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT shipment_id) FROM b) AS actual
    UNION ALL
    SELECT '02. Base shipments vs source', 0,
           (SELECT COUNT(*) FROM b) - (SELECT COUNT(*) FROM src)
    UNION ALL
    SELECT '03. Base freight vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(shipping_cost) FROM b) - (SELECT SUM(shipping_cost) FROM src), 0) AS INT64)
    UNION ALL
    SELECT '04. Schedules that do not cover every shipment once', 0,
           (SELECT COUNTIF(shipments <> (SELECT COUNT(*) FROM b)) FROM dispatches)
         + (4 - (SELECT COUNT(*) FROM dispatches))
    UNION ALL
    SELECT '05. Coarser schedules need more dispatches than finer ones', 0,
           (SELECT IF(MAX(IF(schedule LIKE '1.%', n, NULL)) >= MAX(IF(schedule LIKE '2.%', n, NULL))
                  AND MAX(IF(schedule LIKE '1.%', n, NULL)) >= MAX(IF(schedule LIKE '3.%', n, NULL))
                  AND MAX(IF(schedule LIKE '3.%', n, NULL)) >= MAX(IF(schedule LIKE '4.%', n, NULL)), 0, 1)
              FROM dispatches)
    UNION ALL
    SELECT '06. Negative wait, or any wait under the daily baseline', 0,
           (SELECT COUNTIF(added_wait_days < 0 OR (schedule LIKE '1.%' AND added_wait_days <> 0)) FROM c)
    UNION ALL
    SELECT '07. Buckets longer than their schedule allows (1, 3, 6 days)', 0,
           (SELECT IF(max_2day <= 1 AND max_twice <= 3 AND max_weekly <= 6, 0, 1) FROM spans)
    UNION ALL
    SELECT '08. Freight model slope or intercept vs sums formula', 0,
           (SELECT IF(ABS(m.rate_per_rupee - o.slope) < 1e-9
                  AND ABS(m.fixed_cost_per_shipment - ROUND(o.mean_y - o.slope * o.mean_x, 2)) < 0.01, 0, 1)
              FROM m CROSS JOIN ols AS o)
    UNION ALL
    -- independent rule: Monday-Wednesday are days 0-2 after the ISO week start
    SELECT '09. Twice-weekly half-week inconsistent with the date', 0,
           (SELECT COUNTIF(ENDS_WITH(bucket_twice_weekly, '|A')
                           <> (DATE_DIFF(shipment_date, DATE_TRUNC(shipment_date, ISOWEEK), DAY) <= 2)) FROM b)
    UNION ALL
    SELECT '10. Orders used in the freight model vs independent count', 0,
           (SELECT orders_used FROM m) - (SELECT n FROM ols)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
