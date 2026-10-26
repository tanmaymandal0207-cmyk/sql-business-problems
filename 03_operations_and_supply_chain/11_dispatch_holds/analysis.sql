/* =============================================================================
   Case study · Dispatch holds
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Most orders leave the warehouse within a few days, but some wait one to
   three weeks before the first shipment. Sales believes finance is holding
   orders from customers with overdue invoices; finance believes the
   warehouse is holding orders for stock. Nobody records why an order waits.
   The operations director wants evidence before changing the process:
     1. How many orders are held, and for how long?
     2. Are holds targeted (overdue customers, large orders, particular
        products, salespeople or customers), or do they fall at random?
     3. How much lateness do held orders cause?
     4. Are there dispatch records that cannot be right?

   KEY RULES
     - Dispatch days = first shipment date - order date (shipped orders).
     - Held order: 7 or more dispatch days. The distribution has two parts:
       a normal process of 0-5 days and a flat tail of 6-22 days (Step 1).
       7 days is used so that the normal process's own tail is excluded.
     - Overdue customer at order date: the customer had a delivered order,
       delivered more than 60 days before this order date, that was not fully
       paid by this order date (payments dated on or before it).
     - Groups are compared with a two-proportion z-score against all other
       orders; |z| >= 3 is flagged because many groups are tested.
     - Late = final delivery after the promised date (orders with a delivery
       date on every shipment and a promised date).
   ============================================================================= */

DECLARE hold_days    INT64 DEFAULT 7;
DECLARE overdue_days INT64 DEFAULT 60;

