/* =============================================================================
   Case study · Little's Law backlog planning — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE start_date DATE  DEFAULT DATE '2024-01-01';
DECLARE as_of      DATE  DEFAULT DATE '2026-09-30';
DECLARE stale_days INT64 DEFAULT 30;

WITH o AS (SELECT * FROM `sahyadri_b2b.ll_orders`),
     dly AS (SELECT * FROM `sahyadri_b2b.ll_daily`),
     y AS (SELECT * FROM `sahyadri_b2b.ll_yearly`),

ship AS (
    SELECT order_id, MIN(shipment_date) AS first_ship FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
expected_orders AS (
    SELECT x.order_id
    FROM `sahyadri_b2b.sales_orders` AS x
    LEFT JOIN ship AS s ON s.order_id = x.order_id
    WHERE x.order_date BETWEEN start_date AND as_of
      AND ((s.first_ship IS NOT NULL AND s.first_ship >= x.order_date)
           OR (s.first_ship IS NULL AND x.order_status IN ('Pending', 'Processing')))
),
-- check 05: the daily count on one date, recounted directly from order dates
spot AS (
    SELECT d,
           (SELECT COUNT(*) FROM o WHERE s1_start <= d AND (s1_open OR s1_end > d))                         AS awaiting,
           (SELECT COUNT(*) FROM o WHERE s2_start <= d AND (s2_open OR s2_end > d))                         AS in_transit,
           (SELECT COUNT(*) FROM o WHERE s2_open AND DATE_DIFF(d, s2_start, DAY) > stale_days)               AS stale
    FROM UNNEST([DATE '2024-06-30', DATE '2025-03-31', DATE '2025-12-15', DATE '2026-09-30']) AS d
),
-- check 06: total order-days = sum of daily counts
order_days AS (
    SELECT
        SUM(IF(s1_open, DATE_DIFF(as_of, s1_start, DAY) + 1, DATE_DIFF(s1_end, s1_start, DAY)))           AS s1_days,
        SUM(IF(s2_start IS NULL, 0, IF(s2_open, DATE_DIFF(as_of, s2_start, DAY) + 1, DATE_DIFF(s2_end, s2_start, DAY)))) AS s2_days
    FROM o
),

checks AS (
    SELECT '01. One row per order that entered the dispatch queue (shipped, or still pending)' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT COUNT(*) FROM expected_orders)) + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM o) AS actual
    UNION ALL
    SELECT '02. Stage dates in order: order <= dispatch <= delivery, open stages end at the as-of date', 0,
           (SELECT COUNTIF(s1_end < s1_start OR (s2_start IS NOT NULL AND (s2_start != s1_end OR s2_end < s2_start))
                           OR (s1_open AND s1_end != as_of) OR (s2_open AND s2_end != as_of)
                           OR (s1_open AND s2_start IS NOT NULL)) FROM o)
    UNION ALL
    SELECT '03. One row per stage and calendar day', 0,
           (SELECT COUNTIF(n != DATE_DIFF(as_of, start_date, DAY) + 1) FROM (SELECT stage, COUNT(*) AS n FROM dly GROUP BY stage))
         + ABS(4 - (SELECT COUNT(DISTINCT stage) FROM dly))
    UNION ALL
    SELECT '04. Daily counts are never negative, and entries = orders entering each stage', 0,
           (SELECT COUNTIF(in_stage < 0) FROM dly)
         + ABS((SELECT SUM(entered) FROM dly WHERE stage = 'Awaiting dispatch') - (SELECT COUNT(*) FROM o))
         + ABS((SELECT SUM(entered) FROM dly WHERE stage = 'In transit') - (SELECT COUNTIF(s2_start IS NOT NULL) FROM o))
    UNION ALL
    SELECT '05. Daily counts on four dates = direct recount from order dates', 0,
           (SELECT COUNTIF(a.in_stage != s.awaiting) FROM spot AS s JOIN dly AS a ON a.d = s.d AND a.stage = 'Awaiting dispatch')
         + (SELECT COUNTIF(a.in_stage != s.in_transit) FROM spot AS s JOIN dly AS a ON a.d = s.d AND a.stage = 'In transit')
         + (SELECT COUNTIF(a.in_stage != s.stale) FROM spot AS s JOIN dly AS a ON a.d = s.d AND a.stage = 'Stale: in transit 30+ days, never delivered')
    UNION ALL
    SELECT '06. Sum of daily counts = total order-days in each stage (Little''s Law identity)', 0,
           ABS((SELECT SUM(in_stage) FROM dly WHERE stage = 'Awaiting dispatch') - (SELECT s1_days FROM order_days))
         + ABS((SELECT SUM(in_stage) FROM dly WHERE stage = 'In transit') - (SELECT s2_days FROM order_days))
    UNION ALL
    SELECT '07. Delivered-only and stale counts never exceed the recorded in-transit count', 0,
           (SELECT COUNTIF(dv.in_stage + st.in_stage > t.in_stage)
              FROM dly AS t
              JOIN dly AS dv ON dv.d = t.d AND dv.stage = 'In transit, delivered orders'
              JOIN dly AS st ON st.d = t.d AND st.stage = 'Stale: in transit 30+ days, never delivered'
             WHERE t.stage = 'In transit')
    UNION ALL
    SELECT '08. Yearly entries add up to all entries', 0,
           ABS((SELECT SUM(entries) FROM y WHERE stage = 'Awaiting dispatch') - (SELECT COUNT(*) FROM o))
         + ABS((SELECT SUM(entries) FROM y WHERE stage = 'In transit') - (SELECT COUNTIF(s2_start IS NOT NULL) FROM o))
    UNION ALL
    SELECT '09. Yearly lambda and L recomputed from the daily table', 0,
           (SELECT COUNTIF(ABS(y.lambda_per_day - z.e / z.n) > 1e-9 OR ABS(y.l_observed - z.l) > 1e-9)
              FROM y
              JOIN (SELECT stage, EXTRACT(YEAR FROM d) AS period, SUM(entered) AS e, COUNT(*) AS n, AVG(in_stage) AS l
                      FROM dly GROUP BY stage, period) AS z
                ON z.stage = y.stage AND z.period = y.period)
    UNION ALL
    SELECT '10. Three years for each of the three flow stages', 0,
           ABS(9 - (SELECT COUNT(*) FROM y))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
