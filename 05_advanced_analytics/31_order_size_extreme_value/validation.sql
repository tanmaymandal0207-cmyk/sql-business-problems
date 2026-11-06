/* =============================================================================
   Case study · How big can one order get? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_day DATE    DEFAULT DATE '2024-01-01';
DECLARE last_day  DATE    DEFAULT DATE '2026-09-30';
DECLARE train_end DATE    DEFAULT DATE '2025-12-31';
DECLARE u_threshold FLOAT64 DEFAULT 500000;
DECLARE resamples INT64   DEFAULT 500;

WITH o AS (SELECT * FROM `sahyadri_b2b.ev_orders`),
     f AS (SELECT * FROM `sahyadri_b2b.ev_fits`),
     bt AS (SELECT * FROM `sahyadri_b2b.ev_bootstrap`),

src AS (
    SELECT COUNT(DISTINCT x.order_id) AS n, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned') AND x.order_date BETWEEN first_day AND last_day
),
windows AS (
    SELECT 'Full period, Rs 3 lakh' AS fit, 300000 AS u, first_day AS d0, last_day AS d1
    UNION ALL SELECT 'Full period, Rs 5 lakh', u_threshold, first_day, last_day
    UNION ALL SELECT 'Full period, Rs 8 lakh', 800000, first_day, last_day
    UNION ALL SELECT 'Train 2024-2025, Rs 5 lakh', u_threshold, first_day, train_end
),
ex AS (
    SELECT w.fit, w.u, o.order_id, o.value, o.value - w.u AS y
    FROM windows AS w JOIN o ON o.order_date BETWEEN w.d0 AND w.d1 AND o.value > w.u
),
ranked AS (
    -- rank recounted by a self-join instead of ROW_NUMBER
    SELECT a.fit, a.y, 1 + COUNTIF(b.value < a.value OR (b.value = a.value AND b.order_id < a.order_id)) AS i
    FROM ex AS a JOIN ex AS b USING (fit)
    GROUP BY a.fit, a.order_id, a.y
),
a1_recount AS (
    SELECT r.fit, SUM((c.n - r.i) / (c.n - 1) * r.y) / ANY_VALUE(c.n) AS a1, AVG(r.y) AS a0
    FROM ranked AS r JOIN (SELECT fit, COUNT(*) AS n FROM ex GROUP BY fit) AS c USING (fit)
    GROUP BY r.fit
),
full5 AS (SELECT * FROM f WHERE fit = 'Full period, Rs 5 lakh'),

checks AS (
    SELECT '01. Orders and revenue = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(value) FROM o) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Exceedances per fit = recount of orders above the threshold in the window', 0,
           (SELECT COUNT(*) FROM f JOIN (SELECT fit, COUNT(*) AS n FROM ex GROUP BY fit) AS x USING (fit) WHERE f.n != x.n)
         + ABS((SELECT COUNT(*) FROM f) - 4)
    UNION ALL
    SELECT '03. Probability-weighted moments a0 and a1 = recount (rank by self-join)', 0,
           (SELECT COUNT(*) FROM f JOIN a1_recount AS r USING (fit)
             WHERE ABS(f.a0 - r.a0) > 1e-6 OR ABS(f.a1 - r.a1) > 1e-6)
    UNION ALL
    SELECT '04. Fitted GPD mean sigma / (1 - xi) = mean exceedance, every fit', 0,
           (SELECT COUNTIF(xi >= 1 OR ABS(sigma / (1 - xi) - a0) > 1e-6 * a0) FROM f)
    UNION ALL
    SELECT '05. Rate per year = exceedances / years (2.75 years full, 2 years train)', 0,
           (SELECT COUNTIF(ABS(per_year - n / years) > 1e-9) FROM f)
         + (SELECT COUNTIF(ABS(years - IF(fit LIKE 'Train%', 731, 1004) / 365.25) > 1e-9) FROM f)
    UNION ALL
    SELECT '06. Return levels: expected exceedances at the level x T = 1', 0,
           (SELECT COUNTIF(ABS(per_year * t * POW(1 + xi * (level - u) / sigma, -1 / xi) - 1) > 1e-9)
              FROM (SELECT f5.*, t, f5.u + f5.sigma / f5.xi * (POW(f5.per_year * t, f5.xi) - 1) AS level
                      FROM full5 AS f5 CROSS JOIN UNNEST([1 / 12, 0.25, 1.0, 5.0, 10.0]) AS t))
    UNION ALL
    SELECT '07. 500 bootstrap refits, all with a finite shape between -0.5 and 1.5', 0,
           ABS((SELECT COUNT(*) FROM bt) - resamples)
         + (SELECT COUNTIF(xi IS NULL OR sigma IS NULL OR xi NOT BETWEEN -0.5 AND 1.5 OR sigma <= 0) FROM bt)
    UNION ALL
    SELECT '08. Fitted tail: all exceedances at the threshold, fewer at every higher size', 0,
           (SELECT COUNTIF(ABS(n * POW(1 + xi * 0 / sigma, -1 / xi) - n) > 1e-9) FROM full5)
         + (SELECT COUNTIF(s2 >= s1) FROM (
               SELECT POW(1 + xi * (x - u) / sigma, -1 / xi) AS s1, POW(1 + xi * (x + 100000 - u) / sigma, -1 / xi) AS s2
               FROM full5 CROSS JOIN UNNEST([500000, 1000000, 2000000, 5000000, 10000000]) AS x))
    UNION ALL
    SELECT '09. Training fit uses only 2024-2025 orders', 0,
           IF((SELECT n FROM f WHERE fit LIKE 'Train%') != (SELECT COUNTIF(value > u_threshold AND order_date <= train_end) FROM o), 1, 0)
    UNION ALL
    SELECT '10. Bootstrap shapes centre on the full-sample shape (within 0.1)', 0,
           IF(ABS((SELECT AVG(xi) FROM bt) - (SELECT xi FROM full5)) > 0.1, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
