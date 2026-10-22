/* =============================================================================
   Case study · Cancellation and return leakage
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   About one order in eighteen is cancelled or returned. Each one wastes
   order-processing, picking, freight and sometimes stock. The operations head
   wants to know:
     1. How much order value and gross profit is lost, and is it getting worse?
     2. Is the loss concentrated in particular customers, segments, industries,
        product categories, salespeople, order sizes or promise windows, or is
        it spread evenly?
     3. Are returns caused by late or split deliveries?
     4. Which customers cancel repeatedly, and where has cash been received on
        cancelled orders?

   KEY RULES
     - Closed orders only: Delivered, Cancelled or Returned. Open orders
       (Pending, Processing, Shipped) could still change, so they are excluded.
     - Order value: quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100).
     - Gross profit: order value - quantity * unit_cost (lines with no unit
       cost contribute no cost).
     - Significance: a group's rate is compared with the company rate using a
       z-score, z = (rate - p) / SQRT(p * (1 - p) / n). |z| >= 2 is flagged.
       Because many groups are tested, about 5 % would be flagged by chance
       alone; the screen reports that expected number alongside the actual one.
     - Groups with fewer than 20 closed orders are not tested.
     - Late: final delivery date after the promised date.
   ============================================================================= */

DECLARE period_start DATE    DEFAULT DATE '2024-01-01';
DECLARE as_of_date   DATE    DEFAULT DATE '2026-09-30';
DECLARE min_orders   INT64   DEFAULT 20;
DECLARE z_flag       FLOAT64 DEFAULT 2.0;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per closed order with outcome, value and delivery facts
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.order_outcomes` AS
WITH order_value AS (
    SELECT
        i.order_id,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))  AS order_value,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)
            - i.quantity * IFNULL(p.unit_cost, 0))                                   AS gross_profit,
        COUNT(*)                                                                     AS lines
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    GROUP BY i.order_id
),
shipping AS (
    SELECT
        order_id,
        COUNT(*)                  AS shipments,
        MAX(delivery_date)        AS final_delivery_date,
        SUM(IFNULL(shipping_cost, 0)) AS freight_cost
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
paid AS (
    SELECT order_id, SUM(amount) AS amount_paid
    FROM `sahyadri_b2b.payments`
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    c.customer_segment,
    IFNULL(c.industry, 'Not recorded')                              AS industry,
    o.employee_id,
    o.order_date,
    EXTRACT(YEAR FROM o.order_date)                                 AS order_year,
    o.order_status                                                  AS outcome,
    v.order_value,
    v.gross_profit,
    v.lines,
    CASE
        WHEN v.order_value <  10000  THEN '1. Under 10k'
        WHEN v.order_value <  50000  THEN '2. 10k-50k'
        WHEN v.order_value < 200000  THEN '3. 50k-2 lakh'
        ELSE                              '4. 2 lakh and above'
    END                                                             AS size_band,
    CASE
        WHEN o.promised_delivery_date IS NULL                              THEN '4. No promise date'
        WHEN DATE_DIFF(o.promised_delivery_date, o.order_date, DAY) <= 7   THEN '1. Up to 7 days'
        WHEN DATE_DIFF(o.promised_delivery_date, o.order_date, DAY) <= 14  THEN '2. 8-14 days'
        ELSE                                                                    '3. Over 14 days'
    END                                                             AS promise_band,
    IFNULL(s.shipments, 0)                                          AS shipments,
    s.final_delivery_date,
    IF(s.final_delivery_date IS NULL OR o.promised_delivery_date IS NULL, NULL,
       s.final_delivery_date > o.promised_delivery_date)            AS was_late,
    IFNULL(s.freight_cost, 0)                                       AS freight_cost,
    IFNULL(p.amount_paid, 0)                                        AS amount_paid
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.customers`    AS c ON c.customer_id = o.customer_id
JOIN order_value                 AS v ON v.order_id    = o.order_id
LEFT JOIN shipping               AS s ON s.order_id    = o.order_id
LEFT JOIN paid                   AS p ON p.order_id    = o.order_id
WHERE o.order_status IN ('Delivered', 'Cancelled', 'Returned')
  AND o.order_date BETWEEN period_start AND as_of_date;

