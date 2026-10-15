/* =============================================================================
   Case study · Late delivery root cause — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql (which saves sahyadri_b2b.city_name_map and
   sahyadri_b2b.delivery_performance). Every row should return status = 'PASS'.
   ============================================================================= */

WITH dp AS (
    SELECT * FROM `sahyadri_b2b.delivery_performance`
),

shipments_std AS (
    SELECT
        s.order_id,
        LOWER(TRIM(s.shipping_city))                               AS raw_key,
        COALESCE(m.standard_city, INITCAP(TRIM(s.shipping_city)))  AS std_city
    FROM `sahyadri_b2b.shipments`          AS s
    LEFT JOIN `sahyadri_b2b.city_name_map` AS m
        ON m.raw_city_key = LOWER(TRIM(s.shipping_city))
),

order_dates AS (
    SELECT
        order_id,
        MAX(delivery_date) AS final_delivery_date,
        MIN(shipment_date) AS first_shipment_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),

-- every Delivered order lands in exactly one bucket
scope_bridge AS (
    SELECT
        CASE
            WHEN o.promised_delivery_date IS NULL       THEN 'Excluded: no promised date'
            WHEN d.order_id IS NULL                     THEN 'Excluded: no shipment record'
            WHEN d.final_delivery_date IS NULL          THEN 'Excluded: no delivery date'
            WHEN d.first_shipment_date < o.order_date   THEN 'Excluded: shipped before order date'
            ELSE 'In scope'
        END AS scope_bucket
    FROM `sahyadri_b2b.sales_orders` AS o
    LEFT JOIN order_dates AS d
        ON d.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
),

checks AS (
    SELECT '01. Rows minus distinct orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM dp) AS actual
    UNION ALL
    SELECT '02. In-scope bucket vs delivery_performance rows', 0,
           (SELECT COUNTIF(scope_bucket = 'In scope') FROM scope_bridge) - (SELECT COUNT(*) FROM dp)
    UNION ALL
    SELECT '03. Standard city names differing only by case/space', 0,
           (SELECT COUNT(DISTINCT std_city) - COUNT(DISTINCT LOWER(TRIM(std_city))) FROM shipments_std)
    UNION ALL
    SELECT '04. Orders shipped to more than one standard city', 0,
           (SELECT COUNT(*) FROM (SELECT order_id FROM shipments_std
                                  GROUP BY order_id HAVING COUNT(DISTINCT std_city) > 1))
    UNION ALL
    SELECT '05. Mapping rows that match no shipment', 0,
           (SELECT COUNT(*) FROM `sahyadri_b2b.city_name_map` AS m
              WHERE NOT EXISTS (SELECT 1 FROM shipments_std AS s WHERE s.raw_key = m.raw_city_key))
    UNION ALL
    SELECT '06. Days late <> dispatch + transit + promise components', 0,
           (SELECT COUNTIF(ABS(days_late - (dispatch_excess + transit_excess + promise_shortfall)) > 0.000001) FROM dp)
    UNION ALL
    SELECT '07. Days late <> delivery date - promised date', 0,
           (SELECT COUNTIF(days_late <> DATE_DIFF(final_delivery_date, promised_delivery_date, DAY)) FROM dp)
    UNION ALL
    SELECT '08. Late orders without a cause, or on-time orders with one', 0,
           (SELECT COUNTIF((is_late AND primary_cause IS NULL) OR (NOT is_late AND primary_cause IS NOT NULL)) FROM dp)
    UNION ALL
    SELECT '09. Negative dispatch or transit days', 0,
           (SELECT COUNTIF(dispatch_days < 0 OR transit_days < 0) FROM dp)
    UNION ALL
    SELECT '10. Primary cause is not the largest component', 0,
           (SELECT COUNTIF(
                CASE primary_cause
                    WHEN 'Dispatch delay' THEN dispatch_excess
                    WHEN 'Transit delay'  THEN transit_excess
                    ELSE promise_shortfall
                END < GREATEST(dispatch_excess, transit_excess, promise_shortfall))
            FROM dp WHERE is_late)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;

/* Informational (not pass/fail): how Delivered orders map to the analysis scope
SELECT scope_bucket, COUNT(*) AS orders
FROM scope_bridge
GROUP BY scope_bucket
ORDER BY orders DESC;
*/
