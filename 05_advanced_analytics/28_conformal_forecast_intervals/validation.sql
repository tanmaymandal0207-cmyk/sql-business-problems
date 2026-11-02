/* =============================================================================
   Case study · Conformal forecast intervals — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_test DATE    DEFAULT DATE '2025-07-01';
DECLARE last_test  DATE    DEFAULT DATE '2026-09-01';
DECLARE z80        FLOAT64 DEFAULT 1.2816;

WITH d AS (SELECT * FROM `sahyadri_b2b.cf_demand`),
     i AS (SELECT * FROM `sahyadri_b2b.cf_intervals`),
     s AS (SELECT * FROM `sahyadri_b2b.cf_scores`),

src AS (
    SELECT SUM(it.quantity) AS units
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS it ON it.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN DATE '2024-01-01' AND DATE '2026-09-30'
),
-- previous-month recounts by self-join (independent of the window frames)
ma_recount AS (
    SELECT a.product_id, a.m, a.ma6, AVG(b.units) AS ma6_recount
    FROM d AS a JOIN d AS b ON b.product_id = a.product_id AND b.month_no BETWEEN a.month_no - 6 AND a.month_no - 1
    WHERE a.month_no > 6
    GROUP BY a.product_id, a.m, a.ma6
),
cal_recount AS (
    SELECT a.product_id, a.m, MIN(b.error) AS min_e, MAX(b.error) AS max_e, STDDEV_SAMP(b.error) AS sd_e, COUNT(b.error) AS n
    FROM i AS a
    JOIN d AS x ON x.product_id = a.product_id AND x.m = a.m
    JOIN d AS b ON b.product_id = a.product_id AND b.month_no BETWEEN x.month_no - 12 AND x.month_no - 1
    GROUP BY a.product_id, a.m
),
pooled_n AS (
    SELECT t.m, COUNT(*) AS n
    FROM (SELECT DISTINCT m FROM i) AS t
    JOIN d ON d.m < t.m AND d.m >= DATE_SUB(t.m, INTERVAL 12 MONTH) AND d.scaled_error IS NOT NULL
    GROUP BY t.m
),

checks AS (
    SELECT '01. One row per product per month, units = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM d) - (SELECT COUNT(*) FROM `sahyadri_b2b.products`) * 33)
         + IF(ABS((SELECT SUM(units) FROM d) - (SELECT units FROM src)) > 0.01, 1, 0) AS actual
    UNION ALL
    SELECT '02. MA6 = average of the previous six months (recount)', 0,
           (SELECT COUNTIF(ABS(ma6 - ma6_recount) > 1e-9) FROM ma_recount)
    UNION ALL
    SELECT '03. Error = units - MA6 from month 7, none before', 0,
           (SELECT COUNTIF((month_no > 6 AND ABS(error - (units - ma6)) > 1e-9) OR (month_no <= 6 AND error IS NOT NULL)) FROM d)
    UNION ALL
    SELECT '04. Back-test rows: test months, 12 errors and some demand in the year before', 0,
           (SELECT COUNTIF(m NOT BETWEEN first_test AND last_test) FROM i)
         + (SELECT COUNTIF(n != 12) FROM cal_recount)
    UNION ALL
    SELECT '05. Conformal range = MA6 + smallest and largest of the 12 errors (recount)', 0,
           (SELECT COUNT(*) FROM i JOIN cal_recount AS c USING (product_id, m)
             WHERE ABS(i.conformal_high - (i.ma6 + c.max_e)) > 1e-9 OR ABS(i.conformal_low - GREATEST(i.ma6 + c.min_e, 0)) > 1e-9)
    UNION ALL
    SELECT '06. Normal range = MA6 +/- 1.2816 SD of the 12 errors (recount)', 0,
           (SELECT COUNT(*) FROM i JOIN cal_recount AS c USING (product_id, m)
             WHERE ABS(i.normal_high - (i.ma6 + z80 * c.sd_e)) > 1e-6)
    UNION ALL
    SELECT '07. Pooled ranges use every scaled error of the previous 12 months', 0,
           (SELECT COUNT(*) FROM (SELECT DISTINCT m, n_pooled FROM i) AS a JOIN pooled_n AS b USING (m) WHERE a.n_pooled != b.n)
    UNION ALL
    SELECT '08. Every range has 0 <= low <= high', 0,
           (SELECT COUNTIF(low < 0 OR low > high) FROM s)
    UNION ALL
    SELECT '09. Three methods for every back-test product-month', 0,
           ABS((SELECT COUNT(*) FROM s) - 3 * (SELECT COUNT(*) FROM i))
         + (SELECT COUNTIF(n != 3) FROM (SELECT product_id, m, COUNT(DISTINCT method) AS n FROM s GROUP BY product_id, m))
    UNION ALL
    SELECT '10. Coverage of the conformal range = recount from the interval table', 0,
           IF(ABS((SELECT AVG(IF(units BETWEEN low AND high, 1, 0)) FROM s WHERE method = 'Conformal (own errors)')
                  - (SELECT AVG(IF(units >= conformal_low AND units <= conformal_high, 1, 0)) FROM i)) > 1e-12, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
