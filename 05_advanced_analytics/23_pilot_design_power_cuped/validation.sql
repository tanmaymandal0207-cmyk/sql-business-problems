/* =============================================================================
   Case study · Pilot design, power and CUPED — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE z_alpha  FLOAT64 DEFAULT 1.96;
DECLARE z_power  FLOAT64 DEFAULT 0.8416;
DECLARE uplift   FLOAT64 DEFAULT 0.10;
DECLARE splits   INT64   DEFAULT 500;

WITH c AS (SELECT * FROM `sahyadri_b2b.pd_customers`),
     d AS (SELECT * FROM `sahyadri_b2b.pd_designs`),
     a AS (SELECT * FROM `sahyadri_b2b.pd_aa_tests`),

orders AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, o.order_date
),
active_3m AS (
    SELECT customer_id FROM orders WHERE order_date BETWEEN DATE '2025-07-01' AND DATE '2026-06-30' GROUP BY customer_id
),
totals_3m AS (
    SELECT SUM(IF(o.order_date BETWEEN DATE '2026-07-01' AND DATE '2026-09-30', o.v, 0)) AS y,
           SUM(IF(o.order_date BETWEEN DATE '2025-07-01' AND DATE '2026-06-30', o.v, 0)) AS x
    FROM orders AS o JOIN active_3m USING (customer_id)
),
moments AS (
    SELECT pilot, COVAR_POP(x_revenue, y_revenue) / VAR_POP(x_revenue) AS theta_rev, CORR(x_orders, y_orders) AS rho_orders
    FROM c GROUP BY pilot
),

checks AS (
    SELECT '01. 3-month pilot: one row per customer active in the pre-period' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM c WHERE pilot = '3 months') - (SELECT COUNT(*) FROM active_3m))
         + (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(pilot, CAST(customer_id AS STRING))) FROM c) AS actual
    UNION ALL
    SELECT '02. 3-month window and pre-period revenue = source totals', 0,
           IF(ABS((SELECT SUM(y_revenue) FROM c WHERE pilot = '3 months') - (SELECT y FROM totals_3m)) > 1, 1, 0)
         + IF(ABS((SELECT SUM(x_revenue) FROM c WHERE pilot = '3 months') - (SELECT x FROM totals_3m)) > 1, 1, 0)
    UNION ALL
    SELECT '03. Capped values never exceed the raw value, and a zero stays zero', 0,
           (SELECT COUNTIF(y_capped > y_revenue + 1e-6 OR x_capped > x_revenue + 1e-6 OR (y_revenue = 0 AND y_capped != 0)) FROM c)
    UNION ALL
    SELECT '04. No orders in the window exactly when no revenue, and every customer had pre-period orders', 0,
           (SELECT COUNTIF((y_orders = 0) != (y_revenue = 0) OR x_orders = 0 OR x_revenue <= 0) FROM c)
    UNION ALL
    SELECT '05. Theta and correlation recomputed', 0,
           (SELECT COUNTIF(ABS(d.theta - m.theta_rev) > 1e-9) FROM d JOIN moments AS m USING (pilot) WHERE d.metric = 'Revenue')
         + (SELECT COUNTIF(ABS(d.rho - m.rho_orders) > 1e-12) FROM d JOIN moments AS m USING (pilot) WHERE d.metric = 'Orders')
         + (SELECT COUNTIF(rho < -1 OR rho > 1) FROM d)
    UNION ALL
    SELECT '06. CUPED SD = plain SD x SQRT(1 - rho^2), never above plain', 0,
           (SELECT COUNTIF(ABS(sd_used - sd_y * SQRT(1 - POW(rho, 2))) > 1e-9 OR sd_used > sd_y + 1e-9) FROM d WHERE adjustment = 'CUPED')
         + (SELECT COUNTIF(ABS(sd_used - sd_y) > 1e-12) FROM d WHERE adjustment = 'Plain')
    UNION ALL
    SELECT '07. MDE and customers needed recomputed from the formula', 0,
           (SELECT COUNTIF(ABS(mde_relative - (z_alpha + z_power) * sd_used * SQRT(2 / per_arm) / mean_y) > 1e-12
                           OR ABS(per_arm_needed_for_uplift - CEIL(2 * POW((z_alpha + z_power) * sd_used / (uplift * mean_y), 2))) > 0.5)
              FROM d)
    UNION ALL
    SELECT '08. 500 A/A random draws for each of 12 pilot x metric designs', 0,
           ABS(12 - (SELECT COUNT(DISTINCT CONCAT(pilot, metric, adjustment)) FROM a))
         + (SELECT COUNTIF(k != splits) FROM (SELECT pilot, metric, adjustment, COUNT(*) AS k FROM a GROUP BY pilot, metric, adjustment))
    UNION ALL
    SELECT '09. A/A z-scores finite, centred near zero (|mean z| < 0.2)', 0,
           (SELECT COUNTIF(z IS NULL OR ABS(z) > 10) FROM a)
         + (SELECT COUNTIF(ABS(mz) >= 0.2) FROM (SELECT pilot, metric, adjustment, AVG(z) AS mz FROM a GROUP BY pilot, metric, adjustment))
    UNION ALL
    SELECT '10. A/A spread of differences within 10 % of the formula', 0,
           (SELECT COUNTIF(ABS(s.sd / (d.sd_used * SQRT(2 / d.per_arm)) - 1) > 0.10)
              FROM (SELECT pilot, metric, adjustment, STDDEV_POP(diff) AS sd FROM a GROUP BY pilot, metric, adjustment) AS s
              JOIN d USING (pilot, metric, adjustment))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