-- -----------------------------------------------------------------------------
-- Step 2 · Leakage by year
-- -----------------------------------------------------------------------------
SELECT
    CAST(order_year AS STRING)                                             AS order_year,
    COUNT(*)                                                               AS closed_orders,
    COUNTIF(outcome = 'Cancelled')                                         AS cancelled,
    ROUND(100 * COUNTIF(outcome = 'Cancelled') / COUNT(*), 2)              AS cancel_rate_pct,
    COUNTIF(outcome = 'Returned')                                          AS returned,
    ROUND(100 * COUNTIF(outcome = 'Returned') / COUNT(*), 2)               AS return_rate_pct,
    ROUND(SUM(IF(outcome = 'Cancelled', order_value, 0)), 2)               AS cancelled_value,
    ROUND(SUM(IF(outcome = 'Returned',  order_value, 0)), 2)               AS returned_value,
    ROUND(100 * SUM(IF(outcome <> 'Delivered', order_value, 0)) / SUM(order_value), 2) AS pct_of_value_lost,
    ROUND(SUM(IF(outcome <> 'Delivered', gross_profit, 0)), 2)             AS gross_profit_lost,
    ROUND(SUM(IF(outcome = 'Returned', freight_cost, 0)), 2)               AS outbound_freight_on_returns
FROM `sahyadri_b2b.order_outcomes`
GROUP BY ROLLUP(order_year)
ORDER BY order_year IS NULL, order_year;

