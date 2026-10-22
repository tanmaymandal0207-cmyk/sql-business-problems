/* =============================================================================
   Case study · Customer profitability and the whale curve — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start    DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end      DATE    DEFAULT DATE '2026-09-30';
DECLARE cost_of_capital FLOAT64 DEFAULT 0.12;

WITH t AS (SELECT * FROM `sahyadri_b2b.customer_profitability`),

window_orders AS (
    SELECT order_id, customer_id, employee_id, order_status
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_date BETWEEN window_start AND window_end
),
valid_lines AS (
    SELECT
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue,
        i.quantity * IFNULL(p.unit_cost, 0)                                   AS cost
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN window_orders                    AS w ON w.order_id   = i.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE w.order_status NOT IN ('Cancelled', 'Returned')
),
-- prorated salary recomputed with a day count over the window
prorated AS (
    SELECT
        e.employee_id,
        e.designation,
        d.department_name,
        e.salary * DATE_DIFF(DATE_ADD(window_end, INTERVAL 1 DAY), GREATEST(e.hire_date, window_start), DAY)
                 / DATE_DIFF(DATE_ADD(window_end, INTERVAL 1 DAY), window_start, DAY) AS cost
    FROM `sahyadri_b2b.employees`   AS e
    JOIN `sahyadri_b2b.departments` AS d ON d.department_id = e.department_id
    WHERE e.hire_date <= window_end
),
delivered_customers AS (
    SELECT DISTINCT customer_id FROM window_orders WHERE order_status = 'Delivered'
),

checks AS (
    SELECT '01. Duplicate customers' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM t) AS actual
    UNION ALL
    SELECT '02. Rows vs customers with orders in the window', 0,
           (SELECT COUNT(*) FROM t) - (SELECT COUNT(DISTINCT customer_id) FROM window_orders)
    UNION ALL
    SELECT '03. Revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM t) - (SELECT SUM(revenue) FROM valid_lines), 0) AS INT64)
    UNION ALL
    SELECT '04. Gross profit vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(gross_profit) FROM t) - (SELECT SUM(revenue - cost) FROM valid_lines), 0) AS INT64)
    UNION ALL
    SELECT '05. Freight vs source shipments (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(freight) FROM t)
                    - (SELECT IFNULL(SUM(shipping_cost), 0) FROM `sahyadri_b2b.shipments`
                        WHERE order_id IN (SELECT order_id FROM window_orders)), 0) AS INT64)
    UNION ALL
    SELECT '06. Handling cost vs Operations and Supply Chain salaries (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(handling_cost) FROM t)
                    - (SELECT SUM(cost) FROM prorated
                        WHERE department_name IN ('Operations', 'Supply Chain & Logistics')), 0) AS INT64)
    UNION ALL
    SELECT '07. Sales cost vs salaries of salespeople with orders, excl. Head of Sales (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(sales_cost) FROM t)
                    - (SELECT SUM(cost) FROM prorated
                        WHERE employee_id IN (SELECT employee_id FROM window_orders)
                          AND designation <> 'Head of Sales'), 0) AS INT64)
    UNION ALL
    SELECT '08. Contribution does not equal GP less costs', 0,
           (SELECT COUNTIF(ABS(contribution - (gross_profit - freight - handling_cost - sales_cost - credit_cost)) > 0.05) FROM t)
    UNION ALL
    SELECT '09. Whale curve: ranks not 1..n, or does not end at 100 %', 0,
           (SELECT COUNT(DISTINCT profit_rank) - COUNT(*) + MAX(profit_rank) - COUNT(*) FROM t)
         + (SELECT IF(ABS(cumulative_share_of_profit - 1) < 0.0001, 0, 1) FROM t
             WHERE profit_rank = (SELECT MAX(profit_rank) FROM t))
    UNION ALL
    SELECT '10. Negative credit cost, or credit cost without a delivered order', 0,
           (SELECT COUNTIF(credit_cost < 0
                           OR (credit_cost > 0 AND customer_id NOT IN (SELECT customer_id FROM delivered_customers)))
              FROM t)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
