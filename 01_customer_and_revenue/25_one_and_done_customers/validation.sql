/* =============================================================================
   Case study · One-and-done customers — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */
DECLARE first_order DATE DEFAULT DATE '2024-01-01';
DECLARE last_order  DATE DEFAULT DATE '2026-09-30';
DECLARE cohort_end  DATE DEFAULT DATE '2025-09-30';

WITH so AS (SELECT * FROM `sahyadri_b2b.so_orders`),
     sc AS (SELECT * FROM `sahyadri_b2b.so_customers`),
src AS (
  SELECT COUNT(DISTINCT o.order_id) AS orders, COUNT(DISTINCT o.customer_id) AS customers
  FROM `sahyadri_b2b.sales_orders` AS o
  WHERE o.order_date BETWEEN first_order AND last_order AND o.order_status != 'Cancelled'
),
src_val AS (
  SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
  FROM `sahyadri_b2b.sales_orders` AS o
  JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id)
  WHERE o.order_date BETWEEN first_order AND last_order AND o.order_status != 'Cancelled'
),
checks AS (
  SELECT '01. Order count = non-cancelled source orders' AS check_name, 0 AS expected,
         ABS((SELECT COUNT(*) FROM so) - (SELECT orders FROM src)) AS actual
  UNION ALL
  SELECT '02. Customer count matches distinct source customers', 0,
         ABS((SELECT COUNT(*) FROM sc) - (SELECT customers FROM src))
  UNION ALL
  SELECT '03. Order value = source line value (tolerance Re 1 per order)', 0,
         (SELECT COUNT(*) FROM (SELECT order_id, SUM(v) AS s FROM (
            SELECT o.order_id, i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS v
            FROM `sahyadri_b2b.sales_orders` AS o JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id)
            WHERE o.order_date BETWEEN first_order AND last_order AND o.order_status != 'Cancelled')
          GROUP BY order_id) AS x JOIN so USING (order_id) WHERE ABS(x.s - so.order_value) > 1)
  UNION ALL
  SELECT '04. One row per customer in customer table', 0,
         (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM sc)
  UNION ALL
  SELECT '05. Single-order flag = exactly one order', 0,
         (SELECT COUNT(*) FROM sc JOIN (SELECT customer_id, COUNT(*) AS n FROM so GROUP BY customer_id) AS c USING (customer_id)
          WHERE sc.is_single_order != (c.n = 1))
  UNION ALL
  SELECT '06. First date = MIN(order_date) per customer', 0,
         (SELECT COUNT(*) FROM sc JOIN (SELECT customer_id, MIN(order_date) AS m FROM so GROUP BY customer_id) AS c USING (customer_id)
          WHERE sc.first_date != c.m)
  UNION ALL
  SELECT '07. Cohort flag = first_date <= 2025-09-30', 0,
         (SELECT COUNTIF(in_cohort != (first_date <= cohort_end)) FROM sc)
  UNION ALL
  SELECT '08. No null order values', 0,
         (SELECT COUNTIF(order_value IS NULL) FROM so)
)
SELECT check_name, expected, actual, IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks ORDER BY check_name;
