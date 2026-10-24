/* =============================================================================
   Case study · Statistical process control — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_week     DATE DEFAULT DATE '2024-01-01';
DECLARE baseline_end   DATE DEFAULT DATE '2025-06-30';
DECLARE last_week_late DATE DEFAULT DATE '2026-08-31';
DECLARE last_week_all  DATE DEFAULT DATE '2026-09-21';

WITH w  AS (SELECT * FROM `sahyadri_b2b.spc_weekly`),
     c  AS (SELECT * FROM `sahyadri_b2b.spc_chart`),
     sg AS (SELECT * FROM `sahyadri_b2b.spc_signals`),

src_closed AS (
    SELECT COUNT(*) AS n, COUNTIF(order_status = 'Cancelled') AS x
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status IN ('Delivered', 'Cancelled', 'Returned')
      AND DATE_TRUNC(order_date, ISOWEEK) BETWEEN first_week AND last_week_all
),
-- R4 recomputed with a self-join: weeks whose 7 predecessors and itself are all on one side
r4_recount AS (
    SELECT a.process, a.week_start
    FROM c AS a
    JOIN c AS b
      ON b.process = a.process
     AND b.week_start BETWEEN DATE_SUB(a.week_start, INTERVAL 49 DAY) AND a.week_start
    GROUP BY a.process, a.week_start
    HAVING COUNT(*) = 8 AND (COUNTIF(b.z > 0) = 8 OR COUNTIF(b.z < 0) = 8)
),
consecutive AS (
    SELECT process, week_start,
           DATE_DIFF(week_start, LAG(week_start) OVER (PARTITION BY process ORDER BY week_start), DAY) AS gap
    FROM c
),

checks AS (
    SELECT '01. Duplicate process-week rows' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(process, '|', CAST(week_start AS STRING))) FROM w) AS actual
    UNION ALL
    SELECT '02. Cancellation counts vs source closed orders', 0,
           (SELECT SUM(n) - (SELECT n FROM src_closed) + SUM(x) - (SELECT x FROM src_closed)
              FROM w WHERE process = 'Cancellation')
    UNION ALL
    SELECT '03. Weeks missing between first and last (gaps other than 7 days)', 0,
           (SELECT COUNTIF(gap IS NOT NULL AND gap <> 7) FROM consecutive)
    UNION ALL
    SELECT '04. Centre line not equal to the baseline rate', 0,
           (SELECT COUNTIF(ABS(c.p_bar - b.rate) > 1e-12) FROM c
              JOIN (SELECT process, SUM(x) / SUM(n) AS rate FROM w WHERE phase = 'Baseline' GROUP BY process) AS b
                ON b.process = c.process)
    UNION ALL
    SELECT '05. Limits not symmetric at 3 sigma (UCL - centre <> 3 sigma)', 0,
           (SELECT COUNTIF(ABS(ucl - p_bar - 3 * sigma) > 1e-12 OR lcl < 0 OR lcl > p_bar) FROM c)
    UNION ALL
    SELECT '06. R1 signals vs points outside the control limits', 0,
           (SELECT COUNTIF(rule LIKE 'R1%') FROM sg) - (SELECT COUNTIF(p > ucl OR (p < lcl AND lcl > 0)) FROM c)
    UNION ALL
    SELECT '07. R4 signals vs independent self-join recount', 0,
           (SELECT COUNTIF(rule LIKE 'R4%') FROM sg) - (SELECT COUNT(*) FROM r4_recount)
    UNION ALL
    SELECT '08. Phase inconsistent with the baseline end date', 0,
           (SELECT COUNTIF((phase = 'Baseline') <> (week_start <= baseline_end)) FROM w)
    UNION ALL
    SELECT '09. Late-delivery weeks after the cut-off', 0,
           (SELECT COUNTIF(process = 'Late delivery' AND week_start > last_week_late) FROM w)
    UNION ALL
    SELECT '10. Events above orders, or empty weeks', 0,
           (SELECT COUNTIF(x > n OR n = 0) FROM w)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
