/* =============================================================================
   Case study · Little's Law: backlog, throughput and lead time for 2027
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Orders are growing about 17 % a year. The operations head must decide
   for 2027 how much staging space the warehouse needs for orders waiting
   to be dispatched, how many consignments will be on the road at once, and
   how fast dispatch must become to stop the backlog growing. Today the
   team plans from month-end open-order counts. She asks:
     1. How many orders are, on average, waiting for dispatch and in
        transit, and does Little's Law (average number in a stage = arrival
        rate x average time in it) hold on this data?
     2. Do month-end snapshots give a fair picture of the backlog?
     3. How large are the peaks around the averages?
     4. What will 2027 look like at today's speed, and what dispatch speed
        keeps the backlog at today's level?

   METHOD
     - Stage 1, awaiting dispatch: from order date to first shipment date.
       Stage 2, in transit: from first shipment to final delivery (delivered
       orders). Orders still open on 30 Sep 2026 stay in their stage until
       that date. Cancelled orders never shipped are excluded (the date
       they left the backlog is not recorded); so are 5 orders shipped
       before they were placed and 4 delivered orders without a shipment.
     - Daily count N(d) = orders that entered the stage on or before day d
       and had not left it by the end of day d. Its daily sum equals the
       total days spent in the stage, so over a period
       L (average N) = lambda (entries per day) x W (average days in stage)
       up to the orders that cross the period's boundaries.
     - Shipments never delivered and on the road for more than 30 days are
       counted separately as stale records; transit planning uses
       delivered orders only.
     - 2027 at today's speed: lambda grows by the 12-month order growth
       (Oct 2025 - Sep 2026 against the year before); W stays at its
       2026 level. Required speed to hold L: W x old lambda / new lambda.
   ============================================================================= */

