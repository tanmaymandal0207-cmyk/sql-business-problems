/* =============================================================================
   Case study · Salesperson relationship risk — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start   DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE coverage_start DATE    DEFAULT DATE '2024-10-01';
DECLARE prior_start    DATE    DEFAULT DATE '2024-10-01';
DECLARE prior_end      DATE    DEFAULT DATE '2025-09-30';
DECLARE dominant_share FLOAT64 DEFAULT 0.80;

WITH r AS (SELECT * FROM `sahyadri_b2b.customer_relationship_coverage`),
     h AS (SELECT * FROM `sahyadri_b2b.salesperson_handover`),

lines AS (
    SELECT
        o.customer_id,
        o.employee_id,
        o.order_date,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),

-- independent primary: the employee whose revenue equals the customer's maximum
emp_rev AS (
    SELECT customer_id, employee_id, SUM(revenue) AS rev
    FROM lines
    WHERE order_date BETWEEN window_start AND window_end AND employee_id IS NOT NULL
    GROUP BY customer_id, employee_id
),
max_rev AS (SELECT customer_id, MAX(rev) AS max_rev FROM emp_rev GROUP BY customer_id),

-- independent salesperson count over 24 months
reps_24m AS (
    SELECT customer_id, COUNT(DISTINCT employee_id) AS n
    FROM lines
    WHERE order_date BETWEEN coverage_start AND window_end AND employee_id IS NOT NULL
    GROUP BY customer_id
),

checks AS (
    SELECT '01. Duplicate customers in coverage table' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM r) AS actual
    UNION ALL
    SELECT '02. Customers vs active customers in source', 0,
           (SELECT COUNT(*) FROM r)
         - (SELECT COUNT(DISTINCT customer_id) FROM lines WHERE order_date BETWEEN window_start AND window_end)
    UNION ALL
    SELECT '03. 12-month revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue_12m) FROM r)
                    - (SELECT SUM(revenue) FROM lines WHERE order_date BETWEEN window_start AND window_end), 0) AS INT64)
    UNION ALL
    SELECT '04. Unattributed revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(unattributed_revenue_12m) FROM r)
                    - (SELECT SUM(revenue) FROM lines
                        WHERE order_date BETWEEN window_start AND window_end AND employee_id IS NULL), 0) AS INT64)
    UNION ALL
    SELECT '05. Primary is not the top-revenue salesperson', 0,
           (SELECT COUNT(*) FROM r
              JOIN emp_rev AS e ON e.customer_id = r.customer_id AND e.employee_id = r.primary_employee_id
              JOIN max_rev AS m ON m.customer_id = r.customer_id
             WHERE ABS(e.rev - m.max_rev) > 0.01)
    UNION ALL
    SELECT '06. Salespeople in 24 months vs independent count', 0,
           (SELECT COUNT(*) FROM r LEFT JOIN reps_24m AS x ON x.customer_id = r.customer_id
             WHERE r.salespeople_24m <> IFNULL(x.n, 0))
    UNION ALL
    SELECT '07. Relationship type inconsistent with its rule', 0,
           (SELECT COUNTIF(
                 (relationship_type = 'Unassigned'      AND primary_employee_id IS NOT NULL)
              OR (relationship_type = 'Single-threaded' AND salespeople_24m <> 1)
              OR (relationship_type = 'Dominant'        AND (salespeople_24m < 2 OR primary_share < dominant_share))
              OR (relationship_type = 'Shared'          AND (salespeople_24m < 2 OR primary_share >= dominant_share)))
              FROM r)
    UNION ALL
    SELECT '08. Primary share outside 0-1 or missing', 0,
           (SELECT COUNTIF(primary_employee_id IS NOT NULL
                           AND (primary_share IS NULL OR primary_share <= 0 OR primary_share > 1)) FROM r)
    UNION ALL
    SELECT '09. Handover prior revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(prior_revenue) FROM h)
                    - (SELECT SUM(revenue) FROM lines
                        WHERE order_date BETWEEN prior_start AND prior_end
                          AND customer_id IN (SELECT customer_id FROM lines
                                               WHERE order_date BETWEEN prior_start AND prior_end
                                                 AND employee_id IS NOT NULL)), 0) AS INT64)
    UNION ALL
    SELECT '10. Handover outcome inconsistent with its rule', 0,
           (SELECT COUNTIF(
                 (handover_outcome = 'Stopped buying'          AND current_revenue <> 0)
              OR (handover_outcome = 'Same salesperson'        AND current_primary IS DISTINCT FROM prior_primary)
              OR (handover_outcome = 'Salesperson changed'     AND (current_primary IS NULL OR current_primary = prior_primary))
              OR (handover_outcome = 'No salesperson recorded' AND (current_primary IS NOT NULL OR current_revenue = 0)))
              FROM h)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
