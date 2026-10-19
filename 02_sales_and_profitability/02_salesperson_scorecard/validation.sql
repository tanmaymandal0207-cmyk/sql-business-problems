/* =============================================================================
   Case study · Salesperson performance scorecard — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of_date DATE DEFAULT DATE '2026-09-30';

WITH s AS (
    SELECT * FROM `sahyadri_b2b.salesperson_scorecard`
),

in_scope_lines AS (
    SELECT o.order_id,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),

checks AS (
    SELECT '01. Duplicate salesperson rows' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT IFNULL(employee_id, -1)) FROM s) AS actual
    UNION ALL
    SELECT '02. Salespeople on orders missing from scorecard', 0,
           (SELECT COUNT(DISTINCT IFNULL(employee_id, -1)) FROM `sahyadri_b2b.sales_orders`)
         - (SELECT COUNT(*) FROM s)
    UNION ALL
    SELECT '03. Net revenue vs in-scope line items (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(net_revenue) FROM s) - (SELECT SUM(revenue) FROM in_scope_lines), 0) AS INT64)
    UNION ALL
    SELECT '04. Orders vs in-scope orders', 0,
           (SELECT SUM(orders) FROM s) - (SELECT COUNT(DISTINCT order_id) FROM in_scope_lines)
    UNION ALL
    SELECT '05. Orders placed vs all orders', 0,
           (SELECT SUM(orders_placed) FROM s) - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders`)
    UNION ALL
    SELECT '06. Cancelled orders vs source', 0,
           (SELECT SUM(cancelled_orders) FROM s)
         - (SELECT COUNTIF(order_status = 'Cancelled') FROM `sahyadri_b2b.sales_orders`)
    UNION ALL
    SELECT '07. On-time orders exceed orders measured', 0,
           (SELECT COUNTIF(on_time_orders > delivered_measured) FROM s)
    UNION ALL
    SELECT '08. Overdue balance exceeds aged order value', 0,
           (SELECT COUNTIF(overdue_balance > aged_order_value + 0.01) FROM s)
    UNION ALL
    SELECT '09. Percentage metric outside 0-100', 0,
           (SELECT COUNTIF(gross_margin_pct NOT BETWEEN 0 AND 100
                        OR discount_pct NOT BETWEEN 0 AND 100
                        OR cancellation_rate_pct NOT BETWEEN 0 AND 100
                        OR on_time_pct NOT BETWEEN 0 AND 100
                        OR overdue_receivable_pct NOT BETWEEN 0 AND 100) FROM s)
    UNION ALL
    SELECT '10. Ranked salespeople with a missing metric', 0,
           (SELECT COUNTIF(employee_id IS NOT NULL AND (
                gross_margin_pct IS NULL OR discount_pct IS NULL OR cancellation_rate_pct IS NULL
             OR on_time_pct IS NULL OR overdue_receivable_pct IS NULL)) FROM s)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
