/* =============================================================================
   Case study · Can the warehouse close on Sundays?
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The warehouse ships seven days a week, although customers hardly order
   on Sundays. The new operations head wants to close on Sundays: staff
   would get a weekly day off and the Sunday premium would be saved. Sales
   fear that customer promises would slip. She asks:
     1. How much of today's dispatch happens on Sundays, and how much new
        work arrives on Sundays?
     2. With a six-day week, what daily capacity still meets every dispatch
        deadline if orders ship deadline-first?
     3. Is that more or fewer staff-days than the seven-day week?
     4. What happens with first-in-first-out dispatch instead?

   METHOD
     - Orders and dispatch deadlines exactly as in the dispatch-by-deadline
       study: orders placed 1 Oct 2025 - 30 Sep 2026 that have shipped and
       have a promised date; deadline = promised date - median transit to
       the shipping city, never before the order date.
     - Six-day week: no dispatch on Sundays. A deadline falling on a Sunday
       moves to the Saturday before; if the order itself arrives on that
       Sunday with no slack, it can only ship on Monday (a forced 1-day
       miss, counted separately).
     - Deadline-first feasibility (Hall's condition): for every window of
       days [s, t], the orders arriving on or after s and due by t must fit
       in c x the working days in the window. The least capacity is the
       largest ratio, rounded up.
     - FIFO with capacity c on working days: cumulative departures
       D(t) = c W(t) + MIN(0, running MIN of A(s) - c W(s)), where W(t) is
       the number of working days up to t and A(s) the orders arrived.
   ============================================================================= */

DECLARE window_start DATE DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE DEFAULT DATE '2026-09-30';
DECLARE min_history  INT64 DEFAULT 20;

-- -----------------------------------------------------------------------------
-- Step 1 · Calendar of days with working-day counts
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sw_days` AS
WITH days AS (
    SELECT t, DATE_ADD(window_start, INTERVAL t DAY) AS d FROM UNNEST(GENERATE_ARRAY(0, 600)) AS t
)
SELECT t, d, FORMAT_DATE('%a', d) = 'Sun' AS is_sunday,
       SUM(IF(FORMAT_DATE('%a', d) = 'Sun', 0, 1)) OVER (ORDER BY t)                  AS working_days_to_t
FROM days;

-- -----------------------------------------------------------------------------
-- Step 2 · Orders with seven-day and six-day deadlines
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sw_orders` AS
WITH city_alias AS (
    -- the same alias list as the ship-to / bill-to reconciliation
    SELECT 'ahmadabad' AS raw_key, 'ahmedabad' AS city_key UNION ALL SELECT 'bangalore', 'bengaluru' UNION ALL
    SELECT 'baroda', 'vadodara' UNION ALL SELECT 'bombay', 'mumbai' UNION ALL SELECT 'calcutta', 'kolkata' UNION ALL
    SELECT 'delhi', 'new delhi' UNION ALL SELECT 'gurgaon', 'gurugram' UNION ALL SELECT 'madras', 'chennai' UNION ALL
    SELECT 'mysore', 'mysuru' UNION ALL SELECT 'vizag', 'visakhapatnam'
),
ship AS (
    SELECT s.order_id, MIN(s.shipment_date) AS first_ship, MAX(s.delivery_date) AS last_delivery,
           COUNT(s.delivery_date) = COUNT(*) AS all_delivered,
           MIN(IFNULL(a.city_key, LOWER(TRIM(s.shipping_city)))) AS city
    FROM `sahyadri_b2b.shipments` AS s
    LEFT JOIN city_alias AS a ON a.raw_key = LOWER(TRIM(s.shipping_city))
    GROUP BY s.order_id
),
history AS (
    SELECT s.city, DATE_DIFF(s.last_delivery, s.first_ship, DAY) AS transit
    FROM ship AS s JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = s.order_id
    WHERE o.order_date < window_start AND s.all_delivered
),
city_transit AS (
    SELECT city, APPROX_QUANTILES(transit, 2)[OFFSET(1)] AS planned_transit, COUNT(*) AS history_orders
    FROM history GROUP BY city
    HAVING COUNT(*) >= min_history
),
overall AS (
    SELECT APPROX_QUANTILES(transit, 2)[OFFSET(1)] AS planned_transit FROM history
),
base AS (
    SELECT
        o.order_id, o.order_date, o.promised_delivery_date, s.city, s.first_ship, s.last_delivery,
        IFNULL(ct.planned_transit, ov.planned_transit)                               AS planned_transit,
        DATE_DIFF(o.order_date, window_start, DAY)                                   AS release_day,
        DATE_DIFF(s.first_ship, window_start, DAY)                                   AS actual_ship_day,
        DATE_DIFF(o.promised_delivery_date, window_start, DAY) - IFNULL(ct.planned_transit, ov.planned_transit) AS raw_deadline_day
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN ship AS s ON s.order_id = o.order_id
    LEFT JOIN city_transit AS ct ON ct.city = s.city
    CROSS JOIN overall AS ov
    WHERE o.order_date BETWEEN window_start AND window_end
      AND o.promised_delivery_date IS NOT NULL
)
-- seven-day deadline as in the dispatch-by-deadline study; six-day deadline moves a Sunday
-- deadline to the Saturday before, or to Monday when the order itself arrives that Sunday
SELECT
    b.*,
    GREATEST(b.raw_deadline_day, b.release_day)                                      AS deadline_day,
    CASE WHEN NOT dd.is_sunday THEN GREATEST(b.raw_deadline_day, b.release_day)
         WHEN GREATEST(b.raw_deadline_day, b.release_day) - 1 >= b.release_day THEN GREATEST(b.raw_deadline_day, b.release_day) - 1
         ELSE GREATEST(b.raw_deadline_day, b.release_day) + 1 END                    AS deadline_day_6,
    dd.is_sunday AND GREATEST(b.raw_deadline_day, b.release_day) = b.release_day     AS sunday_forced_late,
    rd.is_sunday                                                                     AS arrives_on_sunday,
    ROW_NUMBER() OVER (ORDER BY b.release_day, b.order_id)                           AS arrival_no