-- -----------------------------------------------------------------------------
-- Step 1 · Dispatch days for every shipped order, and the distribution
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dispatch_holds` AS
WITH ship AS (
    SELECT
        order_id,
        MIN(shipment_date)                                               AS first_shipment_date,
        COUNT(*)                                                         AS shipments,
        IF(COUNT(delivery_date) = COUNT(*), MAX(delivery_date), NULL)    AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
order_value AS (
    SELECT
        order_id,
        COUNT(*)                                                                   AS order_lines,
        SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))       AS order_revenue
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
paid_to_date AS (
    -- for each order and each later order of the same customer: was the
    -- earlier order fully paid by the later order's date?
    SELECT
        later.order_id,
        COUNTIF(earlier_value.order_revenue - IFNULL(p.paid_by_then, 0) > 0.05)    AS overdue_orders
    FROM `sahyadri_b2b.sales_orders` AS later
    JOIN `sahyadri_b2b.sales_orders` AS earlier
      ON earlier.customer_id = later.customer_id
     AND earlier.order_status = 'Delivered'
    JOIN ship AS earlier_ship
      ON earlier_ship.order_id = earlier.order_id
     AND earlier_ship.final_delivery_date < DATE_SUB(later.order_date, INTERVAL overdue_days DAY)
    JOIN order_value AS earlier_value ON earlier_value.order_id = earlier.order_id
    LEFT JOIN (
        SELECT pa.order_id, lo.order_id AS later_order_id, SUM(pa.amount) AS paid_by_then
        FROM `sahyadri_b2b.payments`     AS pa
        JOIN `sahyadri_b2b.sales_orders` AS eo ON eo.order_id = pa.order_id
        JOIN `sahyadri_b2b.sales_orders` AS lo ON lo.customer_id = eo.customer_id AND pa.payment_date <= lo.order_date
        GROUP BY pa.order_id, lo.order_id
    ) AS p
      ON p.order_id = earlier.order_id AND p.later_order_id = later.order_id
    GROUP BY later.order_id
)
SELECT
    o.order_id,
    o.customer_id,
    o.employee_id,
    o.order_date,
    o.promised_delivery_date,
    o.order_status,
    c.customer_segment,
    v.order_lines,
    v.order_revenue,
    s.shipments,
    s.first_shipment_date,
    s.final_delivery_date,
    DATE_DIFF(s.first_shipment_date, o.order_date, DAY)                       AS dispatch_days,
    DATE_DIFF(s.first_shipment_date, o.order_date, DAY) >= hold_days          AS is_held,
    IFNULL(pt.overdue_orders, 0) > 0                                          AS customer_overdue_at_order,
    s.final_delivery_date > o.promised_delivery_date                          AS is_late
FROM `sahyadri_b2b.sales_orders` AS o
JOIN ship        AS s ON s.order_id = o.order_id
JOIN order_value AS v ON v.order_id = o.order_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
LEFT JOIN paid_to_date AS pt ON pt.order_id = o.order_id;

SELECT
    CASE WHEN dispatch_days < 0  THEN 'a. Negative (shipped before ordered)'
         WHEN dispatch_days <= 5 THEN CONCAT('b. ', CAST(dispatch_days AS STRING), ' days')
         WHEN dispatch_days = 6  THEN 'c. 6 days'
         WHEN dispatch_days <= 10 THEN 'd. 7-10 days'
         WHEN dispatch_days <= 14 THEN 'e. 11-14 days'
         WHEN dispatch_days <= 18 THEN 'f. 15-18 days'
         ELSE 'g. 19-22 days' END                                             AS dispatch_band,
    COUNT(*)                                                                  AS orders,
    ROUND(COUNT(*) / COUNT(DISTINCT dispatch_days), 1)                        AS orders_per_day_value,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                          AS orders_pct
FROM `sahyadri_b2b.dispatch_holds`
GROUP BY dispatch_band
ORDER BY dispatch_band;

SELECT
    COUNT(*)                                                                  AS shipped_orders,
    COUNTIF(is_held)                                                          AS held_orders,
    ROUND(100 * AVG(IF(is_held, 1, 0)), 1)                                    AS held_pct,
    APPROX_QUANTILES(IF(is_held, dispatch_days, NULL), 2)[OFFSET(1)]          AS median_days_held,
    APPROX_QUANTILES(IF(NOT is_held AND dispatch_days >= 0, dispatch_days, NULL), 2)[OFFSET(1)] AS median_days_normal,
    ROUND(SUM(IF(is_held, order_revenue, 0)) / 1e7, 2)                        AS held_revenue_crore
FROM `sahyadri_b2b.dispatch_holds`;

-- -----------------------------------------------------------------------------
-- Step 2 · Are holds targeted? Hold rate by group, with z-scores
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dispatch_hold_groups` AS
WITH tagged AS (
    SELECT 'Customer overdue at order' AS dimension,
           IF(customer_overdue_at_order, 'Overdue', 'Not overdue') AS group_value, is_held
    FROM `sahyadri_b2b.dispatch_holds`
    UNION ALL
    SELECT 'Segment', customer_segment, is_held FROM `sahyadri_b2b.dispatch_holds`
    UNION ALL
    SELECT 'Order value',
           CASE WHEN order_revenue < 25000  THEN '1. Under Rs 25k'
                WHEN order_revenue < 100000 THEN '2. Rs 25k-1 lakh'
                WHEN order_revenue < 300000 THEN '3. Rs 1-3 lakh'
                ELSE '4. Rs 3 lakh+' END, is_held
    FROM `sahyadri_b2b.dispatch_holds`
    UNION ALL
    SELECT 'Order lines', IF(order_lines >= 6, '6+', CAST(order_lines AS STRING)), is_held
    FROM `sahyadri_b2b.dispatch_holds`
    UNION ALL
    SELECT 'Salesperson', IFNULL(CAST(employee_id AS STRING), 'None'), is_held
    FROM `sahyadri_b2b.dispatch_holds`
    UNION ALL
    SELECT 'Order month', FORMAT_DATE('%m', order_date), is_held
    FROM `sahyadri_b2b.dispatch_holds`
    UNION ALL
    SELECT 'Order weekday', FORMAT_DATE('%u %a', order_date), is_held
    FROM `sahyadri_b2b.dispatch_holds`
    UNION ALL
    SELECT 'Order year', FORMAT_DATE('%Y', order_date), is_held
    FROM `sahyadri_b2b.dispatch_holds`
),
grouped AS (
    SELECT dimension, group_value, COUNT(*) AS orders, COUNTIF(is_held) AS held
    FROM tagged
    GROUP BY dimension, group_value
),
with_rest AS (
    SELECT
        g.*,
        SUM(orders) OVER (PARTITION BY dimension) - orders                      AS rest_orders,
        SUM(held)   OVER (PARTITION BY dimension) - held                        AS rest_held
    FROM grouped AS g
)
SELECT
    dimension,
    group_value,
    orders,
    held,
    held / orders                                                             AS hold_rate,
    rest_held / rest_orders                                                   AS rest_hold_rate,
    (held / orders - rest_held / rest_orders)
      / SQRT(((held + rest_held) / (orders + rest_orders))
             * (1 - (held + rest_held) / (orders + rest_orders))
             * (1 / orders + 1 / rest_orders))                                AS z_score
FROM with_rest;

