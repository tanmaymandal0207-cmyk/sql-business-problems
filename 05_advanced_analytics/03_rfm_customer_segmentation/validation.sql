/* =============================================================================
   Case study · RFM customer segmentation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of_date   DATE DEFAULT DATE '2026-09-30';
DECLARE window_start DATE DEFAULT DATE '2025-10-01';

WITH r AS (
    SELECT * FROM `sahyadri_b2b.customer_rfm`
),

in_scope_orders AS (
    SELECT o.order_id, o.customer_id, o.order_date
    FROM `sahyadri_b2b.sales_orders` AS o
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),

window_revenue AS (
    SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS total
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN in_scope_orders AS o ON o.order_id = i.order_id
    WHERE o.order_date >= window_start
),

r_bucket_sizes AS (
    SELECT r_score, COUNT(*) AS n FROM r GROUP BY r_score
),

checks AS (
    SELECT '01. Rows minus distinct customers' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM r) AS actual
    UNION ALL
    SELECT '02. Customers vs customers with in-scope orders', 0,
           (SELECT COUNT(*) FROM r) - (SELECT COUNT(DISTINCT customer_id) FROM in_scope_orders)
    UNION ALL
    SELECT '03. 12-month revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(monetary_12m) FROM r) - (SELECT total FROM window_revenue), 0) AS INT64)
    UNION ALL
    SELECT '04. 12-month orders vs source', 0,
           (SELECT SUM(frequency_12m) FROM r)
         - (SELECT COUNT(*) FROM in_scope_orders WHERE order_date >= window_start)
    UNION ALL
    SELECT '05. Scores outside 1-5', 0,
           (SELECT COUNTIF(r_score NOT BETWEEN 1 AND 5 OR f_score NOT BETWEEN 1 AND 5
                        OR m_score NOT BETWEEN 1 AND 5) FROM r)
    UNION ALL
    -- NTILE(5) should split customers into five groups whose sizes differ by at most 1
    SELECT '06. Recency quintile sizes differ by more than 1', 0,
           (SELECT IF(MAX(n) - MIN(n) > 1, 1, 0) FROM r_bucket_sizes)
    UNION ALL
    SELECT '07. Customers with no recent orders not scored F=1, M=1', 0,
           (SELECT COUNTIF(frequency_12m = 0 AND (f_score <> 1 OR m_score <> 1)) FROM r)
    UNION ALL
    SELECT '08. Recency differs from last order date', 0,
           (SELECT COUNT(*) FROM r
              JOIN (SELECT customer_id, MAX(order_date) AS last_order FROM in_scope_orders
                    GROUP BY customer_id) AS l
                ON l.customer_id = r.customer_id
             WHERE r.recency_days <> DATE_DIFF(as_of_date, l.last_order, DAY))
    UNION ALL
    SELECT '09. Customers without a segment', 0,
           (SELECT COUNTIF(rfm_segment IS NULL) FROM r)
    UNION ALL
    SELECT '10. Champions that break the Champion rule', 0,
           (SELECT COUNTIF(rfm_segment = '1. Champions'
                           AND NOT (r_score >= 4 AND f_score >= 4 AND m_score >= 4)) FROM r)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