FROM base AS b
JOIN `sahyadri_b2b.sw_days` AS dd ON dd.t = GREATEST(b.raw_deadline_day, b.release_day)
JOIN `sahyadri_b2b.sw_days` AS rd ON rd.t = b.release_day;

SELECT
    COUNT(*)                                                                          AS orders,
    COUNTIF(o.arrives_on_sunday)                                                      AS arrive_on_sunday,
    COUNTIF(d.is_sunday)                                                              AS deadline_on_sunday,
    COUNTIF(o.sunday_forced_late)                                                     AS forced_late_by_closure,
    COUNTIF(o.deadline_day_6 < o.deadline_day)                                        AS deadline_moved_a_day_earlier
FROM `sahyadri_b2b.sw_orders` AS o
JOIN `sahyadri_b2b.sw_days` AS d ON d.t = o.deadline_day;

-- Today's dispatch by weekday (shipments dispatched in the window)
SELECT
    FORMAT_DATE('%a', shipment_date)                                                  AS weekday,
    COUNT(*)                                                                          AS shipments,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                                  AS share_pct
FROM `sahyadri_b2b.shipments`
WHERE shipment_date BETWEEN window_start AND window_end
GROUP BY weekday
ORDER BY MIN(EXTRACT(DAYOFWEEK FROM shipment_date));

