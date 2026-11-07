/* =============================================================================
   Case study · Are silent customers lost? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE calibration_end DATE    DEFAULT DATE '2026-06-30';
DECLARE holdout_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE holdout_weeks   FLOAT64 DEFAULT 92 / 7;

WITH c AS (SELECT * FROM `sahyadri_b2b.bt_customers`),
     kc AS (SELECT * FROM `sahyadri_b2b.bt_kcounts`),
     g AS (SELECT * FROM `sahyadri_b2b.bt_nbd_grid`),
     n AS (SELECT * FROM `sahyadri_b2b.bt_nbd`),
     pr AS (SELECT * FROM `sahyadri_b2b.bt_profile`),
     p AS (SELECT * FROM `sahyadri_b2b.bt_predictions`),

days AS (
    SELECT DISTINCT customer_id, order_date FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned') AND order_date <= holdout_end
),
recount AS (
    SELECT customer_id, x, y,
           DATE_DIFF(last_cal, first_d, DAY) / 7 AS t_x,
           DATE_DIFF(calibration_end, first_d, DAY) / 7 AS t_cal
    FROM (
        SELECT customer_id,
               COUNTIF(order_date <= calibration_end) - 1 AS x,
               COUNTIF(order_date > calibration_end) AS y,
               MAX(IF(order_date <= calibration_end, order_date, NULL)) AS last_cal,
               MIN(order_date) AS first_d
        FROM days GROUP BY customer_id HAVING MIN(order_date) <= calibration_end
    )
),
nbd_direct AS (
    -- NBD log-likelihood at the fitted point, with the gamma ratio summed per customer (no n_k shortcut)
    SELECT SUM(IFNULL(gr.s, 0) + n.r * LN(n.alpha) - (n.r + c.x) * LN(n.alpha + c.t_cal)) AS ll
    FROM c CROSS JOIN n
    LEFT JOIN (SELECT c2.customer_id, SUM(LN(n2.r + k)) AS s
               FROM c AS c2 CROSS JOIN n AS n2 CROSS JOIN UNNEST(GENERATE_ARRAY(0, 300)) AS k
               WHERE k < c2.x GROUP BY c2.customer_id) AS gr USING (customer_id)
),
bg_point AS (
    -- one BG/NBD grid point recomputed per customer with products written out
    SELECT * FROM pr WHERE m = 0.01 AND a = 0.5 AND ABS(r - 0.7) < 1e-9 AND ABS(alpha - 4.0) < 1e-9
),
bg_direct AS (
    SELECT SUM(IFNULL(gr.s, 0) + bp.r * LN(bp.alpha) - (bp.r + c.x) * LN(bp.alpha + c.t_cal)
               + IF(c.x > 0, LN(1 + EXP(LN(bp.a / (bp.a * (1 - bp.m) / bp.m + c.x - 1))
                                        + (bp.r + c.x) * (LN(bp.alpha + c.t_cal) - LN(bp.alpha + c.t_x)))), 0)) AS ll,
           ANY_VALUE(bp.ll) AS stored
    FROM c CROSS JOIN bg_point AS bp
    LEFT JOIN (SELECT c2.customer_id,
                      SUM(LN(b2.r + k) + LN(b2.a * (1 - b2.m) / b2.m + k) - LN(b2.a + b2.a * (1 - b2.m) / b2.m + k)) AS s
               FROM c AS c2 CROSS JOIN bg_point AS b2 CROSS JOIN UNNEST(GENERATE_ARRAY(0, 300)) AS k
               WHERE k < c2.x GROUP BY c2.customer_id) AS gr USING (customer_id)
),

checks AS (
    SELECT '01. Customers and repeat purchases = recount of distinct order days' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM c) - (SELECT COUNT(*) FROM recount))
         + (SELECT COUNT(*) FROM c JOIN recount AS r USING (customer_id)
             WHERE c.x != r.x OR ABS(c.t_x - r.t_x) > 1e-9 OR ABS(c.t_cal - r.t_cal) > 1e-9) AS actual
    UNION ALL
    SELECT '02. Holdout purchases = recount (July - September 2026)', 0,
           (SELECT COUNTIF(c.y != r.y) FROM c JOIN recount AS r USING (customer_id))
    UNION ALL
    SELECT '03. Sum over k of customers with x > k = total repeat purchases', 0,
           ABS((SELECT SUM(n_k) FROM kc) - (SELECT SUM(x) FROM c))
    UNION ALL
    SELECT '04. NBD grid: 266 coarse + 441 fine points, fitted point = highest likelihood', 0,
           ABS((SELECT COUNTIF(stage = 1) FROM g) - 266) + ABS((SELECT COUNTIF(stage = 2) FROM g) - 441)
         + IF((SELECT ll FROM n) < (SELECT MAX(ll) FROM g) - 1e-9, 1, 0)
    UNION ALL
    SELECT '05. NBD log-likelihood = direct recount per customer', 0,
           IF(ABS((SELECT ll FROM nbd_direct) - (SELECT ll FROM n)) > 1e-6, 1, 0)
    UNION ALL
    SELECT '06. BG/NBD profile: 7 dropout levels x 4 a x 266 points, all below the NBD fit', 0,
           ABS((SELECT COUNT(*) FROM pr) - 7 * 4 * 266)
         + (SELECT COUNTIF(ll > (SELECT ll FROM n)) FROM pr)
    UNION ALL
    SELECT '07. BG/NBD log-likelihood at a grid point = direct recount per customer', 0,
           IF((SELECT ABS(ll - stored) FROM bg_direct) > 1e-6, 1, 0)
         + ABS((SELECT COUNT(*) FROM bg_point) - 1)
    UNION ALL
    SELECT '08. Predictions follow the NBD formulas, chances between 0 and 1', 0,
           (SELECT COUNTIF(ABS(p.expected_purchases - (n.r + p.x) / (n.alpha + p.t_cal) * holdout_weeks) > 1e-9
                        OR p.p_any_purchase NOT BETWEEN 0 AND 1
                        OR ABS(p.naive_purchases - p.x / p.t_cal * holdout_weeks) > 1e-9) FROM p CROSS JOIN n)
    UNION ALL
    SELECT '09. Silent = 3+ repeat purchases and silence above twice the usual gap', 0,
           (SELECT COUNTIF(silent != (x >= 3 AND (t_cal - t_x) > 2 * t_x / x)) FROM p WHERE x > 0)
         + (SELECT COUNTIF(silent) FROM p WHERE x < 3)
    UNION ALL
    SELECT '10. Holdout is 92 days, every customer observed before it is predicted once', 0,
           IF(ABS(holdout_weeks - DATE_DIFF(holdout_end, calibration_end, DAY) / 7) > 1e-12, 1, 0)
         + ABS((SELECT COUNT(*) FROM p) - (SELECT COUNTIF(t_cal > 0) FROM c))
         + ABS((SELECT COUNT(*) FROM p) - (SELECT COUNT(DISTINCT customer_id) FROM p))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
