/* =============================================================================
   Case study 01 · Customer revenue risk — validation checks (version 2)
   Dialect : Google BigQuery Standard SQL
   Run this after analysis_v2.sql. Every row should return status = 'PASS'.
   The revenue rules here must stay identical to analysis_v2.sql.
   ============================================================================= */

WITH line_revenue AS (
    SELECT
        i.order_id,
        o.customer_id,
        o.order_status,
        i.discount_percent,
        i.quantity * i.unit_price
            * (1 - IFNULL(i.discount_percent, 0) / 100) AS net_line
    FROM `sahyadri_b2b.sales_order_items` AS i
    LEFT JOIN `sahyadri_b2b.sales_orders` AS o
        ON o.order_id = i.order_id
),

order_revenue AS (
    SELECT customer_id, order_id, SUM(net_line) AS net_sales
    FROM line_revenue
    WHERE order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY customer_id, order_id
),

customer_metrics AS (
    SELECT customer_id, COUNT(*) AS total_orders, SUM(net_sales) AS net_sales
    FROM order_revenue
    GROUP BY customer_id
),

totals AS (
    SELECT
        (SELECT SUM(net_line) FROM line_revenue)                                         AS all_lines,
        (SELECT SUM(net_line) FROM line_revenue
           WHERE order_status NOT IN ('Cancelled', 'Returned'))                          AS in_scope_lines,
        (SELECT SUM(net_line) FROM line_revenue
           WHERE order_status IN ('Cancelled', 'Returned'))                              AS excluded_lines,
        (SELECT SUM(net_sales) FROM order_revenue)                                       AS order_level,
        (SELECT SUM(net_sales) FROM customer_metrics)                                    AS customer_level
),

checks AS (
-- 1. Join integrity: every line item has a parent order
SELECT '1. Line items without an order' AS check_name,
       0 AS expected,
       (SELECT COUNTIF(customer_id IS NULL) FROM line_revenue) AS actual

UNION ALL
-- 2. Every order has at least one line item (else it would vanish from revenue)
SELECT '2. Orders without line items', 0,
       (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders` AS o
          WHERE NOT EXISTS (SELECT 1 FROM `sahyadri_b2b.sales_order_items` AS i
                            WHERE i.order_id = o.order_id))

UNION ALL
-- 3. Grain: order_revenue has exactly one row per order
SELECT '3. Duplicate orders in order_revenue', 0,
       (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM order_revenue)

UNION ALL
-- 4. No NULL revenue reaches the aggregates
SELECT '4. NULL net_line values', 0,
       (SELECT COUNTIF(net_line IS NULL) FROM line_revenue)

UNION ALL
-- 5. Revenue bridge: all lines = in-scope + excluded statuses (rounded to paise)
SELECT '5. Bridge difference: all - in scope - excluded', 0,
       CAST(ROUND(all_lines - in_scope_lines - excluded_lines, 2) * 100 AS INT64)
FROM totals

UNION ALL
-- 6. Order level reconciles to line level
SELECT '6. Difference: in-scope lines vs order level', 0,
       CAST(ROUND(in_scope_lines - order_level, 2) * 100 AS INT64)
FROM totals

UNION ALL
-- 7. Customer level reconciles to order level
SELECT '7. Difference: order level vs customer level', 0,
       CAST(ROUND(order_level - customer_level, 2) * 100 AS INT64)
FROM totals

UNION ALL
-- 8. Order counts reconcile
SELECT '8. Difference: in-scope orders vs SUM(total_orders)', 0,
       (SELECT COUNT(DISTINCT order_id) FROM order_revenue)
       - (SELECT SUM(total_orders) FROM customer_metrics)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;

/* Informational (not pass/fail): size of the NULL-discount treatment
SELECT
    COUNTIF(discount_percent IS NULL)                                  AS null_discount_lines,
    COUNT(DISTINCT IF(discount_percent IS NULL, order_id, NULL))       AS orders_affected,
    SUM(IF(discount_percent IS NULL, net_line, 0))                     AS revenue_on_null_discount_lines
FROM line_revenue;
*/
