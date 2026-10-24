/* =============================================================================
   Case study · Ship-to vs bill-to reconciliation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE recurring_min INT64 DEFAULT 3;

WITH r AS (SELECT * FROM `sahyadri_b2b.ship_bill_reconciliation`),
     l AS (SELECT * FROM `sahyadri_b2b.city_state_lookup`),

pair_recount AS (
    SELECT customer_id, ship_city, COUNT(*) AS n
    FROM r
    GROUP BY customer_id, ship_city
),
shipped_order_revenue AS (
    SELECT i.order_id,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    WHERE i.order_id IN (SELECT order_id FROM `sahyadri_b2b.shipments`)
    GROUP BY i.order_id
),
order_level AS (
    SELECT order_id, ANY_VALUE(order_revenue) AS revenue, COUNT(DISTINCT order_revenue) AS values_per_order
    FROM r
    GROUP BY order_id
),

checks AS (
    SELECT '01. Reconciliation rows vs source shipments' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM r) - (SELECT COUNT(*) FROM `sahyadri_b2b.shipments`)
         + (SELECT COUNT(*) - COUNT(DISTINCT shipment_id) FROM r) AS actual
    UNION ALL
    SELECT '02. Shipments without a match type', 0,
           (SELECT COUNTIF(match_type IS NULL) FROM r)
    UNION ALL
    SELECT '03. Standard cities with more than one state', 0,
           (SELECT COUNT(*) FROM (SELECT standard_city FROM l GROUP BY standard_city HAVING COUNT(*) > 1))
    UNION ALL
    SELECT '04. Shipping cities not found in the city-state lookup', 0,
           (SELECT COUNTIF(ship_state IS NULL) FROM r)
    UNION ALL
    SELECT '05. Exact / case-only rows inconsistent with raw values', 0,
           (SELECT COUNTIF((match_type = '1. Exact match' AND raw_ship_city != raw_bill_city)
                        OR (match_type = '2. Case or spacing only'
                            AND (raw_ship_city = raw_bill_city OR LOWER(TRIM(raw_ship_city)) != LOWER(TRIM(raw_bill_city))))) FROM r)
    UNION ALL
    SELECT '06. Alias rows not equal after standardising, or equal before', 0,
           (SELECT COUNTIF(match_type = '3. City alias only'
                           AND (ship_city != bill_city OR LOWER(TRIM(raw_ship_city)) = LOWER(TRIM(raw_bill_city)))) FROM r)
    UNION ALL
    SELECT '07. Different-city rows with equal cities or wrong state flag', 0,
           (SELECT COUNTIF((match_type LIKE '4.%' OR match_type LIKE '5.%') AND ship_city = bill_city)
                 + COUNTIF(match_type LIKE '4.%' AND ship_state != bill_state)
                 + COUNTIF(match_type LIKE '5.%' AND ship_state = bill_state) FROM r)
    UNION ALL
    SELECT '08. Recurring flag vs independent pair recount', 0,
           (SELECT COUNTIF(r.destination_pattern IS NOT NULL
                           AND (r.destination_pattern = 'Recurring destination') != (p.n >= recurring_min))
              FROM r JOIN pair_recount AS p ON p.customer_id = r.customer_id AND p.ship_city = r.ship_city)
    UNION ALL
    SELECT '09. No-billing-city rows vs shipments of customers with no city', 0,
           (SELECT COUNTIF(match_type = '6. No billing city') FROM r)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.shipments` AS s
              JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = s.order_id
              JOIN `sahyadri_b2b.customers`    AS c ON c.customer_id = o.customer_id
             WHERE c.city IS NULL)
    UNION ALL
    SELECT '10. Order revenue vs source, one value per order (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM order_level) - (SELECT SUM(revenue) FROM shipped_order_revenue), 0) AS INT64)
         + (SELECT COUNTIF(values_per_order != 1) FROM order_level)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
