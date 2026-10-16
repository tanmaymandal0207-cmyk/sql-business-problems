/* =============================================================================
   Case study · Customer churn early warning
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   B2B customers rarely "cancel" — they simply stop ordering. By the time the
   annual review shows a drop, the account has often moved to a competitor.
   The sales head wants a monthly early-warning view:
     1. How many customers are active, at risk, lapsed or lost?
     2. How much annual revenue sits with customers who have gone quiet?
     3. Which still-active customers are overdue against their own usual
        ordering cycle, so account managers can call them now?
     4. Which lapsed or lost accounts are worth a win-back effort?

   KEY RULES
     - Revenue = SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))
       on orders that are not Cancelled or Returned (repository convention).
     - Activity status by days since last order, at the as-of date:
         Active <= 90 · At risk 91-180 · Lapsed 181-365 · Lost > 365
     - Annual run-rate = revenue in the 365 days up to and including the
       customer's last order (their yearly value when they were last active).
     - Usual ordering cycle = median gap in days between consecutive orders
       (customers with at least 3 orders).
     - Overdue vs cycle = days since last order > 2 x usual cycle and > 30 days.
   ============================================================================= */

DECLARE as_of_date DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · One row per customer: activity, value and status
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_activity_status` AS
WITH order_value AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i
        ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.customer_id, o.order_id, o.order_date
),

customer_orders AS (
    SELECT
        customer_id,
        COUNT(*)            AS total_orders,
        MIN(order_date)     AS first_order_date,
        MAX(order_date)     AS last_order_date,
        SUM(order_revenue)  AS lifetime_revenue
    FROM order_value
    GROUP BY customer_id
),

previous_order AS (
    SELECT
        customer_id,
        order_date,
        LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date, order_id)
            AS previous_order_date
    FROM order_value
),

order_gaps AS (
    SELECT
        customer_id,
        DATE_DIFF(order_date, previous_order_date, DAY) AS gap_days
    FROM previous_order
    WHERE previous_order_date IS NOT NULL
),

usual_cycle AS (
    SELECT DISTINCT
        customer_id,
        PERCENTILE_CONT(gap_days, 0.5) OVER (PARTITION BY customer_id) AS usual_cycle_days
    FROM order_gaps
),

run_rate AS (
    -- revenue in the 365 days up to and including the last order
    SELECT
        v.customer_id,
        SUM(v.order_revenue) AS annual_run_rate
    FROM order_value      AS v
    JOIN customer_orders  AS c
        ON c.customer_id = v.customer_id
    WHERE DATE_DIFF(c.last_order_date, v.order_date, DAY) < 365
    GROUP BY v.customer_id
)

SELECT
    c.customer_id,
    cu.customer_name,
    cu.customer_segment,
    c.total_orders,
    c.first_order_date,
    c.last_order_date,
    DATE_DIFF(as_of_date, c.last_order_date, DAY)        AS days_since_last_order,
    ROUND(c.lifetime_revenue, 2)                         AS lifetime_revenue,
    ROUND(r.annual_run_rate, 2)                          AS annual_run_rate,
    IF(c.total_orders >= 3, u.usual_cycle_days, NULL)    AS usual_cycle_days,
    CASE
        WHEN DATE_DIFF(as_of_date, c.last_order_date, DAY) <= 90  THEN '1. Active'
        WHEN DATE_DIFF(as_of_date, c.last_order_date, DAY) <= 180 THEN '2. At risk'
        WHEN DATE_DIFF(as_of_date, c.last_order_date, DAY) <= 365 THEN '3. Lapsed'
        ELSE                                                          '4. Lost'
    END                                                  AS activity_status,
    IFNULL(
        c.total_orders >= 3
        AND DATE_DIFF(as_of_date, c.last_order_date, DAY) > 30
        AND DATE_DIFF(as_of_date, c.last_order_date, DAY) > 2 * u.usual_cycle_days,
        FALSE)                                           AS overdue_vs_cycle
FROM customer_orders       AS c
JOIN `sahyadri_b2b.customers` AS cu
    ON cu.customer_id = c.customer_id
JOIN run_rate              AS r
    ON r.customer_id = c.customer_id
LEFT JOIN usual_cycle      AS u
    ON u.customer_id = c.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Customer base by activity status
-- -----------------------------------------------------------------------------
SELECT
    activity_status,
    COUNT(*)                                                    AS customers,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS pct_of_customers,
    ROUND(SUM(annual_run_rate), 2)                              AS annual_run_rate,
    ROUND(100 * SUM(annual_run_rate)
          / SUM(SUM(annual_run_rate)) OVER (), 1)               AS pct_of_run_rate,
    ROUND(AVG(total_orders), 1)                                 AS avg_orders,
    COUNTIF(overdue_vs_cycle)                                   AS overdue_vs_cycle
FROM `sahyadri_b2b.customer_activity_status`
GROUP BY activity_status
ORDER BY activity_status;

-- -----------------------------------------------------------------------------
-- Step 3 · Revenue gone quiet by customer segment
--          (At risk + Lapsed + Lost, as a share of each segment's run-rate)
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                                    AS customers,
    COUNTIF(activity_status <> '1. Active')                     AS quiet_customers,
    ROUND(SUM(annual_run_rate), 2)                              AS segment_run_rate,
    ROUND(SUM(IF(activity_status <> '1. Active', annual_run_rate, 0)), 2)
                                                                AS quiet_run_rate,
    ROUND(100 * SUM(IF(activity_status <> '1. Active', annual_run_rate, 0))
          / SUM(annual_run_rate), 1)                            AS pct_run_rate_quiet
FROM `sahyadri_b2b.customer_activity_status`
GROUP BY customer_segment
ORDER BY pct_run_rate_quiet DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Early-warning call list: still active or at risk, but overdue
--          against their own usual ordering cycle
-- -----------------------------------------------------------------------------
SELECT
    customer_id,
    customer_name,
    customer_segment,
    activity_status,
    total_orders,
    usual_cycle_days,
    days_since_last_order,
    ROUND(days_since_last_order / usual_cycle_days, 1)          AS times_usual_cycle,
    annual_run_rate
FROM `sahyadri_b2b.customer_activity_status`
WHERE overdue_vs_cycle
  AND activity_status IN ('1. Active', '2. At risk')
ORDER BY annual_run_rate DESC
LIMIT 15;

-- -----------------------------------------------------------------------------
-- Step 5 · Win-back list: largest lapsed and lost accounts
-- -----------------------------------------------------------------------------
SELECT
    customer_id,
    customer_name,
    customer_segment,
    activity_status,
    last_order_date,
    days_since_last_order,
    total_orders,
    annual_run_rate
FROM `sahyadri_b2b.customer_activity_status`
WHERE activity_status IN ('3. Lapsed', '4. Lost')
ORDER BY annual_run_rate DESC
LIMIT 10;
