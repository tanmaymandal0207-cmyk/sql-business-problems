/* =============================================================================
   Case study · Dispatch capacity: how many orders a day must the warehouse ship?
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The Little's Law study showed that the dispatch queue must fall from
   4.0 to about 3.4 days in 2027 to stop the backlog growing with an
   18.7 % rise in orders. The warehouse manager needs that turned into a
   staffing number: how many orders a day must the team be able to pick,
   pack and ship? She asks:
     1. With strict first-in-first-out dispatch, what waiting time does
        each daily capacity give on the last 12 months of orders?
     2. What capacity is the warehouse effectively running at today?
     3. What capacity does 2027 need, and how much extra in March?
     4. How much of today's waiting is capacity, and how much is holds?

   METHOD
     - Arrivals: every order that entered the dispatch queue (shipped, or
       Pending / Processing), by order date, October 2025 - September 2026.
       2027: the same arrivals plus a copy of a random 18.7 % of them (the
       last 12 months' order growth), chosen with an integer hash.
     - Queue: the warehouse ships up to c orders a day, every day, oldest
       first; an order can leave on the day it arrives. Cumulative orders
       shipped by day t:
           D(t) = MIN over s <= t of [ A(s) + c x (t - s) ]   (A(0) = 0)
       where A(s) = orders arrived by day s. Order number k (in arrival
       order) leaves on the first day with D(t) >= k. Capacities of 11-20
       orders a day are tested; the simulation runs 180 days past the end
       so every order leaves.
     - Today's actual waits are compared with orders that were not held
       (dispatched within 6 days; held orders wait 7-22 days in a separate
       queue, see the dispatch holds study).
   ============================================================================= */

DECLARE sim_start   DATE    DEFAULT DATE '2025-10-01';
DECLARE sim_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE prime       INT64   DEFAULT 2147483647;
DECLARE hold_days   INT64   DEFAULT 7;

