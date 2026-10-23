/* =============================================================================
   Case study · Shipment consolidation opportunity
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The warehouse dispatches every order as soon as it is ready. Customers who
   order several times a week therefore receive several separate shipments to
   the same address, and each one carries a fixed transport charge. The
   logistics manager wants to test fixed dispatch schedules per customer
   ("ship to this customer every second day", "twice a week", "weekly"):
     1. What does a shipment cost, and how much of that is a fixed charge
        that consolidation would save?
     2. Under each schedule, how many shipments would be avoided, what would
        that save, and how long would goods wait?
     3. Which customers offer the biggest saving?

   KEY RULES
     - Window: shipments dated 1 Oct 2025 - 30 Sep 2026 with a known
       shipping_cost and shipment_date.
     - Destination: customer + shipping city (trimmed, lower case). Shipments
       can only be combined for the same customer and city.
     - Freight model: fitted on single-shipment orders in the window,
       cost = fixed + rate * order value (least squares, computed in SQL with
       COVAR_POP / VAR_POP). The fixed part is what consolidation saves.
     - Schedules (shipments in the same bucket for the same destination are
       combined into one):
         Daily       : same shipment date (today's practice, as a baseline)
         Every 2 days: 2-day buckets
         Twice weekly: Monday-Wednesday and Thursday-Sunday of each ISO week
         Weekly      : ISO week (Monday-Sunday)
     - Saving = shipments avoided * fixed cost per shipment.
     - Added wait = days from a shipment's actual date to the last shipment
       date in its bucket (the day the combined load would leave).
   ============================================================================= */

DECLARE window_start DATE DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Freight model: fixed charge per shipment + rate per rupee shipped
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.freight_cost_model` AS
WITH single_shipment_orders AS (
    SELECT s.order_id, ANY_VALUE(s.shipping_cost) AS shipping_cost
    FROM `sahyadri_b2b.shipments` AS s
    WHERE s.shipment_date BETWEEN window_start AND window_end
    GROUP BY s.order_id
    HAVING COUNT(*) = 1 AND COUNT(s.shipping_cost) = 1
),
order_value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
fit AS (
    SELECT
        COUNT(*)                                                       AS orders_used,
        COVAR_POP(s.shipping_cost, v.order_value) / VAR_POP(v.order_value) AS rate_per_rupee,
        AVG(s.shipping_cost)                                           AS mean_cost,
        AVG(v.order_value)                                             AS mean_value,
        CORR(s.shipping_cost, v.order_value)                           AS correlation
    FROM single_shipment_orders AS s
    JOIN order_value            AS v ON v.order_id = s.order_id
)
SELECT
    orders_used,
    ROUND(mean_cost - rate_per_rupee * mean_value, 2)   AS fixed_cost_per_shipment,
    rate_per_rupee,
    ROUND(POW(correlation, 2), 4)                        AS r_squared,
    ROUND(mean_cost, 2)                                  AS mean_cost_per_shipment
FROM fit;

SELECT * FROM `sahyadri_b2b.freight_cost_model`;

-- -----------------------------------------------------------------------------
-- Step 2 · One row per shipment with its destination and schedule buckets
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.shipment_consolidation_base` AS
SELECT
    s.shipment_id,
    s.order_id,
    o.customer_id,
    LOWER(TRIM(s.shipping_city))                                          AS city_key,
    s.shipment_date,
    s.shipping_cost,
    -- bucket keys for each schedule
    s.shipment_date                                                       AS bucket_daily,
    DIV(DATE_DIFF(s.shipment_date, window_start, DAY), 2)                 AS bucket_2day,
    CONCAT(CAST(DATE_TRUNC(s.shipment_date, ISOWEEK) AS STRING), '|',
           IF(EXTRACT(DAYOFWEEK FROM s.shipment_date) BETWEEN 2 AND 4, 'A', 'B')) AS bucket_twice_weekly,
    DATE_TRUNC(s.shipment_date, ISOWEEK)                                  AS bucket_weekly
