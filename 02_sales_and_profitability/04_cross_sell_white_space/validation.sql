/* =============================================================================
   Case study · Cross-sell white-space analysis — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start    DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end      DATE    DEFAULT DATE '2026-09-30';
DECLARE min_penetration FLOAT64 DEFAULT 0.60;

WITH g AS (SELECT * FROM `sahyadri_b2b.customer_category_spend`),
     x AS (SELECT * FROM `sahyadri_b2b.cross_sell_gaps`),

window_lines AS (
    SELECT o.customer_id,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN window_start AND window_end
),

-- penetration recomputed with GROUP BY instead of a window function
penetration AS (
    SELECT customer_segment, category_name, COUNTIF(bought) / COUNT(*) AS p
    FROM g GROUP BY customer_segment, category_name
),

checks AS (
    SELECT '01. Grid rows vs active customers x 10 categories' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM g) - 10 * (SELECT COUNT(DISTINCT customer_id) FROM window_lines) AS actual
    UNION ALL
    SELECT '02. Duplicate customer-category rows', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(category_id AS STRING))) FROM g)
    UNION ALL
    SELECT '03. 12-month revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue_12m) FROM g) - (SELECT SUM(revenue) FROM window_lines), 0) AS INT64)
    UNION ALL
    SELECT '04. Bought flag inconsistent with revenue', 0,
           (SELECT COUNTIF(bought <> (revenue_12m > 0)) FROM g)
    UNION ALL
    SELECT '05. Customers in grid with no purchase at all', 0,
           (SELECT COUNT(*) FROM (SELECT customer_id FROM g GROUP BY customer_id HAVING COUNTIF(bought) = 0))
    UNION ALL
    SELECT '06. Gaps on categories the customer already buys', 0,
           (SELECT COUNT(*) FROM x
              JOIN g ON g.customer_id = x.customer_id AND g.category_name = x.category_name
             WHERE g.bought)
    UNION ALL
    SELECT '07. Gaps in categories below the penetration threshold', 0,
           (SELECT COUNT(*) FROM x
              JOIN penetration AS p
                ON p.customer_segment = x.customer_segment AND p.category_name = x.category_name
             WHERE p.p < min_penetration)
    UNION ALL
    SELECT '08. Duplicate gaps', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', category_name)) FROM x)
    UNION ALL
    SELECT '09. Gaps with missing or non-positive value', 0,
           (SELECT COUNTIF(indicative_gap_value IS NULL OR indicative_gap_value <= 0) FROM x)
    UNION ALL
    -- every qualifying non-bought cell should be a gap: recount independently
    SELECT '10. Gap count vs independent recount', 0,
           (SELECT COUNT(*) FROM x)
         - (SELECT COUNT(*) FROM g
              JOIN penetration AS p
                ON p.customer_segment = g.customer_segment AND p.category_name = g.category_name
             WHERE NOT g.bought AND p.p >= min_penetration)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
