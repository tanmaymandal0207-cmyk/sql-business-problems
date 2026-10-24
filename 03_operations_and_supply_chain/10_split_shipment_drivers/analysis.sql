/* =============================================================================
   Case study · Split shipment drivers
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   About one shipped order in fifteen leaves the warehouse in two shipments.
   The logistics head sees two costs: a second freight charge, and customers
   complaining that the order "arrived late" even when most of it came on
   time. Before changing the dispatch policy (ship complete vs ship what is
   available), the operations director wants to know:
     1. Which orders get split: is it order size, product category, specific
        products or customer segment?
     2. How much later does a split order arrive, and how much of the
        company's late-delivery problem do splits cause?
     3. What does splitting cost in extra freight?
     4. How long does the second shipment follow the first?

   KEY RULES
     - Shipped order: an order with at least one shipment row.
     - Split order: an order with two shipments (no order has more than two).
     - Final delivery = the last shipment's delivery date, only when every
       shipment of the order has a delivery date.
     - Late = final (or first) delivery after the promised delivery date.
     - Freight is compared only for orders where every shipment has a cost.
     - Product and category drivers are measured on multi-line orders only,
       because a single-line order cannot be split by line.
     - Product lift is tested with a z-score against the overall multi-line
       split rate; products need 50+ multi-line orders, and |z| >= 3 is used
       because 100+ products are tested at once.
   ============================================================================= */

DECLARE min_orders INT64 DEFAULT 50;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per shipped order with its shape, timing and freight
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.order_fulfilment` AS
WITH lines AS (
    SELECT
        i.order_id,
        COUNT(*)                                                                   AS order_lines,
        SUM(i.quantity)                                                            AS units,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    GROUP BY i.order_id
),
ship AS (
    SELECT
        s.order_id,
        COUNT(*)                                                    AS shipments,
        MIN(s.shipment_date)                                        AS first_shipment_date,
        MAX(s.shipment_date)                                        AS last_shipment_date,
        MIN(s.delivery_date)                                        AS first_delivery_date,
        IF(COUNT(s.delivery_date) = COUNT(*), MAX(s.delivery_date), NULL) AS final_delivery_date,
        IF(COUNT(s.shipping_cost) = COUNT(*), SUM(s.shipping_cost), NULL) AS freight
    FROM `sahyadri_b2b.shipments` AS s
    GROUP BY s.order_id
)
SELECT
    o.order_id,
    o.customer_id,
    c.customer_segment,
    o.order_date,
    o.promised_delivery_date,
    o.order_status,
    l.order_lines,
    l.units,
    l.revenue,
    s.shipments,
    s.shipments = 2                                                AS is_split,
    s.first_shipment_date,
    s.last_shipment_date,
    DATE_DIFF(s.last_shipment_date, s.first_shipment_date, DAY)     AS days_between_shipments,
    s.first_delivery_date,
    s.final_delivery_date,
    DATE_DIFF(s.final_delivery_date, o.order_date, DAY)             AS order_to_final_delivery_days,
    s.first_delivery_date > o.promised_delivery_date                AS first_delivery_late,
    s.final_delivery_date > o.promised_delivery_date                AS final_delivery_late,
    s.freight
FROM `sahyadri_b2b.sales_orders` AS o
JOIN ship  AS s ON s.order_id = o.order_id
JOIN lines AS l ON l.order_id = o.order_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Which orders get split? Order size, segment and category
-- -----------------------------------------------------------------------------
SELECT
    IF(order_lines >= 6, '6+', CAST(order_lines AS STRING))         AS order_lines,
    COUNT(*)                                                        AS shipped_orders,
    COUNTIF(is_split)                                               AS split_orders,
    ROUND(100 * AVG(IF(is_split, 1, 0)), 1)                         AS split_pct
FROM `sahyadri_b2b.order_fulfilment`
GROUP BY 1
ORDER BY 1;

-- Units per order (multi-line orders): is it the quantity?
SELECT
    CASE WHEN units <= 30  THEN '1. Up to 30 units'
         WHEN units <= 60  THEN '2. 31-60 units'
         WHEN units <= 100 THEN '3. 61-100 units'
         ELSE                   '4. Over 100 units' END            AS units_band,
    COUNT(*)                                                        AS multi_line_orders,
    ROUND(100 * AVG(IF(is_split, 1, 0)), 1)                         AS split_pct
FROM `sahyadri_b2b.order_fulfilment`
WHERE order_lines > 1
GROUP BY units_band
ORDER BY units_band;

SELECT
    customer_segment,
    COUNT(*)                                                        AS multi_line_orders,
    ROUND(AVG(order_lines), 2)                                      AS avg_lines,
    ROUND(100 * AVG(IF(is_split, 1, 0)), 1)                         AS split_pct
FROM `sahyadri_b2b.order_fulfilment`
WHERE order_lines > 1
GROUP BY customer_segment
ORDER BY split_pct DESC;

SELECT
    pc.category_name,
    COUNT(DISTINCT f.order_id)                                      AS multi_line_orders,
    ROUND(100 * AVG(IF(f.is_split, 1, 0)), 1)                       AS split_pct
FROM `sahyadri_b2b.order_fulfilment`  AS f
JOIN `sahyadri_b2b.sales_order_items` AS i  ON i.order_id = f.order_id
JOIN `sahyadri_b2b.products`          AS p  ON p.product_id = i.product_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
WHERE f.order_lines > 1
GROUP BY pc.category_name
ORDER BY split_pct DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · Product lift: which products appear in split orders more than chance?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.split_product_lift` AS
WITH base AS (
    SELECT AVG(IF(is_split, 1, 0)) AS base_rate
    FROM `sahyadri_b2b.order_fulfilment`
    WHERE order_lines > 1
),
by_product AS (
    SELECT
        i.product_id,
        COUNT(*)                                                    AS multi_line_orders,
        COUNTIF(f.is_split)                                         AS split_orders
    FROM `sahyadri_b2b.order_fulfilment`  AS f
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = f.order_id
    WHERE f.order_lines > 1
    GROUP BY i.product_id
)
SELECT
    p.product_id,
    p.product_name,
    pc.category_name,
    b.multi_line_orders,
    b.split_orders,
    b.split_orders / b.multi_line_orders                            AS split_rate,
    base.base_rate,
    (b.split_orders / b.multi_line_orders) / base.base_rate         AS lift,
    (b.split_orders / b.multi_line_orders - base.base_rate)
      / SQRT(base.base_rate * (1 - base.base_rate) / b.multi_line_orders) AS z_score
