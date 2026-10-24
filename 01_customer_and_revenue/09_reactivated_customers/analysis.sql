/* =============================================================================
   Case study · Reactivated customers
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The churn early-warning study classes a customer as Lapsed after 180 days
   without an order. Some of those customers come back on their own or after
   a sales call. The commercial head is deciding how much effort to put into
   win-back, and wants evidence on what a returning customer is worth:
     1. How many lapsed customers come back, and after how long?
     2. How much do they buy when they return, compared with before they
        went quiet?
     3. Do they stay, or lapse again? How does that compare with customers
        who never went quiet?
     4. Which returns are most likely to last (gap length, history, segment,
        salesperson)?
     5. How much of the last 12 months' revenue comes from returned
        customers, and which recent returners need follow-up now?

   KEY RULES
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - A RETURN (reactivation) is an order placed more than 180 days after
       the customer's previous order (the Lapsed threshold of the churn study).
     - "Stayed" = another order within 180 days of the return order. Only
       returns up to 180 days before the as-of date are judged (observed).
     - Before / after revenue: 180 days ending on the last order before the
       silence, and 180 days starting on the return date.
     - As-of date 30 Sep 2026; last 12 months = 1 Oct 2025 - 30 Sep 2026.
   ============================================================================= */

DECLARE as_of      DATE  DEFAULT DATE '2026-09-30';
DECLARE lapse_days INT64 DEFAULT 180;

-- -----------------------------------------------------------------------------
-- Step 1 · Order history per customer with the gap before and after each order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_order_gaps` AS
WITH orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.employee_id,
        o.order_date,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, o.employee_id, o.order_date
),
sequenced AS (
    SELECT
        *,
        ROW_NUMBER()     OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS order_seq,
        LAG(order_date)  OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS previous_order_date,
        LAG(employee_id) OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS previous_employee_id,
        LEAD(order_date) OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS next_order_date
    FROM orders
)
SELECT
    *,
    DATE_DIFF(order_date, previous_order_date, DAY) AS days_since_previous,
    DATE_DIFF(next_order_date, order_date, DAY)     AS days_to_next,
    IFNULL(DATE_DIFF(order_date, previous_order_date, DAY) > lapse_days, FALSE) AS is_return
FROM sequenced;

-- -----------------------------------------------------------------------------
-- Step 2 · One row per return, with before / after value and whether it lasted
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.reactivation_events` AS
WITH events AS (
    SELECT
        g.customer_id,
        g.order_id                                         AS return_order_id,
        g.order_date                                       AS return_date,
        g.previous_order_date                              AS last_order_before_gap,
        g.days_since_previous                              AS gap_days,
        g.order_seq - 1                                    AS orders_before_return,
        g.revenue                                          AS return_order_revenue,
        g.next_order_date,
        g.days_to_next,
        g.employee_id,
        g.previous_employee_id
    FROM `sahyadri_b2b.customer_order_gaps` AS g
    WHERE g.is_return
),
window_revenue AS (
    SELECT
        e.return_order_id,
        SUM(IF(h.order_date >  DATE_SUB(e.last_order_before_gap, INTERVAL lapse_days DAY)
           AND h.order_date <= e.last_order_before_gap, h.revenue, 0))                  AS revenue_180_before,
        SUM(IF(h.order_date >= e.return_date
           AND h.order_date <  DATE_ADD(e.return_date, INTERVAL lapse_days DAY), h.revenue, 0)) AS revenue_180_after,
        COUNTIF(h.order_date >= e.return_date
           AND h.order_date <  DATE_ADD(e.return_date, INTERVAL lapse_days DAY))        AS orders_180_after,
        SUM(IF(h.order_date < e.return_date, h.revenue, 0))                             AS revenue_before_return
    FROM events AS e
    JOIN `sahyadri_b2b.customer_order_gaps` AS h ON h.customer_id = e.customer_id
    GROUP BY e.return_order_id
)
SELECT
    e.*,
    c.customer_name,
    c.customer_segment,
    CASE WHEN e.gap_days <= 270 THEN '1. 181-270 days'
         WHEN e.gap_days <= 365 THEN '2. 271-365 days'
         ELSE                        '3. Over 365 days' END                AS gap_band,
    CASE WHEN e.orders_before_return = 1 THEN '1. One order'
         WHEN e.orders_before_return <= 3 THEN '2. 2-3 orders'
         WHEN e.orders_before_return <= 9 THEN '3. 4-9 orders'
         ELSE                                  '4. 10+ orders' END        AS history_band,
    CASE WHEN e.employee_id IS NULL OR e.previous_employee_id IS NULL THEN 'Not recorded'
         WHEN e.employee_id = e.previous_employee_id THEN 'Same salesperson'
         ELSE 'Different salesperson' END                                 AS salesperson_change,
    e.return_date <= DATE_SUB(as_of, INTERVAL lapse_days DAY)            AS is_observed,
    IFNULL(e.days_to_next <= lapse_days, FALSE)                          AS stayed,
    w.revenue_180_before,
    w.revenue_180_after,
    w.orders_180_after,
    w.revenue_before_return
