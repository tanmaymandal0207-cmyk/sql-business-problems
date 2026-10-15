/* =============================================================================
   Case study · Late delivery root cause
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Customers are complaining about late deliveries. Operations has three
   competing explanations and a limited budget:
     - the warehouse is slow to dispatch (fix: stock / picking capacity),
     - transporters are slow (fix: change carriers or routes),
     - sales promises dates the business cannot meet (fix: promise rules).
   The analysis measures how much each stage contributes to lateness, so that
   money goes to the stage that actually causes it.

   BUSINESS QUESTIONS
     1. What share of delivered orders arrive by the promised date, and how
        late are the late ones?
     2. For each late order, how many days of lateness come from dispatch,
        from transit, and from a promise date shorter than the normal lead time?
     3. Do split shipments and short promise windows predict lateness?
     4. After standardising city names, which destinations and which
        salespeople are associated with late deliveries?

   METHOD — exact days-late decomposition
     actual lead   = dispatch days + transit days
     expected lead = standard dispatch + standard transit for the city
     days late     = actual lead - promised lead
                   = (dispatch - standard dispatch)          -> dispatch_excess
                   + (transit  - standard transit for city)  -> transit_excess
                   + (expected lead - promised lead)         -> promise_shortfall
   The three components always add up to days late (validation check 06).
   Each late order is assigned the component that contributes the most days.

   DEFINITIONS
     - Scope: Delivered orders with a promised date and a final delivery date.
       Orders with a shipment dated before the order date are excluded as
       data errors (counted in validation.sql).
     - Dispatch days = last shipment date - order date
       (an order is fully dispatched only when its last part leaves).
     - Transit days  = final delivery date - last shipment date.
     - Standard dispatch = median dispatch days of single-shipment orders
       (normal performance when all stock is available).
     - Standard transit  = median transit days for the destination city;
       company median for cities with fewer than `min_city_orders` orders.
     - Late = final delivery date after promised delivery date.
     - City names are standardised through a mapping table (Step 0):
       trimmed, title-cased, and historic names mapped to current ones.
   ============================================================================= */

DECLARE min_city_orders INT64 DEFAULT 20;

-- -----------------------------------------------------------------------------
-- Step 0 · City name mapping table (historic / alternate name -> standard name)
--          Names not listed are standardised with INITCAP(TRIM(...)).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.city_name_map` AS
SELECT * FROM UNNEST([
    STRUCT('ahmadabad' AS raw_city_key, 'Ahmedabad' AS standard_city),
    STRUCT('bangalore', 'Bengaluru'),
    STRUCT('baroda',    'Vadodara'),
    STRUCT('bombay',    'Mumbai'),
    STRUCT('calcutta',  'Kolkata'),
    STRUCT('delhi',     'New Delhi'),
    STRUCT('gurgaon',   'Gurugram'),
    STRUCT('madras',    'Chennai'),
    STRUCT('mysore',    'Mysuru'),
    STRUCT('vizag',     'Visakhapatnam')
]);

-- -----------------------------------------------------------------------------
-- Step 1 · Order-level delivery performance table
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.delivery_performance` AS
WITH shipments_clean AS (
    SELECT
        s.order_id,
        s.shipment_date,
        s.delivery_date,
        COALESCE(m.standard_city, INITCAP(TRIM(s.shipping_city))) AS delivery_city
    FROM `sahyadri_b2b.shipments`          AS s
    LEFT JOIN `sahyadri_b2b.city_name_map` AS m
        ON m.raw_city_key = LOWER(TRIM(s.shipping_city))
),

order_shipments AS (
    SELECT
        order_id,
        COUNT(*)            AS shipment_count,
        MIN(shipment_date)  AS first_shipment_date,
        MAX(shipment_date)  AS last_shipment_date,
        MAX(delivery_date)  AS final_delivery_date,
        ANY_VALUE(delivery_city) AS delivery_city   -- one city per order (validation check 04)
    FROM shipments_clean
    GROUP BY order_id
),

