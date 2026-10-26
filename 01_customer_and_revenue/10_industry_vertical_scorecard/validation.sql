/* =============================================================================
   Case study · Industry vertical scorecard — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE current_start DATE DEFAULT DATE '2025-10-01';
DECLARE prior_start   DATE DEFAULT DATE '2024-10-01';
DECLARE as_of         DATE DEFAULT DATE '2026-09-30';

WITH k AS (SELECT * FROM `sahyadri_b2b.industry_customer_period`),
     s AS (SELECT * FROM `sahyadri_b2b.industry_scorecard`),

source_lines AS (
    SELECT o.customer_id, o.order_date,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue,
           i.quantity * p.unit_cost                                             AS cost
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date >= prior_start AND o.order_date <= as_of
),
industry_costed AS (
    SELECT industry, SUM(costed_revenue) AS costed FROM k WHERE period = 'Current' GROUP BY industry
),

checks AS (
    SELECT '01. Duplicate customer-period rows' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', period)) FROM k) AS actual
    UNION ALL
    SELECT '02. Two-period revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM k) - (SELECT SUM(revenue) FROM source_lines), 0) AS INT64)
    UNION ALL
    SELECT '03. Current margin vs source lines with a cost (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(margin) FROM k WHERE period = 'Current')
                    - (SELECT SUM(revenue - cost) FROM source_lines
                        WHERE cost IS NOT NULL AND order_date >= current_start), 0) AS INT64)
    UNION ALL
    SELECT '04. Scorecard rows vs industries, one row each', 0,
           ABS((SELECT COUNT(*) FROM s) - (SELECT COUNT(DISTINCT industry) FROM k))
         + (SELECT COUNT(*) - COUNT(DISTINCT industry) FROM s)
    UNION ALL
    SELECT '05. Active customers vs distinct current-period customers', 0,
           (SELECT SUM(active_customers) FROM s)
         - (SELECT COUNT(DISTINCT customer_id) FROM source_lines WHERE order_date >= current_start)
    UNION ALL
    SELECT '06. Registered customers vs customer master', 0,
           (SELECT SUM(registered_customers) FROM s) - (SELECT COUNT(*) FROM `sahyadri_b2b.customers`)
    UNION ALL
    SELECT '07. Growth vs recomputation from source', 0,
           (SELECT COUNTIF(ABS(s.growth_pct - (x.cur / x.pri - 1)) > 1e-9) FROM s
              JOIN (SELECT IFNULL(c.industry, 'Not recorded') AS industry,
                           SUM(IF(l.order_date >= current_start, l.revenue, 0)) AS cur,
                           SUM(IF(l.order_date <  current_start, l.revenue, 0)) AS pri
                      FROM source_lines AS l JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = l.customer_id
                     GROUP BY industry) AS x ON x.industry = s.industry)
    UNION ALL
    SELECT '08. Mix-expected margin sums to actual company margin (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(s.margin_gap_pct * c.costed) FROM s JOIN industry_costed AS c USING (industry)), 0) AS INT64)
    UNION ALL
    SELECT '09. Retention outside 0-1', 0,
           (SELECT COUNTIF(retention_pct < 0 OR retention_pct > 1) FROM s)
    UNION ALL
    SELECT '10. Largest customer share outside 0-1, or top grower outside its industry', 0,
           (SELECT COUNTIF(largest_customer_share <= 0 OR largest_customer_share > 1) FROM s)
         + (SELECT COUNT(*) FROM s JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = s.top_grower_id
             WHERE IFNULL(c.industry, 'Not recorded') != s.industry)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
