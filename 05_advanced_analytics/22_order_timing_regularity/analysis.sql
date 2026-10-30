/* =============================================================================
   Case study · Order timing: do customers order like clockwork, or at random?
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The CRM vendor is selling a "next order date" feature: it learns each
   customer's ordering cycle and alerts the salesperson when a customer is
   overdue. Sales management likes the idea of calling customers just as
   their next order falls due. Before paying for it, the commercial head
   asks:
     1. Do customers order on a regular cycle, or at random times?
     2. Which customers, if any, are regular enough for a cycle-based alert?
     3. Is a customer more likely to order when it is "due" or "overdue"
        against its own cycle?
     4. What should the alerts be based on instead?

   METHOD
     - Order days: distinct dates with a valid order (not Cancelled or
       Returned) per customer. Customers with at least 7 order days
       (6 gaps), January 2024 - September 2026.
     - Regularity: coefficient of variation (CV) of the gaps between order
       days. A fixed cycle gives CV near 0; random (Poisson) ordering gives
       CV near 1; bursts give more.
     - Random benchmark: 200 times per customer, the same number of orders
       is placed at random between the customer's first and last order
       (uniform positions from an integer hash). p(regular) = share of
       random versions with a CV as low as observed; p(bursty) = share with
       a CV as high. At 5 %, about 5 % of customers fall in each tail by
       chance alone.
     - Due-ness: at every month-end from June 2024 to August 2026, for
       customers with 4+ order days so far, days since the last order
       divided by their average gap so far. Outcome: any order in the next
       30 days. Random ordering at the customer's own rate predicts
       1 - EXP(-30 / average gap), whatever the time since the last order.
   ============================================================================= */

DECLARE min_order_days  INT64 DEFAULT 7;
DECLARE simulations     INT64 DEFAULT 200;
DECLARE first_snapshot  DATE  DEFAULT DATE '2024-06-30';
DECLARE last_snapshot   DATE  DEFAULT DATE '2026-08-31';
DECLARE horizon_days    INT64 DEFAULT 30;
DECLARE min_history     INT64 DEFAULT 4;
DECLARE prime           INT64 DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Order days, gaps and the observed regularity
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ot_days` AS
SELECT customer_id, order_date,
       ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date)                              AS seq,
       DATE_DIFF(order_date, LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date), DAY) AS gap
FROM (
    SELECT DISTINCT customer_id, order_date
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
);

CREATE OR REPLACE TABLE `sahyadri_b2b.ot_customers` AS
SELECT
    d.customer_id, c.customer_segment,
    COUNT(*)                                      AS order_days,
    MIN(d.order_date)                             AS first_day,
    MAX(d.order_date)                             AS last_day,
    AVG(d.gap)                                    AS mean_gap,
    STDDEV_POP(d.gap) / AVG(d.gap)                AS cv
FROM `sahyadri_b2b.ot_days` AS d
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = d.customer_id
GROUP BY d.customer_id, c.customer_segment
HAVING COUNT(*) >= min_order_days;

-- -----------------------------------------------------------------------------
-- Step 2 · Random benchmark: the same number of orders at random times
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ot_simulated_cv` AS
WITH points AS (
    -- interior orders (2 .. n-1) get a random position; first and last stay fixed
    SELECT b, c.customer_id, d.seq,
           CASE WHEN d.seq = 1 THEN 0.0
                WHEN d.seq = c.order_days THEN 1.0
                ELSE MOD(MOD(MOD(b * 7919 + d.seq * 104729 + c.customer_id * 1299709, prime)
                           * MOD(b * 7919 + d.seq * 104729 + c.customer_id * 1299709, prime) + 12345, prime)
                       * 48271, prime) / prime END                                                     AS u,
           DATE_DIFF(c.last_day, c.first_day, DAY)                                                     AS span
    FROM `sahyadri_b2b.ot_customers` AS c
    JOIN `sahyadri_b2b.ot_days` AS d ON d.customer_id = c.customer_id
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, simulations)) AS b
),
gaps AS (
    SELECT b, customer_id,
           span * (u - LAG(u) OVER (PARTITION BY b, customer_id ORDER BY u, seq)) AS gap
    FROM points
)
SELECT b, customer_id, STDDEV_POP(gap) / AVG(gap) AS cv, COUNT(*) AS gaps, SUM(gap) AS total_gap
FROM gaps
WHERE gap IS NOT NULL
GROUP BY b, customer_id;