in_scope AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.employee_id,
        o.order_date,
        o.promised_delivery_date,
        s.final_delivery_date,
        s.delivery_city,
        s.shipment_count,
        DATE_DIFF(o.promised_delivery_date, o.order_date, DAY)        AS promised_lead_days,
        DATE_DIFF(s.last_shipment_date,     o.order_date, DAY)        AS dispatch_days,
        DATE_DIFF(s.final_delivery_date,    s.last_shipment_date, DAY) AS transit_days
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN order_shipments             AS s
        ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
      AND o.promised_delivery_date IS NOT NULL
      AND s.final_delivery_date    IS NOT NULL
      AND s.first_shipment_date   >= o.order_date      -- exclude impossible dates
),

dispatch_standard AS (
    SELECT DISTINCT
        PERCENTILE_CONT(dispatch_days, 0.5) OVER () AS std_dispatch_days
    FROM in_scope
    WHERE shipment_count = 1
),

company_transit AS (
    SELECT DISTINCT
        PERCENTILE_CONT(transit_days, 0.5) OVER () AS company_std_transit_days
    FROM in_scope
),

city_transit AS (
    SELECT DISTINCT
        delivery_city,
        COUNT(*) OVER (PARTITION BY delivery_city)                          AS city_orders,
        PERCENTILE_CONT(transit_days, 0.5) OVER (PARTITION BY delivery_city) AS city_median_transit
    FROM in_scope
),

measured AS (
    SELECT
        i.*,
        d.std_dispatch_days,
        IF(c.city_orders >= min_city_orders,
           c.city_median_transit,
           t.company_std_transit_days)                               AS std_transit_days,
        i.dispatch_days + i.transit_days                             AS actual_lead_days
    FROM in_scope AS i
    CROSS JOIN dispatch_standard AS d
    CROSS JOIN company_transit   AS t
    JOIN city_transit            AS c
        ON c.delivery_city = i.delivery_city
),

decomposed AS (
    SELECT
        *,
        actual_lead_days - promised_lead_days                        AS days_late,
        actual_lead_days > promised_lead_days                        AS is_late,
        dispatch_days - std_dispatch_days                            AS dispatch_excess,
        transit_days  - std_transit_days                             AS transit_excess,
        (std_dispatch_days + std_transit_days) - promised_lead_days  AS promise_shortfall
    FROM measured
)

SELECT
    *,
    CASE
        WHEN NOT is_late THEN NULL
        WHEN dispatch_excess >= transit_excess
         AND dispatch_excess >= promise_shortfall THEN 'Dispatch delay'
        WHEN transit_excess  >= promise_shortfall THEN 'Transit delay'
        ELSE 'Promise shorter than normal lead time'
    END AS primary_cause,
    CASE
        WHEN promised_lead_days <= 7  THEN '1. 7 days or less'
        WHEN promised_lead_days <= 10 THEN '2. 8-10 days'
        WHEN promised_lead_days <= 14 THEN '3. 11-14 days'
        ELSE                               '4. 15 days or more'
    END AS promise_window
FROM decomposed;

-- -----------------------------------------------------------------------------
-- Step 2 · Headline on-time performance and the standards used
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                  AS delivered_orders,
    COUNTIF(NOT is_late)                                      AS on_time_orders,
    COUNTIF(is_late)                                          AS late_orders,
    ROUND(100 * COUNTIF(NOT is_late) / COUNT(*), 1)           AS on_time_pct,
    ROUND(AVG(IF(is_late, days_late, NULL)), 1)               AS avg_days_late_when_late,
    MAX(days_late)                                            AS max_days_late,
    ANY_VALUE(std_dispatch_days)                              AS std_dispatch_days,
    ROUND(AVG(std_transit_days), 1)                           AS avg_std_transit_days
FROM `sahyadri_b2b.delivery_performance`;

-- -----------------------------------------------------------------------------
-- Step 3 · Days-late bridge: total days late split into its three components
--          (negative = that stage was faster than standard and absorbed delay)
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                          AS late_orders,
    SUM(days_late)                    AS total_days_late,
    ROUND(SUM(dispatch_excess), 1)    AS dispatch_excess_days,
    ROUND(SUM(transit_excess), 1)     AS transit_excess_days,
    ROUND(SUM(promise_shortfall), 1)  AS promise_shortfall_days
FROM `sahyadri_b2b.delivery_performance`
WHERE is_late;

