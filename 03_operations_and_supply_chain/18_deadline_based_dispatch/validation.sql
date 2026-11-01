/* =============================================================================
   Case study · Dispatch by deadline — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start DATE DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE DEFAULT DATE '2026-09-30';
DECLARE min_history  INT64 DEFAULT 20;

WITH o AS (SELECT * FROM `sahyadri_b2b.dd_orders`),
     aw AS (SELECT * FROM `sahyadri_b2b.dd_all_windows`),
     w AS (SELECT * FROM `sahyadri_b2b.dd_windows`),
     f AS (SELECT * FROM `sahyadri_b2b.dd_fifo`),

src AS (
    SELECT COUNT(DISTINCT x.order_id) AS n
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = x.order_id
    WHERE x.order_date BETWEEN window_start AND window_end AND x.promised_delivery_date IS NOT NULL
),
-- direct count of orders that arrive on or after s and are due by t, for each start day's tightest window
recount AS (
    SELECT w.s, w.t, w.orders, COUNTIF(o.release_day >= w.s AND o.deadline_day <= w.t) AS n
    FROM w CROSS JOIN o
    GROUP BY w.s, w.t, w.orders
),
least AS (
    SELECT CAST(CEIL(MAX(required_per_day)) AS INT64) AS c FROM aw
),
daily AS (
    SELECT g.c, g.t,
           IFNULL(sh.shipped, 0)                                                     AS shipped,
           SUM(IFNULL(ar.arrived, 0)) OVER (PARTITION BY g.c ORDER BY g.t)
             - SUM(IFNULL(sh.shipped, 0)) OVER (PARTITION BY g.c ORDER BY g.t)       AS left_waiting
    FROM (SELECT c, t FROM (SELECT DISTINCT c FROM f) CROSS JOIN UNNEST(GENERATE_ARRAY(0, 600)) AS t) AS g
    LEFT JOIN (SELECT c, ship_day, COUNT(*) AS shipped FROM f GROUP BY c, ship_day) AS sh ON sh.c = g.c AND sh.ship_day = g.t
    LEFT JOIN (SELECT release_day, COUNT(*) AS arrived FROM o GROUP BY release_day) AS ar ON ar.release_day = g.t
),
fifo_order AS (
    SELECT c, ship_day, LAG(ship_day) OVER (PARTITION BY c ORDER BY arrival_no) AS previous_ship_day FROM f
),

checks AS (
    SELECT '01. Orders = shipped orders of the window with a promised date, numbered 1..n' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src))
         + IF((SELECT MAX(arrival_no) FROM o) != (SELECT COUNT(*) FROM o) OR (SELECT COUNT(DISTINCT arrival_no) FROM o) != (SELECT COUNT(*) FROM o), 1, 0) AS actual
    UNION ALL
    SELECT '02. Deadline = promised date - planned transit, never before the order date', 0,
           (SELECT COUNTIF(deadline_day != GREATEST(DATE_DIFF(promised_delivery_date, window_start, DAY) - planned_transit, release_day)
                           OR slack_days < 0 OR planned_transit IS NULL) FROM o)
    UNION ALL
    SELECT '03. One tightest window for every day on which orders arrive', 0,
           ABS((SELECT COUNT(DISTINCT s) FROM aw) - (SELECT COUNT(DISTINCT release_day) FROM o))
         + ABS((SELECT COUNT(*) FROM w) - (SELECT COUNT(DISTINCT s) FROM aw))
    UNION ALL
    SELECT '04. Window counts = direct recount of orders arriving after s and due by t', 0,
           (SELECT COUNTIF(orders != n) FROM recount)
    UNION ALL
    SELECT '05. Least capacity fits every window, one order a day less does not', 0,
           (SELECT COUNTIF(orders > (SELECT c FROM least) * days) FROM aw)
         + IF((SELECT COUNTIF(orders > ((SELECT c FROM least) - 1) * days) FROM aw) = 0, 1, 0)
    UNION ALL
    SELECT '06. FIFO: every order ships exactly once at every capacity, never before its order date', 0,
           (SELECT COUNT(*) FROM (SELECT c, COUNT(*) AS n, COUNT(DISTINCT order_id) AS u FROM f GROUP BY c) WHERE n != (SELECT COUNT(*) FROM o) OR u != n)
         + (SELECT COUNTIF(ship_day < release_day) FROM f)
         + ABS((SELECT COUNT(DISTINCT c) FROM f) - 11)
    UNION ALL
    SELECT '07. FIFO: no day ships more than the capacity, and orders ship in arrival order', 0,
           (SELECT COUNTIF(shipped > c) FROM daily)
         + (SELECT COUNTIF(ship_day < previous_ship_day) FROM fifo_order)
    UNION ALL
    SELECT '08. FIFO never idles: a day below capacity leaves nobody waiting', 0,
           (SELECT COUNTIF(shipped < c AND left_waiting > 0) FROM daily)
    UNION ALL
    SELECT '09. Missed flag = ship day after deadline', 0,
           (SELECT COUNTIF(missed != (ship_day > deadline_day)) FROM f)
    UNION ALL
    SELECT '10. Window ratio = orders / days, and the tightest window per start day is kept', 0,
           (SELECT COUNTIF(ABS(required_per_day - orders / days) > 1e-12 OR days != t - s + 1) FROM aw)
         + (SELECT COUNT(*) FROM w JOIN (SELECT s, MAX(required_per_day) AS m FROM aw GROUP BY s) AS x USING (s)
             WHERE ABS(w.required_per_day - x.m) > 1e-12)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
