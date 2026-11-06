/* =============================================================================
   Case study · Will we hit the full-year target? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE sims INT64 DEFAULT 1000;

WITH o AS (SELECT * FROM `sahyadri_b2b.ft_orders`),
     pool AS (SELECT * FROM `sahyadri_b2b.ft_pool`),
     m AS (SELECT * FROM `sahyadri_b2b.ft_months`),
     g AS (SELECT * FROM `sahyadri_b2b.ft_growth`),
     pl AS (SELECT * FROM `sahyadri_b2b.ft_plan`),
     ct AS (SELECT * FROM `sahyadri_b2b.ft_counts`),
     sm AS (SELECT * FROM `sahyadri_b2b.ft_sims`),
     bt AS (SELECT * FROM `sahyadri_b2b.ft_backtest`),

src AS (
    SELECT COUNT(DISTINCT x.order_id) AS n, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned')
),
fy_revenue AS (
    SELECT
        SUM(IF(order_date BETWEEN DATE '2025-04-01' AND DATE '2026-03-31', value, 0)) AS fy2526,
        SUM(IF(order_date BETWEEN DATE '2026-04-01' AND DATE '2026-09-30', value, 0)) AS h1_2627,
        SUM(IF(order_date BETWEEN DATE '2025-04-01' AND DATE '2025-09-30', value, 0)) AS h1_2526
    FROM o
),
growth_recount AS (
    SELECT g.c,
           SUM(IF(x.month BETWEEN g.fy_start AND g.cutoff_month, x.orders, 0))
             / SUM(IF(x.month BETWEEN DATE_SUB(g.fy_start, INTERVAL 12 MONTH) AND DATE_SUB(g.cutoff_month, INTERVAL 12 MONTH), x.orders, 0)) AS cg
    FROM g CROSS JOIN m AS x GROUP BY g.c
),
draw_totals AS (
    SELECT c, s, SUM(n) AS n FROM ct GROUP BY c, s
),
pct_recount AS (
    SELECT s.c, COUNTIF(s.fy_total_a <= f.fy2526) / COUNT(*) AS pa, COUNTIF(s.fy_total_b <= f.fy2526) / COUNT(*) AS pb
    FROM sm AS s CROSS JOIN fy_revenue AS f WHERE s.c <= 10 GROUP BY s.c
),

checks AS (
    SELECT '01. Orders and revenue = source (valid orders)' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(value) FROM o) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Draw pool numbered 1..n within each month, n = orders of the month', 0,
           (SELECT COUNT(*) FROM (SELECT month, COUNT(*) AS n, MIN(rn) AS lo, MAX(rn) AS hi, COUNT(DISTINCT rn) AS d FROM pool GROUP BY month) AS p
              JOIN m USING (month) WHERE p.lo != 1 OR p.hi != m.orders OR p.d != m.orders OR p.n != m.orders)
    UNION ALL
    SELECT '03. Monthly orders and revenue = recount', 0,
           (SELECT COUNT(*) FROM m JOIN (SELECT month, COUNT(*) AS n, SUM(value) AS v FROM o GROUP BY month) AS x USING (month)
             WHERE m.orders != x.n OR ABS(m.revenue - x.v) > 1e-6)
    UNION ALL
    SELECT '04. Twelve cut-offs, FY from April, FY-to-date revenue = recount (Sep 2025, Sep 2026)', 0,
           ABS((SELECT COUNT(*) FROM g) - 12)
         + (SELECT COUNTIF(EXTRACT(MONTH FROM fy_start) != 4) FROM g)
         + IF(ABS((SELECT ytd_revenue FROM g WHERE c = 5) - (SELECT h1_2526 FROM fy_revenue)) > 1, 1, 0)
         + IF(ABS((SELECT ytd_revenue FROM g WHERE c = 11) - (SELECT h1_2627 FROM fy_revenue)) > 1, 1, 0)
    UNION ALL
    SELECT '05. Count growth = FY-to-date orders / same months last year (recount)', 0,
           (SELECT COUNT(*) FROM g JOIN growth_recount AS r USING (c) WHERE ABS(g.count_growth - r.cg) > 1e-12)
    UNION ALL
    SELECT '06. Plan covers every remaining month, base = same month last year x count growth', 0,
           (SELECT COUNT(*) FROM (SELECT c, COUNT(*) AS n FROM pl GROUP BY c) AS x JOIN g USING (c)
             WHERE x.n != DATE_DIFF(g.fy_last_month, g.cutoff_month, MONTH))
         + (SELECT COUNT(*) FROM pl JOIN g USING (c) JOIN m ON m.month = pl.ly_month
             WHERE DATE_DIFF(pl.month, pl.ly_month, MONTH) != 12 OR pl.ly_orders != m.orders
                OR ABS(pl.mean_orders - m.orders * g.count_growth) > 1e-9)
    UNION ALL
    SELECT '07. 1,000 counts per plan month, never negative, normal draws with mean ~0 and SD ~1', 0,
           (SELECT COUNT(*) FROM (SELECT c, k, COUNT(*) AS n FROM ct GROUP BY c, k) WHERE n != sims)
         + (SELECT COUNTIF(n < 0) FROM ct)
         + IF(ABS((SELECT AVG(z) FROM ct)) > 0.02 OR ABS((SELECT STDDEV_POP(z) FROM ct) - 1) > 0.02, 1, 0)
    UNION ALL
    SELECT '08. Every simulated order was drawn: orders per simulation = sum of monthly counts', 0,
           (SELECT COUNT(*) FROM sm JOIN draw_totals AS d USING (c, s) WHERE sm.rest_orders != d.n)
         + ABS((SELECT COUNT(*) FROM sm) - 12 * sims)
    UNION ALL
    SELECT '09. FY total = FY-to-date + rest (rule A), + rest x size growth (rule B)', 0,
           (SELECT COUNTIF(ABS(sm.fy_total_a - sm.ytd_revenue - sm.rest_last_year_prices) > 1e-3
                        OR ABS(sm.fy_total_b - sm.ytd_revenue - sm.rest_last_year_prices * g.size_growth) > 1e-3)
              FROM sm JOIN g USING (c))
    UNION ALL
    SELECT '10. Back-test actual = FY 2025-26 revenue, percentiles = recount', 0,
           (SELECT COUNTIF(ABS(fy_actual - (SELECT fy2526 FROM fy_revenue)) > 1) FROM bt)
         + (SELECT COUNT(*) FROM bt JOIN pct_recount AS r USING (c)
             WHERE ABS(bt.actual_percentile - IF(bt.rule LIKE 'A.%', r.pa, r.pb)) > 1e-12)
         + ABS((SELECT COUNT(*) FROM bt) - 22)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
