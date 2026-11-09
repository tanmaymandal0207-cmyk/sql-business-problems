/* =============================================================================
   Case study · Liquidated damages: what a standard delay-penalty clause
   would cost on our late deliveries, and how much promise buffer avoids it
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Large buyers, public-sector units in particular, are moving their
   purchase orders onto standard terms with a liquidated damages (LD)
   clause: 0.5 % of the value of the delayed supply for each week or part
   of a week of delay, up to 10 % of the order value. Sales wants to bid
   for that business, and two enterprise customers have asked to add the
   clause at renewal. Before agreeing, the COO asks:
     1. What would the clause have cost on our actual deliveries, for all
        customers and for enterprise customers only?
     2. Is any customer already deducting delay penalties from payments?
     3. Which customers and lanes would generate the deductions?
     4. How many days of buffer on the promised date would remove most of
        the exposure, and what does that do to the promises we quote?

   CLAUSE APPLIED (as written in published public-sector purchase terms; see the README)
     - 0.5 % of the value of the delayed portion of supply, per week or
       part of a week of delay.
     - Capped at 10 % of the total order value.
     - Value includes taxes and freight; GST at 18 % is added here.

   METHOD AND ASSUMPTIONS
     - Orders: Delivered orders with a promised date and every shipment
       delivered, last delivery 1 January 2024 - 30 September 2026.
     - Delayed portion: each shipment delivered after the promised date;
       shipment value = order value / shipments of the order (as in the
       e-way bill study) x 1.18.
     - Weeks of delay = CEIL(days late / 7) for each late shipment.
     - LD per order = MIN(sum over late shipments of 0.5 % x value x weeks,
       10 % x order value x 1.18).
     - Short payment test: an order paid more than Re 1 below its value,
       for orders delivered by 31 March 2026.
     - Buffer test: the promised date moved later by b days, b = 0 - 10.
   ============================================================================= */

DECLARE ld_rate_per_week FLOAT64 DEFAULT 0.005;
DECLARE ld_cap           FLOAT64 DEFAULT 0.10;
DECLARE gst_rate         FLOAT64 DEFAULT 0.18;
DECLARE first_delivery   DATE    DEFAULT DATE '2024-01-01';
DECLARE last_delivery    DATE    DEFAULT DATE '2026-09-30';
DECLARE years_covered    FLOAT64 DEFAULT 2.75;

