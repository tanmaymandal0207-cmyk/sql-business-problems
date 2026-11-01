/* =============================================================================
   Case study · Dispatch by deadline: the capacity needed to keep every promise
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The dispatch capacity study sized the warehouse for a first-in-first-out
   queue. But customers are promised different dates: a pump promised in
   20 days can wait, a valve promised in 5 cannot. The operations head
   asks:
     1. If every order had a dispatch deadline (promised delivery date less
        the usual transit time to its city), what is the least daily
        capacity that meets every deadline?
     2. How much more capacity does first-in-first-out dispatch need for
        the same result?
     3. How many deadlines does the warehouse actually miss today, and is
        it short of capacity?
     4. When in the year is the requirement set?

   METHOD
     - Orders placed 1 Oct 2025 - 30 Sep 2026 that have been shipped and
       have a promised date. Day 0 = 1 Oct 2025; shipping is possible
       every day, including the order date.
     - Planned transit: the median days from first shipment to final
       delivery for the shipping city (names standardised: case, spacing
       and aliases such as Bombay -> Mumbai), on orders before the
       window; the overall median for cities with fewer than 20 such
       orders.
     - Dispatch deadline = promised date - planned transit, never earlier
       than the order date.
     - Deadline-first (EDF) feasibility: with c orders a day, every order
       can meet its deadline if and only if, for every window of days
       [s, t], the orders that arrive on or after s and are due by t are
       no more than c x (t - s + 1) (Hall's condition; earliest-deadline-
       first dispatch then meets every deadline). The least capacity is
       the largest such ratio, rounded up.
     - FIFO at capacity c: cumulative departures D(t) = MIN(c (t + 1),
       MIN over s <= t of A(s) + c (t - s)), the closed form of the
       dispatch capacity study with day 0 as the first shipping day; the
       k-th order ships on the first day with D(t) >= k.
     - Both rules ship the same number of orders each day (each ships as
       much as it can), so they give the same average wait; only the
       order of dispatch differs.
   ============================================================================= */

DECLARE window_start DATE DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE DEFAULT DATE '2026-09-30';
DECLARE min_history  INT64 DEFAULT 20;

