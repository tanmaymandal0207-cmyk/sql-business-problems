/* =============================================================================
   Case study · Sales force cost efficiency — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start DATE DEFAULT DATE '2025-10-01';
DECLARE period_end   DATE DEFAULT DATE '2026-09-30';

WITH s AS (SELECT * FROM `sahyadri_b2b.sales_cost_efficiency`),

source_lines AS (
    SELECT o.order_id, o.employee_id,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue,
           i.quantity * p.unit_cost                                             AS cost
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN period_start AND period_end
),
sales_team AS (
    SELECT e.*
    FROM `sahyadri_b2b.employees` AS e
    JOIN `sahyadri_b2b.departments` AS d ON d.department_id = e.department_id
    WHERE d.department_name = 'Sales'
),

checks AS (
    SELECT '01. Rows: one per salesperson plus one unassigned row' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM s) - ((SELECT COUNT(*) FROM sales_team) + 1))
         + (SELECT COUNTIF(employee_id IS NOT NULL) - COUNT(DISTINCT employee_id) FROM s) AS actual
    UNION ALL
    SELECT '02. Revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM s) - (SELECT SUM(revenue) FROM source_lines), 0) AS INT64)
    UNION ALL
    SELECT '03. Costed gross profit vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(costed_gp) FROM s)
                    - (SELECT SUM(revenue - cost) FROM source_lines WHERE cost IS NOT NULL), 0) AS INT64)
    UNION ALL
    SELECT '04. Gross profit = costed GP + uncosted revenue x own margin', 0,
           (SELECT COUNTIF(revenue > 0 AND ABS(gross_profit - (costed_gp + (revenue - costed_revenue) * gp_margin_pct)) > 0.01) FROM s)
    UNION ALL
    SELECT '05. Salary cost above annual salary, or below it for a full-period employee', 0,
           (SELECT COUNTIF(salary_cost > annual_salary + 0.01
                        OR (hire_date < period_start AND ABS(salary_cost - annual_salary) > 0.01)) FROM s)
    UNION ALL
    SELECT '06. Salary cost vs independent recount (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(salary_cost) FROM s)
                    - (SELECT SUM(salary * (DATE_DIFF(period_end, GREATEST(hire_date, period_start), DAY) + 1)
                                  / (DATE_DIFF(period_end, period_start, DAY) + 1)) FROM sales_team
                        WHERE hire_date <= period_end), 0) AS INT64)
    UNION ALL
    SELECT '07. Orders vs distinct source orders', 0,
           (SELECT SUM(orders) FROM s) - (SELECT COUNT(DISTINCT order_id) FROM source_lines)
    UNION ALL
    SELECT '08. Role group inconsistent with designation', 0,
           (SELECT COUNTIF(role_group != CASE WHEN designation = 'Head of Sales' THEN 'Management'
                                              WHEN designation IN ('Regional Sales Manager', 'Key Account Manager') THEN 'Managers and key accounts'
                                              WHEN designation IN ('Senior Sales Executive', 'Sales Executive') THEN 'Executives'
                                              ELSE 'Unassigned' END) FROM s)
    UNION ALL
    SELECT '09. Orders booked by people outside the Sales department', 0,
           (SELECT COUNT(DISTINCT order_id) FROM source_lines
             WHERE employee_id IS NOT NULL AND employee_id NOT IN (SELECT employee_id FROM sales_team))
    UNION ALL
    SELECT '10. Gross margin % outside 0-100 %', 0,
           (SELECT COUNTIF(gp_margin_pct < 0 OR gp_margin_pct > 1) FROM s)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