-- -----------------------------------------------------------------------------
-- Step 3 · Driver screen: is the cancellation rate higher in any group than
--          chance would explain?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cancellation_driver_screen` AS
WITH company AS (
    SELECT COUNTIF(outcome = 'Cancelled') / COUNT(*) AS p
    FROM `sahyadri_b2b.order_outcomes`
),
order_category AS (
    SELECT DISTINCT i.order_id, pc.category_name
    FROM `sahyadri_b2b.sales_order_items`  AS i
    JOIN `sahyadri_b2b.products`           AS p  ON p.product_id   = i.product_id
    JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
),
groups AS (
    SELECT 'Customer segment' AS dimension, customer_segment AS group_value, outcome FROM `sahyadri_b2b.order_outcomes`
    UNION ALL
    SELECT 'Industry', industry, outcome FROM `sahyadri_b2b.order_outcomes`
    UNION ALL
    SELECT 'Salesperson', IFNULL(CAST(employee_id AS STRING), 'Not recorded'), outcome FROM `sahyadri_b2b.order_outcomes`
    UNION ALL
    SELECT 'Order size', size_band, outcome FROM `sahyadri_b2b.order_outcomes`
    UNION ALL
    SELECT 'Promise window', promise_band, outcome FROM `sahyadri_b2b.order_outcomes`
    UNION ALL
    SELECT 'Order month', FORMAT('%02d', EXTRACT(MONTH FROM order_date)), outcome FROM `sahyadri_b2b.order_outcomes`
    UNION ALL
    SELECT 'Product category', oc.category_name, o.outcome
    FROM `sahyadri_b2b.order_outcomes` AS o
    JOIN order_category                AS oc ON oc.order_id = o.order_id
    UNION ALL
    SELECT 'Customer', CAST(customer_id AS STRING), outcome FROM `sahyadri_b2b.order_outcomes`
)
SELECT
    g.dimension,
    g.group_value,
    COUNT(*)                                                         AS closed_orders,
    COUNTIF(g.outcome = 'Cancelled')                                 AS cancelled,
    ROUND(100 * COUNTIF(g.outcome = 'Cancelled') / COUNT(*), 2)      AS cancel_rate_pct,
    ROUND((COUNTIF(g.outcome = 'Cancelled') / COUNT(*) - ANY_VALUE(c.p))
          / SQRT(ANY_VALUE(c.p) * (1 - ANY_VALUE(c.p)) / COUNT(*)), 2) AS z_score
FROM groups       AS g
CROSS JOIN company AS c
GROUP BY g.dimension, g.group_value
HAVING COUNT(*) >= min_orders;

-- Summary: groups flagged vs the number expected by chance
SELECT
    dimension,
    COUNT(*)                                          AS groups_tested,
    COUNTIF(ABS(z_score) >= z_flag)                   AS groups_flagged,
    ROUND(COUNT(*) * 0.0455, 1)                       AS expected_by_chance,
    COUNTIF(z_score >=  z_flag)                       AS flagged_high,
    COUNTIF(z_score <= -z_flag)                       AS flagged_low,
    MIN(cancel_rate_pct)                              AS lowest_rate_pct,
    MAX(cancel_rate_pct)                              AS highest_rate_pct
FROM `sahyadri_b2b.cancellation_driver_screen`
GROUP BY dimension
ORDER BY dimension;

-- Flagged groups other than individual customers
SELECT dimension, group_value, closed_orders, cancelled, cancel_rate_pct, z_score
FROM `sahyadri_b2b.cancellation_driver_screen`
WHERE ABS(z_score) >= z_flag AND dimension <> 'Customer'
ORDER BY z_score DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Returns vs delivery experience: were returned orders late or split?
-- -----------------------------------------------------------------------------
WITH shipped AS (
    SELECT outcome, was_late, shipments
    FROM `sahyadri_b2b.order_outcomes`
    WHERE outcome IN ('Delivered', 'Returned') AND was_late IS NOT NULL
),
stats AS (
    SELECT
        COUNTIF(outcome = 'Returned')                       AS n_returned,
        COUNTIF(outcome = 'Delivered')                      AS n_delivered,
        COUNTIF(outcome = 'Returned'  AND was_late)         AS late_returned,
        COUNTIF(outcome = 'Delivered' AND was_late)         AS late_delivered,
        COUNTIF(outcome = 'Returned'  AND shipments > 1)    AS split_returned,
        COUNTIF(outcome = 'Delivered' AND shipments > 1)    AS split_delivered
    FROM shipped
)
SELECT
    n_returned,
    n_delivered,
    ROUND(100 * late_returned  / n_returned,  1)        AS late_rate_returned_pct,
    ROUND(100 * late_delivered / n_delivered, 1)        AS late_rate_delivered_pct,
    -- two-proportion z-test with a pooled rate
    ROUND((late_returned / n_returned - late_delivered / n_delivered)
          / SQRT((late_returned + late_delivered) / (n_returned + n_delivered)
                 * (1 - (late_returned + late_delivered) / (n_returned + n_delivered))
                 * (1 / n_returned + 1 / n_delivered)), 2) AS z_late,
    ROUND(100 * split_returned  / n_returned,  1)       AS split_rate_returned_pct,
    ROUND(100 * split_delivered / n_delivered, 1)       AS split_rate_delivered_pct,
    ROUND((split_returned / n_returned - split_delivered / n_delivered)
          / SQRT((split_returned + split_delivered) / (n_returned + n_delivered)
                 * (1 - (split_returned + split_delivered) / (n_returned + n_delivered))
                 * (1 / n_returned + 1 / n_delivered)), 2) AS z_split
FROM stats;

-- -----------------------------------------------------------------------------
-- Step 5 · Follow-up lists
-- -----------------------------------------------------------------------------
-- 5a. Customers who cancel significantly more often than the company rate
SELECT
    d.group_value                                         AS customer_id,
    c.customer_name,
    c.customer_segment,
    d.closed_orders,
    d.cancelled,
    d.cancel_rate_pct,
    d.z_score,
    ROUND(SUM(IF(o.outcome = 'Cancelled', o.order_value, 0)), 2) AS cancelled_value
FROM `sahyadri_b2b.cancellation_driver_screen` AS d
JOIN `sahyadri_b2b.customers`      AS c ON CAST(c.customer_id AS STRING) = d.group_value
JOIN `sahyadri_b2b.order_outcomes` AS o ON o.customer_id = c.customer_id
WHERE d.dimension = 'Customer' AND d.z_score >= z_flag
GROUP BY d.group_value, c.customer_name, c.customer_segment, d.closed_orders, d.cancelled, d.cancel_rate_pct, d.z_score
ORDER BY d.z_score DESC;

-- 5b. Cancelled or returned orders on which cash has been received (refund or credit due)
SELECT
    o.order_id,
    o.customer_id,
    o.outcome,
    o.order_date,
    ROUND(o.order_value, 2)  AS order_value,
    ROUND(o.amount_paid, 2)  AS amount_paid
FROM `sahyadri_b2b.order_outcomes` AS o
WHERE o.outcome IN ('Cancelled', 'Returned') AND o.amount_paid > 0
ORDER BY o.amount_paid DESC;