CREATE OR REPLACE TABLE `sahyadri_b2b.ot_regularity` AS
SELECT
    c.customer_id, c.customer_segment, c.order_days, c.mean_gap, c.cv,
    AVG(s.cv)                                                                    AS random_cv,
    (1 + COUNTIF(s.cv <= c.cv)) / (1 + COUNT(*))                                 AS p_regular,
    (1 + COUNTIF(s.cv >= c.cv)) / (1 + COUNT(*))                                 AS p_bursty,
    CASE WHEN (1 + COUNTIF(s.cv <= c.cv)) / (1 + COUNT(*)) < 0.05 THEN 'More regular than random'
         WHEN (1 + COUNTIF(s.cv >= c.cv)) / (1 + COUNT(*)) < 0.05 THEN 'Burstier than random'
         ELSE 'Random-like' END                                                  AS pattern
FROM `sahyadri_b2b.ot_customers` AS c
JOIN `sahyadri_b2b.ot_simulated_cv` AS s ON s.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_segment, c.order_days, c.mean_gap, c.cv;

SELECT
    COUNT(*)                                                       AS customers,
    ROUND(AVG(cv), 3)                                              AS avg_observed_cv,
    ROUND(AVG(random_cv), 3)                                       AS avg_random_cv,
    ROUND(APPROX_QUANTILES(cv, 100)[OFFSET(50)], 3)                AS median_observed_cv,
    COUNTIF(cv < 0.5)                                              AS cv_below_0_5
FROM `sahyadri_b2b.ot_regularity`;

SELECT
    pattern,
    COUNT(*)                                                       AS customers,
    ROUND(0.05 * SUM(COUNT(*)) OVER (), 1)                         AS expected_by_chance_if_tail,
    ROUND(AVG(cv), 2)                                              AS avg_cv,
    ROUND(AVG(mean_gap), 1)                                        AS avg_gap_days,
    ROUND(AVG(order_days), 1)                                      AS avg_order_days
FROM `sahyadri_b2b.ot_regularity`
GROUP BY pattern
ORDER BY pattern;

-- Are there more regular (or bursty) customers than chance? Binomial z against 5 %
SELECT
    COUNTIF(pattern = 'More regular than random')                                              AS regular,
    COUNTIF(pattern = 'Burstier than random')                                                  AS bursty,
    ROUND((COUNTIF(pattern = 'More regular than random') - 0.05 * COUNT(*)) / SQRT(COUNT(*) * 0.05 * 0.95), 2) AS z_regular,
    ROUND((COUNTIF(pattern = 'Burstier than random') - 0.05 * COUNT(*)) / SQRT(COUNT(*) * 0.05 * 0.95), 2)     AS z_bursty
FROM `sahyadri_b2b.ot_regularity`;

-- Who are the regular customers?
SELECT
    customer_segment,
    COUNT(*)                                                                       AS customers,
    COUNTIF(pattern = 'More regular than random')                                  AS regular,
    ROUND(100 * COUNTIF(pattern = 'More regular than random') / COUNT(*), 1)       AS regular_pct,
    ROUND(AVG(IF(pattern = 'More regular than random', mean_gap, NULL)), 1)        AS regular_avg_gap_days,
    ROUND(AVG(IF(pattern = 'More regular than random', cv, NULL)), 2)              AS regular_avg_cv
FROM `sahyadri_b2b.ot_regularity`
GROUP BY customer_segment
ORDER BY customer_segment;

