/* =============================================================================
   Case study · Order-to-cash process mining
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The finance and operations teams describe order-to-cash as one simple
   flow: order -> dispatch -> delivery -> payment. The ERP project team
   is about to configure workflow rules and approval steps on that basis,
   and wants evidence of how orders really move through the system before
   it hard-codes the flow:
     1. Which paths do orders actually take, and how many distinct paths
        (variants) are there?
     2. How much of the volume follows the expected path?
     3. Which paths are slow, and in which step is the time lost?
     4. Which deviations follow a rule (policy) and which are errors?

   METHOD
     - Event log built from the transaction tables, one row per event:
         Order placed      sales_orders.order_date
         Dispatched        shipments.shipment_date        (one per shipment)
         Delivered         shipments.delivery_date        (one per shipment, if dated)
         Payment           payments.payment_date          (one per payment)
       Events on the same day are ordered Order < Dispatch < Delivery <
       Payment (the logical order), so same-day events never count as a
       deviation.
     - Variant = the ordered sequence of activities of an order, plus its
       end state for Cancelled and Returned orders.
     - Directly-follows relations: each event and the next event of the same
       order, with counts and average days between them.
     - Fully paid date = date of the payment that takes cumulative receipts
       to the order value (within Rs 0.05).
     - Path group per order:
         Cancelled / Returned / In progress (Pending, Processing, Shipped)
         Advance payment         first payment before the first dispatch
         Paid during delivery    first payment after dispatch, before the last delivery
         Paid once after delivery
         Paid in instalments after delivery
         Delivered, not fully paid
   ============================================================================= */

DECLARE as_of        DATE    DEFAULT DATE '2026-09-30';
DECLARE paise        FLOAT64 DEFAULT 0.05;

-- -----------------------------------------------------------------------------
-- Step 1 · Event log
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pm_events` AS
WITH raw AS (
              SELECT order_id, order_date    AS event_date, 1 AS activity_rank, 'Order'    AS activity, NULL AS source_id FROM `sahyadri_b2b.sales_orders`
    UNION ALL SELECT order_id, shipment_date,                2,                  'Dispatch',             shipment_id      FROM `sahyadri_b2b.shipments`
    UNION ALL SELECT order_id, delivery_date,                3,                  'Delivery',             shipment_id      FROM `sahyadri_b2b.shipments` WHERE delivery_date IS NOT NULL
    UNION ALL SELECT order_id, payment_date,                 4,                  'Payment',              payment_id       FROM `sahyadri_b2b.payments`
)
SELECT
    r.*,
    ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY event_date, activity_rank, source_id) AS event_no
FROM raw AS r;

-- -----------------------------------------------------------------------------
-- Step 2 · One row per order (case): variant, path group and cycle times
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pm_cases` AS
WITH value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
paid_running AS (
    SELECT p.order_id, p.payment_date,
           SUM(p.amount) OVER (PARTITION BY p.order_id ORDER BY p.payment_date, p.payment_id) AS cum_paid
    FROM `sahyadri_b2b.payments` AS p
),
fully_paid AS (
    SELECT r.order_id, MIN(r.payment_date) AS fully_paid_date
    FROM paid_running AS r
    JOIN value AS v ON v.order_id = r.order_id
    WHERE r.cum_paid >= v.order_value - paise
    GROUP BY r.order_id
),
ev AS (
    SELECT
        order_id,
        STRING_AGG(activity, ' > ' ORDER BY event_no)                     AS activity_path,
        COUNT(*)                                                         AS events,
        COUNTIF(activity = 'Dispatch')                                   AS dispatches,
        COUNTIF(activity = 'Delivery')                                   AS deliveries,
        COUNTIF(activity = 'Payment')                                    AS payments,
        MIN(IF(activity = 'Dispatch', event_date, NULL))                 AS first_dispatch,
        MAX(IF(activity = 'Delivery', event_date, NULL))                 AS last_delivery,
        MIN(IF(activity = 'Payment',  event_date, NULL))                 AS first_payment
    FROM `sahyadri_b2b.pm_events`
    GROUP BY order_id
)
SELECT
    o.order_id, o.customer_id, c.customer_segment, o.order_status, o.payment_status, o.order_date,
    v.order_value,
    CONCAT(e.activity_path,
           CASE o.order_status WHEN 'Cancelled' THEN ' > [Cancelled]'
                               WHEN 'Returned'  THEN ' > [Returned]' ELSE '' END)   AS variant,
    e.events, e.dispatches, e.deliveries, e.payments,
    e.first_dispatch, e.last_delivery, e.first_payment, f.fully_paid_date,
    CASE
        WHEN o.order_status = 'Cancelled'                              THEN '7. Cancelled'
        WHEN o.order_status = 'Returned'                               THEN '8. Returned'
        WHEN o.order_status IN ('Pending', 'Processing', 'Shipped')    THEN '6. In progress'
        WHEN f.fully_paid_date IS NULL                                 THEN '5. Delivered, not fully paid'
        WHEN e.first_payment < e.first_dispatch                        THEN '3. Advance payment'
        WHEN e.first_payment < e.last_delivery                         THEN '4. Paid during delivery'
        WHEN e.payments = 1                                            THEN '1. Paid once after delivery'
        ELSE                                                                '2. Paid in instalments after delivery'
    END                                                                         AS path_group,
    DATE_DIFF(e.first_dispatch, o.order_date, DAY)                              AS days_order_to_dispatch,
    DATE_DIFF(e.last_delivery, e.first_dispatch, DAY)                           AS days_dispatch_to_delivery,
    DATE_DIFF(f.fully_paid_date, e.last_delivery, DAY)                          AS days_delivery_to_cash,
    DATE_DIFF(f.fully_paid_date, o.order_date, DAY)                             AS days_order_to_cash