FROM by_product AS b
CROSS JOIN base
JOIN `sahyadri_b2b.products`           AS p  ON p.product_id = b.product_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
WHERE b.multi_line_orders >= min_orders;

SELECT
    COUNT(*)                                                        AS products_tested,
    ROUND(100 * ANY_VALUE(base_rate), 1)                            AS base_split_pct,
    COUNTIF(z_score >= 3)                                           AS products_z_at_least_3,
    COUNTIF(z_score <= -3)                                          AS products_z_at_most_minus_3,
    COUNTIF(ABS(z_score) >= 2)                                      AS products_abs_z_at_least_2
FROM `sahyadri_b2b.split_product_lift`;

SELECT
    product_id,
    product_name,
    category_name,
    multi_line_orders,
    split_orders,
    ROUND(100 * split_rate, 1)                                      AS split_pct,
    ROUND(lift, 2)                                                  AS lift,
    ROUND(z_score, 2)                                               AS z_score
FROM `sahyadri_b2b.split_product_lift`
ORDER BY z_score DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 4 · How much later do split orders arrive, and how much lateness do
--          they cause?
-- -----------------------------------------------------------------------------
SELECT
    IF(is_split, 'Split (2 shipments)', 'Single shipment')          AS fulfilment,
    COUNT(*)                                                        AS orders_measured,
    ROUND(100 * AVG(IF(first_delivery_late, 1, 0)), 1)              AS first_delivery_late_pct,
    ROUND(100 * AVG(IF(final_delivery_late, 1, 0)), 1)              AS final_delivery_late_pct,
    APPROX_QUANTILES(order_to_final_delivery_days, 2)[OFFSET(1)]    AS median_days_to_final_delivery,
    COUNTIF(final_delivery_late)                                    AS late_orders,
    ROUND(100 * COUNTIF(final_delivery_late) / SUM(COUNTIF(final_delivery_late)) OVER (), 1) AS share_of_late_orders
