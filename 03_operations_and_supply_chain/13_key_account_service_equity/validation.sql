/* =============================================================================
   Case study · Key-account service equity — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE standard_pct FLOAT64 DEFAULT 0.8;

WITH s AS (SELECT * FROM `sahyadri_b2b.sq_orders`),

eligible AS (
    SELECT o.order_id
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN (SELECT order_id, COUNT(*) AS n, COUNT(delivery_date) AS d FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS x
      ON x.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND o.promised_delivery_date IS NOT NULL AND x.n = x.d
),
dates AS (
    SELECT order_id, MIN(shipment_date) AS f, MAX(delivery_date) AS l FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
first_ship AS (
    SELECT order_id, INITCAP(TRIM(shipping_city)) AS c
    FROM `sahyadri_b2b.shipments`
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY shipment_date, shipment_id) = 1
),
city_share AS (
    SELECT city, COUNTIF(lead_time <= city_standard) AS within, COUNT(*) AS n FROM s GROUP BY city
),
tier_sizes AS (
    SELECT revenue_tier, COUNT(DISTINCT customer_id) AS customers FROM s GROUP BY revenue_tier
),
tier_value AS (
    SELECT customer_id, ANY_VALUE(revenue_tier) AS tier, SUM(order_value) AS v FROM s GROUP BY customer_id
),

checks AS (
    SELECT '01. One row per eligible delivered order' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM s) - (SELECT COUNT(*) FROM eligible)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM s) AS actual
    UNION ALL
    SELECT '02. Dispatch, transit and lead time recomputed from shipments', 0,
           (SELECT COUNT(*) FROM s JOIN dates AS d USING (order_id)
             WHERE s.dispatch_days != DATE_DIFF(d.f, s.order_date, DAY)
                OR s.lead_time != DATE_DIFF(d.l, s.order_date, DAY)
                OR s.lead_time != s.dispatch_days + s.transit_days)
    UNION ALL
    SELECT '03. On-time flag = final delivery on or before promise', 0,
           (SELECT COUNTIF(on_time != (final_delivery_date <= promised_delivery_date)) FROM s)
    UNION ALL
    SELECT '04. Promise window = promised date - order date', 0,
           (SELECT COUNTIF(promise_window != DATE_DIFF(promised_delivery_date, order_date, DAY)) FROM s)
    UNION ALL
    SELECT '05. City = standardised name of the first shipment (recount)', 0,
           (SELECT COUNT(*) FROM s JOIN first_ship AS f USING (order_id) WHERE s.city != f.c)
    UNION ALL
    SELECT '06. Lead time vs city sums to zero in every city (x1000)', 0,
           (SELECT COUNTIF(ABS(t) > 0.001) FROM (SELECT city, SUM(lead_time_vs_city) AS t FROM s GROUP BY city))
    UNION ALL
    SELECT '07. Each city standard covers at least the 80th-percentile position', 0,
           (SELECT COUNTIF(within < FLOOR(standard_pct * (n - 1) + 1e-9) + 1) FROM city_share)
    UNION ALL
    SELECT '08. Common-standard flag = lead time <= city standard', 0,
           (SELECT COUNTIF(on_time_common != (lead_time <= city_standard)) FROM s)
    UNION ALL
    SELECT '09. Revenue tiers are equal in size (within 1 customer)', 0,
           (SELECT MAX(customers) - MIN(customers) - IF(MAX(customers) - MIN(customers) <= 1, MAX(customers) - MIN(customers), 0) FROM tier_sizes)
    UNION ALL
    SELECT '10. Every tier-1 customer outsells every tier-2 customer', 0,
           (SELECT COUNT(*) FROM tier_value AS a JOIN tier_value AS b ON a.tier = 1 AND b.tier = 2 WHERE a.v < b.v)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
