/* =============================================================================
   Case study · Can the warehouse close on Sundays? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start DATE DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE DEFAULT DATE '2026-09-30';

WITH dy AS (SELECT * FROM `sahyadri_b2b.sw_days`),
     o AS (SELECT * FROM `sahyadri_b2b.sw_orders`),
     w AS (SELECT * FROM `sahyadri_b2b.sw_windows`),
     f AS (SELECT * FROM `sahyadri_b2b.sw_fifo`),

src AS (
    SELECT COUNT(DISTINCT x.order_id) AS n
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = x.order_id
    WHERE x.order_date BETWEEN window_start AND window_end AND x.promised_delivery_date IS NOT NULL
),
day_steps AS (
    SELECT t, is_sunday, working_days_to_t - IFNULL(LAG(working_days_to_t) OVER (ORDER BY t), 0) AS step FROM dy
),
six AS (
    SELECT * FROM w WHERE week = 'Six-day week'
),
least6 AS (
    SELECT CAST(CEIL(MAX(required_per_day)) AS INT64) AS c FROM six
),
top6 AS (
    SELECT * FROM six ORDER BY required_per_day DESC, s, t LIMIT 1
),
top6_recount AS (
    SELECT ANY_VALUE(tp.orders) AS stored, COUNTIF(o.release_day >= tp.s AND o.deadline_day_6 <= tp.t) AS recount
    FROM top6 AS tp CROSS JOIN o
),
first_sunday AS (
    SELECT MIN(t) AS t0 FROM dy WHERE is_sunday
),
daily AS (
    SELECT f.c, f.ship_day AS t, COUNT(*) AS shipped FROM f GROUP BY f.c, f.ship_day
),
backlog AS (
    -- working days on which FIFO shipped below capacity although orders were waiting at the end of the day
    SELECT g.c, g.t,
           SUM(IFNULL(a.arrived, 0)) OVER (PARTITION BY g.c ORDER BY g.t)
             - SUM(IFNULL(sh.shipped, 0)) OVER (PARTITION BY g.c ORDER BY g.t)       AS waiting,
           IFNULL(sh.shipped, 0) AS shipped, g.is_sunday
    FROM (SELECT DISTINCT f.c, dy.t, dy.is_sunday FROM f CROSS JOIN dy) AS g
    LEFT JOIN daily AS sh ON sh.c = g.c AND sh.t = g.t
    LEFT JOIN (SELECT release_day, COUNT(*) AS arrived FROM o GROUP BY release_day) AS a ON a.release_day = g.t
),

checks AS (
    SELECT '01. Orders = shipped orders of the window with a promised date' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src)) AS actual
    UNION ALL
    SELECT '02. Working-day count rises by one except on Sundays, which fall every seventh day', 0,
           (SELECT COUNTIF(step != IF(is_sunday, 0, 1)) FROM day_steps)
         + (SELECT COUNTIF(dy.is_sunday != (MOD(dy.t - fs.t0, 7) = 0)) FROM dy CROSS JOIN first_sunday AS fs)
         + IF((SELECT FORMAT_DATE('%a', dy.d) FROM dy WHERE t = 0) != 'Wed', 1, 0)
    UNION ALL
    SELECT '03. Six-day deadlines never fall on a Sunday and move at most one day', 0,
           (SELECT COUNT(*) FROM o JOIN dy ON dy.t = o.deadline_day_6 WHERE dy.is_sunday)
         + (SELECT COUNTIF(ABS(deadline_day_6 - deadline_day) > 1 OR (deadline_day_6 < release_day AND NOT sunday_forced_late)) FROM o)
    UNION ALL
    SELECT '04. Tightest six-day window = direct recount of orders', 0,
           (SELECT ABS(stored - recount) FROM top6_recount)
    UNION ALL
    SELECT '05. Six-day least capacity fits every window, one order a day less does not', 0,
           (SELECT COUNTIF(orders > (SELECT c FROM least6) * capacity_days) FROM six)
         + IF((SELECT COUNTIF(orders > ((SELECT c FROM least6) - 1) * capacity_days) FROM six) = 0, 1, 0)
    UNION ALL
    SELECT '06. Window capacity days = working days in the window (recount)', 0,
           (SELECT COUNT(*) FROM (
               SELECT x.s, x.t, ANY_VALUE(x.capacity_days) AS cd, COUNTIF(NOT dd.is_sunday) AS n
               FROM (SELECT * FROM six ORDER BY required_per_day DESC LIMIT 50) AS x
               JOIN dy AS dd ON dd.t BETWEEN x.s AND x.t
               GROUP BY x.s, x.t) WHERE cd != n)
    UNION ALL
    SELECT '07. FIFO never ships on a Sunday or above capacity', 0,
           (SELECT COUNT(*) FROM f JOIN dy ON dy.t = f.ship_day WHERE dy.is_sunday)
         + (SELECT COUNTIF(shipped > c) FROM daily)
    UNION ALL
    SELECT '08. FIFO ships every order once per capacity, never before it arrives', 0,
           (SELECT COUNT(*) FROM (SELECT c, COUNT(*) AS n, COUNT(DISTINCT order_id) AS u FROM f GROUP BY c) WHERE n != (SELECT COUNT(*) FROM o) OR u != n)
         + (SELECT COUNTIF(ship_day < release_day) FROM f)
    UNION ALL
    SELECT '09. FIFO never idles on a working day while orders wait', 0,
           (SELECT COUNTIF(NOT is_sunday AND shipped < c AND waiting > 0) FROM backlog)
    UNION ALL
    SELECT '10. Seven-day windows use calendar days, one start per arrival day', 0,
           (SELECT COUNTIF(capacity_days != t - s + 1) FROM w WHERE week = 'Seven-day week')
         + ABS((SELECT COUNT(DISTINCT s) FROM w WHERE week = 'Seven-day week') - (SELECT COUNT(DISTINCT release_day) FROM o))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
