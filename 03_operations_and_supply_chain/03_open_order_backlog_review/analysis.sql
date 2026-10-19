/* =============================================================================
   Case study · Open order backlog review
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   At every month-end the operations manager reviews orders that are still
   open (Pending, Processing or Shipped). The open-order list is meant to show
   work in progress, but nobody checks whether it is accurate. Before the
   September close, operations wants to know:
     1. How many orders, and how much value, are open at month-end?
     2. Which open orders are healthy, and which need action: overdue for
        dispatch, past the promised date, stuck in transit, or actually
        delivered but never closed?
     3. How much money has already been received against orders that the
        customer has not yet received?

   KEY RULES
     - As-of date: 30 Sep 2026 (last transaction date in the dataset).
     - Open order = order_status Pending, Processing or Shipped.
     - Order value = SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)).
     - Stuck in transit = a shipment still In Transit more than `stuck_days`
       (30) after it left. For context: 90 % of delivered shipments arrive
       within 8 days (see the late delivery case study).
     - Each open order gets one review status, in this order of priority:
         1. Delivered - status not updated   (Shipped, every shipment delivered)
         2. Stuck in transit                 (a shipment in transit > 30 days)
         3. Overdue - not yet dispatched     (Pending/Processing, promise date passed)
         4. Overdue - in transit             (Shipped, promise date passed)
         5. No promised date
         6. On track
   ============================================================================= */

DECLARE as_of_date DATE  DEFAULT DATE '2026-09-30';
DECLARE stuck_days INT64 DEFAULT 30;

-- -----------------------------------------------------------------------------
-- Step 1 · Open order review table
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.open_order_review` AS
WITH order_value AS (
    SELECT order_id,
           SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),

shipment_summary AS (
    SELECT
        order_id,
        COUNT(*)                                       AS shipments,
        COUNTIF(shipment_status = 'In Transit')        AS shipments_in_transit,
        COUNTIF(shipment_status = 'Delivered')         AS shipments_delivered,
        MAX(shipment_date)                             AS last_shipment_date,
        MIN(IF(shipment_status = 'In Transit', shipment_date, NULL)) AS oldest_in_transit_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),

payment_summary AS (
    SELECT order_id, SUM(amount) AS amount_paid
    FROM `sahyadri_b2b.payments`
    GROUP BY order_id
),

base AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.employee_id,
        o.order_status,
        o.payment_status,
        o.order_date,
        o.promised_delivery_date,
        ROUND(v.order_value, 2)                                          AS order_value,
        ROUND(IFNULL(p.amount_paid, 0), 2)                               AS amount_paid,
        IFNULL(s.shipments, 0)                                           AS shipments,
        IFNULL(s.shipments_in_transit, 0)                                AS shipments_in_transit,
        IFNULL(s.shipments_delivered, 0)                                 AS shipments_delivered,
        s.last_shipment_date,
        DATE_DIFF(as_of_date, o.order_date, DAY)                         AS days_open,
        DATE_DIFF(as_of_date, s.oldest_in_transit_date, DAY)             AS days_in_transit,
        DATE_DIFF(as_of_date, o.promised_delivery_date, DAY)             AS days_past_promise
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN order_value                 AS v ON v.order_id = o.order_id
    LEFT JOIN shipment_summary       AS s ON s.order_id = o.order_id
    LEFT JOIN payment_summary        AS p ON p.order_id = o.order_id
    WHERE o.order_status IN ('Pending', 'Processing', 'Shipped')
)

SELECT
    *,
    CASE
        WHEN order_status = 'Shipped' AND shipments > 0
         AND shipments_delivered = shipments                     THEN '1. Delivered - status not updated'
        WHEN days_in_transit > stuck_days                        THEN '2. Stuck in transit'
        WHEN order_status IN ('Pending', 'Processing')
         AND days_past_promise > 0                               THEN '3. Overdue - not yet dispatched'
        WHEN order_status = 'Shipped' AND days_past_promise > 0  THEN '4. Overdue - in transit'
        WHEN promised_delivery_date IS NULL                      THEN '5. No promised date'
        ELSE                                                          '6. On track'
    END AS review_status
FROM base;

-- -----------------------------------------------------------------------------
-- Step 2 · Backlog summary by review status
-- -----------------------------------------------------------------------------
SELECT
    review_status,
    COUNT(*)                                                    AS orders,
    ROUND(SUM(order_value), 2)                                  AS order_value,
    ROUND(100 * SUM(order_value) / SUM(SUM(order_value)) OVER (), 1) AS pct_of_open_value,
    ROUND(SUM(amount_paid), 2)                                  AS amount_already_paid,
    MAX(days_open)                                              AS oldest_days_open
FROM `sahyadri_b2b.open_order_review`
GROUP BY review_status
ORDER BY review_status;

-- -----------------------------------------------------------------------------
-- Step 3 · Review status by recorded order status (cross-check)
-- -----------------------------------------------------------------------------
SELECT
    order_status,
    COUNTIF(review_status LIKE '1.%') AS delivered_not_updated,
    COUNTIF(review_status LIKE '2.%') AS stuck_in_transit,
    COUNTIF(review_status LIKE '3.%') AS overdue_not_dispatched,
    COUNTIF(review_status LIKE '4.%') AS overdue_in_transit,
    COUNTIF(review_status LIKE '5.%') AS no_promised_date,
    COUNTIF(review_status LIKE '6.%') AS on_track,
    COUNT(*)                          AS total_orders
FROM `sahyadri_b2b.open_order_review`
GROUP BY order_status
ORDER BY order_status;

-- -----------------------------------------------------------------------------
-- Step 4 · Action list: every open order that needs attention
-- -----------------------------------------------------------------------------
SELECT
    review_status,
    order_id,
    customer_id,
    employee_id,
    order_status,
    order_date,
    promised_delivery_date,
    days_open,
    days_in_transit,
    GREATEST(IFNULL(days_past_promise, 0), 0)   AS days_past_promise,
    order_value,
    amount_paid,
    payment_status
FROM `sahyadri_b2b.open_order_review`
WHERE review_status NOT LIKE '6.%'
ORDER BY review_status, days_open DESC;
