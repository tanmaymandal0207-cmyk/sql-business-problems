/* =============================================================================
   Case study · Open order backlog review — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE stuck_days INT64 DEFAULT 30;

WITH r AS (
    SELECT * FROM `sahyadri_b2b.open_order_review`
),

open_orders AS (
    SELECT order_id FROM `sahyadri_b2b.sales_orders`
    WHERE order_status IN ('Pending', 'Processing', 'Shipped')
),

checks AS (
    SELECT '01. Rows minus distinct orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM r) AS actual
    UNION ALL
    SELECT '02. Table rows vs open orders in source', 0,
           (SELECT COUNT(*) FROM r) - (SELECT COUNT(*) FROM open_orders)
    UNION ALL
    SELECT '03. Order value vs line items (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(order_value) FROM r)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i
                         JOIN open_orders AS o ON o.order_id = i.order_id), 0) AS INT64)
    UNION ALL
    SELECT '04. Amount paid vs payments table (paise)', 0,
           CAST(ROUND((SELECT SUM(amount_paid) FROM r)
                    - (SELECT IFNULL(SUM(p.amount), 0) FROM `sahyadri_b2b.payments` AS p
                         JOIN open_orders AS o ON o.order_id = p.order_id), 2) * 100 AS INT64)
    UNION ALL
    SELECT '05. Shipment count vs shipments table', 0,
           (SELECT SUM(shipments) FROM r)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.shipments` AS s JOIN open_orders AS o ON o.order_id = s.order_id)
    UNION ALL
    SELECT '06. Rows without a review status', 0,
           (SELECT COUNTIF(review_status IS NULL) FROM r)
    UNION ALL
    SELECT '07. "Delivered - status not updated" with a shipment in transit', 0,
           (SELECT COUNTIF(review_status LIKE '1.%' AND shipments_in_transit > 0) FROM r)
    UNION ALL
    SELECT '08. "Stuck in transit" at or under the threshold', 0,
           (SELECT COUNTIF(review_status LIKE '2.%' AND (days_in_transit IS NULL OR days_in_transit <= stuck_days)) FROM r)
    UNION ALL
    SELECT '09. "On track" orders already past their promised date', 0,
           (SELECT COUNTIF(review_status LIKE '6.%' AND days_past_promise > 0) FROM r)
    UNION ALL
    SELECT '10. In-transit + delivered shipments vs total shipments', 0,
           (SELECT SUM(shipments_in_transit + shipments_delivered) - SUM(shipments) FROM r)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
