/* =============================================================================
   Case study · Monte Carlo collections forecast — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of      DATE  DEFAULT DATE '2026-09-30';
DECLARE replicates INT64 DEFAULT 500;

WITH si AS (SELECT * FROM `sahyadri_b2b.mc_snapshot_items`),
     st AS (SELECT * FROM `sahyadri_b2b.mc_settings`),
     pl AS (SELECT * FROM `sahyadri_b2b.mc_pool`),
     rp AS (SELECT * FROM `sahyadri_b2b.mc_replicates`),
     rs AS (SELECT * FROM `sahyadri_b2b.mc_results`),

-- open book at the latest month-end, rebuilt directly from source
src_open AS (
    SELECT o.order_id,
           v.order_value - IFNULL(p.paid, 0) AS outstanding
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN (SELECT order_id, MAX(delivery_date) AS d FROM `sahyadri_b2b.shipments` GROUP BY order_id
          HAVING COUNT(delivery_date) = COUNT(*)) AS s ON s.order_id = o.order_id
    JOIN (SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
            FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id) AS v ON v.order_id = o.order_id
    LEFT JOIN (SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date <= as_of GROUP BY order_id) AS p
      ON p.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND s.d <= as_of
      AND v.order_value - IFNULL(p.paid, 0) > 1
),
-- actual collections of each back-test book, recounted from payments
actual_recount AS (
    SELECT t.forecast_date, t.horizon_days,
           SUM(LEAST(IFNULL(x.paid, 0), i.outstanding)) AS actual
    FROM st AS t
    JOIN si AS i ON i.snapshot_date = t.forecast_date
    LEFT JOIN (
        SELECT t2.forecast_date, t2.horizon_days, p.order_id, SUM(p.amount) AS paid
        FROM st AS t2
        JOIN `sahyadri_b2b.payments` AS p
          ON p.payment_date > t2.forecast_date
         AND DATE_DIFF(p.payment_date, t2.forecast_date, DAY) <= t2.horizon_days
        GROUP BY t2.forecast_date, t2.horizon_days, p.order_id
    ) AS x ON x.forecast_date = t.forecast_date AND x.horizon_days = t.horizon_days AND x.order_id = i.order_id
    WHERE t.forecast_date < as_of
    GROUP BY t.forecast_date, t.horizon_days
),
open_counts AS (
    SELECT t.forecast_date, t.horizon_days, COUNT(*) AS n
    FROM st AS t JOIN si AS i ON i.snapshot_date = t.forecast_date
    GROUP BY t.forecast_date, t.horizon_days
),

checks AS (
    SELECT '01. Latest open book = source rebuild (items and rupees)' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM si WHERE snapshot_date = as_of) - (SELECT COUNT(*) FROM src_open))
         + CAST(ROUND(ABS((SELECT SUM(outstanding) FROM si WHERE snapshot_date = as_of) - (SELECT SUM(outstanding) FROM src_open)), 0) AS INT64) AS actual
    UNION ALL
    SELECT '02. Collected shares lie in 0-1 and never fall as the horizon grows', 0,
           (SELECT COUNTIF(share_30 < 0 OR share_90 > 1 OR share_30 > share_60 OR share_60 > share_90) FROM si)
    UNION ALL
    SELECT '03. Age band agrees with age in days', 0,
           (SELECT COUNTIF(age_band != CASE WHEN age_days <= 30 THEN 1 WHEN age_days <= 60 THEN 2 WHEN age_days <= 90 THEN 3
                                            WHEN age_days <= 180 THEN 4 WHEN age_days <= 365 THEN 5 ELSE 6 END) FROM si)
    UNION ALL
    SELECT '04. 28 snapshots, each the last day of a month', 0,
           ABS((SELECT COUNT(DISTINCT snapshot_date) FROM si) - 28)
         + (SELECT COUNTIF(EXTRACT(DAY FROM DATE_ADD(snapshot_date, INTERVAL 1 DAY)) != 1) FROM (SELECT DISTINCT snapshot_date FROM si))
    UNION ALL
    SELECT '05. History pools only use outcomes known at the forecast date', 0,
           (SELECT COUNTIF(DATE_DIFF(forecast_date, snapshot_date, DAY) > 365
                        OR DATE_DIFF(forecast_date, snapshot_date, DAY) < horizon_days) FROM pl)
    UNION ALL
    SELECT '06. Pool members are numbered 1..n in every month and age band', 0,
           (SELECT COUNTIF(mx != n OR mx != members) FROM (
               SELECT forecast_date, horizon_days, snapshot_no, age_band, MAX(member_no) AS mx, COUNT(*) AS n, MAX(members) AS members
               FROM pl GROUP BY forecast_date, horizon_days, snapshot_no, age_band))
    UNION ALL
    SELECT '07. Replicates = 500 per forecast date and horizon', 0,
           (SELECT COUNT(*) FROM rp) - (SELECT COUNT(*) FROM st) * replicates
         + (SELECT COUNTIF(n != replicates) FROM (SELECT forecast_date, horizon_days, COUNT(*) AS n FROM rp GROUP BY forecast_date, horizon_days))
    UNION ALL
    SELECT '08. Each replicate draws at most one history item per open item', 0,
           (SELECT COUNT(*) FROM rp JOIN open_counts AS c USING (forecast_date, horizon_days) WHERE rp.items_drawn > c.n)
    UNION ALL
    SELECT '09. Actual collections = recount from payments (rupees, rounded)', 0,
           (SELECT COUNT(*) FROM rs JOIN actual_recount AS a USING (forecast_date, horizon_days)
             WHERE ROUND(rs.actual_collections) != ROUND(a.actual))
    UNION ALL
    SELECT '10. P10 <= P50 <= P90, and the mean lies inside the range', 0,
           (SELECT COUNTIF(NOT (mc_p10 <= mc_p50 AND mc_p50 <= mc_p90 AND mc_mean BETWEEN mc_p10 AND mc_p90)) FROM rs)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
