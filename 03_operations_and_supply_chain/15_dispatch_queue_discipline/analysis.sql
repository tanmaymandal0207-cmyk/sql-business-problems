/* =============================================================================
   Case study · Dispatch queue discipline: is it first come, first served?
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Customers complain that an order placed on Monday sometimes ships after
   one placed on Wednesday. The warehouse manager says orders are picked in
   the order they arrive, except for urgent key-account orders. The
   operations head wants evidence before rewriting the picking rule:
     1. How often is an earlier order dispatched after a later one?
     2. Is that more than random dispatch timing would produce?
     3. Do key-account (Enterprise) orders jump the queue?
     4. What would strict first-in-first-out (FIFO) dispatch change for
        waiting times and on-time delivery?

   METHOD
     - Orders with at least one shipment; dispatch date = first shipment
       date; lag = dispatch date - order date (orders shipped before they
       were placed are excluded).
     - Pairs: every two orders placed 1 to 7 days apart. The earlier order is
       "overtaken" if it was dispatched on a later date than the later order;
       a "tie" if both left on the same day.
     - Expected overtaking with no queue discipline: if lags are independent
       of order sequence, P(overtaken | gap g) = P(L1 - L2 > g) for two
       independent lags from the observed lag distribution.
     - FIFO simulation: keep the actual number of dispatches on each day,
       but give the k-th earliest order the k-th earliest dispatch slot
       (never before its own order date). Delivery = simulated dispatch +
       the order's actual transit time.
   ============================================================================= */

DECLARE max_gap INT64 DEFAULT 7;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per dispatched order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.fq_orders` AS
SELECT
    o.order_id, o.customer_id, c.customer_segment, o.order_date, o.order_status, o.promised_delivery_date,
    MIN(s.shipment_date)                                                   AS dispatch_date,
    DATE_DIFF(MIN(s.shipment_date), o.order_date, DAY)                     AS lag_days,
    IF(COUNT(s.delivery_date) = COUNT(*), MAX(s.delivery_date), NULL)     AS final_delivery_date
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
GROUP BY o.order_id, o.customer_id, c.customer_segment, o.order_date, o.order_status, o.promised_delivery_date
HAVING MIN(s.shipment_date) >= o.order_date;

SELECT COUNT(*) AS orders, ROUND(AVG(lag_days), 2) AS avg_lag,
       APPROX_QUANTILES(lag_days, 100)[OFFSET(50)] AS median_lag,
       APPROX_QUANTILES(lag_days, 100)[OFFSET(90)] AS p90_lag, MAX(lag_days) AS max_lag
FROM `sahyadri_b2b.fq_orders`;

-- -----------------------------------------------------------------------------
-- Step 2 · Overtaking: observed against random dispatch timing
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.fq_pairs` AS
SELECT
    DATE_DIFF(b.order_date, a.order_date, DAY)                  AS gap_days,
    a.order_id AS earlier_order, b.order_id AS later_order,
    a.lag_days AS earlier_lag, b.lag_days AS later_lag,
    a.customer_segment AS earlier_segment, b.customer_segment AS later_segment,
    a.dispatch_date > b.dispatch_date                           AS overtaken,
    a.dispatch_date = b.dispatch_date                           AS same_day
FROM `sahyadri_b2b.fq_orders` AS a
JOIN `sahyadri_b2b.fq_orders` AS b
  ON b.order_date > a.order_date
 AND DATE_DIFF(b.order_date, a.order_date, DAY) <= max_gap;

CREATE OR REPLACE TABLE `sahyadri_b2b.fq_expected` AS
WITH lag_dist AS (
    SELECT lag_days, COUNT(*) / SUM(COUNT(*)) OVER () AS p
    FROM `sahyadri_b2b.fq_orders`
    GROUP BY lag_days
)
SELECT g AS gap_days,
       SUM(IF(x.lag_days - y.lag_days > g, x.p * y.p, 0))       AS expected_overtaken,
       SUM(IF(x.lag_days - y.lag_days = g, x.p * y.p, 0))       AS expected_same_day
FROM lag_dist AS x
CROSS JOIN lag_dist AS y
CROSS JOIN UNNEST(GENERATE_ARRAY(1, max_gap)) AS g
GROUP BY g;

SELECT
    p.gap_days,
    COUNT(*)                                                    AS pairs,
    ROUND(100 * AVG(IF(p.overtaken, 1, 0)), 1)                  AS overtaken_pct,
    ROUND(100 * ANY_VALUE(e.expected_overtaken), 1)             AS expected_if_random_pct,
    ROUND(100 * AVG(IF(p.same_day, 1, 0)), 1)                   AS same_day_pct,
    ROUND(100 * ANY_VALUE(e.expected_same_day), 1)              AS expected_same_day_pct
