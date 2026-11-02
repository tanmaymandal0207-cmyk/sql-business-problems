/* =============================================================================
   Case study · Do overdue balances slow a customer's ordering? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_month   DATE    DEFAULT DATE '2024-04-01';
DECLARE last_month    DATE    DEFAULT DATE '2026-09-01';
DECLARE overdue_days  INT64   DEFAULT 90;
DECLARE settled_share FLOAT64 DEFAULT 0.99;
DECLARE test_month    DATE    DEFAULT DATE '2026-01-01';

WITH m AS (SELECT * FROM `sahyadri_b2b.ob_months`),
     w AS (SELECT * FROM `sahyadri_b2b.ob_within`),
     p AS (SELECT * FROM `sahyadri_b2b.ob_permutations`),

span AS (
    SELECT customer_id, MIN(order_date) AS first_order, MAX(order_date) AS last_order
    FROM `sahyadri_b2b.sales_orders` GROUP BY customer_id
),
expected_rows AS (
    SELECT COUNT(*) AS n
    FROM span AS s
    JOIN UNNEST(GENERATE_DATE_ARRAY(first_month, last_month, INTERVAL 1 MONTH)) AS mm ON mm > s.first_order
),
order_value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS value
    FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id
),
in_scope_orders AS (
    SELECT o.order_id, o.order_status, v.value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN span AS s ON s.customer_id = o.customer_id
    LEFT JOIN order_value AS v ON v.order_id = o.order_id
    WHERE DATE_TRUNC(o.order_date, MONTH) > s.first_order
      AND DATE_TRUNC(o.order_date, MONTH) BETWEEN first_month AND last_month
),
-- independent recount of who was overdue at the start of the test month
test_overdue AS (
    SELECT DISTINCT o.customer_id
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN (SELECT order_id, MAX(delivery_date) AS d FROM `sahyadri_b2b.shipments` GROUP BY order_id
          HAVING COUNT(delivery_date) = COUNT(*)) AS s ON s.order_id = o.order_id
    JOIN (SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS v
            FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id) AS v ON v.order_id = o.order_id
    LEFT JOIN (SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date < test_month GROUP BY order_id) AS pd
      ON pd.order_id = o.order_id
    JOIN span AS sp ON sp.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND DATE_ADD(s.d, INTERVAL overdue_days DAY) < test_month
      AND v.v - IFNULL(pd.paid, 0) > (1 - settled_share) * v.v
      AND sp.first_order < test_month
),
prior AS (
    SELECT a.customer_id, a.month, a.prior_6m_orders, IFNULL(SUM(b.orders), 0) AS recount
    FROM m AS a
    LEFT JOIN m AS b ON b.customer_id = a.customer_id AND b.month_no BETWEEN a.month_no - 6 AND a.month_no - 1
    GROUP BY a.customer_id, a.month, a.prior_6m_orders
),
cells AS (
    SELECT customer_id, activity_band, COUNTIF(overdue) AS od, COUNTIF(NOT overdue) AS clear, SUM(orders_dev) AS dev_sum
    FROM w GROUP BY customer_id, activity_band
),

checks AS (
    SELECT '01. One row per customer per month after the first order' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM m) - (SELECT n FROM expected_rows))
         + (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), CAST(month AS STRING))) FROM m) AS actual
    UNION ALL
    SELECT '02. Orders per month add up to the orders placed in scope', 0,
           ABS((SELECT SUM(orders) FROM m) - (SELECT COUNT(*) FROM in_scope_orders))
    UNION ALL
    SELECT '03. Revenue = valid order value in scope', 0,
           IF(ABS((SELECT SUM(revenue) FROM m)
                  - (SELECT SUM(IF(order_status NOT IN ('Cancelled', 'Returned'), value, 0)) FROM in_scope_orders)) > 1, 1, 0)
    UNION ALL
    SELECT '04. Overdue customers in January 2026 = independent recount', 0,
           (SELECT COUNT(*) FROM (SELECT customer_id FROM m WHERE month = test_month AND overdue) AS a
              FULL OUTER JOIN test_overdue AS b USING (customer_id)
             WHERE a.customer_id IS NULL OR b.customer_id IS NULL)
    UNION ALL
    SELECT '05. Overdue flag, overdue orders and amount agree', 0,
           (SELECT COUNTIF(overdue != (overdue_orders > 0) OR (overdue AND overdue_amount <= 0) OR (NOT overdue AND overdue_amount != 0)) FROM m)
    UNION ALL
    SELECT '06. Orders in the previous six months = recount', 0,
           (SELECT COUNTIF(prior_6m_orders != recount) FROM prior)
    UNION ALL
    SELECT '07. Every comparison cell has both kinds of month, deviations sum to zero', 0,
           (SELECT COUNTIF(od = 0 OR clear = 0 OR ABS(dev_sum) > 1e-6) FROM cells)
    UNION ALL
    SELECT '08. 500 random relabellings, centred on zero', 0,
           ABS((SELECT COUNT(*) FROM p) - 500) + IF(ABS((SELECT AVG(difference) FROM p)) > 0.01, 1, 0)
    UNION ALL
    SELECT '09. Active month = on or before the last order', 0,
           (SELECT COUNTIF(active_month != (m.month <= s.last_order)) FROM m JOIN span AS s USING (customer_id))
    UNION ALL
    SELECT '10. Within-cell rows are a subset of all customer-months', 0,
           (SELECT COUNT(*) FROM w LEFT JOIN m USING (customer_id, month) WHERE m.customer_id IS NULL)
         + IF((SELECT COUNT(*) FROM w) > (SELECT COUNT(*) FROM m), 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
