/* =============================================================================
   Case study · Net and gross revenue retention — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE quarter_ends ARRAY<DATE> DEFAULT [DATE '2025-12-31', DATE '2026-03-31', DATE '2026-06-30', DATE '2026-09-30'];

WITH c AS (SELECT * FROM `sahyadri_b2b.revenue_retention_customers`),
     r AS (SELECT * FROM `sahyadri_b2b.revenue_retention_quarterly`),

quarters AS (
    SELECT quarter_end FROM UNNEST(quarter_ends) AS quarter_end
),
source_lines AS (
    SELECT o.customer_id, o.order_date,
           i.quantity * i.unit_price    * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue,
           i.quantity * p.selling_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue_at_list
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
source_windows AS (
    SELECT q.quarter_end,
           SUM(IF(l.order_date >  DATE_SUB(q.quarter_end, INTERVAL 12 MONTH), l.revenue, 0))         AS current_revenue,
           SUM(IF(l.order_date <= DATE_SUB(q.quarter_end, INTERVAL 12 MONTH), l.revenue, 0))         AS base_revenue,
           SUM(IF(l.order_date >  DATE_SUB(q.quarter_end, INTERVAL 12 MONTH), l.revenue_at_list, 0)) AS current_at_list
    FROM quarters AS q
    JOIN source_lines AS l
      ON l.order_date > DATE_SUB(q.quarter_end, INTERVAL 24 MONTH) AND l.order_date <= q.quarter_end
    GROUP BY q.quarter_end
),
-- customers with an order in both windows, counted from source
both_windows AS (
    SELECT q.quarter_end, l.customer_id,
           COUNTIF(l.order_date <= DATE_SUB(q.quarter_end, INTERVAL 12 MONTH)) AS base_lines,
           COUNTIF(l.order_date >  DATE_SUB(q.quarter_end, INTERVAL 12 MONTH)) AS current_lines
    FROM quarters AS q
    JOIN source_lines AS l
      ON l.order_date > DATE_SUB(q.quarter_end, INTERVAL 24 MONTH) AND l.order_date <= q.quarter_end
    GROUP BY q.quarter_end, l.customer_id
),

checks AS (
    SELECT '01. Duplicate quarter-customer rows' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(quarter_end AS STRING), '|', CAST(customer_id AS STRING))) FROM c) AS actual
    UNION ALL
    SELECT '02. Current 12-month revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(current_revenue) FROM r) - (SELECT SUM(current_revenue) FROM source_windows), 0) AS INT64)
    UNION ALL
    SELECT '03. Base 12-month revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(base_revenue) FROM r) - (SELECT SUM(base_revenue) FROM source_windows), 0) AS INT64)
    UNION ALL
    SELECT '04. Bridge: base - churn - contraction + expansion + new = current', 0,
           (SELECT COUNTIF(ABS(base_revenue - churn - contraction + expansion + new_revenue - current_revenue) > 0.01) FROM r)
    UNION ALL
    SELECT '05. GRR = 1 - (churn + contraction) / base', 0,
           (SELECT COUNTIF(ABS(grr - (1 - (churn + contraction) / base_revenue)) > 1e-9) FROM r)
    UNION ALL
    SELECT '06. Retained customers vs source recount', 0,
           (SELECT SUM(retained_customers) FROM r) - (SELECT COUNTIF(base_lines > 0 AND current_lines > 0) FROM both_windows)
    UNION ALL
    SELECT '07. Base customers vs source recount', 0,
           (SELECT SUM(base_customers) FROM r) - (SELECT COUNTIF(base_lines > 0) FROM both_windows)
    UNION ALL
    SELECT '08. Current revenue at list price vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(current_revenue_at_list) FROM c) - (SELECT SUM(current_at_list) FROM source_windows), 0) AS INT64)
    UNION ALL
    SELECT '09. Size band missing for a base customer, or set for a new one', 0,
           (SELECT COUNTIF((base_revenue > 0) != (base_size_band IS NOT NULL)) FROM c)
    UNION ALL
    SELECT '10. Movement inconsistent with base and current revenue', 0,
           (SELECT COUNTIF(movement != CASE WHEN base_revenue = 0 THEN 'New or returning'
                                            WHEN current_revenue = 0 THEN 'Churned'
                                            WHEN current_revenue < base_revenue THEN 'Contracted'
                                            WHEN current_revenue > base_revenue THEN 'Expanded'
                                            ELSE 'Flat' END) FROM c)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
