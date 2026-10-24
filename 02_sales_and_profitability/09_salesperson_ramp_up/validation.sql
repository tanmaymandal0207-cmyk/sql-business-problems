/* =============================================================================
   Case study · Salesperson ramp-up — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of DATE DEFAULT DATE '2026-09-30';

WITH m AS (SELECT * FROM `sahyadri_b2b.rep_monthly`),
     r AS (SELECT * FROM `sahyadri_b2b.rep_ramp`),

source_orders AS (
    SELECT o.order_id, o.employee_id, o.customer_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.employee_id, o.customer_id, o.order_date
),
sales_reps AS (
    SELECT e.employee_id, e.hire_date, e.designation
    FROM `sahyadri_b2b.employees`   AS e
    JOIN `sahyadri_b2b.departments` AS d ON d.department_id = e.department_id
    WHERE d.department_name = 'Sales'
),
expected_rows AS (
    -- months from the month after hire (or Jan 2024) to the as-of month
    SELECT SUM(DATE_DIFF(DATE_TRUNC(as_of, MONTH), DATE_TRUNC(GREATEST(hire_date, DATE '2023-12-31'), MONTH), MONTH)) AS n
    FROM sales_reps
),
-- benchmark recomputed straight from the source orders
peer_month AS (
    SELECT DATE_TRUNC(s.order_date, MONTH) AS month_start, s.employee_id, SUM(s.revenue) AS revenue
    FROM source_orders AS s
    JOIN sales_reps    AS p ON p.employee_id = s.employee_id
    WHERE p.hire_date < DATE '2024-01-01'
      AND p.designation IN ('Sales Executive', 'Senior Sales Executive')
    GROUP BY month_start, s.employee_id
),
peer_benchmark AS (
    SELECT month_start, SUM(revenue) / 4 AS benchmark_revenue FROM peer_month GROUP BY month_start
),
-- 3-month rolling index recomputed with a self-join instead of a window
rolling_recount AS (
    SELECT a.employee_id, a.tenure_month, a.revenue_index_3m,
           SUM(b.revenue) / SUM(b.benchmark_revenue) AS recomputed
    FROM r AS a
    JOIN r AS b ON b.employee_id = a.employee_id AND b.tenure_month BETWEEN a.tenure_month - 2 AND a.tenure_month
    GROUP BY a.employee_id, a.tenure_month, a.revenue_index_3m
),
first_valid AS (
    SELECT customer_id, MIN(order_date) AS first_order_date FROM source_orders GROUP BY customer_id
),

checks AS (
    SELECT '01. Duplicate salesperson-month rows' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(employee_id AS STRING), '|', CAST(month_start AS STRING))) FROM m) AS actual
    UNION ALL
    SELECT '02. Monthly revenue vs source orders with a salesperson (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM m)
                    - (SELECT SUM(revenue) FROM source_orders WHERE employee_id IS NOT NULL), 0) AS INT64)
    UNION ALL
    SELECT '03. Monthly orders vs source orders with a salesperson', 0,
           (SELECT SUM(orders) FROM m) - (SELECT COUNT(*) FROM source_orders WHERE employee_id IS NOT NULL)
    UNION ALL
    SELECT '04. Orders dated in or before the hire month', 0,
           (SELECT COUNT(*) FROM source_orders AS s JOIN sales_reps AS p ON p.employee_id = s.employee_id
             WHERE DATE_TRUNC(s.order_date, MONTH) <= DATE_TRUNC(p.hire_date, MONTH))
    UNION ALL
    SELECT '05. Zero-filled rows vs months after hire, per salesperson', 0,
           (SELECT COUNT(*) FROM m) - (SELECT n FROM expected_rows)
    UNION ALL
    SELECT '06. Benchmark months with other than 4 peers', 0,
           (SELECT COUNTIF(peers != 4) FROM r)
    UNION ALL
    SELECT '07. Benchmark revenue vs independent recount', 0,
           (SELECT COUNTIF(ABS(r.benchmark_revenue - IFNULL(b.benchmark_revenue, 0)) > 0.01)
              FROM r LEFT JOIN peer_benchmark AS b ON b.month_start = r.month_start)
    UNION ALL
    SELECT '08. 3-month rolling index vs self-join recount', 0,
           (SELECT COUNTIF(ABS(revenue_index_3m - recomputed) > 1e-9) FROM rolling_recount)
    UNION ALL
    SELECT '09. Tenure months not consecutive from 1', 0,
           (SELECT COUNT(*) FROM (
               SELECT employee_id, MIN(tenure_month) AS lo, MAX(tenure_month) AS hi, COUNT(*) AS n
               FROM r GROUP BY employee_id) WHERE lo != 1 OR hi != n)
    UNION ALL
    SELECT '10. Joiner revenue in ramp table vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM r)
                    - (SELECT SUM(s.revenue) FROM source_orders AS s JOIN sales_reps AS p ON p.employee_id = s.employee_id
                        WHERE p.hire_date >= DATE '2024-01-01'), 0) AS INT64)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
