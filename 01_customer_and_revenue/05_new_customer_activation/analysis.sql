/* =============================================================================
   Case study · New customer onboarding and activation
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Sales reports count new customer registrations, but a registration earns
   nothing until the customer orders, and orders again. The commercial head
   wants to know whether accounts opened since January 2024 are turning into
   real buyers:
     1. How many registered customers place a first order, and how quickly?
     2. How many come back for a second order?
     3. How valuable are new customers in their first year, compared with
        established customers in the same segment?
     4. Which new accounts have stalled and need follow-up?

   KEY RULES
     - New customer: registration_date from 1 Jan 2024 to the as-of date.
       Customers with no registration date are excluded.
     - Orders: Cancelled and Returned orders do not count as purchases.
     - Revenue: quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100).
     - Fair-window rule: a "within 90 days" rate only counts customers who
       have had 90 days to do it, so recent registrations do not drag the
       rate down.
     - First-year value: revenue in the 365 days from the first order, for
       customers whose first order was at least 365 days before the as-of date.
     - Benchmark: established customers (registered before 2024) in the same
       segment, revenue in the last 12 months, among those who bought.
   ============================================================================= */

DECLARE new_from    DATE  DEFAULT DATE '2024-01-01';
DECLARE as_of_date  DATE  DEFAULT DATE '2026-09-30';
DECLARE fair_days   INT64 DEFAULT 90;
DECLARE stall_days  INT64 DEFAULT 90;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per new customer: activation milestones and value
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.new_customer_activation` AS
WITH order_value AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        o.order_status,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_date <= as_of_date
    GROUP BY o.customer_id, o.order_id, o.order_date, o.order_status
),
valid_orders AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS order_seq
    FROM order_value
    WHERE order_status NOT IN ('Cancelled', 'Returned')
),
milestones AS (
    SELECT
        customer_id,
        MIN(IF(order_seq = 1, order_date, NULL)) AS first_order_date,
        MIN(IF(order_seq = 2, order_date, NULL)) AS second_order_date,
        MAX(order_date)                          AS last_order_date,
        COUNT(*)                                 AS valid_orders,
        SUM(revenue)                             AS revenue_to_date
    FROM valid_orders
    GROUP BY customer_id
),
first_year AS (
    SELECT v.customer_id, SUM(v.revenue) AS revenue_first_365
    FROM valid_orders AS v
    JOIN milestones   AS m ON m.customer_id = v.customer_id
    WHERE v.order_date < DATE_ADD(m.first_order_date, INTERVAL 365 DAY)
    GROUP BY v.customer_id
),
invalid_only AS (
    SELECT customer_id, COUNT(*) AS cancelled_or_returned_orders
    FROM order_value
    WHERE order_status IN ('Cancelled', 'Returned')
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.customer_name,
    c.customer_segment,
    c.registration_date,
    EXTRACT(YEAR FROM c.registration_date)                         AS registration_year,
    DATE_DIFF(as_of_date, c.registration_date, DAY)                AS days_since_registration,
    m.first_order_date,
    m.second_order_date,
    m.last_order_date,
    IFNULL(m.valid_orders, 0)                                      AS valid_orders,
    IFNULL(x.cancelled_or_returned_orders, 0)                      AS cancelled_or_returned_orders,
    DATE_DIFF(m.first_order_date,  c.registration_date, DAY)       AS days_to_first_order,
    DATE_DIFF(m.second_order_date, m.first_order_date,  DAY)       AS days_first_to_second,
    ROUND(IFNULL(m.revenue_to_date, 0), 2)                         AS revenue_to_date,
    IF(DATE_DIFF(as_of_date, m.first_order_date, DAY) >= 365,
       ROUND(f.revenue_first_365, 2), NULL)                        AS revenue_first_365,
    CASE
        WHEN m.first_order_date IS NULL AND x.customer_id IS NOT NULL THEN 'Only cancelled or returned orders'
        WHEN m.first_order_date IS NULL                               THEN 'Not yet ordered'
        WHEN m.second_order_date IS NULL                              THEN 'One order only'
        ELSE 'Repeat buyer'
    END                                                            AS activation_stage
FROM `sahyadri_b2b.customers` AS c
LEFT JOIN milestones          AS m ON m.customer_id = c.customer_id
LEFT JOIN first_year          AS f ON f.customer_id = c.customer_id
LEFT JOIN invalid_only        AS x ON x.customer_id = c.customer_id
WHERE c.registration_date BETWEEN new_from AND as_of_date;

-- -----------------------------------------------------------------------------
-- Step 2 · Activation funnel by registration year (fair-window rates)
-- -----------------------------------------------------------------------------
SELECT
    registration_year,
    COUNT(*)                                                         AS registered,
    COUNTIF(first_order_date IS NOT NULL)                            AS placed_first_order,
    COUNTIF(second_order_date IS NOT NULL)                           AS placed_second_order,
    ROUND(100 * COUNTIF(first_order_date IS NOT NULL) / COUNT(*), 1) AS pct_ordered,
    -- first order within 90 days, among customers registered at least 90 days ago
    ROUND(100 * SAFE_DIVIDE(
        COUNTIF(days_since_registration >= fair_days AND days_to_first_order <= fair_days),
        COUNTIF(days_since_registration >= fair_days)), 1)           AS pct_first_order_in_90d,
    -- second order within 90 days of the first, among first orders at least 90 days old
    ROUND(100 * SAFE_DIVIDE(
        COUNTIF(DATE_DIFF(as_of_date, first_order_date, DAY) >= fair_days AND days_first_to_second <= fair_days),
        COUNTIF(DATE_DIFF(as_of_date, first_order_date, DAY) >= fair_days)), 1) AS pct_repeat_in_90d,
    ROUND(SUM(revenue_to_date), 2)                                   AS revenue_to_date
FROM `sahyadri_b2b.new_customer_activation`
GROUP BY ROLLUP(registration_year)
ORDER BY registration_year IS NULL, registration_year;

-- -----------------------------------------------------------------------------
-- Step 3 · Where new customers stand today, and how fast they move, by segment
-- -----------------------------------------------------------------------------
WITH speed AS (
    SELECT DISTINCT
        customer_segment,
        PERCENTILE_CONT(days_to_first_order,  0.5) OVER (PARTITION BY customer_segment) AS median_days_to_first,
        PERCENTILE_CONT(days_first_to_second, 0.5) OVER (PARTITION BY customer_segment) AS median_days_to_second
    FROM `sahyadri_b2b.new_customer_activation`
)
SELECT
    a.customer_segment,
    COUNT(*)                                                        AS registered,
    COUNTIF(a.activation_stage = 'Not yet ordered')                 AS not_yet_ordered,
    COUNTIF(a.activation_stage = 'Only cancelled or returned orders') AS only_cancelled_or_returned,
    COUNTIF(a.activation_stage = 'One order only')                  AS one_order_only,
    COUNTIF(a.activation_stage = 'Repeat buyer')                    AS repeat_buyers,
    ANY_VALUE(s.median_days_to_first)                               AS median_days_to_first_order,
    ANY_VALUE(s.median_days_to_second)                              AS median_days_first_to_second
FROM `sahyadri_b2b.new_customer_activation` AS a
JOIN speed AS s ON s.customer_segment = a.customer_segment
GROUP BY a.customer_segment
ORDER BY registered DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · First-year value of new customers vs established customers
-- -----------------------------------------------------------------------------
WITH established AS (
    SELECT
        c.customer_segment,
        o.customer_id,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue_12m
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.customers`         AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN DATE_SUB(as_of_date, INTERVAL 364 DAY) AND as_of_date
      AND c.registration_date < new_from
    GROUP BY c.customer_segment, o.customer_id
),
established_median AS (
    SELECT DISTINCT
        customer_segment,
        PERCENTILE_CONT(revenue_12m, 0.5) OVER (PARTITION BY customer_segment) AS median_revenue_12m
    FROM established
),
new_median AS (
    SELECT DISTINCT
        customer_segment,
        COUNT(*)                         OVER (PARTITION BY customer_segment)      AS new_customers_measured,
        PERCENTILE_CONT(revenue_first_365, 0.5) OVER (PARTITION BY customer_segment) AS median_first_year_revenue
    FROM `sahyadri_b2b.new_customer_activation`
    WHERE revenue_first_365 IS NOT NULL
)
SELECT
    e.customer_segment,
    n.new_customers_measured,
    ROUND(n.median_first_year_revenue, 0)                              AS new_median_first_year,
    ROUND(e.median_revenue_12m, 0)                                     AS established_median_12m,
    ROUND(100 * n.median_first_year_revenue / e.median_revenue_12m, 0) AS new_as_pct_of_established
FROM established_median AS e
LEFT JOIN new_median    AS n ON n.customer_segment = e.customer_segment
ORDER BY e.customer_segment;

-- -----------------------------------------------------------------------------
-- Step 5 · Follow-up list: stalled new accounts
--          Not yet ordered 30+ days after registering, or one order only and
--          nothing for 90+ days
-- -----------------------------------------------------------------------------
SELECT
    customer_id,
    customer_name,
    customer_segment,
    registration_date,
    activation_stage,
    last_order_date,
    revenue_to_date,
    IF(last_order_date IS NULL,
       days_since_registration,
       DATE_DIFF(as_of_date, last_order_date, DAY))     AS days_inactive
FROM `sahyadri_b2b.new_customer_activation`
WHERE (activation_stage IN ('Not yet ordered', 'Only cancelled or returned orders') AND days_since_registration >= 30)
   OR (activation_stage = 'One order only' AND DATE_DIFF(as_of_date, last_order_date, DAY) >= stall_days)
ORDER BY activation_stage, revenue_to_date DESC, registration_date;
