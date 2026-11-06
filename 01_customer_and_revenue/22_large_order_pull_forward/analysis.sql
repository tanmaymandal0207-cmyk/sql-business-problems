/* =============================================================================
   Case study · Do large orders steal next quarter's demand?
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Orders of Rs 5 lakh or more are about a fifth of revenue. Each time one
   lands, the sales director is told not to celebrate: "they have just
   stocked up, the next quarter will be quiet". If that is true, the plan
   should net a large order against the customer's next months; if not,
   large orders are extra business. The FP&A lead asks:
     1. After a large order, does the customer's regular ordering drop?
     2. Is any drop larger than what random dates would show for the same
        customers?
     3. Does it depend on the window, or on how often the customer places
        large orders?
     4. How should the plan treat a large order?

   METHOD
     - Valid orders (not Cancelled or Returned), January 2024 - September
       2026. Large order: Rs 5 lakh or more. Base revenue: orders below that.
     - Event: a large order with a full window of W days before and after it
       inside the data (W = 30, 60, 90 and 180 days).
     - Customer change = base revenue in the W days after / the W days
       before (the event order itself excluded).
     - Market change = the same ratio for all other customers over the same
       calendar days, which removes trend and season.
     - Relative change = customer change / market change, pooled over events
       (sum of after / sum of before, so large accounts weigh more).
     - Placebo test: 400 sets of random dates for the same customers (one
       per event, from an integer hash), each scored the same way. The share
       of placebo sets with a relative change at or below the actual one is
       the one-sided p-value; the placebo median is the "no-event" level.
   ============================================================================= */

DECLARE first_day   DATE    DEFAULT DATE '2024-01-01';
DECLARE last_day    DATE    DEFAULT DATE '2026-09-30';
DECLARE large_order FLOAT64 DEFAULT 500000;
DECLARE placebo_sets INT64  DEFAULT 400;

