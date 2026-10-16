/* =============================================================================
   Case study · Freight cost-to-serve — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

WITH t AS (
    SELECT * FROM `sahyadri_b2b.order_cost_to_serve`
),

delivered AS (
    SELECT o.order_id
    FROM `sahyadri_b2b.sales_orders` AS o
    WHERE o.order_status = 'Delivered'
),

missing_freight AS (
    SELECT DISTINCT order_id FROM `sahyadri_b2b.shipments` WHERE shipping_cost IS NULL
),

missing_cost AS (
    SELECT DISTINCT i.order_id
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE p.unit_cost IS NULL
),

has_shipment AS (
    SELECT DISTINCT order_id FROM `sahyadri_b2b.shipments`
),

-- each Delivered order falls in exactly one bucket
scope_bridge AS (
    SELECT
        d.order_id,
        CASE
            WHEN s.order_id IS NULL  THEN 'Excluded: no shipment record'
            WHEN mf.order_id IS NOT NULL THEN 'Excluded: freight cost missing'
            WHEN mc.order_id IS NOT NULL THEN 'Excluded: product cost missing'
            ELSE 'In scope'
        END AS scope_bucket
    FROM delivered            AS d
    LEFT JOIN has_shipment    AS s  ON s.order_id  = d.order_id
    LEFT JOIN missing_freight AS mf ON mf.order_id = d.order_id
    LEFT JOIN missing_cost    AS mc ON mc.order_id = d.order_id
),

checks AS (
    SELECT '01. Rows minus distinct orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM t) AS actual
    UNION ALL
    SELECT '02. In-scope bucket vs table rows', 0,
           (SELECT COUNTIF(scope_bucket = 'In scope') FROM scope_bridge) - (SELECT COUNT(*) FROM t)
    UNION ALL
    SELECT '03. Freight vs shipments table for in-scope orders (paise)', 0,
           CAST(ROUND((SELECT SUM(freight) FROM t)
                    - (SELECT SUM(s.shipping_cost) FROM `sahyadri_b2b.shipments` AS s
                         JOIN t ON t.order_id = s.order_id), 2) * 100 AS INT64)
    UNION ALL
    SELECT '04. Revenue vs line items for in-scope orders (paise)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM t)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i
                         JOIN t ON t.order_id = i.order_id), 2) * 100 AS INT64)
    UNION ALL
    SELECT '05. Contribution <> revenue - cost - freight (rows)', 0,
           (SELECT COUNTIF(ABS(contribution_after_freight - (revenue - product_cost - freight)) > 0.001) FROM t)
    UNION ALL
    SELECT '06. NULL revenue, cost or freight', 0,
           (SELECT COUNTIF(revenue IS NULL OR product_cost IS NULL OR freight IS NULL) FROM t)
    UNION ALL
    SELECT '07. Shipment count differs from source', 0,
           (SELECT COUNT(*) FROM t
              JOIN (SELECT order_id, COUNT(*) AS n FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS s
                ON s.order_id = t.order_id
             WHERE s.n <> t.shipments)
    UNION ALL
    SELECT '08. Orders in the wrong size band', 0,
           (SELECT COUNTIF(
                (order_size_band = '1. Under 10k'    AND revenue >= 10000)
             OR (order_size_band = '2. 10k-25k'      AND (revenue < 10000  OR revenue >= 25000))
             OR (order_size_band = '3. 25k-50k'      AND (revenue < 25000  OR revenue >= 50000))
             OR (order_size_band = '4. 50k-1L'       AND (revenue < 50000  OR revenue >= 100000))
             OR (order_size_band = '5. 1L-5L'        AND (revenue < 100000 OR revenue >= 500000))
             OR (order_size_band = '6. 5L and above' AND revenue < 500000))
            FROM t)
    UNION ALL
    SELECT '09. Size band freight vs total (paise)', 0,
           CAST(ROUND((SELECT SUM(f) FROM (SELECT SUM(freight) AS f FROM t GROUP BY order_size_band))
                    - (SELECT SUM(freight) FROM t), 2) * 100 AS INT64)
    UNION ALL
    SELECT '10. Orders without a customer segment', 0,
           (SELECT COUNTIF(customer_segment IS NULL) FROM t)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;

/* Informational (not pass/fail): how Delivered orders map to the analysis scope
SELECT scope_bucket, COUNT(*) AS orders FROM scope_bridge GROUP BY scope_bucket ORDER BY orders DESC;
*/