SELECT
    dimension,
    COUNT(*)                                                                  AS groups,
    ROUND(100 * MIN(hold_rate), 1)                                            AS lowest_hold_pct,
    ROUND(100 * MAX(hold_rate), 1)                                            AS highest_hold_pct,
    ROUND(MAX(ABS(z_score)), 2)                                               AS largest_abs_z,
    COUNTIF(ABS(z_score) >= 3)                                                AS groups_abs_z_3
FROM `sahyadri_b2b.dispatch_hold_groups`
GROUP BY dimension
ORDER BY largest_abs_z DESC;

SELECT dimension, group_value, orders, held,
       ROUND(100 * hold_rate, 1) AS hold_pct, ROUND(100 * rest_hold_rate, 1) AS rest_pct, ROUND(z_score, 2) AS z_score
FROM `sahyadri_b2b.dispatch_hold_groups`
WHERE dimension IN ('Customer overdue at order', 'Order value', 'Segment')
ORDER BY dimension, group_value;

-- Customer level: do some customers get held far more than chance allows?
-- Over-dispersion ratio = observed variance of customer hold rates / binomial variance
WITH by_customer AS (
    SELECT customer_id, COUNT(*) AS n, AVG(IF(is_held, 1, 0)) AS rate
    FROM `sahyadri_b2b.dispatch_holds`
    GROUP BY customer_id
    HAVING COUNT(*) >= 20
),
overall AS (
    SELECT AVG(IF(is_held, 1, 0)) AS p FROM `sahyadri_b2b.dispatch_holds`
)
SELECT
    COUNT(*)                                                                  AS customers_20_plus_orders,
    ROUND(100 * MIN(rate), 1)                                                 AS lowest_customer_hold_pct,
    ROUND(100 * MAX(rate), 1)                                                 AS highest_customer_hold_pct,
    ROUND(SUM(POW(rate - o.p, 2) * n) / SUM(o.p * (1 - o.p)), 2)             AS overdispersion_ratio,
    COUNTIF(ABS(rate - o.p) / SQRT(o.p * (1 - o.p) / n) >= 3)                 AS customers_abs_z_3
FROM by_customer
CROSS JOIN overall AS o;

-- -----------------------------------------------------------------------------
-- Step 3 · How much lateness do holds cause?
-- -----------------------------------------------------------------------------
WITH measured AS (
    SELECT * FROM `sahyadri_b2b.dispatch_holds`
    WHERE final_delivery_date IS NOT NULL AND promised_delivery_date IS NOT NULL
      AND order_status = 'Delivered' AND dispatch_days >= 0
),
normal_rate AS (
    SELECT AVG(IF(is_late, 1, 0)) AS rate FROM measured WHERE NOT is_held
)
SELECT
    IF(is_held, 'Held 7+ days', 'Dispatched within 6 days')                  AS dispatch,
    COUNT(*)                                                                  AS orders_measured,
    ROUND(100 * AVG(IF(is_late, 1, 0)), 1)                                    AS late_pct,
    COUNTIF(is_late)                                                          AS late_orders,
    ROUND(100 * COUNTIF(is_late) / SUM(COUNTIF(is_late)) OVER (), 1)          AS share_of_late_orders,
    ROUND(AVG(DATE_DIFF(final_delivery_date, order_date, DAY)), 1)            AS avg_days_to_delivery,
    ROUND(AVG(DATE_DIFF(promised_delivery_date, order_date, DAY)), 1)         AS avg_days_promised
FROM measured
GROUP BY dispatch
UNION ALL
SELECT
    'All, if held orders were late at the normal rate',
    COUNT(*),
    ROUND(100 * (COUNTIF(is_late AND NOT is_held) + COUNTIF(is_held) * ANY_VALUE(r.rate)) / COUNT(*), 1),
    CAST(ROUND(COUNTIF(is_late AND NOT is_held) + COUNTIF(is_held) * ANY_VALUE(r.rate)) AS INT64),
    NULL, NULL, NULL
FROM measured
CROSS JOIN normal_rate AS r
UNION ALL
SELECT 'All, actual', COUNT(*), ROUND(100 * AVG(IF(is_late, 1, 0)), 1), COUNTIF(is_late), NULL, NULL, NULL
FROM measured
ORDER BY dispatch;

-- -----------------------------------------------------------------------------
-- Step 4 · Records that cannot be right: shipped before the order date
-- -----------------------------------------------------------------------------
SELECT
    order_id,
    customer_id,
    order_date,
    first_shipment_date,
    dispatch_days,
    order_status,
    ROUND(order_revenue, 0)                                                   AS order_revenue
FROM `sahyadri_b2b.dispatch_holds`
WHERE dispatch_days < 0
ORDER BY dispatch_days;