-- -----------------------------------------------------------------------------
-- Step 1 · Shipments, orders and the LD each would have attracted
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ld_shipments` AS
WITH order_value AS (
    SELECT o.order_id, o.customer_id, o.promised_delivery_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND o.promised_delivery_date IS NOT NULL
    GROUP BY o.order_id, o.customer_id, o.promised_delivery_date
),
complete AS (
    SELECT order_id, COUNT(*) AS shipments_of_order, MAX(delivery_date) AS last_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
    HAVING COUNTIF(delivery_date IS NULL) = 0
)
SELECT s.shipment_id, s.order_id, v.customer_id, s.shipping_city, s.delivery_date, v.promised_delivery_date,
       v.order_value / c.shipments_of_order * (1 + gst_rate)                          AS shipment_value_incl_gst,
       DATE_DIFF(s.delivery_date, v.promised_delivery_date, DAY)                      AS days_late,
       IF(DATE_DIFF(s.delivery_date, v.promised_delivery_date, DAY) > 0,
          CAST(CEIL(DATE_DIFF(s.delivery_date, v.promised_delivery_date, DAY) / 7) AS INT64), 0) AS weeks_of_delay
FROM `sahyadri_b2b.shipments` AS s
JOIN order_value AS v ON v.order_id = s.order_id
JOIN complete AS c ON c.order_id = s.order_id
WHERE c.last_delivery_date BETWEEN first_delivery AND last_delivery;

CREATE OR REPLACE TABLE `sahyadri_b2b.ld_orders` AS
WITH by_order AS (
    SELECT order_id, customer_id, promised_delivery_date,
           COUNT(*)                                                                   AS shipments,
           SUM(shipment_value_incl_gst)                                               AS order_value_incl_gst,
           MAX(delivery_date)                                                         AS last_delivery_date,
           MAX(days_late)                                                             AS max_days_late,
           MAX(weeks_of_delay)                                                        AS max_weeks_of_delay,
           SUM(ld_rate_per_week * shipment_value_incl_gst * weeks_of_delay)           AS ld_before_cap
    FROM `sahyadri_b2b.ld_shipments`
    GROUP BY order_id, customer_id, promised_delivery_date
),
paid AS (
    SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date <= last_delivery GROUP BY order_id
)
SELECT b.*, c.customer_name, c.customer_segment,
       LEAST(b.ld_before_cap, ld_cap * b.order_value_incl_gst)                         AS ld,
       b.ld_before_cap > ld_cap * b.order_value_incl_gst                              AS cap_binds,
       b.order_value_incl_gst / (1 + gst_rate)                                        AS order_value,
       IFNULL(p.paid, 0)                                                              AS paid
FROM by_order AS b
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = b.customer_id
LEFT JOIN paid AS p ON p.order_id = b.order_id;

-- -----------------------------------------------------------------------------
-- Step 2 · What the clause would have cost
-- -----------------------------------------------------------------------------
SELECT
    IFNULL(customer_segment, 'All')                                                   AS segment,
    COUNT(*)                                                                          AS orders,
    COUNTIF(max_days_late > 0)                                                        AS late_orders,
    ROUND(100 * COUNTIF(max_days_late > 0) / COUNT(*), 1)                             AS late_pct,
    ROUND(SUM(order_value) / 1e7, 2)                                                  AS order_value_crore,
    ROUND(SUM(ld) / 1e5, 2)                                                           AS ld_lakh,
    ROUND(SUM(ld) / years_covered / 1e5, 2)                                           AS ld_per_year_lakh,
    ROUND(100 * SUM(ld) / SUM(order_value_incl_gst), 3)                               AS ld_as_pct_of_value,
    COUNTIF(cap_binds)                                                                AS orders_hitting_the_cap
FROM `sahyadri_b2b.ld_orders`
GROUP BY ROLLUP (customer_segment)
ORDER BY customer_segment IS NULL, ld_lakh DESC;

SELECT
    max_weeks_of_delay                                                                AS weeks_of_delay,
    COUNT(*)                                                                          AS orders,
    ROUND(SUM(ld) / 1e5, 2)                                                           AS ld_lakh,
    ROUND(100 * SUM(ld) / SUM(SUM(ld)) OVER (), 1)                                    AS share_of_ld_pct,
    ROUND(100 * ld_rate_per_week * max_weeks_of_delay, 1)                             AS ld_rate_on_late_value_pct
FROM `sahyadri_b2b.ld_orders`
WHERE max_days_late > 0
GROUP BY max_weeks_of_delay
ORDER BY max_weeks_of_delay;

-- -----------------------------------------------------------------------------
-- Step 3 · Is anyone already deducting delay penalties?
-- -----------------------------------------------------------------------------
SELECT
    IF(max_days_late > 0, '2. Delivered late', '1. Delivered on time')                AS delivery,
    COUNT(*)                                                                          AS orders,
    ROUND(100 * COUNTIF(paid > 0 AND paid < order_value - 1) / COUNT(*), 2)           AS short_paid_pct,
    ROUND(100 * AVG(IF(paid > 0 AND paid < order_value - 1, 1 - paid / order_value, NULL)), 1) AS average_shortfall_when_short_pct,
    -- short payments of up to 10 %, the size an LD deduction could take
    COUNTIF(paid > 0 AND paid < order_value - 1 AND paid >= 0.9 * order_value)         AS short_by_up_to_10_pct
FROM `sahyadri_b2b.ld_orders`
WHERE last_delivery_date <= DATE '2026-03-31'
GROUP BY delivery
ORDER BY delivery;

-- -----------------------------------------------------------------------------
-- Step 4 · Which customers and lanes would generate it
-- -----------------------------------------------------------------------------
SELECT
    customer_name, customer_segment,
    COUNT(*)                                                                          AS orders,
    COUNTIF(max_days_late > 0)                                                        AS late_orders,
    ROUND(SUM(ld) / 1e5, 2)                                                           AS ld_lakh,
    ROUND(100 * SUM(ld) / SUM(order_value_incl_gst), 2)                               AS ld_as_pct_of_value
FROM `sahyadri_b2b.ld_orders`
GROUP BY customer_name, customer_segment
ORDER BY ld_lakh DESC
LIMIT 10;

SELECT
    shipping_city,
    COUNT(*)                                                                          AS shipments,
    ROUND(100 * COUNTIF(days_late > 0) / COUNT(*), 1)                                 AS late_pct,
    ROUND(AVG(IF(days_late > 0, days_late, NULL)), 1)                                 AS average_days_late_when_late,
    ROUND(SUM(ld_rate_per_week * shipment_value_incl_gst * weeks_of_delay) / 1e5, 2)   AS ld_before_cap_lakh
FROM `sahyadri_b2b.ld_shipments`
GROUP BY shipping_city
HAVING COUNT(*) >= 100
ORDER BY ld_before_cap_lakh DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 5 · How much promise buffer removes the exposure
-- -----------------------------------------------------------------------------
WITH buffers AS (
    SELECT b AS buffer_days FROM UNNEST(GENERATE_ARRAY(0, 10)) AS b
),
by_order AS (
    SELECT bf.buffer_days, s.order_id,
           SUM(ld_rate_per_week * s.shipment_value_incl_gst
               * IF(s.days_late - bf.buffer_days > 0, CAST(CEIL((s.days_late - bf.buffer_days) / 7) AS INT64), 0)) AS ld_before_cap,
           MAX(s.days_late - bf.buffer_days)                                          AS max_days_late
    FROM `sahyadri_b2b.ld_shipments` AS s
    CROSS JOIN buffers AS bf
    GROUP BY bf.buffer_days, s.order_id
)
SELECT
    b.buffer_days,
    COUNTIF(b.max_days_late > 0)                                                      AS late_orders,
    ROUND(100 * COUNTIF(b.max_days_late > 0) / COUNT(*), 1)                           AS late_pct,
    ROUND(SUM(LEAST(b.ld_before_cap, ld_cap * o.order_value_incl_gst)) / years_covered / 1e5, 2) AS ld_per_year_all_lakh,
    ROUND(SUM(IF(o.customer_segment = 'Enterprise', LEAST(b.ld_before_cap, ld_cap * o.order_value_incl_gst), 0)) / years_covered / 1e5, 2) AS ld_per_year_enterprise_lakh,
    ROUND(AVG(DATE_DIFF(o.promised_delivery_date, so.order_date, DAY) + b.buffer_days), 1) AS average_promised_lead_time_days
FROM by_order AS b
JOIN `sahyadri_b2b.ld_orders` AS o ON o.order_id = b.order_id
JOIN `sahyadri_b2b.sales_orders` AS so ON so.order_id = b.order_id
GROUP BY b.buffer_days
ORDER BY b.buffer_days;
