/* =============================================================================
   Case study · Cancellation and return leakage — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start DATE  DEFAULT DATE '2024-01-01';
DECLARE as_of_date   DATE  DEFAULT DATE '2026-09-30';
DECLARE min_orders   INT64 DEFAULT 20;

WITH t AS (SELECT * FROM `sahyadri_b2b.order_outcomes`),
     d AS (SELECT * FROM `sahyadri_b2b.cancellation_driver_screen`),

closed AS (
    SELECT order_id, order_status
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status IN ('Delivered', 'Cancelled', 'Returned')
      AND order_date BETWEEN period_start AND as_of_date
),
company AS (SELECT COUNTIF(outcome = 'Cancelled') / COUNT(*) AS p FROM t),

-- orders per dimension, for dimensions where each order belongs to exactly one group
single_valued AS (
    SELECT dimension, SUM(closed_orders) AS orders
    FROM d
    WHERE dimension IN ('Customer segment', 'Industry', 'Salesperson', 'Order size', 'Promise window', 'Order month')
    GROUP BY dimension
),
category_recount AS (
    SELECT pc.category_name, COUNT(DISTINCT i.order_id) AS orders
    FROM `sahyadri_b2b.sales_order_items`  AS i
    JOIN `sahyadri_b2b.products`           AS p  ON p.product_id   = i.product_id
    JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
    WHERE i.order_id IN (SELECT order_id FROM closed)
    GROUP BY pc.category_name
),

checks AS (
    SELECT '01. Duplicate orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM t) AS actual
    UNION ALL
    SELECT '02. Rows vs closed orders in source', 0,
           (SELECT COUNT(*) FROM t) - (SELECT COUNT(*) FROM closed)
    UNION ALL
    SELECT '03. Order value vs source lines (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(order_value) FROM t)
                    - (SELECT SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items`
                        WHERE order_id IN (SELECT order_id FROM closed)), 0) AS INT64)
    UNION ALL
    SELECT '04. Cancelled and returned counts vs source', 0,
           (SELECT COUNTIF(outcome IN ('Cancelled', 'Returned')) FROM t)
         - (SELECT COUNTIF(order_status IN ('Cancelled', 'Returned')) FROM closed)
    UNION ALL
    SELECT '05. Freight vs source shipments (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(freight_cost) FROM t)
                    - (SELECT IFNULL(SUM(shipping_cost), 0) FROM `sahyadri_b2b.shipments`
                        WHERE order_id IN (SELECT order_id FROM closed)), 0) AS INT64)
    UNION ALL
    SELECT '06. Amount paid vs source payments (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(amount_paid) FROM t)
                    - (SELECT SUM(amount) FROM `sahyadri_b2b.payments`
                        WHERE order_id IN (SELECT order_id FROM closed)), 0) AS INT64)
    UNION ALL
    SELECT '07. Late flag missing or present when it should not be', 0,
           (SELECT COUNTIF((was_late IS NULL) <> (final_delivery_date IS NULL OR promise_band = '4. No promise date')) FROM t)
    UNION ALL
    SELECT '08. Single-valued dimensions that do not cover every order', 0,
           (SELECT COUNTIF(orders <> (SELECT COUNT(*) FROM t)) FROM single_valued)
         + (6 - (SELECT COUNT(*) FROM single_valued))
    UNION ALL
    SELECT '09. Z-scores that do not match an independent recompute', 0,
           (SELECT COUNTIF(ABS(z_score - (cancelled / closed_orders - c.p)
                                         / SQRT(c.p * (1 - c.p) / closed_orders)) > 0.01)
              FROM d CROSS JOIN company AS c)
    UNION ALL
    SELECT '10. Category order counts vs independent recount', 0,
           (SELECT COUNT(*) FROM d
              JOIN category_recount AS r ON r.category_name = d.group_value
             WHERE d.dimension = 'Product category' AND d.closed_orders <> r.orders)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