-- -----------------------------------------------------------------------------
-- Step 1 · Orders and a daily base-revenue index
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.po_orders` AS
SELECT o.order_id, o.customer_id, o.order_date,
       DATE_DIFF(o.order_date, first_day, DAY)                                        AS t,
       SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))     AS value
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN first_day AND last_day
GROUP BY o.order_id, o.customer_id, o.order_date;

-- Cumulative base revenue of all customers by day, for the market change
CREATE OR REPLACE TABLE `sahyadri_b2b.po_days` AS
WITH days AS (
    SELECT DATE_DIFF(d, first_day, DAY) AS t FROM UNNEST(GENERATE_DATE_ARRAY(first_day, last_day)) AS d
),
daily AS (
    SELECT t, SUM(value) AS base FROM `sahyadri_b2b.po_orders` WHERE value < large_order GROUP BY t
)
SELECT dy.t, IFNULL(dl.base, 0) AS base,
       SUM(IFNULL(dl.base, 0)) OVER (ORDER BY dy.t)                                   AS cum_base
FROM days AS dy LEFT JOIN daily AS dl ON dl.t = dy.t;

-- -----------------------------------------------------------------------------
-- Step 2 · Events and placebo dates, each scored on the same windows
-- -----------------------------------------------------------------------------
-- Windows are the W days before and after the date; the date itself is left out.
CREATE OR REPLACE TABLE `sahyadri_b2b.po_scores` AS
WITH windows AS (
    SELECT w FROM UNNEST([30, 60, 90, 180]) AS w
),
n AS (
    SELECT COUNT(*) AS days FROM `sahyadri_b2b.po_days`
),
events AS (
    SELECT wn.w, ROW_NUMBER() OVER (PARTITION BY wn.w ORDER BY o.order_id) AS e,
           o.order_id, o.customer_id, o.t AS t0, o.value
    FROM `sahyadri_b2b.po_orders` AS o
    CROSS JOIN windows AS wn CROSS JOIN n
    WHERE o.value >= large_order AND o.t >= wn.w + 1 AND o.t <= n.days - 1 - wn.w
),
dates AS (
    -- k = 0: the event itself; k = 1 .. placebo_sets: a random date for the same customer
    SELECT w, e, order_id, customer_id, value, 0 AS k, t0 AS t FROM events
    UNION ALL
    SELECT ev.w, ev.e, ev.order_id, ev.customer_id, ev.value, k,
           ev.w + 1 + MOD(MOD(ev.e * 7919 + k * 1299709, 1000003) * MOD(ev.e * 7919 + k * 1299709, 1000003) + 12345,
                          n.days - 2 * ev.w - 1)                                      AS t
    FROM events AS ev CROSS JOIN n CROSS JOIN UNNEST(GENERATE_ARRAY(1, placebo_sets)) AS k
),
own AS (
    SELECT dt.w, dt.e, dt.k,
           SUM(IF(o.t < dt.t AND o.value < large_order, o.value, 0))                  AS before_base,
           SUM(IF(o.t > dt.t AND o.value < large_order, o.value, 0))                  AS after_base,
           SUM(IF(o.t < dt.t AND o.value >= large_order, o.value, 0))                 AS before_large,
           SUM(IF(o.t > dt.t AND o.value >= large_order, o.value, 0))                 AS after_large
    FROM dates AS dt
    LEFT JOIN `sahyadri_b2b.po_orders` AS o
      ON o.customer_id = dt.customer_id AND o.t BETWEEN dt.t - dt.w AND dt.t + dt.w AND o.t != dt.t
    GROUP BY dt.w, dt.e, dt.k
)
SELECT
    dt.w, dt.e, dt.k, dt.order_id, dt.customer_id, dt.value AS event_value, dt.t,
    own.before_base, own.after_base, own.before_large, own.after_large,
    -- everyone else's base revenue over the same calendar days
    (b1.cum_base - b0.cum_base) - own.before_base                                     AS market_before,
    (a1.cum_base - a0.cum_base) - own.after_base                                      AS market_after
FROM dates AS dt
JOIN own USING (w, e, k)
JOIN `sahyadri_b2b.po_days` AS b1 ON b1.t = dt.t - 1
JOIN `sahyadri_b2b.po_days` AS b0 ON b0.t = dt.t - dt.w - 1
JOIN `sahyadri_b2b.po_days` AS a1 ON a1.t = dt.t + dt.w
JOIN `sahyadri_b2b.po_days` AS a0 ON a0.t = dt.t;

-- One relative change per window and set (k = 0 actual, k >= 1 placebo)
CREATE OR REPLACE TABLE `sahyadri_b2b.po_sets` AS
SELECT w, k,
       COUNT(*)                                                                       AS events,
       SUM(before_base)                                                               AS before_base,
       SUM(after_base)                                                                AS after_base,
       SUM(after_base) / SUM(before_base)                                             AS customer_change,
       SUM(market_after) / SUM(market_before)                                         AS market_change,
       (SUM(after_base) / SUM(before_base)) / (SUM(market_after) / SUM(market_before)) AS relative_change
FROM `sahyadri_b2b.po_scores`
GROUP BY w, k;

-- -----------------------------------------------------------------------------
-- Step 3 · Does regular ordering drop after a large order?
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                                          AS large_orders,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(SUM(value) / 1e7, 2)                                                        AS large_order_revenue_crore,
    ROUND(100 * SUM(value) / (SELECT SUM(value) FROM `sahyadri_b2b.po_orders`), 1)    AS share_of_revenue_pct,
    ROUND(AVG(value) / 1e5, 2)                                                        AS average_large_order_lakh
FROM `sahyadri_b2b.po_orders`
WHERE value >= large_order;

WITH actual AS (SELECT * FROM `sahyadri_b2b.po_sets` WHERE k = 0),
placebo AS (
    SELECT p.w,
           APPROX_QUANTILES(p.relative_change, 100)[OFFSET(5)]                        AS p05,
           APPROX_QUANTILES(p.relative_change, 100)[OFFSET(50)]                       AS p50,
           APPROX_QUANTILES(p.relative_change, 100)[OFFSET(95)]                       AS p95,
           COUNTIF(p.relative_change <= a.relative_change)                            AS at_or_below,
           COUNT(*)                                                                   AS sets
    FROM `sahyadri_b2b.po_sets` AS p JOIN actual AS a USING (w)
    WHERE p.k > 0
    GROUP BY p.w
)
SELECT
    a.w                                                                               AS window_days,
    a.events,
    ROUND(a.before_base / 1e7, 2)                                                     AS base_before_crore,
    ROUND(a.after_base / 1e7, 2)                                                      AS base_after_crore,
    ROUND(a.customer_change, 3)                                                       AS customer_change,
    ROUND(a.market_change, 3)                                                         AS market_change,
    ROUND(a.relative_change, 3)                                                       AS relative_change,
    ROUND(p.p50, 3)                                                                   AS placebo_median,
    ROUND(p.p05, 3)                                                                   AS placebo_p05,
    ROUND(p.p95, 3)                                                                   AS placebo_p95,
    ROUND(p.at_or_below / p.sets, 3)                                                  AS p_value_one_sided,
    ROUND(100 * (a.relative_change / p.p50 - 1), 1)                                   AS dip_vs_placebo_pct
FROM actual AS a JOIN placebo AS p USING (w)
ORDER BY a.w;

-- Robustness: the same test on one common set of events, those with a full 180-day window
-- (the windows above use different events, because longer windows drop events near the edges)
WITH common AS (
    SELECT DISTINCT order_id FROM `sahyadri_b2b.po_scores` WHERE w = 180 AND k = 0
),
sets AS (
    SELECT s.w, s.k, COUNT(*) AS events,
           (SUM(s.after_base) / SUM(s.before_base)) / (SUM(s.market_after) / SUM(s.market_before)) AS rel
    FROM `sahyadri_b2b.po_scores` AS s JOIN common AS c USING (order_id)
    GROUP BY s.w, s.k
)
SELECT
    a.w                                                                               AS window_days,
    ANY_VALUE(a.events)                                                               AS events,
    ROUND(ANY_VALUE(a.rel), 3)                                                        AS relative_change,
    ROUND(APPROX_QUANTILES(p.rel, 100)[OFFSET(50)], 3)                                AS placebo_median,
    ROUND(COUNTIF(p.rel <= a.rel) / COUNT(*), 3)                                      AS p_value_one_sided
FROM (SELECT * FROM sets WHERE k = 0) AS a
JOIN (SELECT * FROM sets WHERE k > 0) AS p USING (w)
GROUP BY a.w
ORDER BY a.w;

-- -----------------------------------------------------------------------------
-- Step 4 · What it is worth, and who it applies to
-- -----------------------------------------------------------------------------
-- Base revenue lost against the placebo level, as a share of the large orders, by window
WITH actual AS (SELECT * FROM `sahyadri_b2b.po_sets` WHERE k = 0),
placebo AS (
    SELECT w, APPROX_QUANTILES(relative_change, 100)[OFFSET(50)] AS p50
    FROM `sahyadri_b2b.po_sets` WHERE k > 0 GROUP BY w
),
ev AS (
    SELECT w, SUM(event_value) AS large_value FROM `sahyadri_b2b.po_scores` WHERE k = 0 GROUP BY w
)
SELECT
    a.w                                                                               AS window_days,
    ROUND(ev.large_value / 1e7, 2)                                                    AS large_orders_crore,
    ROUND(a.after_base * (p.p50 / a.relative_change - 1) / 1e7, 2)                    AS base_lost_crore,
    ROUND(100 * a.after_base * (p.p50 / a.relative_change - 1) / ev.large_value, 1)   AS lost_as_share_of_large_pct
FROM actual AS a JOIN placebo AS p USING (w) JOIN ev USING (w)
ORDER BY a.w;

-- Habitual large-order customers (3 or more large orders) against occasional ones
WITH habit AS (
    SELECT customer_id, IF(COUNTIF(value >= large_order) >= 3, 'Habitual (3+ large orders)', 'Occasional (1-2 large orders)') AS kind
    FROM `sahyadri_b2b.po_orders` GROUP BY customer_id
),
sets AS (
    SELECT h.kind, s.k,
           (SUM(s.after_base) / SUM(s.before_base)) / (SUM(s.market_after) / SUM(s.market_before)) AS rel,
           COUNT(*) AS events, COUNT(DISTINCT s.customer_id) AS customers
    FROM `sahyadri_b2b.po_scores` AS s JOIN habit AS h USING (customer_id)
    WHERE s.w = 90
    GROUP BY h.kind, s.k
)
SELECT
    a.kind,
    ANY_VALUE(a.events)                                                               AS events,
    ANY_VALUE(a.customers)                                                            AS customers,
    ROUND(ANY_VALUE(a.rel), 3)                                                        AS relative_change,
    ROUND(APPROX_QUANTILES(p.rel, 100)[OFFSET(50)], 3)                                AS placebo_median,
    ROUND(COUNTIF(p.rel <= a.rel) / COUNT(*), 3)                                      AS p_value_one_sided
FROM (SELECT * FROM sets WHERE k = 0) AS a
JOIN (SELECT * FROM sets WHERE k > 0) AS p USING (kind)
GROUP BY a.kind
ORDER BY a.kind;
