/* =============================================================================
   Case study · Split shipment drivers — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE min_orders INT64 DEFAULT 50;

WITH f AS (SELECT * FROM `sahyadri_b2b.order_fulfilment`),
     l AS (SELECT * FROM `sahyadri_b2b.split_product_lift`),

ship_orders AS (
    SELECT order_id, COUNT(*) AS shipments, SUM(shipping_cost) AS cost, COUNT(shipping_cost) AS costed
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
-- split rate per product recomputed from line items with an EXISTS-free join
product_recount AS (
    SELECT i.product_id, COUNT(*) AS n, COUNTIF(s.shipments = 2) AS splits
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN ship_orders AS s ON s.order_id = i.order_id
    JOIN (SELECT order_id FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id HAVING COUNT(*) > 1) AS m
      ON m.order_id = i.order_id
    GROUP BY i.product_id
),

checks AS (
    SELECT '01. Fulfilment rows vs distinct shipped orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM f) - (SELECT COUNT(*) FROM ship_orders)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM f) AS actual
    UNION ALL
    SELECT '02. Orders with more than 2 shipments', 0,
           (SELECT COUNTIF(shipments > 2) FROM ship_orders)
    UNION ALL
    SELECT '03. Split orders vs shipment table', 0,
           (SELECT COUNTIF(is_split) FROM f) - (SELECT COUNTIF(shipments = 2) FROM ship_orders)
    UNION ALL
    SELECT '04. Single-line orders that were split', 0,
           (SELECT COUNTIF(is_split AND order_lines = 1) FROM f)
    UNION ALL
    SELECT '05. Freight vs source for fully costed orders (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(freight) FROM f)
                    - (SELECT SUM(cost) FROM ship_orders WHERE costed = shipments), 0) AS INT64)
    UNION ALL
    SELECT '06. Final delivery before first delivery, or last shipment before first', 0,
           (SELECT COUNTIF(final_delivery_date < first_delivery_date OR last_shipment_date < first_shipment_date) FROM f)
    UNION ALL
    SELECT '07. Single-shipment orders with first and final delivery different', 0,
           (SELECT COUNTIF(NOT is_split AND final_delivery_date IS NOT NULL AND final_delivery_date != first_delivery_date) FROM f)
    UNION ALL
    SELECT '08. Product split counts vs independent recount', 0,
           (SELECT COUNTIF(p.n IS NULL OR p.n != l.multi_line_orders OR p.splits != l.split_orders)
              FROM l LEFT JOIN product_recount AS p ON p.product_id = l.product_id)
    UNION ALL
    SELECT '09. Products below the minimum order count in the lift table', 0,
           (SELECT COUNTIF(multi_line_orders < min_orders) FROM l)
         + ABS((SELECT COUNT(*) FROM l) - (SELECT COUNTIF(n >= min_orders) FROM product_recount))
    UNION ALL
    SELECT '10. Fulfilment revenue vs source line items of shipped orders (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM f)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i JOIN ship_orders AS s ON s.order_id = i.order_id), 0) AS INT64)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