FROM `sahyadri_b2b.fq_pairs` AS p
JOIN `sahyadri_b2b.fq_expected` AS e ON e.gap_days = p.gap_days
GROUP BY p.gap_days
ORDER BY p.gap_days;

-- Does anyone jump the queue? Overtaking by the later order's segment (gaps of 1-3 days)
SELECT
    later_segment,
    COUNT(*)                                                    AS pairs,
    ROUND(100 * AVG(IF(overtaken, 1, 0)), 1)                    AS earlier_order_overtaken_pct
FROM `sahyadri_b2b.fq_pairs`
WHERE gap_days <= 3
GROUP BY later_segment
ORDER BY later_segment;

-- Without the long holds (both orders dispatched within 6 days)
SELECT
    gap_days,
    COUNT(*)                                                    AS pairs,
    ROUND(100 * AVG(IF(overtaken, 1, 0)), 1)                    AS overtaken_pct,
    ROUND(100 * AVG(IF(same_day, 1, 0)), 1)                     AS same_day_pct
FROM `sahyadri_b2b.fq_pairs`
WHERE earlier_lag <= 6 AND later_lag <= 6
GROUP BY gap_days
ORDER BY gap_days;

-- -----------------------------------------------------------------------------
-- Step 3 · What would strict FIFO change?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.fq_fifo` AS
WITH order_seq AS (
    SELECT order_id, ROW_NUMBER() OVER (ORDER BY order_date, order_id) AS k FROM `sahyadri_b2b.fq_orders`
),
slot_seq AS (
    SELECT dispatch_date AS slot_date, ROW_NUMBER() OVER (ORDER BY dispatch_date, order_id) AS k FROM `sahyadri_b2b.fq_orders`
)
SELECT
    o.*,
    GREATEST(s.slot_date, o.order_date)                                                       AS fifo_dispatch_date,
    DATE_DIFF(GREATEST(s.slot_date, o.order_date), o.order_date, DAY)                          AS fifo_lag_days,
    IF(o.final_delivery_date IS NULL, NULL,
       DATE_ADD(GREATEST(s.slot_date, o.order_date), INTERVAL DATE_DIFF(o.final_delivery_date, o.dispatch_date, DAY) DAY)) AS fifo_delivery_date
FROM `sahyadri_b2b.fq_orders` AS o
JOIN order_seq AS q ON q.order_id = o.order_id
JOIN slot_seq AS s ON s.k = q.k;

SELECT 'Actual' AS policy,
       ROUND(AVG(lag_days), 2) AS avg_wait_days,
       APPROX_QUANTILES(lag_days, 100)[OFFSET(50)] AS median_wait,
       APPROX_QUANTILES(lag_days, 100)[OFFSET(90)] AS p90_wait,
       APPROX_QUANTILES(lag_days, 100)[OFFSET(99)] AS p99_wait,
       MAX(lag_days) AS max_wait,
       ROUND(100 * AVG(IF(lag_days >= 7, 1, 0)), 1) AS waited_7_plus_pct
FROM `sahyadri_b2b.fq_fifo`
UNION ALL
SELECT 'Strict FIFO (same daily capacity)',
       ROUND(AVG(fifo_lag_days), 2),
       APPROX_QUANTILES(fifo_lag_days, 100)[OFFSET(50)],
       APPROX_QUANTILES(fifo_lag_days, 100)[OFFSET(90)],
       APPROX_QUANTILES(fifo_lag_days, 100)[OFFSET(99)],
       MAX(fifo_lag_days),
       ROUND(100 * AVG(IF(fifo_lag_days >= 7, 1, 0)), 1)
FROM `sahyadri_b2b.fq_fifo`;

-- On-time delivery: delivered orders with a promise date
SELECT
    COUNT(*)                                                                         AS delivered_orders,
    ROUND(100 * AVG(IF(final_delivery_date <= promised_delivery_date, 1, 0)), 1)     AS on_time_actual_pct,
    ROUND(100 * AVG(IF(fifo_delivery_date  <= promised_delivery_date, 1, 0)), 1)     AS on_time_fifo_pct,
    COUNTIF(final_delivery_date > promised_delivery_date)                            AS late_actual,
    COUNTIF(fifo_delivery_date  > promised_delivery_date)                            AS late_fifo
FROM `sahyadri_b2b.fq_fifo`
WHERE order_status = 'Delivered' AND final_delivery_date IS NOT NULL AND promised_delivery_date IS NOT NULL;