FROM `sahyadri_b2b.sales_orders` AS o
JOIN ev    AS e ON e.order_id = o.order_id
JOIN value AS v ON v.order_id = o.order_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
LEFT JOIN fully_paid AS f ON f.order_id = o.order_id;

-- -----------------------------------------------------------------------------
-- Step 3 · Variants: how many paths, and how concentrated?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pm_variants` AS
SELECT
    variant,
    COUNT(*)                                                       AS orders,
    SUM(order_value)                                               AS order_value,
    AVG(days_order_to_cash)                                        AS avg_days_order_to_cash,
    RANK() OVER (ORDER BY COUNT(*) DESC, variant)                  AS variant_rank,
    SUM(COUNT(*)) OVER (ORDER BY COUNT(*) DESC, variant) / SUM(COUNT(*)) OVER () AS cumulative_share
FROM `sahyadri_b2b.pm_cases`
GROUP BY variant;

SELECT
    COUNT(*)                                                       AS variants,
    COUNTIF(orders = 1)                                            AS variants_seen_once,
    MIN(IF(cumulative_share >= 0.80, variant_rank, NULL))          AS variants_for_80pct_of_orders,
    MIN(IF(cumulative_share >= 0.95, variant_rank, NULL))          AS variants_for_95pct_of_orders
FROM `sahyadri_b2b.pm_variants`;

SELECT variant_rank, variant, orders, ROUND(100 * cumulative_share, 1) AS cumulative_pct,
       ROUND(avg_days_order_to_cash, 1) AS avg_days_order_to_cash
FROM `sahyadri_b2b.pm_variants`
WHERE variant_rank <= 12
ORDER BY variant_rank;

-- Directly-follows relations (the process map)
WITH pairs AS (
    SELECT a.activity AS from_activity, b.activity AS to_activity, DATE_DIFF(b.event_date, a.event_date, DAY) AS days
    FROM `sahyadri_b2b.pm_events` AS a
    JOIN `sahyadri_b2b.pm_events` AS b ON b.order_id = a.order_id AND b.event_no = a.event_no + 1
)
SELECT from_activity, to_activity, COUNT(*) AS transitions, ROUND(AVG(days), 1) AS avg_days,
       APPROX_QUANTILES(days, 2)[OFFSET(1)] AS median_days
FROM pairs
GROUP BY from_activity, to_activity
ORDER BY transitions DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Path groups: volume and where the time goes
-- -----------------------------------------------------------------------------
SELECT
    path_group,
    COUNT(*)                                                       AS orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS share_pct,
    ROUND(SUM(order_value) / 1e7, 2)                               AS value_crore,
    ROUND(AVG(order_value))                                        AS avg_order_value,
    ROUND(AVG(days_order_to_dispatch), 1)                          AS order_to_dispatch,
    ROUND(AVG(days_dispatch_to_delivery), 1)                       AS dispatch_to_delivery,
    ROUND(AVG(days_delivery_to_cash), 1)                           AS delivery_to_cash,
    ROUND(AVG(days_order_to_cash), 1)                              AS order_to_cash,
    APPROX_QUANTILES(days_order_to_cash, 2)[OFFSET(1)]             AS median_order_to_cash
FROM `sahyadri_b2b.pm_cases`
GROUP BY path_group
ORDER BY path_group;

-- Which customers follow which payment path? (completed orders only)
SELECT
    customer_segment,
    COUNT(*)                                                                                  AS completed_orders,
    ROUND(100 * AVG(IF(path_group = '3. Advance payment', 1, 0)), 1)                           AS advance_payment_pct,
    ROUND(100 * AVG(IF(path_group = '4. Paid during delivery', 1, 0)), 1)                      AS paid_during_delivery_pct,
    ROUND(100 * AVG(IF(path_group = '1. Paid once after delivery', 1, 0)), 1)                  AS paid_once_pct,
    ROUND(100 * AVG(IF(path_group = '2. Paid in instalments after delivery', 1, 0)), 1)        AS instalments_pct,
    ROUND(100 * AVG(IF(path_group = '5. Delivered, not fully paid', 1, 0)), 1)                 AS not_fully_paid_pct
FROM `sahyadri_b2b.pm_cases`
WHERE path_group IN ('1. Paid once after delivery', '2. Paid in instalments after delivery', '3. Advance payment',
                     '4. Paid during delivery', '5. Delivered, not fully paid')
GROUP BY customer_segment
ORDER BY customer_segment;

-- Instalments: how much later does the cash arrive?
SELECT
    payments,
    COUNT(*)                                                       AS fully_paid_orders,
    ROUND(AVG(order_value))                                        AS avg_order_value,
    ROUND(AVG(days_delivery_to_cash), 1)                           AS avg_delivery_to_cash,
    ROUND(SUM(order_value * days_delivery_to_cash) / SUM(order_value), 1) AS value_weighted_delivery_to_cash
FROM `sahyadri_b2b.pm_cases`
WHERE path_group IN ('1. Paid once after delivery', '2. Paid in instalments after delivery')
GROUP BY payments
ORDER BY payments;

-- -----------------------------------------------------------------------------
-- Step 5 · Conformance: deviations from the expected flow
-- -----------------------------------------------------------------------------
SELECT '1. Dispatched before the order date' AS deviation, 'Error' AS kind, COUNT(*) AS orders
FROM `sahyadri_b2b.pm_cases` WHERE first_dispatch < order_date
UNION ALL
SELECT '2. Delivered status, no shipment record', 'Error', COUNT(*)
FROM `sahyadri_b2b.pm_cases` WHERE order_status = 'Delivered' AND dispatches = 0
UNION ALL
SELECT '3. Delivered status, a shipment without a delivery date', 'Error', COUNT(*)
FROM `sahyadri_b2b.pm_cases` WHERE order_status = 'Delivered' AND dispatches > deliveries
UNION ALL
SELECT '4. Shipped status, every shipment already delivered', 'Error (status not updated)', COUNT(*)
FROM `sahyadri_b2b.pm_cases` WHERE order_status = 'Shipped' AND dispatches > 0 AND dispatches = deliveries
UNION ALL
SELECT '5. Cancelled, but payments received', 'Follow-up (refund or re-use)', COUNT(*)
FROM `sahyadri_b2b.pm_cases` WHERE order_status = 'Cancelled' AND payments > 0
UNION ALL
SELECT '6. Payment before dispatch (advance)', 'Policy', COUNT(*)
FROM `sahyadri_b2b.pm_cases` WHERE first_payment < first_dispatch
UNION ALL
SELECT '7. Payment while goods in transit', 'Policy or timing', COUNT(*)
FROM `sahyadri_b2b.pm_cases` WHERE first_payment >= first_dispatch AND first_payment < last_delivery
UNION ALL
SELECT '8. Second dispatch after the first delivery', 'Process (back-order)', COUNT(*)
FROM `sahyadri_b2b.pm_cases` WHERE STRPOS(variant, 'Delivery > Dispatch') > 0
UNION ALL
SELECT '9. Delivered over 90 days ago, not fully paid', 'Collections', COUNT(*)
FROM `sahyadri_b2b.pm_cases` WHERE path_group = '5. Delivered, not fully paid' AND DATE_DIFF(as_of, last_delivery, DAY) > 90
ORDER BY deviation;

-- Conformance summary: share of orders on the expected path
SELECT
    COUNT(*)                                                                         AS orders,
    COUNTIF(path_group IN ('1. Paid once after delivery', '2. Paid in instalments after delivery')
            AND first_dispatch >= order_date)                                        AS completed_on_expected_path,
    ROUND(100 * COUNTIF(path_group IN ('1. Paid once after delivery', '2. Paid in instalments after delivery')
            AND first_dispatch >= order_date) / COUNT(*), 1)                         AS expected_path_pct,
    ROUND(100 * COUNTIF(variant = 'Order > Dispatch > Delivery > Payment') / COUNT(*), 1) AS single_textbook_variant_pct
FROM `sahyadri_b2b.pm_cases`;
