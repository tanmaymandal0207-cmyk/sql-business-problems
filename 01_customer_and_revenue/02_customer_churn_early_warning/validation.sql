/* =============================================================================
   Case study · Customer churn early warning — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of_date DATE DEFAULT DATE '2026-09-30';

WITH cas AS (
    SELECT * FROM `sahyadri_b2b.customer_activity_status`
),

in_scope_orders AS (
    SELECT o.order_id, o.customer_id, o.order_date
    FROM `sahyadri_b2b.sales_orders` AS o
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),

line_total AS (
    SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS total
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN in_scope_orders AS o
        ON o.order_id = i.order_id
),

checks AS (
    SELECT '01. Rows minus distinct customers' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM cas) AS actual
    UNION ALL
    SELECT '02. Customers with in-scope orders vs table rows', 0,
           (SELECT COUNT(DISTINCT customer_id) FROM in_scope_orders) - (SELECT COUNT(*) FROM cas)
    UNION ALL
    SELECT '03. Order count vs in-scope orders', 0,
           (SELECT SUM(total_orders) FROM cas) - (SELECT COUNT(*) FROM in_scope_orders)
    UNION ALL
    -- lifetime revenue is rounded per customer: allow ₹0.005 per customer
    SELECT '04. Lifetime revenue vs line items outside rounding (1 = yes)', 0,
           IF(ABS((SELECT SUM(lifetime_revenue) FROM cas) - (SELECT total FROM line_total))
              > 0.005 * (SELECT COUNT(*) FROM cas), 1, 0)
    UNION ALL
    SELECT '05. Run-rate greater than lifetime revenue', 0,
           (SELECT COUNTIF(annual_run_rate > lifetime_revenue + 0.01) FROM cas)
    UNION ALL
    SELECT '06. Last order date differs from source', 0,
           (SELECT COUNT(*) FROM cas AS c
              JOIN (SELECT customer_id, MAX(order_date) AS last_order_date
                    FROM in_scope_orders GROUP BY customer_id) AS s
                ON s.customer_id = c.customer_id
             WHERE s.last_order_date <> c.last_order_date)
    UNION ALL
    SELECT '07. Status inconsistent with days since last order', 0,
           (SELECT COUNTIF(
                (activity_status = '1. Active'  AND days_since_last_order > 90)
             OR (activity_status = '2. At risk' AND (days_since_last_order <= 90  OR days_since_last_order > 180))
             OR (activity_status = '3. Lapsed'  AND (days_since_last_order <= 180 OR days_since_last_order > 365))
             OR (activity_status = '4. Lost'    AND days_since_last_order <= 365))
            FROM cas)
    UNION ALL
    SELECT '08. Days since last order recomputed differs', 0,
           (SELECT COUNTIF(days_since_last_order <> DATE_DIFF(as_of_date, last_order_date, DAY)) FROM cas)
    UNION ALL
    SELECT '09. Overdue flag on customers with fewer than 3 orders', 0,
           (SELECT COUNTIF(overdue_vs_cycle AND total_orders < 3) FROM cas)
    UNION ALL
    SELECT '10. Last order after the as-of date', 0,
           (SELECT COUNTIF(last_order_date > as_of_date) FROM cas)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
