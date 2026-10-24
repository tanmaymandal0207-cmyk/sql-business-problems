/* =============================================================================
   Case study · Time-to-reorder survival analysis — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start DATE DEFAULT DATE '2024-01-01';
DECLARE as_of_date   DATE DEFAULT DATE '2026-09-30';

WITH sp AS (SELECT * FROM `sahyadri_b2b.reorder_spells`),
     kc AS (SELECT * FROM `sahyadri_b2b.reorder_survival_curve`),
     kd AS (SELECT * FROM `sahyadri_b2b.reorder_survival_daily`),

src_days AS (
    SELECT DISTINCT customer_id, order_date
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
      AND order_date BETWEEN period_start AND as_of_date
),
-- S(30) for all customers recomputed with a join instead of window functions
event_days AS (
    SELECT duration_days AS t, COUNTIF(reordered) AS d
    FROM sp WHERE duration_days <= 30
    GROUP BY duration_days HAVING COUNTIF(reordered) > 0
),
risk AS (
    SELECT e.t, e.d, COUNT(*) AS n
    FROM event_days AS e
    JOIN sp ON sp.duration_days >= e.t
    GROUP BY e.t, e.d
),
s30_recount AS (SELECT EXP(SUM(LN(1 - d / n))) AS s FROM risk),
monotone AS (
    SELECT curve, t, survival, greenwood_sum,
           LAG(survival)      OVER (PARTITION BY curve ORDER BY t) AS prev_s,
           LAG(greenwood_sum) OVER (PARTITION BY curve ORDER BY t) AS prev_g
    FROM kd
),

checks AS (
    SELECT '01. Duplicate spells (customer x date)' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(spell_start AS STRING))) FROM sp) AS actual
    UNION ALL
    SELECT '02. Spells vs distinct customer order dates in source', 0,
           (SELECT COUNT(*) FROM sp) - (SELECT COUNT(*) FROM src_days)
    UNION ALL
    SELECT '03. Open (censored) spells vs customers: exactly one each', 0,
           (SELECT COUNTIF(NOT reordered) FROM sp) - (SELECT COUNT(DISTINCT customer_id) FROM src_days)
    UNION ALL
    SELECT '04. Durations inconsistent with dates', 0,
           (SELECT COUNTIF((reordered AND (duration_days <= 0 OR duration_days <> DATE_DIFF(next_order_date, spell_start, DAY)))
                        OR (NOT reordered AND duration_days <> DATE_DIFF(as_of_date, spell_start, DAY))) FROM sp)
    UNION ALL
    SELECT '05. First at-risk count vs spells in the curve', 0,
           (SELECT COUNTIF(k.n_at_risk <> c.spells) FROM
               (SELECT curve, n_at_risk FROM kc WHERE TRUE QUALIFY ROW_NUMBER() OVER (PARTITION BY curve ORDER BY t) = 1) AS k
               JOIN (SELECT customer_segment AS curve, COUNT(*) AS spells FROM sp GROUP BY customer_segment
                     UNION ALL SELECT 'All customers', COUNT(*) FROM sp) AS c ON c.curve = k.curve)
    UNION ALL
    SELECT '06. Survival outside 0-1 or increasing over time', 0,
           (SELECT COUNTIF(survival < 0 OR survival > 1 OR survival > prev_s + 1e-12) FROM monotone)
    UNION ALL
    SELECT '07. S(30) for all customers vs independent product-limit recount', 0,
           (SELECT IF(ABS(k.survival - r.s) < 1e-9, 0, 1)
              FROM kd AS k CROSS JOIN s30_recount AS r
             WHERE k.curve = 'All customers' AND k.t = 30)
    UNION ALL
    SELECT '08. Events in each curve vs reordered spells', 0,
           (SELECT COUNTIF(k.events <> c.n) FROM
               (SELECT curve, SUM(events) AS events FROM kc GROUP BY curve) AS k
               JOIN (SELECT customer_segment AS curve, COUNTIF(reordered) AS n FROM sp GROUP BY customer_segment
                     UNION ALL SELECT 'All customers', COUNTIF(reordered) FROM sp) AS c ON c.curve = k.curve)
    UNION ALL
    SELECT '09. Daily table incomplete, or survival at day 0 not 1', 0,
           (SELECT COUNT(DISTINCT curve) * 1001 - COUNT(*) FROM kd)
         + (SELECT COUNTIF(t = 0 AND survival <> 1) FROM kd)
    UNION ALL
    SELECT '10. Greenwood sum negative or decreasing', 0,
           (SELECT COUNTIF(greenwood_sum < 0 OR greenwood_sum < prev_g - 1e-15) FROM monotone)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