-- -----------------------------------------------------------------------------
-- Step 4 · Root cause of late orders: primary cause and average day components
-- -----------------------------------------------------------------------------
SELECT
    primary_cause,
    COUNT(*)                                                  AS late_orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_late_orders,
    ROUND(AVG(days_late), 1)                                  AS avg_days_late,
    ROUND(AVG(dispatch_excess), 1)                            AS avg_dispatch_excess,
    ROUND(AVG(transit_excess), 1)                             AS avg_transit_excess,
    ROUND(AVG(promise_shortfall), 1)                          AS avg_promise_shortfall,
    ROUND(100 * COUNTIF(shipment_count > 1) / COUNT(*), 1)    AS pct_split_shipments
FROM `sahyadri_b2b.delivery_performance`
WHERE is_late
GROUP BY primary_cause
ORDER BY late_orders DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · How far beyond standard dispatch an order left, and its late rate
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN dispatch_excess <= 0 THEN '1. Within standard'
        WHEN dispatch_excess <= 2 THEN '2. 1-2 days over'
        WHEN dispatch_excess <= 5 THEN '3. 3-5 days over'
        ELSE                           '4. 6+ days over'
    END                                                       AS dispatch_band,
    COUNT(*)                                                  AS orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_orders,
    COUNTIF(is_late)                                          AS late_orders,
    ROUND(100 * COUNTIF(is_late) / COUNT(*), 1)               AS late_pct,
    ROUND(100 * COUNTIF(is_late)
          / SUM(COUNTIF(is_late)) OVER (), 1)                 AS pct_of_all_late,
    COUNTIF(shipment_count > 1)                               AS split_shipments
FROM `sahyadri_b2b.delivery_performance`
GROUP BY dispatch_band
ORDER BY dispatch_band;

-- -----------------------------------------------------------------------------
-- Step 6 · Lateness by shipment pattern and promise window
-- -----------------------------------------------------------------------------
SELECT
    IF(shipment_count > 1, 'Split shipment', 'Single shipment') AS shipment_pattern,
    promise_window,
    COUNT(*)                                                    AS orders,
    COUNTIF(is_late)                                            AS late_orders,
    ROUND(100 * COUNTIF(is_late) / COUNT(*), 1)                 AS late_pct,
    ROUND(AVG(dispatch_days), 1)                                AS avg_dispatch_days
FROM `sahyadri_b2b.delivery_performance`
GROUP BY shipment_pattern, promise_window
ORDER BY shipment_pattern, promise_window;

-- -----------------------------------------------------------------------------
-- Step 7 · Destinations: transit performance by standardised city
-- -----------------------------------------------------------------------------
SELECT
    delivery_city,
    COUNT(*)                                                  AS orders,
    ROUND(100 * COUNTIF(is_late) / COUNT(*), 1)               AS late_pct,
    ANY_VALUE(std_transit_days)                               AS median_transit_days,
    COUNTIF(primary_cause = 'Transit delay')                  AS late_due_to_transit,
    ROUND(100 * COUNTIF(primary_cause = 'Transit delay')
          / COUNT(*), 1)                                      AS transit_late_pct
FROM `sahyadri_b2b.delivery_performance`
GROUP BY delivery_city
HAVING COUNT(*) >= min_city_orders
ORDER BY transit_late_pct DESC, orders DESC;

-- -----------------------------------------------------------------------------
-- Step 8 · Salespeople: promise windows and promise-driven lateness
-- -----------------------------------------------------------------------------
SELECT
    p.employee_id,
    e.employee_name,
    e.designation,
    COUNT(*)                                                  AS orders,
    ROUND(AVG(p.promised_lead_days), 1)                       AS avg_promised_days,
    ROUND(100 * COUNTIF(p.promised_lead_days <= 7) / COUNT(*), 1)
                                                              AS pct_promised_7_days_or_less,
    ROUND(100 * COUNTIF(p.is_late) / COUNT(*), 1)             AS late_pct,
    ROUND(AVG(p.dispatch_days), 1)                            AS avg_dispatch_days,
    ROUND(AVG(p.transit_days), 1)                             AS avg_transit_days,
    COUNTIF(p.primary_cause = 'Promise shorter than normal lead time')
                                                              AS late_due_to_promise
FROM `sahyadri_b2b.delivery_performance` AS p
LEFT JOIN `sahyadri_b2b.employees`       AS e
    ON e.employee_id = p.employee_id
GROUP BY p.employee_id, e.employee_name, e.designation
ORDER BY late_due_to_promise DESC, late_pct DESC;
