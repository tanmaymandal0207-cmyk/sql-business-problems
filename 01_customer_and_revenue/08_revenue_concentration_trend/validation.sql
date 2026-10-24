/* =============================================================================
   Case study · Revenue concentration trend — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE last_quarter DATE DEFAULT DATE '2026-07-01';

WITH p AS (SELECT * FROM `sahyadri_b2b.concentration_periods`),
     m AS (SELECT * FROM `sahyadri_b2b.concentration_measures`),

lines AS (
    SELECT o.customer_id, o.order_date,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
-- Gini recomputed with the mean absolute difference formula: sum |xi - xj| / (2 n^2 mean)
gini_alt AS (
    SELECT a.period_type, a.period_end_quarter,
           SUM(ABS(a.revenue - b.revenue)) / (2 * POW(COUNT(DISTINCT a.customer_id), 2)
               * (SUM(a.revenue) / COUNT(*) )) AS gini
    FROM p AS a
    JOIN p AS b ON b.period_type = a.period_type AND b.period_end_quarter = a.period_end_quarter
    GROUP BY a.period_type, a.period_end_quarter
),
rolling_recount AS (
    SELECT r.period_end_quarter, r.customer_id, r.revenue AS rolling, SUM(q.revenue) AS from_quarters
    FROM p AS r
    JOIN p AS q
      ON q.customer_id = r.customer_id
     AND q.period_type = 'Quarter'
     AND q.period_end_quarter BETWEEN DATE_SUB(r.period_end_quarter, INTERVAL 9 MONTH) AND r.period_end_quarter
    WHERE r.period_type = 'Rolling 12 months'
    GROUP BY r.period_end_quarter, r.customer_id, r.revenue
),

checks AS (
    SELECT '01. Duplicate customer-period rows' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(period_type, '|', CAST(period_end_quarter AS STRING), '|', CAST(customer_id AS STRING))) FROM p) AS actual
    UNION ALL
    SELECT '02. Quarterly revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM p WHERE period_type = 'Quarter')
                    - (SELECT SUM(revenue) FROM lines WHERE DATE_TRUNC(order_date, QUARTER) <= last_quarter), 0) AS INT64)
    UNION ALL
    SELECT '03. Latest 12-month revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT revenue FROM m WHERE period_type = 'Rolling 12 months' AND period_end_quarter = last_quarter)
                    - (SELECT SUM(revenue) FROM lines
                        WHERE order_date >= DATE_SUB(last_quarter, INTERVAL 9 MONTH)
                          AND order_date <  DATE_ADD(last_quarter, INTERVAL 3 MONTH)), 0) AS INT64)
    UNION ALL
    SELECT '04. Latest 12-month customers vs source', 0,
           (SELECT customers FROM m WHERE period_type = 'Rolling 12 months' AND period_end_quarter = last_quarter)
         - (SELECT COUNT(DISTINCT customer_id) FROM lines
             WHERE order_date >= DATE_SUB(last_quarter, INTERVAL 9 MONTH)
               AND order_date <  DATE_ADD(last_quarter, INTERVAL 3 MONTH))
    UNION ALL
    SELECT '05. HHI outside [1/n, 1] or effective customers above customers', 0,
           (SELECT COUNTIF(hhi < 1 / customers - 1e-12 OR hhi > 1 OR effective_customers > customers + 1e-9) FROM m)
    UNION ALL
    SELECT '06. Top-1 <= top-5 <= top-10 <= 1 violated', 0,
           (SELECT COUNTIF(NOT (top1_share <= top5_share AND top5_share <= top10_share AND top10_share <= 1 + 1e-12)) FROM m)
    UNION ALL
    SELECT '07. Gini vs mean-absolute-difference formula', 0,
           (SELECT COUNTIF(ABS(m.gini - g.gini) > 1e-9) FROM m
              JOIN gini_alt AS g ON g.period_type = m.period_type AND g.period_end_quarter = m.period_end_quarter)
    UNION ALL
    SELECT '08. Gini outside 0-1', 0,
           (SELECT COUNTIF(gini < 0 OR gini >= 1) FROM m)
    UNION ALL
    SELECT '09. Periods: 11 quarters and 8 rolling windows', 0,
           ABS((SELECT COUNTIF(period_type = 'Quarter') FROM m) - 11)
         + ABS((SELECT COUNTIF(period_type = 'Rolling 12 months') FROM m) - 8)
    UNION ALL
    SELECT '10. Rolling-window revenue vs sum of its four quarters', 0,
           (SELECT COUNTIF(ABS(rolling - from_quarters) > 0.01) FROM rolling_recount)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
