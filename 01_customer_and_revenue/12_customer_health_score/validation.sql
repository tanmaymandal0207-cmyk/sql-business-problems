/* =============================================================================
   Case study · Customer health score — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE snapshots        ARRAY<DATE> DEFAULT [DATE '2025-03-31', DATE '2025-09-30', DATE '2026-09-30'];
DECLARE current_snapshot DATE        DEFAULT DATE '2026-09-30';

WITH h AS (SELECT * FROM `sahyadri_b2b.health_scores`),
     a AS (SELECT * FROM `sahyadri_b2b.health_auc`),

snaps AS (SELECT snapshot_date FROM UNNEST(snapshots) AS snapshot_date),
valid_orders AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, o.order_date
),
window_source AS (
    SELECT s.snapshot_date, v.customer_id, SUM(v.revenue) AS revenue
    FROM snaps AS s
    JOIN valid_orders AS v
      ON v.order_date <= s.snapshot_date AND v.order_date > DATE_SUB(s.snapshot_date, INTERVAL 365 DAY)
    GROUP BY s.snapshot_date, v.customer_id
),
next_year AS (
    SELECT DISTINCT s.snapshot_date, v.customer_id
    FROM snaps AS s
    JOIN valid_orders AS v
      ON v.order_date > s.snapshot_date AND v.order_date <= DATE_ADD(s.snapshot_date, INTERVAL 365 DAY)
),
-- AUC by brute force: share of (retained, churned) pairs where the retained customer scores higher
pairs AS (
    SELECT
        AVG(IF(r.health_score > c.health_score, 1, IF(r.health_score = c.health_score, 0.5, 0)))       AS auc_health,
        AVG(IF(r.activity_score > c.activity_score, 1, IF(r.activity_score = c.activity_score, 0.5, 0))) AS auc_activity,
        AVG(IF(r.pts_frequency > c.pts_frequency, 1, IF(r.pts_frequency = c.pts_frequency, 0.5, 0)))   AS auc_frequency
    FROM h AS r
    CROSS JOIN h AS c
    WHERE r.is_backtest AND c.is_backtest AND NOT r.churned AND c.churned
),

checks AS (
    SELECT '01. Duplicate snapshot-customer rows' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(snapshot_date AS STRING), '|', CAST(customer_id AS STRING))) FROM h) AS actual
    UNION ALL
    SELECT '02. Scored customers vs source customers active in each window', 0,
           (SELECT COUNT(*) FROM h) - (SELECT COUNT(*) FROM window_source)
    UNION ALL
    SELECT '03. 12-month revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue_12m) FROM h) - (SELECT SUM(revenue) FROM window_source), 0) AS INT64)
    UNION ALL
    SELECT '04. Churn flag vs independent recount', 0,
           (SELECT COUNTIF(h.churned != (n.customer_id IS NULL)) FROM h
              LEFT JOIN next_year AS n ON n.snapshot_date = h.snapshot_date AND n.customer_id = h.customer_id
             WHERE h.is_backtest)
    UNION ALL
    SELECT '05. Look-ahead: last order after the snapshot', 0,
           (SELECT COUNTIF(last_order_date > snapshot_date) FROM h)
    UNION ALL
    SELECT '06. Points outside 0-100, or scores not the average of points', 0,
           (SELECT COUNTIF(LEAST(pts_recency, pts_frequency, pts_trend, pts_breadth, pts_delivery, pts_payment, pts_cancellation) < 0
                        OR GREATEST(pts_recency, pts_frequency, pts_trend, pts_breadth, pts_delivery, pts_payment, pts_cancellation) > 100
                        OR ABS(health_score - (pts_recency + pts_frequency + pts_trend + pts_breadth + pts_delivery + pts_payment + pts_cancellation) / 7) > 1e-9
                        OR ABS(activity_score - (pts_recency + pts_frequency + pts_breadth) / 3) > 1e-9) FROM h)
    UNION ALL
    SELECT '07. Health score AUC vs brute-force pair count', 0,
           (SELECT COUNTIF(ABS(a.auc - p.auc_health) > 1e-9) FROM a CROSS JOIN pairs AS p WHERE a.signal LIKE '08.%')
    UNION ALL
    SELECT '08. Activity score AUC vs brute-force pair count', 0,
           (SELECT COUNTIF(ABS(a.auc - p.auc_activity) > 1e-9) FROM a CROSS JOIN pairs AS p WHERE a.signal LIKE '10.%')
    UNION ALL
    SELECT '09. Frequency AUC vs brute-force pair count', 0,
           (SELECT COUNTIF(ABS(a.auc - p.auc_frequency) > 1e-9) FROM a CROSS JOIN pairs AS p WHERE a.signal LIKE '02.%')
    UNION ALL
    SELECT '10. Outcome set only for back-test dates', 0,
           (SELECT COUNTIF((snapshot_date < current_snapshot) != (churned IS NOT NULL)) FROM h)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
