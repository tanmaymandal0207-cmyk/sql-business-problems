/* =============================================================================
   Case study · Dispatch workload and capacity planning
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The warehouse plans staff and vehicles on a flat daily average. Supervisors
   say some days and months are far busier than others, and the late delivery
   study found that slow dispatch causes most late orders. Before the next
   staffing and transport contract, operations wants to know:
     1. How does dispatch volume vary by day of the week and month of the year?
     2. How much daily capacity covers a normal day, a busy day and a peak day?
     3. Does a heavy order intake make dispatch slower?

   KEY RULES
     - Period: 2 Jan 2024 (first shipment) to 30 Sep 2026.
     - A calendar of every day in the period is generated, so days with no
       shipments count as zero rather than disappearing.
     - Shipments per day = shipment records with that shipment date.
     - Orders received per day = orders with that order date.
     - Dispatch days = first shipment date - order date (single and split orders).
     - Capacity levels: median day, 90th percentile day ("busy"),
       95th percentile day ("peak").
   ============================================================================= */

DECLARE period_start DATE DEFAULT DATE '2024-01-02';
DECLARE period_end   DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Daily workload table (every calendar day, zero-filled)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.daily_dispatch_workload` AS
WITH calendar AS (
    SELECT day
    FROM UNNEST(GENERATE_DATE_ARRAY(period_start, period_end)) AS day
),
shipments_per_day AS (
    SELECT shipment_date AS day, COUNT(*) AS shipments
    FROM `sahyadri_b2b.shipments`
    GROUP BY shipment_date
),
orders_per_day AS (
    SELECT order_date AS day, COUNT(*) AS orders_received
    FROM `sahyadri_b2b.sales_orders`
    GROUP BY order_date
)
SELECT
    c.day,
    EXTRACT(DAYOFWEEK FROM c.day)          AS weekday_number,   -- 1 = Sunday
    FORMAT_DATE('%A', c.day)               AS weekday_name,
    EXTRACT(MONTH FROM c.day)              AS month_number,
    IFNULL(s.shipments, 0)                 AS shipments,
    IFNULL(o.orders_received, 0)           AS orders_received
FROM calendar               AS c
LEFT JOIN shipments_per_day AS s ON s.day = c.day
LEFT JOIN orders_per_day    AS o ON o.day = c.day;

-- -----------------------------------------------------------------------------
-- Step 2 · Weekday profile: orders in vs shipments out
-- -----------------------------------------------------------------------------
SELECT
    weekday_name,
    COUNT(*)                                                     AS days,
    ROUND(AVG(orders_received), 1)                               AS avg_orders_received,
    ROUND(AVG(shipments), 1)                                     AS avg_shipments,
    ROUND(100 * SUM(shipments) / SUM(SUM(shipments)) OVER (), 1) AS pct_of_shipments,
    MAX(shipments)                                               AS max_shipments
FROM `sahyadri_b2b.daily_dispatch_workload`
GROUP BY weekday_name, weekday_number
ORDER BY MOD(weekday_number + 5, 7);   -- Monday first

-- -----------------------------------------------------------------------------
-- Step 3 · Monthly seasonality (index: 100 = average day across the period)
-- -----------------------------------------------------------------------------
SELECT
    month_number,
    FORMAT_DATE('%B', DATE(2000, month_number, 1))               AS month_name,
    COUNT(*)                                                     AS days,
    ROUND(AVG(shipments), 1)                                     AS avg_shipments_per_day,
    ROUND(100 * AVG(shipments)
          / (SELECT AVG(shipments) FROM `sahyadri_b2b.daily_dispatch_workload`), 0)
                                                                 AS seasonality_index
FROM `sahyadri_b2b.daily_dispatch_workload`
GROUP BY month_number
ORDER BY month_number;

-- -----------------------------------------------------------------------------
-- Step 4 · Capacity sizing: daily shipments at normal, busy and peak levels
-- -----------------------------------------------------------------------------
WITH levels AS (
    SELECT DISTINCT
        PERCENTILE_CONT(shipments, 0.5)  OVER () AS median_day,
        PERCENTILE_CONT(shipments, 0.9)  OVER () AS busy_day_p90,
        PERCENTILE_CONT(shipments, 0.95) OVER () AS peak_day_p95,
        MAX(shipments)                   OVER () AS max_day,
        AVG(shipments)                   OVER () AS average_day
    FROM `sahyadri_b2b.daily_dispatch_workload`
)
SELECT
    ROUND(l.average_day, 1)                                       AS average_day,
    l.median_day,
    l.busy_day_p90,
    l.peak_day_p95,
    l.max_day,
    COUNTIF(w.shipments > l.median_day)                           AS days_above_median,
    COUNTIF(w.shipments > l.busy_day_p90)                         AS days_above_p90,
    COUNTIF(w.shipments > l.peak_day_p95)                         AS days_above_p95,
    COUNT(*)                                                      AS days_in_period
FROM `sahyadri_b2b.daily_dispatch_workload` AS w
CROSS JOIN levels AS l
GROUP BY l.average_day, l.median_day, l.busy_day_p90, l.peak_day_p95, l.max_day;

-- -----------------------------------------------------------------------------
-- Step 5 · Does heavy order intake slow dispatch?
--          Orders grouped by how many orders arrived on the same day
-- -----------------------------------------------------------------------------
WITH first_dispatch AS (
    SELECT order_id, MIN(shipment_date) AS first_shipment_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
orders_with_load AS (
    SELECT
        o.order_id,
        w.orders_received                                         AS same_day_orders,
        DATE_DIFF(f.first_shipment_date, o.order_date, DAY)       AS dispatch_days
    FROM `sahyadri_b2b.sales_orders`            AS o
    JOIN first_dispatch                         AS f ON f.order_id = o.order_id
    JOIN `sahyadri_b2b.daily_dispatch_workload` AS w ON w.day      = o.order_date
    WHERE f.first_shipment_date >= o.order_date
)
SELECT
    CASE
        WHEN same_day_orders <= 8  THEN '1. Light (8 or fewer orders)'
        WHEN same_day_orders <= 12 THEN '2. Normal (9-12)'
        WHEN same_day_orders <= 16 THEN '3. Busy (13-16)'
        ELSE                            '4. Heavy (17 or more)'
    END                                                           AS intake_band,
    COUNT(*)                                                      AS orders,
    ROUND(AVG(dispatch_days), 2)                                  AS avg_dispatch_days,
    ROUND(100 * COUNTIF(dispatch_days <= 3) / COUNT(*), 1)        AS pct_dispatched_within_3_days,
    ROUND(100 * COUNTIF(dispatch_days >= 9) / COUNT(*), 1)        AS pct_dispatched_after_8_days
FROM orders_with_load
GROUP BY intake_band
ORDER BY intake_band;
