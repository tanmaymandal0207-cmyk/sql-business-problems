/* =============================================================================
   Case study · Dispatch holds — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE hold_days    INT64 DEFAULT 7;
DECLARE overdue_days INT64 DEFAULT 60;

WITH h AS (SELECT * FROM `sahyadri_b2b.dispatch_holds`),
     g AS (SELECT * FROM `sahyadri_b2b.dispatch_hold_groups`),

first_ship AS (
    SELECT order_id, MIN(shipment_date) AS first_shipment_date
    FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
customer_first_order AS (
    SELECT * FROM `sahyadri_b2b.sales_orders`
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) = 1
),
-- latest delivery of each customer's delivered orders before each order date
earlier_delivery AS (
    SELECT a.order_id, COUNT(b.order_id) AS delivered_earlier
    FROM h AS a
    LEFT JOIN h AS b
      ON b.customer_id = a.customer_id
     AND b.order_status = 'Delivered'
     AND b.final_delivery_date < DATE_SUB(a.order_date, INTERVAL overdue_days DAY)
    GROUP BY a.order_id
),

checks AS (
    SELECT '01. Rows vs distinct shipped orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM h) - (SELECT COUNT(*) FROM first_ship)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM h) AS actual
    UNION ALL
    SELECT '02. Dispatch days vs independent recount', 0,
           (SELECT COUNTIF(h.dispatch_days != DATE_DIFF(f.first_shipment_date, o.order_date, DAY))
              FROM h JOIN first_ship AS f USING (order_id)
              JOIN `sahyadri_b2b.sales_orders` AS o USING (order_id))
    UNION ALL
    SELECT '03. Held flag inconsistent with threshold', 0,
           (SELECT COUNTIF(is_held != (dispatch_days >= hold_days)) FROM h)
    UNION ALL
    SELECT '04. Every dimension covers all shipped orders', 0,
           (SELECT COUNTIF(n != (SELECT COUNT(*) FROM h))
              FROM (SELECT dimension, SUM(orders) AS n FROM g GROUP BY dimension))
    UNION ALL
    SELECT '05. Every dimension covers all held orders', 0,
           (SELECT COUNTIF(n != (SELECT COUNTIF(is_held) FROM h))
              FROM (SELECT dimension, SUM(held) AS n FROM g GROUP BY dimension))
    UNION ALL
    SELECT '06. z-score sign disagrees with rate difference', 0,
           (SELECT COUNTIF(SIGN(z_score) != SIGN(hold_rate - rest_hold_rate)) FROM g)
    UNION ALL
    SELECT '07. Customer first orders flagged as overdue', 0,
           (SELECT COUNTIF(h.customer_overdue_at_order) FROM h JOIN customer_first_order AS f USING (order_id))
    UNION ALL
    SELECT '08. Overdue flag without an earlier delivered order 60+ days before', 0,
           (SELECT COUNTIF(h.customer_overdue_at_order AND e.delivered_earlier = 0)
              FROM h JOIN earlier_delivery AS e USING (order_id))
    UNION ALL
    SELECT '09. Order revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(order_revenue) FROM h)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i JOIN first_ship AS f USING (order_id)), 0) AS INT64)
    UNION ALL
    SELECT '10. Late flag inconsistent with dates', 0,
           (SELECT COUNTIF(is_late != (final_delivery_date > promised_delivery_date)) FROM h
             WHERE final_delivery_date IS NOT NULL AND promised_delivery_date IS NOT NULL)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
