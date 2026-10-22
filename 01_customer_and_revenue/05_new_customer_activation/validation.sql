/* =============================================================================
   Case study · New customer onboarding and activation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE new_from    DATE  DEFAULT DATE '2024-01-01';
DECLARE as_of_date  DATE  DEFAULT DATE '2026-09-30';

WITH a AS (SELECT * FROM `sahyadri_b2b.new_customer_activation`),

new_customers AS (
    SELECT customer_id
    FROM `sahyadri_b2b.customers`
    WHERE registration_date BETWEEN new_from AND as_of_date
),

-- valid order lines of new customers, built independently of the analysis
lines AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date <= as_of_date
      AND o.customer_id IN (SELECT customer_id FROM new_customers)
),
first_dates AS (
    SELECT customer_id, MIN(order_date) AS first_date, COUNT(DISTINCT order_id) AS orders
    FROM lines GROUP BY customer_id
),
first_year_recount AS (
    SELECT l.customer_id, SUM(l.revenue) AS rev
    FROM lines AS l
    JOIN first_dates AS f ON f.customer_id = l.customer_id
    WHERE DATE_DIFF(l.order_date, f.first_date, DAY) < 365
      AND DATE_DIFF(as_of_date, f.first_date, DAY) >= 365
    GROUP BY l.customer_id
),

checks AS (
    SELECT '01. Duplicate customers' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM a) AS actual
    UNION ALL
    SELECT '02. Rows vs new customers in source', 0,
           (SELECT COUNT(*) FROM a) - (SELECT COUNT(*) FROM new_customers)
    UNION ALL
    SELECT '03. Revenue to date vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue_to_date) FROM a) - (SELECT SUM(revenue) FROM lines), 0) AS INT64)
    UNION ALL
    SELECT '04. Valid order count vs source', 0,
           (SELECT SUM(valid_orders) FROM a) - (SELECT COUNT(DISTINCT order_id) FROM lines)
    UNION ALL
    SELECT '05. First order date vs independent minimum', 0,
           (SELECT COUNT(*) FROM a LEFT JOIN first_dates AS f ON f.customer_id = a.customer_id
             WHERE a.first_order_date IS DISTINCT FROM f.first_date)
    UNION ALL
    SELECT '06. Second order present only with 2+ valid orders', 0,
           (SELECT COUNTIF((second_order_date IS NOT NULL) <> (valid_orders >= 2)) FROM a)
    UNION ALL
    SELECT '07. Orders before registration or second before first', 0,
           (SELECT COUNTIF(days_to_first_order < 0 OR days_first_to_second < 0) FROM a)
    UNION ALL
    SELECT '08. Activation stage inconsistent with its rule', 0,
           (SELECT COUNTIF(
                 (activation_stage = 'Repeat buyer'    AND valid_orders < 2)
              OR (activation_stage = 'One order only'  AND valid_orders <> 1)
              OR (activation_stage = 'Not yet ordered' AND (valid_orders <> 0 OR cancelled_or_returned_orders <> 0))
              OR (activation_stage = 'Only cancelled or returned orders'
                  AND (valid_orders <> 0 OR cancelled_or_returned_orders = 0)))
              FROM a)
    UNION ALL
    SELECT '09. First-year revenue on customers without a full year, or above revenue to date', 0,
           (SELECT COUNTIF(revenue_first_365 IS NOT NULL
                           AND (DATE_DIFF(as_of_date, first_order_date, DAY) < 365
                                OR revenue_first_365 > revenue_to_date + 0.01)) FROM a)
    UNION ALL
    SELECT '10. First-year revenue vs independent recount (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue_first_365) FROM a) - (SELECT SUM(rev) FROM first_year_recount), 0) AS INT64)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
