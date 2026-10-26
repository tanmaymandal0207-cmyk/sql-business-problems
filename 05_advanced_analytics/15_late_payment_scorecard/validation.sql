/* =============================================================================
   Case study · Late payment scorecard — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE train_end     DATE    DEFAULT DATE '2025-10-01';
DECLARE last_delivery DATE    DEFAULT DATE '2026-07-31';
DECLARE window_days   INT64   DEFAULT 60;
DECLARE pdo_factor    FLOAT64 DEFAULT 28.85;

WITH o AS (SELECT * FROM `sahyadri_b2b.lps_orders`),
     w AS (SELECT * FROM `sahyadri_b2b.lps_woe`),
     s AS (SELECT * FROM `sahyadri_b2b.lps_scores`),
     a AS (SELECT * FROM `sahyadri_b2b.lps_auc`),

population AS (
    SELECT x.order_id
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN (SELECT order_id, MAX(delivery_date) AS dd FROM `sahyadri_b2b.shipments`
          GROUP BY order_id HAVING COUNT(delivery_date) = COUNT(*)) AS d ON d.order_id = x.order_id
    WHERE x.order_status = 'Delivered' AND d.dd <= last_delivery
),
-- late flag recomputed with a correlated-free aggregate over all payments, filtered afterwards
pay AS (
    SELECT o.order_id,
           SUM(IF(p.payment_date <= DATE_ADD(o.final_delivery_date, INTERVAL window_days DAY), p.amount, 0)) AS paid
    FROM o LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = o.order_id
    GROUP BY o.order_id
),
first_orders AS (
    SELECT * FROM o
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) = 1
),
pairs AS (
    SELECT
        AVG(IF(g.score > b.score, 1, IF(g.score = b.score, 0.5, 0)))                           AS auc_scorecard,
        AVG(IF(g.score_segment_only > b.score_segment_only, 1,
               IF(g.score_segment_only = b.score_segment_only, 0.5, 0)))                       AS auc_segment
    FROM s AS g CROSS JOIN s AS b
    WHERE g.sample = 'Test' AND b.sample = 'Test' AND NOT g.is_late AND b.is_late
),

checks AS (
    SELECT '01. Modelling rows vs source delivered orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM o) - (SELECT COUNT(*) FROM population)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM o) AS actual
    UNION ALL
    SELECT '02. Order value vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(order_value) FROM o)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i JOIN population AS p ON p.order_id = i.order_id), 0) AS INT64)
    UNION ALL
    SELECT '03. Late flag vs independent recount', 0,
           (SELECT COUNTIF(o.is_late != (p.paid < o.order_value - 0.05)) FROM o JOIN pay AS p USING (order_id))
    UNION ALL
    SELECT '04. Customer first orders always have no history', 0,
           (SELECT COUNTIF(bin_history != '1. No history') FROM first_orders)
    UNION ALL
    SELECT '05. Train / test split agrees with delivery date', 0,
           (SELECT COUNTIF(sample != IF(final_delivery_date < train_end, 'Train', 'Test')) FROM o)
    UNION ALL
    SELECT '06. Bins cover every train order for each characteristic', 0,
           (SELECT COUNTIF(n != (SELECT COUNTIF(sample = 'Train') FROM o))
              FROM (SELECT characteristic, SUM(on_time_orders + late_orders) AS n FROM w GROUP BY characteristic))
    UNION ALL
    SELECT '07. Late orders by bin add up to train late orders', 0,
           (SELECT COUNTIF(n != (SELECT COUNTIF(sample = 'Train' AND is_late) FROM o))
              FROM (SELECT characteristic, SUM(late_orders) AS n FROM w GROUP BY characteristic))
    UNION ALL
    SELECT '08. Points = ROUND(28.85 x WoE)', 0,
           (SELECT COUNTIF(points != CAST(ROUND(pdo_factor * woe) AS INT64)) FROM w)
    UNION ALL
    SELECT '09. Test AUC (scorecard) vs brute-force pair count', 0,
           (SELECT COUNTIF(ABS(a.auc - p.auc_scorecard) > 1e-9) FROM a CROSS JOIN pairs AS p
             WHERE a.sample = 'Test' AND a.model LIKE 'Scorecard%')
    UNION ALL
    SELECT '10. Test AUC (segment only) vs brute-force pair count', 0,
           (SELECT COUNTIF(ABS(a.auc - p.auc_segment) > 1e-9) FROM a CROSS JOIN pairs AS p
             WHERE a.sample = 'Test' AND a.model = 'Segment only')
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
