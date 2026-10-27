/* =============================================================================
   Case study · Key-account service: better service or easier promises?
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The key-account team reports 87 % on-time delivery to Enterprise
   customers against about 79 % for everyone else, and presents it as proof
   that key accounts get priority service. The operations head is not sure
   the warehouse treats them any differently and wants to know what the gap
   is made of:
     1. Do Enterprise and top-revenue customers get faster dispatch or
        faster transit than other customers in the same city?
     2. Are their promise windows different?
     3. Measured against one common standard, is their delivery any better?
     4. What should the service KPI reported to key accounts be?

   METHOD
     - Delivered orders with a promise date and a delivery date on every
       shipment.
     - Dispatch days = first shipment date - order date. Transit days =
       final delivery date - first shipment date. Lead time = final delivery
       date - order date. Promise window = promised date - order date.
     - City = INITCAP(TRIM(shipping_city)) of the first shipment.
     - Lead time vs city = lead time - average lead time of all orders to
       the same city (positive = slower than usual for that destination).
     - Common standard: the 80th percentile of lead time in the order's
       city, the same for every customer (PERCENTILE_CONT). On-time vs the
       common standard = lead time <= that standard.
     - Revenue tier: customers ranked by net revenue of their delivered
       orders, in five equal groups (tier 1 = largest).
     - Two-proportion z and Welch t for Enterprise against all other
       segments.
   ============================================================================= */