-- -----------------------------------------------------------------------------
-- Step 1 · Orders with release day, deadline and actual dispatch
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dd_orders` AS
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
SELECT
    *,
    GREATEST(raw_deadline_day, release_day)                                          AS deadline_day,
    GREATEST(raw_deadline_day, release_day) - release_day                            AS slack_days,
    ROW_NUMBER() OVER (ORDER BY release_day, order_id)                               AS arrival_no
FROM base;

SELECT
    COUNT(*)                                                                         AS orders,
    ROUND(COUNT(*) / (DATE_DIFF(window_end, window_start, DAY) + 1), 2)              AS orders_per_day,
    ROUND(AVG(DATE_DIFF(promised_delivery_date, order_date, DAY)), 1)                AS avg_promise_days,
    ROUND(AVG(planned_transit), 1)                                                   AS avg_planned_transit,
    ROUND(AVG(slack_days), 1)                                                        AS avg_slack_days,
    COUNTIF(raw_deadline_day <= release_day)                                         AS must_ship_on_order_day,
    COUNTIF(slack_days <= 3)                                                         AS slack_3_days_or_less,
    COUNTIF(actual_ship_day > deadline_day)                                          AS actual_missed_deadlines,
    ROUND(100 * COUNTIF(actual_ship_day > deadline_day) / COUNT(*), 1)               AS actual_missed_pct,
    ROUND(AVG(actual_ship_day - release_day), 2)                                     AS actual_avg_wait_days
FROM `sahyadri_b2b.dd_orders`;

-- -----------------------------------------------------------------------------
-- Step 2 · Deadline-first feasibility: the tightest window of days
-- -----------------------------------------------------------------------------
-- For each start day s, the orders arriving on or after s sorted by deadline;
-- the k-th of them must ship by its deadline t, so c >= k / (t - s + 1).
CREATE OR REPLACE TABLE `sahyadri_b2b.dd_all_windows` AS
WITH starts AS (
    SELECT DISTINCT release_day AS s FROM `sahyadri_b2b.dd_orders`
),
due AS (
    SELECT st.s, o.deadline_day AS t,
           ROW_NUMBER() OVER (PARTITION BY st.s ORDER BY o.deadline_day, o.order_id) AS k
    FROM starts AS st
    JOIN `sahyadri_b2b.dd_orders` AS o ON o.release_day >= st.s
)
-- the last order due on day t gives the count for the window [s, t]
SELECT s, t, MAX(k) AS orders, t - s + 1 AS days, MAX(k) / (t - s + 1) AS required_per_day
FROM due GROUP BY s, t;

CREATE OR REPLACE TABLE `sahyadri_b2b.dd_windows` AS
SELECT * EXCEPT (rk)
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY s ORDER BY required_per_day DESC, t) AS rk FROM `sahyadri_b2b.dd_all_windows`
)
WHERE rk = 1;

SELECT
    DATE_ADD(window_start, INTERVAL s DAY)                                           AS window_from,
    DATE_ADD(window_start, INTERVAL t DAY)                                           AS window_to,
    days, orders,
    ROUND(required_per_day, 2)                                                       AS required_per_day,
    CAST(CEIL(required_per_day) AS INT64)                                            AS least_capacity
FROM `sahyadri_b2b.dd_windows`
ORDER BY required_per_day DESC, s
LIMIT 5;

-- The tightest window starting in each month
SELECT
    DATE_TRUNC(DATE_ADD(window_start, INTERVAL s DAY), MONTH)                        AS month,
    ROUND(MAX(required_per_day), 2)                                                  AS required_per_day,
    CAST(CEIL(MAX(required_per_day)) AS INT64)                                       AS least_capacity
FROM `sahyadri_b2b.dd_windows`
GROUP BY month
ORDER BY month;

-- A seasonal plan: 12 a day from October to March, 10 a day from April to September.
-- Feasible if every window's orders fit within the capacity summed over its days.
WITH plan AS (
    SELECT t, IF(t < DATE_DIFF(DATE '2026-04-01', window_start, DAY), 12, 10) AS capacity
    FROM UNNEST(GENERATE_ARRAY(0, 600)) AS t
),
cumulative AS (
    SELECT t, SUM(capacity) OVER (ORDER BY t) AS cap_to_t, SUM(capacity) OVER (ORDER BY t) - capacity AS cap_before_t FROM plan
)
SELECT
    COUNT(*)                                                                         AS windows_checked,
    COUNTIF(w.orders > e.cap_to_t - b.cap_before_t)                                  AS windows_over_capacity,
    ROUND(MAX(w.orders / (e.cap_to_t - b.cap_before_t)), 3)                          AS tightest_load_ratio,
    ROUND((SELECT SUM(capacity) FROM plan WHERE t <= 364) / 365, 2)                  AS plan_avg_capacity
FROM `sahyadri_b2b.dd_all_windows` AS w
JOIN cumulative AS b ON b.t = w.s
JOIN cumulative AS e ON e.t = w.t;

-- -----------------------------------------------------------------------------
-- Step 3 · First-in-first-out at the same capacities
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dd_fifo` AS
WITH days AS (
    SELECT t FROM UNNEST(GENERATE_ARRAY(0, 600)) AS t
),
caps AS (
    SELECT c FROM UNNEST([10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]) AS c
),
arrivals AS (
    SELECT d.t, COUNTIF(o.order_id IS NOT NULL) AS arrived
    FROM days AS d LEFT JOIN `sahyadri_b2b.dd_orders` AS o ON o.release_day = d.t
    GROUP BY d.t
),
cumulative AS (
    SELECT t, SUM(arrived) OVER (ORDER BY t) AS a FROM arrivals
),
departures AS (
    SELECT c.c, x.t, x.a,
           -- day 0 is the first shipping day, so up to c (t + 1) orders can have shipped by day t
           c.c * x.t + LEAST(c.c, MIN(x.a - c.c * x.t) OVER (PARTITION BY c.c ORDER BY x.t)) AS d
    FROM cumulative AS x CROSS JOIN caps AS c
),
steps AS (
    SELECT c, t, d, IFNULL(LAG(d) OVER (PARTITION BY c ORDER BY t), 0) AS d_before FROM departures
)
SELECT st.c, o.order_id, o.arrival_no, o.release_day, o.deadline_day, st.t AS ship_day,
       st.t > o.deadline_day AS missed