-- -----------------------------------------------------------------------------
-- Step 3 · Is a customer more likely to order when it is "due"?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ot_snapshots` AS
WITH snapshots AS (
    SELECT LAST_DAY(m) AS snapshot_date
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(first_snapshot, MONTH), DATE_TRUNC(last_snapshot, MONTH), INTERVAL 1 MONTH)) AS m
),
history AS (
    SELECT s.snapshot_date, d.customer_id, COUNT(*) AS order_days, MIN(d.order_date) AS first_day, MAX(d.order_date) AS last_day
    FROM snapshots AS s
    JOIN `sahyadri_b2b.ot_days` AS d ON d.order_date <= s.snapshot_date
    GROUP BY s.snapshot_date, d.customer_id
    HAVING COUNT(*) >= min_history
),
next_orders AS (
    SELECT h.snapshot_date, h.customer_id, COUNT(d.order_date) AS orders_next
    FROM history AS h
    LEFT JOIN `sahyadri_b2b.ot_days` AS d
      ON d.customer_id = h.customer_id AND d.order_date > h.snapshot_date
     AND d.order_date <= DATE_ADD(h.snapshot_date, INTERVAL horizon_days DAY)
    GROUP BY h.snapshot_date, h.customer_id
)
SELECT
    h.snapshot_date, h.customer_id, h.order_days,
    DATE_DIFF(h.last_day, h.first_day, DAY) / (h.order_days - 1)                         AS mean_gap_so_far,
    DATE_DIFF(h.snapshot_date, h.last_day, DAY)                                          AS days_since_last,
    DATE_DIFF(h.snapshot_date, h.last_day, DAY) / (DATE_DIFF(h.last_day, h.first_day, DAY) / (h.order_days - 1)) AS dueness,
    n.orders_next > 0                                                                    AS ordered_next,
    1 - EXP(-horizon_days / (DATE_DIFF(h.last_day, h.first_day, DAY) / (h.order_days - 1))) AS random_expectation,
    IFNULL(r.pattern, 'Fewer than 7 order days')                                         AS pattern
FROM history AS h
JOIN next_orders AS n ON n.snapshot_date = h.snapshot_date AND n.customer_id = h.customer_id
LEFT JOIN `sahyadri_b2b.ot_regularity` AS r ON r.customer_id = h.customer_id;

SELECT
    CASE WHEN dueness < 0.5 THEN '1. Just ordered (< 0.5 cycles)'
         WHEN dueness < 1   THEN '2. Not yet due (0.5-1)'
         WHEN dueness < 2   THEN '3. Due (1-2 cycles)'
         WHEN dueness < 4   THEN '4. Overdue (2-4 cycles)'
         ELSE                    '5. Long silent (4+ cycles)' END                AS position_in_cycle,
    COUNT(*)                                                                     AS customer_months,
    ROUND(100 * AVG(IF(ordered_next, 1, 0)), 1)                                  AS ordered_in_30_days_pct,
    ROUND(100 * AVG(random_expectation), 1)                                      AS random_ordering_predicts_pct,
    ROUND(AVG(days_since_last), 0)                                               AS avg_days_since_last
FROM `sahyadri_b2b.ot_snapshots`
GROUP BY position_in_cycle
ORDER BY position_in_cycle;

-- The same for the customers classed as regular
SELECT
    CASE WHEN dueness < 0.5 THEN '1. Just ordered (< 0.5 cycles)'
         WHEN dueness < 1   THEN '2. Not yet due (0.5-1)'
         WHEN dueness < 2   THEN '3. Due (1-2 cycles)'
         ELSE                    '4. Overdue (2+ cycles)' END                    AS position_in_cycle,
    COUNT(*)                                                                     AS customer_months,
    ROUND(100 * AVG(IF(ordered_next, 1, 0)), 1)                                  AS ordered_in_30_days_pct,
    ROUND(100 * AVG(random_expectation), 1)                                      AS random_ordering_predicts_pct
FROM `sahyadri_b2b.ot_snapshots`
WHERE pattern = 'More regular than random'
GROUP BY position_in_cycle
ORDER BY position_in_cycle;

-- Ordering rate as a predictor: share ordering in the next 30 days by average gap so far
SELECT
    CASE WHEN mean_gap_so_far < 15 THEN '1. Under 15 days'
         WHEN mean_gap_so_far < 30 THEN '2. 15-30 days'
         WHEN mean_gap_so_far < 60 THEN '3. 30-60 days'
         WHEN mean_gap_so_far < 120 THEN '4. 60-120 days'
         ELSE '5. 120+ days' END                                                 AS average_gap_so_far,
    COUNT(*)                                                                     AS customer_months,
    ROUND(100 * AVG(IF(ordered_next, 1, 0)), 1)                                  AS ordered_in_30_days_pct,
    ROUND(100 * AVG(random_expectation), 1)                                      AS random_ordering_predicts_pct
FROM `sahyadri_b2b.ot_snapshots`
GROUP BY average_gap_so_far
ORDER BY average_gap_so_far;