DECLARE standard_pct FLOAT64 DEFAULT 0.8;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per delivered order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sq_orders` AS
WITH ship AS (
    SELECT
        order_id,
        MIN(shipment_date)                                                     AS first_ship_date,
        MAX(delivery_date)                                                     AS final_delivery_date,
        COUNT(*)                                                               AS shipments,
        COUNT(delivery_date)                                                   AS delivered_shipments,
        ARRAY_AGG(INITCAP(TRIM(shipping_city)) ORDER BY shipment_date, shipment_id LIMIT 1)[OFFSET(0)] AS city
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
base AS (
    SELECT
        o.order_id, o.customer_id, c.customer_segment, s.city, v.order_value, s.shipments,
        o.order_date, o.promised_delivery_date, s.first_ship_date, s.final_delivery_date,
        DATE_DIFF(s.first_ship_date, o.order_date, DAY)                        AS dispatch_days,
        DATE_DIFF(s.final_delivery_date, s.first_ship_date, DAY)               AS transit_days,
        DATE_DIFF(s.final_delivery_date, o.order_date, DAY)                    AS lead_time,
        DATE_DIFF(o.promised_delivery_date, o.order_date, DAY)                 AS promise_window,
        s.final_delivery_date <= o.promised_delivery_date                      AS on_time
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN ship  AS s ON s.order_id = o.order_id
    JOIN value AS v ON v.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'Delivered'
      AND o.promised_delivery_date IS NOT NULL
      AND s.delivered_shipments = s.shipments
),
tiers AS (
    SELECT customer_id, NTILE(5) OVER (ORDER BY SUM(order_value) DESC, customer_id) AS revenue_tier
    FROM base
    GROUP BY customer_id
)
SELECT
    b.*, t.revenue_tier,
    AVG(b.lead_time) OVER (PARTITION BY b.city)                                         AS city_avg_lead_time,
    b.lead_time - AVG(b.lead_time) OVER (PARTITION BY b.city)                           AS lead_time_vs_city,
    PERCENTILE_CONT(b.lead_time, standard_pct) OVER (PARTITION BY b.city)               AS city_standard,
    b.lead_time <= PERCENTILE_CONT(b.lead_time, standard_pct) OVER (PARTITION BY b.city) AS on_time_common
FROM base AS b
JOIN tiers AS t ON t.customer_id = b.customer_id;

SELECT COUNT(*) AS orders, COUNT(DISTINCT customer_id) AS customers, COUNT(DISTINCT city) AS cities,
       ROUND(100 * AVG(IF(on_time, 1, 0)), 1) AS on_time_pct
FROM `sahyadri_b2b.sq_orders`;

-- -----------------------------------------------------------------------------
-- Step 2 · Service by segment: promise, speed and on-time
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                                    AS orders,
    ROUND(AVG(promise_window), 2)                               AS avg_promise_days,
    MIN(promise_window)                                         AS shortest_promise,
    MAX(promise_window)                                         AS longest_promise,
    ROUND(AVG(dispatch_days), 2)                                AS avg_dispatch_days,
    ROUND(AVG(transit_days), 2)                                 AS avg_transit_days,
    ROUND(AVG(lead_time), 2)                                    AS avg_lead_time,
    ROUND(AVG(lead_time_vs_city), 2)                            AS lead_time_vs_city,
    ROUND(100 * AVG(IF(on_time, 1, 0)), 1)                      AS on_time_reported_pct,
    ROUND(100 * AVG(IF(on_time_common, 1, 0)), 1)               AS on_time_common_standard_pct
FROM `sahyadri_b2b.sq_orders`
GROUP BY customer_segment
ORDER BY on_time_reported_pct DESC;

-- Enterprise against all other segments: significance
WITH g AS (
    SELECT
        customer_segment = 'Enterprise'                         AS is_enterprise,
        COUNT(*)                                                AS n,
        AVG(IF(on_time, 1, 0))                                  AS p_reported,
        AVG(IF(on_time_common, 1, 0))                           AS p_common,
        AVG(dispatch_days)                                      AS m_dispatch,
        VAR_SAMP(dispatch_days)                                 AS v_dispatch,
        AVG(lead_time_vs_city)                                  AS m_speed,
        VAR_SAMP(lead_time_vs_city)                             AS v_speed,
        AVG(promise_window)                                     AS m_promise,
        VAR_SAMP(promise_window)                                AS v_promise
    FROM `sahyadri_b2b.sq_orders`
    GROUP BY is_enterprise
),
e AS (SELECT * FROM g WHERE is_enterprise),
o AS (SELECT * FROM g WHERE NOT is_enterprise),
pooled AS (
    SELECT (e.n * e.p_reported + o.n * o.p_reported) / (e.n + o.n) AS pr,
           (e.n * e.p_common   + o.n * o.p_common)   / (e.n + o.n) AS pc
    FROM e CROSS JOIN o
)
SELECT '1. On-time vs promise (%)' AS measure, ROUND(100 * e.p_reported, 1) AS enterprise, ROUND(100 * o.p_reported, 1) AS other_segments,
       ROUND((e.p_reported - o.p_reported) / SQRT(p.pr * (1 - p.pr) * (1 / e.n + 1 / o.n)), 2) AS z
FROM e CROSS JOIN o CROSS JOIN pooled AS p
UNION ALL
SELECT '2. On-time vs common city standard (%)', ROUND(100 * e.p_common, 1), ROUND(100 * o.p_common, 1),
       ROUND((e.p_common - o.p_common) / SQRT(p.pc * (1 - p.pc) * (1 / e.n + 1 / o.n)), 2)
FROM e CROSS JOIN o CROSS JOIN pooled AS p
UNION ALL
SELECT '3. Promise window (days)', ROUND(e.m_promise, 2), ROUND(o.m_promise, 2),
       ROUND((e.m_promise - o.m_promise) / SQRT(e.v_promise / e.n + o.v_promise / o.n), 2)
FROM e CROSS JOIN o
UNION ALL
SELECT '4. Dispatch days', ROUND(e.m_dispatch, 2), ROUND(o.m_dispatch, 2),
       ROUND((e.m_dispatch - o.m_dispatch) / SQRT(e.v_dispatch / e.n + o.v_dispatch / o.n), 2)
FROM e CROSS JOIN o
UNION ALL
SELECT '5. Lead time vs city average (days)', ROUND(e.m_speed, 2), ROUND(o.m_speed, 2),
       ROUND((e.m_speed - o.m_speed) / SQRT(e.v_speed / e.n + o.v_speed / o.n), 2)
FROM e CROSS JOIN o
ORDER BY measure;

-- -----------------------------------------------------------------------------
-- Step 3 · Same promise, same result? On-time by promise window band
-- -----------------------------------------------------------------------------
SELECT
    CASE WHEN promise_window <= 9  THEN '1. 5-9 days'
         WHEN promise_window <= 12 THEN '2. 10-12 days'
         WHEN promise_window <= 15 THEN '3. 13-15 days'
         ELSE                           '4. 16+ days' END                        AS promise_band,
    COUNTIF(customer_segment = 'Enterprise')                                     AS enterprise_orders,
    ROUND(100 * AVG(IF(customer_segment = 'Enterprise', IF(on_time, 1, 0), NULL)), 1)  AS enterprise_on_time_pct,
    COUNTIF(customer_segment != 'Enterprise')                                    AS other_orders,
    ROUND(100 * AVG(IF(customer_segment != 'Enterprise', IF(on_time, 1, 0), NULL)), 1) AS other_on_time_pct,
    ROUND(100 * COUNTIF(customer_segment = 'Enterprise')
          / SUM(COUNTIF(customer_segment = 'Enterprise')) OVER (), 1)            AS share_of_enterprise_orders_pct,
    ROUND(100 * COUNTIF(customer_segment != 'Enterprise')
          / SUM(COUNTIF(customer_segment != 'Enterprise')) OVER (), 1)           AS share_of_other_orders_pct
FROM `sahyadri_b2b.sq_orders`
GROUP BY promise_band
ORDER BY promise_band;

-- Reported on-time if other segments' orders had Enterprise-style promises:
-- re-weight other segments' band on-time rates by the Enterprise band mix
WITH b AS (
    SELECT
        CASE WHEN promise_window <= 9 THEN 1 WHEN promise_window <= 12 THEN 2 WHEN promise_window <= 15 THEN 3 ELSE 4 END AS band,
        COUNTIF(customer_segment = 'Enterprise')                                       AS e_n,
        AVG(IF(customer_segment != 'Enterprise', IF(on_time, 1, 0), NULL))             AS o_rate,
        AVG(IF(customer_segment = 'Enterprise', IF(on_time, 1, 0), NULL))              AS e_rate
    FROM `sahyadri_b2b.sq_orders`
    GROUP BY band
)
SELECT
    ROUND(100 * SUM(e_n * e_rate) / SUM(e_n), 1)                                      AS enterprise_on_time_pct,
    ROUND(100 * SUM(e_n * o_rate) / SUM(e_n), 1)                                      AS other_segments_with_enterprise_promises_pct
FROM b;

-- -----------------------------------------------------------------------------
-- Step 4 · Do the largest customers get faster service?
-- -----------------------------------------------------------------------------
SELECT
    revenue_tier,
    COUNT(DISTINCT customer_id)                                 AS customers,
    COUNT(*)                                                    AS orders,
    ROUND(100 * COUNTIF(customer_segment = 'Enterprise') / COUNT(*), 1) AS enterprise_share_pct,
    ROUND(AVG(promise_window), 2)                               AS avg_promise_days,
    ROUND(AVG(dispatch_days), 2)                                AS avg_dispatch_days,
    ROUND(AVG(lead_time_vs_city), 2)                            AS lead_time_vs_city,
    ROUND(100 * AVG(IF(on_time, 1, 0)), 1)                      AS on_time_reported_pct,
    ROUND(100 * AVG(IF(on_time_common, 1, 0)), 1)               AS on_time_common_standard_pct
FROM `sahyadri_b2b.sq_orders`
GROUP BY revenue_tier
ORDER BY revenue_tier;

-- Within the largest tier, Enterprise vs other customers
SELECT
    customer_segment = 'Enterprise'                             AS is_enterprise,
    COUNT(*)                                                    AS orders,
    ROUND(AVG(promise_window), 2)                               AS avg_promise_days,
    ROUND(AVG(dispatch_days), 2)                                AS avg_dispatch_days,
    ROUND(100 * AVG(IF(on_time, 1, 0)), 1)                      AS on_time_reported_pct,
    ROUND(100 * AVG(IF(on_time_common, 1, 0)), 1)               AS on_time_common_standard_pct
FROM `sahyadri_b2b.sq_orders`
WHERE revenue_tier = 1
GROUP BY is_enterprise
ORDER BY is_enterprise DESC;