FROM events AS e
JOIN window_revenue AS w ON w.return_order_id = e.return_order_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = e.customer_id;

-- -----------------------------------------------------------------------------
-- Step 3 · How many come back, and after how long? Returns against new
--          customers each quarter
-- -----------------------------------------------------------------------------
WITH quarterly AS (
    SELECT
        DATE_TRUNC(order_date, QUARTER)                      AS quarter_start,
        COUNTIF(order_seq = 1)                               AS new_customers,
        COUNTIF(is_return)                                   AS returns,
        SUM(IF(order_seq = 1, revenue, 0))                   AS new_customer_first_order_revenue,
        SUM(IF(is_return, revenue, 0))                       AS return_order_revenue
    FROM `sahyadri_b2b.customer_order_gaps`
    GROUP BY quarter_start
)
SELECT
    quarter_start,
    new_customers,
    returns,
    ROUND(new_customer_first_order_revenue, 0)               AS new_customer_first_order_revenue,
    ROUND(return_order_revenue, 0)                           AS return_order_revenue
FROM quarterly
ORDER BY quarter_start;

SELECT
    COUNT(*)                                                 AS returns,
    COUNT(DISTINCT customer_id)                              AS customers_returned,
    COUNT(DISTINCT IF(customer_id IN (SELECT customer_id FROM `sahyadri_b2b.reactivation_events`
                                      GROUP BY customer_id HAVING COUNT(*) > 1), customer_id, NULL))
                                                             AS customers_returned_more_than_once,
    APPROX_QUANTILES(gap_days, 2)[OFFSET(1)]                 AS median_gap_days,
    ROUND(SUM(return_order_revenue), 0)                      AS return_order_revenue
FROM `sahyadri_b2b.reactivation_events`;

-- -----------------------------------------------------------------------------
-- Step 4 · Do they stay? Returned customers against the normal repeat rate
-- -----------------------------------------------------------------------------
SELECT
    'Return order (after 180+ days of silence)'              AS order_type,
    COUNT(*)                                                 AS orders_observed,
    ROUND(100 * AVG(IF(IFNULL(days_to_next <= 90, FALSE), 1, 0)), 1)  AS next_order_within_90_pct,
    ROUND(100 * AVG(IF(IFNULL(days_to_next <= 180, FALSE), 1, 0)), 1) AS next_order_within_180_pct
FROM `sahyadri_b2b.customer_order_gaps`
WHERE is_return AND order_date <= DATE_SUB(as_of, INTERVAL lapse_days DAY)
UNION ALL
SELECT
    'Repeat order (previous order within 180 days)',
    COUNT(*),
    ROUND(100 * AVG(IF(IFNULL(days_to_next <= 90, FALSE), 1, 0)), 1),
    ROUND(100 * AVG(IF(IFNULL(days_to_next <= 180, FALSE), 1, 0)), 1)
FROM `sahyadri_b2b.customer_order_gaps`
WHERE NOT is_return AND order_seq > 1 AND order_date <= DATE_SUB(as_of, INTERVAL lapse_days DAY)
UNION ALL
SELECT
    'First order (new customer)',
    COUNT(*),
    ROUND(100 * AVG(IF(IFNULL(days_to_next <= 90, FALSE), 1, 0)), 1),
    ROUND(100 * AVG(IF(IFNULL(days_to_next <= 180, FALSE), 1, 0)), 1)
FROM `sahyadri_b2b.customer_order_gaps`
WHERE order_seq = 1 AND order_date <= DATE_SUB(as_of, INTERVAL lapse_days DAY);

