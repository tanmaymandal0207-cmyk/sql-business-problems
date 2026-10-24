/* =============================================================================
   Case study · Safety stock and reorder points — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE train_start      DATE    DEFAULT DATE '2024-09-30';
DECLARE review_start     DATE    DEFAULT DATE '2025-09-29';
DECLARE last_week        DATE    DEFAULT DATE '2026-09-21';
DECLARE lead_time_weeks  FLOAT64 DEFAULT 3;
DECLARE lead_time_sd     FLOAT64 DEFAULT 1;
DECLARE order_cost       FLOAT64 DEFAULT 1500;
DECLARE holding_rate     FLOAT64 DEFAULT 0.24;

WITH w AS (SELECT * FROM `sahyadri_b2b.weekly_product_demand`),
     s AS (SELECT * FROM `sahyadri_b2b.safety_stock_policy`),
     b AS (SELECT * FROM `sahyadri_b2b.safety_stock_backtest`),

src_units AS (
    SELECT SUM(i.quantity) AS units
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date >= train_start
      AND o.order_date <  DATE_ADD(last_week, INTERVAL 7 DAY)
),
-- review-year mean and variance recomputed from sums (not AVG / STDDEV)
moments AS (
    SELECT product_id,
           SUM(units) / COUNT(*) AS mean_w,
           (SUM(units * units) - SUM(units) * SUM(units) / COUNT(*)) / (COUNT(*) - 1) AS var_w
    FROM w WHERE period = 'Review'
    GROUP BY product_id
),
class_share AS (
    SELECT
        SUM(IF(s.abc_class = 'A', r.revenue, 0)) / SUM(r.revenue)                              AS a_share,
        (SUM(IF(s.abc_class = 'A', r.revenue, 0)) - MIN(IF(s.abc_class = 'A', r.revenue, NULL))) / SUM(r.revenue) AS a_share_without_last
    FROM s JOIN (SELECT product_id, SUM(revenue) AS revenue FROM w WHERE period = 'Review' GROUP BY product_id) AS r
      ON r.product_id = s.product_id
),

checks AS (
    SELECT '01. Weekly rows vs products x 104 weeks' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM w) - (SELECT COUNT(*) FROM `sahyadri_b2b.products`) * 104 AS actual
    UNION ALL
    SELECT '02. Weekly units vs source units', 0,
           (SELECT SUM(units) FROM w) - (SELECT units FROM src_units)
    UNION ALL
    SELECT '03. Policy rows vs product master', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT product_id) FROM s)
         + (SELECT COUNT(*) FROM s) - (SELECT COUNT(*) FROM `sahyadri_b2b.products`)
    UNION ALL
    SELECT '04. Class A is the smallest set reaching 80 % of revenue', 0,
           (SELECT IF(a_share >= 0.80 AND a_share_without_last < 0.80, 0, 1) FROM class_share)
    UNION ALL
    SELECT '05. Safety stock vs formula from independently computed moments', 0,
           (SELECT COUNTIF(s.safety_stock_units <> CEIL(s.z * SQRT(lead_time_weeks * m.var_w
                                                                   + POW(m.mean_w, 2) * POW(lead_time_sd, 2)) - 1e-9))
              FROM s JOIN moments AS m ON m.product_id = s.product_id
             WHERE s.abc_class <> 'No demand')
    UNION ALL
    SELECT '06. Reorder point not equal to lead-time demand plus safety stock (within rounding)', 0,
           (SELECT COUNTIF(ABS(reorder_point_units - safety_stock_units - mean_weekly_units * lead_time_weeks) > 1.01)
              FROM s WHERE abc_class <> 'No demand')
    UNION ALL
    SELECT '07. EOQ vs formula', 0,
           (SELECT COUNTIF(s.eoq_units <> CEIL(SQRT(2 * m.mean_w * 52 * order_cost / (holding_rate * s.unit_cost)) - 1e-9))
              FROM s JOIN moments AS m ON m.product_id = s.product_id
             WHERE s.abc_class <> 'No demand' AND s.unit_cost IS NOT NULL)
    UNION ALL
    SELECT '08. Service level or z inconsistent with class', 0,
           (SELECT COUNTIF((abc_class = 'A' AND (service_level <> 0.98 OR z <> 2.0537))
                        OR (abc_class = 'B' AND (service_level <> 0.95 OR z <> 1.6449))
                        OR (abc_class = 'C' AND (service_level <> 0.90 OR z <> 1.2816))) FROM s)
    UNION ALL
    SELECT '09. Backtest products without 50 full 3-week windows', 0,
           (SELECT COUNTIF(windows <> 50) FROM b)
    UNION ALL
    SELECT '10. Demand pattern inconsistent with its rule', 0,
           (SELECT COUNTIF(
                 (demand_pattern = 'Lumpy'   AND NOT (zero_week_share > 0.5 OR cv > 1.5))
              OR (demand_pattern = 'Regular' AND NOT (zero_week_share <= 0.5 AND cv <= 1.5))) FROM s)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