FROM `sahyadri_b2b.shipments`    AS s
JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = s.order_id
WHERE s.shipment_date BETWEEN window_start AND window_end
  AND s.shipping_cost IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Step 3 · Scenario comparison
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.consolidation_scenarios` AS
WITH long_form AS (
    SELECT '1. Daily (today)' AS schedule, shipment_id, customer_id, city_key, shipment_date, CAST(bucket_daily AS STRING) AS bucket
    FROM `sahyadri_b2b.shipment_consolidation_base`
    UNION ALL
    SELECT '2. Every 2 days', shipment_id, customer_id, city_key, shipment_date, CAST(bucket_2day AS STRING)
    FROM `sahyadri_b2b.shipment_consolidation_base`
    UNION ALL
    SELECT '3. Twice weekly', shipment_id, customer_id, city_key, shipment_date, bucket_twice_weekly
    FROM `sahyadri_b2b.shipment_consolidation_base`
    UNION ALL
    SELECT '4. Weekly', shipment_id, customer_id, city_key, shipment_date, CAST(bucket_weekly AS STRING)
    FROM `sahyadri_b2b.shipment_consolidation_base`
),
with_departure AS (
    SELECT
        *,
        MAX(shipment_date) OVER (PARTITION BY schedule, customer_id, city_key, bucket) AS departure_date
    FROM long_form
)
SELECT
    schedule,
    customer_id,
    city_key,
    bucket,
    COUNT(*)                                                  AS shipments,
    SUM(DATE_DIFF(departure_date, shipment_date, DAY))        AS added_wait_days
FROM with_departure
GROUP BY schedule, customer_id, city_key, bucket;

SELECT
    c.schedule,
    SUM(c.shipments)                                                           AS shipments_today,
    COUNT(*)                                                                   AS dispatches_needed,
    SUM(c.shipments) - COUNT(*)                                                AS shipments_avoided,
    ROUND(100 * (SUM(c.shipments) - COUNT(*)) / SUM(c.shipments), 1)           AS pct_avoided,
    ROUND((SUM(c.shipments) - COUNT(*)) * ANY_VALUE(m.fixed_cost_per_shipment), 0) AS annual_saving,
    ROUND(100 * (SUM(c.shipments) - COUNT(*)) * ANY_VALUE(m.fixed_cost_per_shipment)
          / ANY_VALUE(t.total_freight), 1)                                      AS saving_pct_of_freight,
    ROUND(SUM(c.added_wait_days) / SUM(c.shipments), 2)                        AS avg_added_wait_days,
    ROUND(SUM(c.added_wait_days) / NULLIF(SUM(IF(c.shipments > 1, c.shipments, 0)), 0), 2) AS avg_wait_for_combined_shipments
FROM `sahyadri_b2b.consolidation_scenarios` AS c
CROSS JOIN `sahyadri_b2b.freight_cost_model` AS m
CROSS JOIN (SELECT SUM(shipping_cost) AS total_freight
              FROM `sahyadri_b2b.shipment_consolidation_base`) AS t
GROUP BY c.schedule
ORDER BY c.schedule;

-- -----------------------------------------------------------------------------
-- Step 4 · Customers with the biggest twice-weekly saving
-- -----------------------------------------------------------------------------
SELECT
    c.customer_id,
    cu.customer_name,
    cu.customer_segment,
    SUM(c.shipments)                                                   AS shipments_today,
    COUNT(*)                                                           AS twice_weekly_dispatches,
    SUM(c.shipments) - COUNT(*)                                        AS shipments_avoided,
    ROUND((SUM(c.shipments) - COUNT(*)) * ANY_VALUE(m.fixed_cost_per_shipment), 0) AS annual_saving,
    ROUND(SUM(c.added_wait_days) / SUM(c.shipments), 2)                AS avg_added_wait_days
FROM `sahyadri_b2b.consolidation_scenarios` AS c
JOIN `sahyadri_b2b.customers`               AS cu ON cu.customer_id = c.customer_id
CROSS JOIN `sahyadri_b2b.freight_cost_model` AS m
WHERE c.schedule = '3. Twice weekly'
GROUP BY c.customer_id, cu.customer_name, cu.customer_segment
ORDER BY annual_saving DESC
LIMIT 10;