-- Which returns last? Stay rate by gap length, history, segment and salesperson
SELECT 'Gap length' AS dimension, gap_band AS value_band, COUNT(*) AS returns_observed,
       ROUND(100 * AVG(IF(stayed, 1, 0)), 1) AS stayed_pct
FROM `sahyadri_b2b.reactivation_events` WHERE is_observed GROUP BY gap_band
UNION ALL
SELECT 'Orders before return', history_band, COUNT(*), ROUND(100 * AVG(IF(stayed, 1, 0)), 1)
FROM `sahyadri_b2b.reactivation_events` WHERE is_observed GROUP BY history_band
UNION ALL
SELECT 'Segment', customer_segment, COUNT(*), ROUND(100 * AVG(IF(stayed, 1, 0)), 1)
FROM `sahyadri_b2b.reactivation_events` WHERE is_observed GROUP BY customer_segment
UNION ALL
SELECT 'Salesperson on return order', salesperson_change, COUNT(*), ROUND(100 * AVG(IF(stayed, 1, 0)), 1)
FROM `sahyadri_b2b.reactivation_events` WHERE is_observed GROUP BY salesperson_change
ORDER BY dimension, value_band;

-- -----------------------------------------------------------------------------
-- Step 5 · How much do they buy after returning, against before the silence?
-- -----------------------------------------------------------------------------
SELECT
    IF(stayed, 'Stayed (reordered within 180 days)', 'Lapsed again')  AS outcome,
    COUNT(*)                                                 AS returns_observed,
    ROUND(SUM(revenue_180_before), 0)                        AS revenue_180_days_before_silence,
    ROUND(SUM(revenue_180_after), 0)                         AS revenue_180_days_after_return,
    ROUND(SAFE_DIVIDE(SUM(revenue_180_after), SUM(revenue_180_before)), 2) AS after_to_before_ratio,
    ROUND(AVG(orders_180_after), 1)                          AS avg_orders_180_days_after
FROM `sahyadri_b2b.reactivation_events`
WHERE is_observed
GROUP BY outcome
UNION ALL
SELECT
    'All observed returns',
    COUNT(*),
    ROUND(SUM(revenue_180_before), 0),
    ROUND(SUM(revenue_180_after), 0),
    ROUND(SAFE_DIVIDE(SUM(revenue_180_after), SUM(revenue_180_before)), 2),
    ROUND(AVG(orders_180_after), 1)
FROM `sahyadri_b2b.reactivation_events`
WHERE is_observed
ORDER BY outcome;

-- -----------------------------------------------------------------------------
-- Step 6 · Contribution in the last 12 months, and recent returners to follow up
-- -----------------------------------------------------------------------------
WITH returns_12m AS (
    SELECT customer_id, MIN(return_date) AS first_return_in_period
    FROM `sahyadri_b2b.reactivation_events`
    WHERE return_date > DATE_SUB(as_of, INTERVAL 12 MONTH)
    GROUP BY customer_id
)
SELECT
    COUNT(DISTINCT r.customer_id)                            AS customers_returned_12m,
    ROUND(SUM(IF(g.order_date >= r.first_return_in_period, g.revenue, 0)), 0) AS revenue_from_return_onwards,
    ROUND((SELECT SUM(revenue) FROM `sahyadri_b2b.customer_order_gaps`
           WHERE order_date > DATE_SUB(as_of, INTERVAL 12 MONTH) AND order_date <= as_of), 0) AS total_revenue_12m
FROM returns_12m AS r
JOIN `sahyadri_b2b.customer_order_gaps` AS g ON g.customer_id = r.customer_id;

-- Follow-up list: customers who returned in the last 180 days and have not ordered since
SELECT
    customer_id,
    customer_name,
    customer_segment,
    return_date,
    gap_days,
    orders_before_return,
    ROUND(return_order_revenue, 0)                           AS return_order_revenue,
    ROUND(revenue_before_return, 0)                          AS lifetime_revenue_before_return,
    DATE_DIFF(as_of, return_date, DAY)                       AS days_since_return
FROM `sahyadri_b2b.reactivation_events`
WHERE NOT is_observed AND next_order_date IS NULL
ORDER BY return_order_revenue DESC
LIMIT 10;