-- -----------------------------------------------------------------------------
-- Step 3 · Least capacity that meets every deadline: seven-day against six-day week
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sw_windows` AS
WITH starts AS (
    SELECT DISTINCT release_day AS s FROM `sahyadri_b2b.sw_orders`
),
due7 AS (
    SELECT st.s, o.deadline_day AS t,
           ROW_NUMBER() OVER (PARTITION BY st.s ORDER BY o.deadline_day, o.order_id)  AS k
    FROM starts AS st JOIN `sahyadri_b2b.sw_orders` AS o ON o.release_day >= st.s
),
due6 AS (
    SELECT st.s, o.deadline_day_6 AS t,
           ROW_NUMBER() OVER (PARTITION BY st.s ORDER BY o.deadline_day_6, o.order_id) AS k
    FROM starts AS st JOIN `sahyadri_b2b.sw_orders` AS o ON o.release_day >= st.s
),
w7 AS (
    SELECT 'Seven-day week' AS week, s, t, MAX(k) AS orders, t - s + 1 AS capacity_days FROM due7 GROUP BY s, t
),
w6 AS (
    SELECT 'Six-day week' AS week, d6.s, d6.t, MAX(d6.k) AS orders,
           ANY_VALUE(e.working_days_to_t) - ANY_VALUE(IFNULL(b.working_days_to_t, 0)) AS capacity_days
    FROM due6 AS d6
    JOIN `sahyadri_b2b.sw_days` AS e ON e.t = d6.t
    LEFT JOIN `sahyadri_b2b.sw_days` AS b ON b.t = d6.s - 1
    GROUP BY d6.s, d6.t
)
SELECT *, orders / capacity_days AS required_per_day FROM w7
UNION ALL
SELECT *, orders / capacity_days FROM w6;

SELECT
    week,
    COUNT(*)                                                                          AS windows_checked,
    ROUND(MAX(required_per_day), 2)                                                   AS required_per_day,
    CAST(CEIL(MAX(required_per_day)) AS INT64)                                        AS least_capacity,
    CAST(CEIL(MAX(required_per_day)) AS INT64) * IF(week = 'Six-day week', 6, 7)      AS order_slots_per_week
FROM `sahyadri_b2b.sw_windows`
GROUP BY week
ORDER BY week DESC;

SELECT week, DATE_ADD(window_start, INTERVAL s DAY) AS window_from, DATE_ADD(window_start, INTERVAL t DAY) AS window_to,
       orders, capacity_days, ROUND(required_per_day, 2) AS required_per_day
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY week ORDER BY required_per_day DESC, s, t) AS rk FROM `sahyadri_b2b.sw_windows`)
WHERE rk <= 2
ORDER BY week DESC, rk;

-- -----------------------------------------------------------------------------
-- Step 4 · First-in-first-out on a six-day week
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sw_fifo` AS
WITH caps AS (
    SELECT c FROM UNNEST([12, 13, 14, 15, 16, 17, 18, 19, 20, 21]) AS c
),
arrivals AS (
    SELECT d.t, d.is_sunday, d.working_days_to_t, COUNTIF(o.order_id IS NOT NULL) AS arrived
    FROM `sahyadri_b2b.sw_days` AS d LEFT JOIN `sahyadri_b2b.sw_orders` AS o ON o.release_day = d.t
    GROUP BY d.t, d.is_sunday, d.working_days_to_t
),
cumulative AS (
    SELECT t, working_days_to_t, SUM(arrived) OVER (ORDER BY t) AS a FROM arrivals
),
departures AS (
    SELECT c.c, x.t,
           c.c * x.working_days_to_t
             + LEAST(0, MIN(x.a - c.c * x.working_days_to_t) OVER (PARTITION BY c.c ORDER BY x.t)) AS d
    FROM cumulative AS x CROSS JOIN caps AS c
),
steps AS (
    SELECT c, t, d, IFNULL(LAG(d) OVER (PARTITION BY c ORDER BY t), 0) AS d_before FROM departures
)
SELECT st.c, o.order_id, o.release_day, o.deadline_day, o.deadline_day_6, st.t AS ship_day,
       st.t > o.deadline_day                                                          AS missed
FROM `sahyadri_b2b.sw_orders` AS o
JOIN steps AS st ON o.arrival_no > st.d_before AND o.arrival_no <= st.d;

SELECT
    c                                                                                 AS capacity_per_working_day,
    c * 6                                                                             AS order_slots_per_week,
    COUNTIF(missed)                                                                   AS fifo_missed,
    ROUND(100 * COUNTIF(missed) / COUNT(*), 2)                                        AS fifo_missed_pct,
    MAX(GREATEST(ship_day - deadline_day, 0))                                         AS worst_days_late,
    ROUND(AVG(ship_day - release_day), 2)                                             AS avg_wait_days
FROM `sahyadri_b2b.sw_fifo`
GROUP BY c
ORDER BY c;