-- -----------------------------------------------------------------------------
-- Step 1 · Arrivals: today and 2027
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cs_arrivals` AS
WITH ship AS (
    SELECT order_id, MIN(shipment_date) AS dispatch_date FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
queue_orders AS (
    SELECT o.order_id, o.order_date, s.dispatch_date,
           DATE_DIFF(s.dispatch_date, o.order_date, DAY) AS actual_wait
    FROM `sahyadri_b2b.sales_orders` AS o
    LEFT JOIN ship AS s ON s.order_id = o.order_id
    WHERE (s.dispatch_date >= o.order_date OR (s.dispatch_date IS NULL AND o.order_status IN ('Pending', 'Processing')))
),
growth AS (
    SELECT COUNTIF(order_date BETWEEN sim_start AND sim_end)
         / COUNTIF(order_date BETWEEN DATE_SUB(sim_start, INTERVAL 1 YEAR) AND DATE_SUB(sim_end, INTERVAL 1 YEAR)) - 1 AS g
    FROM queue_orders
),
period AS (
    SELECT q.*,
           MOD(MOD(q.order_id * 104729 + 7919, prime) * MOD(q.order_id * 104729 + 7919, prime) + 12345, prime) / prime AS u
    FROM queue_orders AS q
    WHERE q.order_date BETWEEN sim_start AND sim_end
),
copies AS (
    SELECT 'Today' AS scenario, order_id, 0 AS copy_no, order_date, actual_wait FROM period
    UNION ALL
    SELECT '2027', order_id, 0, order_date, actual_wait FROM period
    UNION ALL
    SELECT '2027', p.order_id, 1, p.order_date, NULL FROM period AS p CROSS JOIN growth AS g WHERE p.u < g.g
)
SELECT c.*,
       ROW_NUMBER() OVER (PARTITION BY scenario ORDER BY order_date, copy_no, order_id) AS k,
       (SELECT g FROM growth)                                                         AS growth
FROM copies AS c;

SELECT scenario, COUNT(*) AS orders, ROUND(COUNT(*) / 365, 2) AS orders_per_day, ROUND(100 * ANY_VALUE(growth), 1) AS growth_pct,
       MAX(n_day) AS busiest_day_arrivals
FROM (SELECT scenario, order_date, growth, COUNT(*) OVER (PARTITION BY scenario, order_date) AS n_day FROM `sahyadri_b2b.cs_arrivals`)
GROUP BY scenario
ORDER BY scenario DESC;

-- -----------------------------------------------------------------------------
-- Step 2 · Daily departures for every capacity (FIFO, c orders a day)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cs_days` AS
WITH days AS (
    SELECT d, DATE_DIFF(d, sim_start, DAY) + 1 AS t
    FROM UNNEST(GENERATE_DATE_ARRAY(sim_start, DATE_ADD(sim_end, INTERVAL 180 DAY))) AS d
),
capacities AS (
    SELECT c FROM UNNEST([11, 12, 13, 14, 15, 16, 18, 20]) AS c
),
scenarios AS (
    SELECT DISTINCT scenario FROM `sahyadri_b2b.cs_arrivals`
),
daily AS (
    SELECT scenario, order_date, COUNT(*) AS n FROM `sahyadri_b2b.cs_arrivals` GROUP BY scenario, order_date
),
arrived AS (
    -- A(t): orders arrived by the end of day t
    SELECT s.scenario, x.d, x.t,
           SUM(IFNULL(y.n, 0)) OVER (PARTITION BY s.scenario ORDER BY x.t ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS a_t
    FROM scenarios AS s
    CROSS JOIN days AS x
    LEFT JOIN daily AS y ON y.scenario = s.scenario AND y.order_date = x.d
)
SELECT
    r.scenario, k.c, r.d, r.t, r.a_t,
    -- D(t) = c t + MIN(0, MIN over s <= t of (A(s) - c s))
    k.c * r.t + LEAST(0, MIN(r.a_t - k.c * r.t) OVER (PARTITION BY r.scenario, k.c ORDER BY r.t
                                                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS d_t
FROM arrived AS r
CROSS JOIN capacities AS k;

-- Each order leaves on the first day the cumulative departures reach its number
CREATE OR REPLACE TABLE `sahyadri_b2b.cs_waits` AS
WITH ranges AS (
    SELECT scenario, c, d, d_t, IFNULL(LAG(d_t) OVER (PARTITION BY scenario, c ORDER BY t), 0) AS d_prev
    FROM `sahyadri_b2b.cs_days`
)
SELECT a.scenario, r.c, a.order_id, a.copy_no, a.k, a.order_date, r.d AS sim_dispatch_date,
       DATE_DIFF(r.d, a.order_date, DAY) AS sim_wait, a.actual_wait
FROM `sahyadri_b2b.cs_arrivals` AS a
JOIN ranges AS r ON r.scenario = a.scenario AND a.k > r.d_prev AND a.k <= r.d_t;

-- -----------------------------------------------------------------------------
-- Step 3 · Waiting time by capacity, today and in 2027
-- -----------------------------------------------------------------------------
SELECT
    scenario, c                                                       AS capacity_per_day,
    ROUND(COUNT(*) / 365 / c * 100, 1)                                AS utilisation_pct,
    ROUND(AVG(sim_wait), 2)                                           AS avg_wait_days,
    APPROX_QUANTILES(sim_wait, 100)[OFFSET(90)]                       AS p90_wait,
    APPROX_QUANTILES(sim_wait, 100)[OFFSET(99)]                       AS p99_wait,
    MAX(sim_wait)                                                     AS max_wait,
    ROUND(100 * AVG(IF(sim_wait <= 1, 1, 0)), 1)                      AS within_1_day_pct
FROM `sahyadri_b2b.cs_waits`
GROUP BY scenario, c
ORDER BY scenario DESC, c;

-- -----------------------------------------------------------------------------
-- Step 4 · Today's effective capacity, and holds
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                                    AS orders_dispatched,
    ROUND(AVG(actual_wait), 2)                                                  AS actual_avg_wait,
    ROUND(100 * AVG(IF(actual_wait >= hold_days, 1, 0)), 1)                     AS held_pct,
    ROUND(AVG(IF(actual_wait < hold_days, actual_wait, NULL)), 2)               AS not_held_avg_wait,
    ROUND(AVG(IF(actual_wait >= hold_days, actual_wait, NULL)), 2)              AS held_avg_wait,
    ROUND(AVG(actual_wait) - AVG(IF(actual_wait >= hold_days, hold_days - 1, actual_wait)), 2) AS days_of_avg_wait_from_holds_beyond_6
FROM `sahyadri_b2b.cs_arrivals`
WHERE scenario = 'Today' AND copy_no = 0 AND actual_wait IS NOT NULL;

-- What the warehouse actually ships in a day (orders dispatched per calendar day, last 12 months)
WITH dispatched AS (
    SELECT DATE_ADD(order_date, INTERVAL actual_wait DAY) AS dispatch_date
    FROM `sahyadri_b2b.cs_arrivals`
    WHERE scenario = 'Today' AND copy_no = 0 AND actual_wait IS NOT NULL
),
per_day AS (
    SELECT x.d, COUNT(y.dispatch_date) AS shipped
    FROM UNNEST(GENERATE_DATE_ARRAY(sim_start, sim_end)) AS x
    LEFT JOIN dispatched AS y ON y.dispatch_date = x.d
    GROUP BY x.d
)
SELECT
    ROUND(AVG(shipped), 2)                                   AS avg_orders_shipped_per_day,
    APPROX_QUANTILES(shipped, 100)[OFFSET(50)]               AS median_day,
    APPROX_QUANTILES(shipped, 100)[OFFSET(95)]               AS p95_day,
    MAX(shipped)                                             AS busiest_day,
    COUNTIF(shipped >= 20)                                   AS days_with_20_plus
FROM per_day;

-- The capacity whose simulated average wait is closest to today's non-held average
WITH target AS (
    SELECT AVG(IF(actual_wait < hold_days, actual_wait, NULL)) AS w FROM `sahyadri_b2b.cs_arrivals`
    WHERE scenario = 'Today' AND copy_no = 0
)
SELECT w.c AS capacity_per_day, ROUND(AVG(w.sim_wait), 2) AS sim_avg_wait, ROUND(ANY_VALUE(t.w), 2) AS actual_not_held_avg_wait
FROM `sahyadri_b2b.cs_waits` AS w CROSS JOIN target AS t
WHERE w.scenario = 'Today'
GROUP BY w.c
ORDER BY ABS(AVG(w.sim_wait) - ANY_VALUE(t.w))
LIMIT 3;

-- -----------------------------------------------------------------------------
-- Step 5 · 2027 by month at the chosen capacities: where the queue builds
-- -----------------------------------------------------------------------------
SELECT
    EXTRACT(MONTH FROM order_date)                                     AS month_no,
    COUNTIF(c = 14)                                                    AS orders_2027,
    ROUND(AVG(IF(c = 13, sim_wait, NULL)), 2)                          AS avg_wait_at_13,
    ROUND(AVG(IF(c = 14, sim_wait, NULL)), 2)                          AS avg_wait_at_14,
    ROUND(AVG(IF(c = 15, sim_wait, NULL)), 2)                          AS avg_wait_at_15,
    MAX(IF(c = 14, sim_wait, NULL))                                    AS max_wait_at_14
FROM `sahyadri_b2b.cs_waits`
WHERE scenario = '2027'
GROUP BY month_no
ORDER BY avg_wait_at_14 DESC
LIMIT 6;