FROM `sahyadri_b2b.dd_orders` AS o
JOIN steps AS st ON o.arrival_no > st.d_before AND o.arrival_no <= st.d;

WITH required AS (
    SELECT CAST(CEIL(MAX(required_per_day)) AS INT64) AS edf_capacity FROM `sahyadri_b2b.dd_windows`
)
SELECT
    f.c                                                                              AS capacity_per_day,
    COUNT(*)                                                                         AS orders,
    COUNTIF(f.missed)                                                                AS fifo_missed,
    ROUND(100 * COUNTIF(f.missed) / COUNT(*), 2)                                     AS fifo_missed_pct,
    MAX(GREATEST(f.ship_day - f.deadline_day, 0))                                    AS fifo_worst_days_late,
    ROUND(AVG(f.ship_day - f.release_day), 2)                                        AS avg_wait_days_either_rule,
    IF(f.c >= ANY_VALUE(r.edf_capacity), 'Every deadline met', 'Some deadlines missed') AS deadline_first
FROM `sahyadri_b2b.dd_fifo` AS f
CROSS JOIN required AS r
GROUP BY f.c
ORDER BY f.c;

-- -----------------------------------------------------------------------------
-- Step 4 · Today: missed deadlines against capacity actually used
-- -----------------------------------------------------------------------------
WITH shipped_per_day AS (
    SELECT actual_ship_day AS t, COUNT(*) AS shipped FROM `sahyadri_b2b.dd_orders` GROUP BY actual_ship_day
)
SELECT
    (SELECT ROUND(AVG(shipped), 2) FROM shipped_per_day)                             AS avg_shipped_per_shipping_day,
    (SELECT APPROX_QUANTILES(shipped, 10)[OFFSET(9)] FROM shipped_per_day)           AS p90_shipped_per_day,
    (SELECT MAX(shipped) FROM shipped_per_day)                                       AS most_shipped_in_a_day,
    (SELECT COUNTIF(shipped >= 12) FROM shipped_per_day)                             AS days_shipping_12_or_more,
    (SELECT COUNTIF(actual_ship_day > deadline_day) FROM `sahyadri_b2b.dd_orders`)   AS missed_deadlines,
    (SELECT COUNTIF(actual_ship_day > deadline_day AND last_delivery > promised_delivery_date) FROM `sahyadri_b2b.dd_orders`) AS missed_and_delivered_late,
    (SELECT COUNTIF(actual_ship_day <= deadline_day AND last_delivery > promised_delivery_date) FROM `sahyadri_b2b.dd_orders`) AS on_time_dispatch_but_late,
    (SELECT COUNTIF(last_delivery > promised_delivery_date) FROM `sahyadri_b2b.dd_orders`) AS delivered_late;

-- Missed deadlines by slack: are the tight orders the ones that miss?
SELECT
    CASE WHEN o.slack_days <= 3 THEN '1. 0-3 days' WHEN o.slack_days <= 7 THEN '2. 4-7 days'
         WHEN o.slack_days <= 11 THEN '3. 8-11 days' ELSE '4. 12+ days' END        AS slack,
    COUNT(*)                                                                         AS orders,
    ROUND(AVG(o.actual_ship_day - o.release_day), 1)                                 AS actual_avg_wait_days,
    ROUND(100 * COUNTIF(o.actual_ship_day > o.deadline_day) / COUNT(*), 1)           AS actual_missed_pct,
    ROUND(100 * COUNTIF(f.missed) / COUNT(*), 1)                                     AS fifo_12_missed_pct
FROM `sahyadri_b2b.dd_orders` AS o
JOIN `sahyadri_b2b.dd_fifo` AS f ON f.order_id = o.order_id AND f.c = 12
GROUP BY slack
ORDER BY slack;