FROM `sahyadri_b2b.order_fulfilment`
WHERE final_delivery_date IS NOT NULL AND promised_delivery_date IS NOT NULL
GROUP BY fulfilment
ORDER BY fulfilment;

-- What if split orders were late only as often as single-shipment orders?
WITH measured AS (
    SELECT * FROM `sahyadri_b2b.order_fulfilment`
    WHERE final_delivery_date IS NOT NULL AND promised_delivery_date IS NOT NULL
),
single_rate AS (
    SELECT AVG(IF(final_delivery_late, 1, 0)) AS rate FROM measured WHERE NOT is_split
)
SELECT
    COUNT(*)                                                        AS orders_measured,
    COUNTIF(final_delivery_late)                                    AS late_orders_actual,
    ROUND(100 * AVG(IF(final_delivery_late, 1, 0)), 1)              AS late_pct_actual,
    ROUND(COUNTIF(final_delivery_late AND NOT is_split) + COUNTIF(is_split) * ANY_VALUE(s.rate), 0) AS late_orders_if_splits_like_single,
    ROUND(100 * (COUNTIF(final_delivery_late AND NOT is_split) + COUNTIF(is_split) * ANY_VALUE(s.rate)) / COUNT(*), 1) AS late_pct_if_splits_like_single
FROM measured
CROSS JOIN single_rate AS s;

-- Same comparison holding order size constant (multi-line orders)
SELECT
    IF(order_lines >= 6, '6+', CAST(order_lines AS STRING))         AS order_lines,
    ROUND(100 * AVG(IF(NOT is_split, IF(final_delivery_late, 1, 0), NULL)), 1) AS single_late_pct,
    ROUND(100 * AVG(IF(is_split,     IF(final_delivery_late, 1, 0), NULL)), 1) AS split_late_pct,
    COUNTIF(is_split)                                               AS split_orders
FROM `sahyadri_b2b.order_fulfilment`
WHERE final_delivery_date IS NOT NULL AND promised_delivery_date IS NOT NULL AND order_lines > 1
GROUP BY 1
ORDER BY 1;

-- -----------------------------------------------------------------------------
-- Step 5 · Extra freight from splitting (multi-line orders, fully costed)
-- -----------------------------------------------------------------------------
WITH by_size AS (
    SELECT
        IF(order_lines >= 6, 6, order_lines)                        AS size_band,
        AVG(IF(NOT is_split, freight, NULL))                        AS single_freight,
        AVG(IF(is_split, freight, NULL))                            AS split_freight,
        COUNTIF(is_split)                                           AS split_orders
    FROM `sahyadri_b2b.order_fulfilment`
    WHERE freight IS NOT NULL AND order_lines > 1
    GROUP BY size_band
)
SELECT
    IF(size_band = 6, '6+', CAST(size_band AS STRING))              AS order_lines,
    split_orders,
    ROUND(single_freight, 0)                                        AS avg_freight_single,
    ROUND(split_freight, 0)                                         AS avg_freight_split,
    ROUND(split_freight - single_freight, 0)                        AS extra_freight_per_split,
    ROUND(split_orders * (split_freight - single_freight), 0)       AS extra_freight_total
FROM by_size
UNION ALL
SELECT 'All', SUM(split_orders), NULL, NULL,
       ROUND(SUM(split_orders * (split_freight - single_freight)) / SUM(split_orders), 0),
       ROUND(SUM(split_orders * (split_freight - single_freight)), 0)
FROM by_size
ORDER BY order_lines;

-- -----------------------------------------------------------------------------
-- Step 6 · How long does the second shipment follow the first?
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                        AS split_orders,
    MIN(days_between_shipments)                                     AS min_days,
    APPROX_QUANTILES(days_between_shipments, 4)[OFFSET(2)]          AS median_days,
    APPROX_QUANTILES(days_between_shipments, 10)[OFFSET(9)]         AS p90_days,
    MAX(days_between_shipments)                                     AS max_days,
    ROUND(100 * AVG(IF(first_delivery_late, 1, 0)), 1)              AS first_part_late_pct,
    ROUND(100 * AVG(IF(final_delivery_late, 1, 0)), 1)              AS final_part_late_pct
FROM `sahyadri_b2b.order_fulfilment`
WHERE is_split
  AND final_delivery_date IS NOT NULL AND promised_delivery_date IS NOT NULL;
