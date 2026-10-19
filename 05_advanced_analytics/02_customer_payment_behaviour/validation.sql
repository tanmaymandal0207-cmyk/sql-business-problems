/* =============================================================================
   Case study · Customer payment behaviour — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

WITH t AS (
    SELECT * FROM `sahyadri_b2b.paid_order_timing`
),

expected_orders AS (
    -- Delivered, fully paid, with a delivery date and at least one payment
    SELECT o.order_id
    FROM `sahyadri_b2b.sales_orders` AS o
    WHERE o.order_status = 'Delivered'
      AND o.payment_status = 'Paid'
      AND EXISTS (SELECT 1 FROM `sahyadri_b2b.shipments` AS s
                  WHERE s.order_id = o.order_id AND s.delivery_date IS NOT NULL)
      AND EXISTS (SELECT 1 FROM `sahyadri_b2b.payments` AS p WHERE p.order_id = o.order_id)
),

checks AS (
    SELECT '01. Rows minus distinct orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM t) AS actual
    UNION ALL
    SELECT '02. Table rows vs expected population', 0,
           (SELECT COUNT(*) FROM t) - (SELECT COUNT(*) FROM expected_orders)
    UNION ALL
    SELECT '03. Days to pay differs from recomputed dates', 0,
           (SELECT COUNTIF(days_to_pay <> DATE_DIFF(final_payment_date, final_delivery_date, DAY)) FROM t)
    UNION ALL
    SELECT '04. Final payment date differs from source', 0,
           (SELECT COUNT(*) FROM t
              JOIN (SELECT order_id, MAX(payment_date) AS d FROM `sahyadri_b2b.payments` GROUP BY order_id) AS p
                ON p.order_id = t.order_id
             WHERE p.d <> t.final_payment_date)
    UNION ALL
    SELECT '05. Final delivery date differs from source', 0,
           (SELECT COUNT(*) FROM t
              JOIN (SELECT order_id, MAX(delivery_date) AS d FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS s
                ON s.order_id = t.order_id
             WHERE s.d <> t.final_delivery_date)
    UNION ALL
    SELECT '06. Payment count differs from source', 0,
           (SELECT COUNT(*) FROM t
              JOIN (SELECT order_id, COUNT(*) AS n FROM `sahyadri_b2b.payments` GROUP BY order_id) AS p
                ON p.order_id = t.order_id
             WHERE p.n <> t.payments)
    UNION ALL
    SELECT '07. Rows with NULL value, dates or segment', 0,
           (SELECT COUNTIF(order_value IS NULL OR final_delivery_date IS NULL
                        OR final_payment_date IS NULL OR customer_segment IS NULL) FROM t)
    UNION ALL
    SELECT '08. Delivery year differs from delivery date', 0,
           (SELECT COUNTIF(delivery_year <> EXTRACT(YEAR FROM final_delivery_date)) FROM t)
    UNION ALL
    SELECT '09. Segment order counts vs total', 0,
           (SELECT SUM(n) FROM (SELECT COUNT(*) AS n FROM t GROUP BY customer_segment))
         - (SELECT COUNT(*) FROM t)
    UNION ALL
    -- fully paid orders: amount received should equal order value within ₹0.05,
    -- except the known duplicate receipts and short payments
    SELECT '10. Paid orders whose receipts differ from value (expected 16)', 16,
           (SELECT COUNT(*) FROM t
              JOIN (SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` GROUP BY order_id) AS p
                ON p.order_id = t.order_id
             WHERE ABS(p.paid - t.order_value) > 0.05)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
