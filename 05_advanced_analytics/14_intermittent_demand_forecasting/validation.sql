/* =============================================================================
   Case study · Intermittent demand forecasting — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE alpha        FLOAT64 DEFAULT 0.1;
DECLARE lead_weeks   INT64   DEFAULT 4;
DECLARE first_origin INT64   DEFAULT 52;

WITH w AS (SELECT * FROM `sahyadri_b2b.idf_weekly`),
     s AS (SELECT * FROM `sahyadri_b2b.idf_states`),
     b AS (SELECT * FROM `sahyadri_b2b.idf_backtest`),
     p AS (SELECT * FROM `sahyadri_b2b.idf_pattern`),

lagged AS (
    SELECT *,
           LAG(f_ses)     OVER (PARTITION BY product_id ORDER BY week_index) AS prev_ses,
           LAG(f_croston) OVER (PARTITION BY product_id ORDER BY week_index) AS prev_croston
    FROM s
),
first_demand AS (
    SELECT product_id, MIN(week_index) AS wk FROM w WHERE units > 0 GROUP BY product_id
),
ma_recount AS (
    SELECT a.product_id, a.week_index, AVG(b2.units) AS ma
    FROM w AS a
    JOIN w AS b2 ON b2.product_id = a.product_id AND b2.week_index BETWEEN a.week_index - 12 AND a.week_index
    GROUP BY a.product_id, a.week_index
),
lead_recount AS (
    SELECT a.product_id, a.week_index, SUM(b2.units) AS lead_demand
    FROM w AS a
    JOIN w AS b2 ON b2.product_id = a.product_id AND b2.week_index BETWEEN a.week_index + 1 AND a.week_index + lead_weeks
    GROUP BY a.product_id, a.week_index
),

checks AS (
    SELECT '01. Weekly grid = products x weeks, one row each' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM w) - (SELECT COUNT(DISTINCT product_id) * COUNT(DISTINCT week_index) FROM w)
         + (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(product_id AS STRING), '|', CAST(week_index AS STRING))) FROM w) AS actual
    UNION ALL
    SELECT '02. Weekly units vs source', 0,
           (SELECT SUM(units) FROM w)
         - (SELECT SUM(i.quantity) FROM `sahyadri_b2b.sales_order_items` AS i
              JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
             WHERE o.order_status NOT IN ('Cancelled', 'Returned'))
    UNION ALL
    SELECT '03. Pattern inconsistent with ADI and CV2', 0,
           (SELECT COUNTIF(pattern != CASE WHEN adi < 1.32 AND cv2 < 0.49 THEN 'Smooth' WHEN adi < 1.32 THEN 'Erratic'
                                            WHEN cv2 < 0.49 THEN 'Intermittent' ELSE 'Lumpy' END) FROM p)
    UNION ALL
    SELECT '04. SES closed form = recursion a*y + (1-a)*previous', 0,
           (SELECT COUNTIF(ABS(f_ses - (alpha * units + (1 - alpha) * prev_ses)) > 1e-6) FROM lagged WHERE week_index >= 2)
    UNION ALL
    SELECT '05. Croston forecast unchanged in weeks without demand', 0,
           (SELECT COUNTIF(units = 0 AND prev_croston IS NOT NULL AND ABS(f_croston - prev_croston) > 1e-9) FROM lagged)
    UNION ALL
    SELECT '06. Croston at first demand = first size / first interval', 0,
           (SELECT COUNTIF(ABS(s.f_croston - s.units / f.wk) > 1e-9) FROM s JOIN first_demand AS f
              ON f.product_id = s.product_id AND f.wk = s.week_index)
    UNION ALL
    SELECT '07. MA13 vs self-join recount', 0,
           (SELECT COUNTIF(ABS(s.f_ma13 - m.ma) > 1e-9) FROM s JOIN ma_recount AS m USING (product_id, week_index))
    UNION ALL
    SELECT '08. Lead-time demand vs self-join recount', 0,
           (SELECT COUNTIF(b.lead_demand != l.lead_demand) FROM b
              JOIN lead_recount AS l ON l.product_id = b.product_id AND l.week_index = b.origin)
    UNION ALL
    SELECT '09. Forecasts = 5 methods x origins x products', 0,
           (SELECT COUNT(*) FROM b)
         - 5 * (SELECT COUNT(DISTINCT product_id) FROM w)
             * (SELECT COUNT(DISTINCT week_index) FROM w
                 WHERE week_index >= first_origin AND week_index <= (SELECT MAX(week_index) FROM w) - lead_weeks)
    UNION ALL
    SELECT '10. SBA = (1 - a/2) x Croston on every forecast', 0,
           (SELECT COUNTIF(ABS(x.forecast - (1 - alpha / 2) * y.forecast) > 1e-9)
              FROM b AS x JOIN b AS y USING (product_id, origin)
             WHERE x.method = '5. SBA' AND y.method = '4. Croston')
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