DECLARE start_date DATE DEFAULT DATE '2024-01-01';
DECLARE as_of      DATE DEFAULT DATE '2026-09-30';
DECLARE stale_days INT64 DEFAULT 30;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per order with its stage dates
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ll_orders` AS
WITH ship AS (
    SELECT order_id, MIN(shipment_date) AS dispatch_date,
           IF(COUNT(delivery_date) = COUNT(*), MAX(delivery_date), NULL) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
)
SELECT
    o.order_id, o.order_date, o.order_status, s.dispatch_date, s.final_delivery_date,
    -- stage 1: awaiting dispatch (open orders stay until the as-of date)
    o.order_date                                                                       AS s1_start,
    IFNULL(s.dispatch_date, as_of)                                                     AS s1_end,
    s.dispatch_date IS NULL                                                            AS s1_open,
    -- stage 2: in transit (only orders that were dispatched)
    s.dispatch_date                                                                    AS s2_start,
    IF(s.dispatch_date IS NULL, NULL, IFNULL(s.final_delivery_date, as_of))            AS s2_end,
    s.dispatch_date IS NOT NULL AND s.final_delivery_date IS NULL                      AS s2_open
FROM `sahyadri_b2b.sales_orders` AS o
LEFT JOIN ship AS s ON s.order_id = o.order_id
WHERE o.order_date BETWEEN start_date AND as_of
  AND (s.dispatch_date IS NOT NULL OR o.order_status IN ('Pending', 'Processing'))   -- never-shipped cancellations and data errors out
  AND (s.dispatch_date IS NULL OR s.dispatch_date >= o.order_date);

-- -----------------------------------------------------------------------------
-- Step 2 · Daily number in each stage
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ll_daily` AS
WITH days AS (
    SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(start_date, as_of)) AS d
),
moves AS (
    SELECT 'Awaiting dispatch' AS stage, s1_start AS d, 1 AS entered, 0 AS left_stage FROM `sahyadri_b2b.ll_orders`
    UNION ALL SELECT 'Awaiting dispatch', s1_end, 0, 1 FROM `sahyadri_b2b.ll_orders` WHERE NOT s1_open
    UNION ALL SELECT 'In transit', s2_start, 1, 0 FROM `sahyadri_b2b.ll_orders` WHERE s2_start IS NOT NULL
    UNION ALL SELECT 'In transit', s2_end, 0, 1 FROM `sahyadri_b2b.ll_orders` WHERE s2_start IS NOT NULL AND NOT s2_open
    -- the same stage for orders that were delivered (the flow Little's Law describes)
    UNION ALL SELECT 'In transit, delivered orders', s2_start, 1, 0 FROM `sahyadri_b2b.ll_orders` WHERE s2_start IS NOT NULL AND NOT s2_open
    UNION ALL SELECT 'In transit, delivered orders', s2_end, 0, 1 FROM `sahyadri_b2b.ll_orders` WHERE s2_start IS NOT NULL AND NOT s2_open
    -- stale records: shipped, never delivered, and more than 30 days on the road
    UNION ALL SELECT 'Stale: in transit 30+ days, never delivered', DATE_ADD(s2_start, INTERVAL (stale_days + 1) DAY), 1, 0
              FROM `sahyadri_b2b.ll_orders`
              WHERE s2_open AND DATE_ADD(s2_start, INTERVAL (stale_days + 1) DAY) <= as_of
),
per_day AS (
    SELECT k.stage, x.d, IFNULL(SUM(m.entered), 0) AS entered, IFNULL(SUM(m.left_stage), 0) AS left_stage
    FROM days AS x
    CROSS JOIN (SELECT 'Awaiting dispatch' AS stage UNION ALL SELECT 'In transit'
                UNION ALL SELECT 'In transit, delivered orders'
                UNION ALL SELECT 'Stale: in transit 30+ days, never delivered') AS k
    LEFT JOIN moves AS m ON m.stage = k.stage AND m.d = x.d
    GROUP BY k.stage, x.d
)
SELECT
    stage, d, entered, left_stage,
    SUM(entered - left_stage) OVER (PARTITION BY stage ORDER BY d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS in_stage,
    d = LAST_DAY(d)                                                                                                 AS is_month_end
FROM per_day;

-- -----------------------------------------------------------------------------
-- Step 3 · Little's Law by year: L against lambda x W
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ll_yearly` AS
WITH stage_rows AS (
    SELECT 'Awaiting dispatch' AS stage, order_id, s1_start AS start_d, s1_end AS end_d FROM `sahyadri_b2b.ll_orders`
    UNION ALL
    SELECT 'In transit', order_id, s2_start, s2_end FROM `sahyadri_b2b.ll_orders` WHERE s2_start IS NOT NULL
    UNION ALL
    SELECT 'In transit, delivered orders', order_id, s2_start, s2_end FROM `sahyadri_b2b.ll_orders` WHERE s2_start IS NOT NULL AND NOT s2_open
),
periods AS (
    SELECT 2024 AS period, DATE '2024-01-01' AS p_start, DATE '2024-12-31' AS p_end UNION ALL
    SELECT 2025, DATE '2025-01-01', DATE '2025-12-31' UNION ALL
    SELECT 2026, DATE '2026-01-01', as_of
),
flow AS (
    SELECT p.period, r.stage,
           COUNT(*)                                       AS entries,
           AVG(DATE_DIFF(r.end_d, r.start_d, DAY))        AS avg_days_in_stage
    FROM stage_rows AS r
    JOIN periods AS p ON r.start_d BETWEEN p.p_start AND p.p_end
    GROUP BY p.period, r.stage
),
level AS (
    SELECT p.period, y.stage, AVG(y.in_stage) AS avg_in_stage, MAX(y.in_stage) AS peak_in_stage,
           APPROX_QUANTILES(y.in_stage, 100)[OFFSET(95)] AS p95_in_stage,
           AVG(IF(y.is_month_end, y.in_stage, NULL)) AS avg_at_month_end,
           DATE_DIFF(ANY_VALUE(p.p_end), ANY_VALUE(p.p_start), DAY) + 1 AS days
    FROM `sahyadri_b2b.ll_daily` AS y
    JOIN periods AS p ON y.d BETWEEN p.p_start AND p.p_end
    GROUP BY p.period, y.stage
)
SELECT
    l.period, l.stage, l.days,
    f.entries,
    f.entries / l.days                                        AS lambda_per_day,
    f.avg_days_in_stage                                       AS w_days,
    f.entries / l.days * f.avg_days_in_stage                  AS lambda_times_w,
    l.avg_in_stage                                            AS l_observed,
    l.p95_in_stage, l.peak_in_stage, l.avg_at_month_end
FROM level AS l
JOIN flow AS f ON f.period = l.period AND f.stage = l.stage;

SELECT
    stage, period,
    entries,
    ROUND(lambda_per_day, 2)                                   AS orders_per_day,
    ROUND(w_days, 2)                                           AS avg_days_in_stage,
    ROUND(lambda_times_w, 1)                                   AS lambda_x_w,
    ROUND(l_observed, 1)                                       AS avg_number_in_stage,
    ROUND(100 * (l_observed / lambda_times_w - 1), 1)          AS difference_pct
FROM `sahyadri_b2b.ll_yearly`
ORDER BY stage, period;

-- Whole period: boundary effects only at the two ends
WITH whole AS (
    SELECT stage, AVG(in_stage) AS l_observed, SUM(entered) AS entries, COUNT(*) AS days FROM `sahyadri_b2b.ll_daily` GROUP BY stage
),
w AS (
    SELECT 'Awaiting dispatch' AS stage, AVG(DATE_DIFF(s1_end, s1_start, DAY)) AS w FROM `sahyadri_b2b.ll_orders`
    UNION ALL
    SELECT 'In transit', AVG(DATE_DIFF(s2_end, s2_start, DAY)) FROM `sahyadri_b2b.ll_orders` WHERE s2_start IS NOT NULL
    UNION ALL
    SELECT 'In transit, delivered orders', AVG(DATE_DIFF(s2_end, s2_start, DAY)) FROM `sahyadri_b2b.ll_orders` WHERE s2_start IS NOT NULL AND NOT s2_open
)
SELECT
    h.stage, h.days, h.entries,
    ROUND(h.entries / h.days, 3)                              AS lambda_per_day,
    ROUND(w.w, 3)                                             AS w_days,
    ROUND(h.entries / h.days * w.w, 2)                        AS lambda_x_w,
    ROUND(h.l_observed, 2)                                    AS l_observed
FROM whole AS h JOIN w USING (stage)
ORDER BY h.stage;

-- -----------------------------------------------------------------------------
-- Step 4 · Month-end snapshots against daily reality, and the peaks
-- -----------------------------------------------------------------------------
SELECT
    stage, period,
    ROUND(l_observed, 1)                                       AS daily_average,
    ROUND(avg_at_month_end, 1)                                 AS month_end_average,
    ROUND(100 * (avg_at_month_end / l_observed - 1), 1)        AS month_end_vs_daily_pct,
    p95_in_stage                                               AS p95_day,
    peak_in_stage                                              AS peak_day
FROM `sahyadri_b2b.ll_yearly`
WHERE stage IN ('Awaiting dispatch', 'In transit')
ORDER BY stage, period;

-- Stale in-transit records: what they add to the in-transit count
SELECT
    d                                                          AS month_end,
    MAX(IF(stage = 'In transit', in_stage, NULL))              AS in_transit_recorded,
    MAX(IF(stage = 'Stale: in transit 30+ days, never delivered', in_stage, NULL)) AS stale_records,
    MAX(IF(stage = 'In transit', in_stage, NULL))
      - MAX(IF(stage = 'Stale: in transit 30+ days, never delivered', in_stage, NULL)) AS in_transit_excluding_stale
FROM `sahyadri_b2b.ll_daily`
WHERE is_month_end AND EXTRACT(MONTH FROM d) IN (3, 9)
GROUP BY d
ORDER BY d;

SELECT
    COUNT(*)                                                   AS open_in_transit_at_as_of,
    COUNTIF(DATE_DIFF(as_of, s2_start, DAY) > stale_days)      AS of_which_over_30_days,
    MAX(DATE_DIFF(as_of, s2_start, DAY))                       AS oldest_days,
    SUM(DATE_DIFF(s2_end, s2_start, DAY))                      AS order_days_in_transit,
    ROUND(100 * SUM(DATE_DIFF(s2_end, s2_start, DAY))
          / (SELECT SUM(DATE_DIFF(s2_end, s2_start, DAY)) FROM `sahyadri_b2b.ll_orders` WHERE s2_start IS NOT NULL), 1) AS share_of_all_transit_days_pct
FROM `sahyadri_b2b.ll_orders`
WHERE s2_open;

-- Busiest calendar months for the dispatch backlog (all years)
SELECT
    EXTRACT(MONTH FROM d)                                      AS month_no,
    ROUND(AVG(in_stage), 1)                                    AS avg_awaiting_dispatch,
    MAX(in_stage)                                              AS peak_awaiting_dispatch
FROM `sahyadri_b2b.ll_daily`
WHERE stage = 'Awaiting dispatch'
GROUP BY month_no
ORDER BY avg_awaiting_dispatch DESC
LIMIT 4;

-- -----------------------------------------------------------------------------
-- Step 5 · 2027 at today's speed, and the speed that holds today's backlog
-- -----------------------------------------------------------------------------
WITH growth AS (
    SELECT
        COUNTIF(order_date BETWEEN DATE_SUB(as_of, INTERVAL 364 DAY) AND as_of)
      / COUNTIF(order_date BETWEEN DATE_SUB(as_of, INTERVAL 729 DAY) AND DATE_SUB(as_of, INTERVAL 365 DAY)) - 1 AS g
    FROM `sahyadri_b2b.ll_orders`
),
base AS (
    SELECT * FROM `sahyadri_b2b.ll_yearly` WHERE period = 2026 AND stage != 'In transit'
)
SELECT
    b.stage,
    ROUND(100 * g.g, 1)                                        AS order_growth_pct,
    ROUND(b.lambda_per_day, 2)                                 AS orders_per_day_2026,
    ROUND(b.lambda_per_day * (1 + g.g), 2)                     AS orders_per_day_2027,
    ROUND(b.w_days, 2)                                         AS days_in_stage_2026,
    ROUND(b.l_observed, 1)                                     AS avg_in_stage_2026,
    ROUND(b.lambda_per_day * (1 + g.g) * b.w_days, 1)          AS avg_in_stage_2027_same_speed,
    ROUND(b.p95_in_stage * (1 + g.g), 0)                       AS p95_day_2027_same_speed,
    ROUND(b.w_days / (1 + g.g), 2)                             AS days_in_stage_to_hold_2026_level
FROM base AS b
CROSS JOIN growth AS g
ORDER BY b.stage;
