/* =============================================================================
   Case study · Inventory pooling: how much extra safety stock a second
   dispatch hub would need, and which products it should stock
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The second dispatch hub study found that a hub in Kanpur would serve
   31 cities in the north and east and cut transit by about 1.2 days per
   shipment, but it assumed the hub would always have the stock. Splitting
   one warehouse's stock across two locations needs more safety stock in
   total, because each location must cover its own demand swings that
   used to partly cancel out. Before the board decides, the supply chain
   manager asks:
     1. How much more safety stock would two locations need than one, at
        the same service level?
     2. What would that cost to hold, against the freight the hub saves?
     3. Is the rise close to the textbook square-root law, or do the two
        regions' demands move together?
     4. Would stocking only the fast movers at the hub capture most of the
        service benefit for a fraction of the extra stock?

   METHOD AND ASSUMPTIONS
     - Demand: units ordered per product per week, valid orders (not
       Cancelled), 1 October 2024 - 28 September 2026: 104 seven-day weeks
       counted from 1 October 2024.
     - Region of an order: the city of its first shipment, served from the
       nearer of Mumbai (the main warehouse, as located in the hub study)
       and Kanpur by straight-line distance. Orders with no shipment or an
       unmapped city are left out.
     - Safety stock = z x sigma x SQRT(lead time), z = 1.645 (95 % cycle
       service level), replenishment lead time 2 weeks for both locations.
     - One location: sigma of total weekly demand. Two locations: sigma of
       each region's weekly demand, stocked separately.
     - Value at product unit cost; holding cost 20 % of value a year.
     - Hub range test: the hub stocks only its fastest movers (by hub
       units), the rest is shipped from Mumbai as today.
   ============================================================================= */

DECLARE demand_start  DATE    DEFAULT DATE '2024-10-01';
DECLARE n_weeks       INT64   DEFAULT 104;
DECLARE z_service     FLOAT64 DEFAULT 1.645;
DECLARE lead_weeks    FLOAT64 DEFAULT 2;
DECLARE holding_rate  FLOAT64 DEFAULT 0.20;

-- -----------------------------------------------------------------------------
-- Step 1 · Cities, the region each is served from, and weekly demand
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ip_cities` AS
SELECT 'ahmedabad' AS city_key, 23.03 AS lat, 72.58 AS lon
    UNION ALL SELECT 'aurangabad', 19.88, 75.34
    UNION ALL SELECT 'baddi', 30.96, 76.79
    UNION ALL SELECT 'bengaluru', 12.97, 77.59
    UNION ALL SELECT 'bhilai', 21.21, 81.38
    UNION ALL SELECT 'bhiwadi', 28.21, 76.86
    UNION ALL SELECT 'bhopal', 23.26, 77.41
    UNION ALL SELECT 'bhubaneswar', 20.30, 85.82
    UNION ALL SELECT 'chennai', 13.08, 80.27
    UNION ALL SELECT 'coimbatore', 11.02, 76.96
    UNION ALL SELECT 'dhanbad', 23.80, 86.43
    UNION ALL SELECT 'durgapur', 23.52, 87.31
    UNION ALL SELECT 'faridabad', 28.41, 77.32
    UNION ALL SELECT 'ghaziabad', 28.67, 77.45
    UNION ALL SELECT 'gurugram', 28.46, 77.03
    UNION ALL SELECT 'guwahati', 26.14, 91.74
    UNION ALL SELECT 'haridwar', 29.95, 78.16
    UNION ALL SELECT 'hosur', 12.74, 77.83
    UNION ALL SELECT 'howrah', 22.59, 88.26
    UNION ALL SELECT 'hubballi', 15.36, 75.12
    UNION ALL SELECT 'hyderabad', 17.39, 78.49
    UNION ALL SELECT 'indore', 22.72, 75.86
    UNION ALL SELECT 'jaipur', 26.91, 75.79
    UNION ALL SELECT 'jalandhar', 31.33, 75.58
    UNION ALL SELECT 'jamshedpur', 22.80, 86.20
    UNION ALL SELECT 'jodhpur', 26.24, 73.02
    UNION ALL SELECT 'kanpur', 26.45, 80.33
    UNION ALL SELECT 'kochi', 9.93, 76.27
    UNION ALL SELECT 'kolkata', 22.57, 88.36
    UNION ALL SELECT 'lucknow', 26.85, 80.95
    UNION ALL SELECT 'ludhiana', 30.90, 75.86
    UNION ALL SELECT 'madurai', 9.93, 78.12
    UNION ALL SELECT 'margao', 15.27, 73.96
    UNION ALL SELECT 'mumbai', 19.08, 72.88
    UNION ALL SELECT 'mysuru', 12.30, 76.64
    UNION ALL SELECT 'nagpur', 21.15, 79.09
    UNION ALL SELECT 'nashik', 20.00, 73.79
    UNION ALL SELECT 'new delhi', 28.61, 77.21
    UNION ALL SELECT 'noida', 28.54, 77.39
    UNION ALL SELECT 'panipat', 29.39, 76.97
    UNION ALL SELECT 'patna', 25.59, 85.14
    UNION ALL SELECT 'pithampur', 22.61, 75.68
    UNION ALL SELECT 'pune', 18.52, 73.86
    UNION ALL SELECT 'raipur', 21.25, 81.63
    UNION ALL SELECT 'rajkot', 22.30, 70.80
    UNION ALL SELECT 'ranchi', 23.34, 85.31
    UNION ALL SELECT 'rourkela', 22.26, 84.85
    UNION ALL SELECT 'rudrapur', 28.98, 79.40
    UNION ALL SELECT 'surat', 21.17, 72.83
    UNION ALL SELECT 'vadodara', 22.31, 73.18
    UNION ALL SELECT 'visakhapatnam', 17.69, 83.22;

CREATE OR REPLACE TABLE `sahyadri_b2b.ip_regions` AS
WITH distance AS (
    SELECT c.city_key,
           2 * 6371 * ASIN(SQRT(POW(SIN((m.lat - c.lat) * ACOS(-1) / 360), 2)
               + COS(c.lat * ACOS(-1) / 180) * COS(m.lat * ACOS(-1) / 180) * POW(SIN((m.lon - c.lon) * ACOS(-1) / 360), 2))) AS km_mumbai,
           2 * 6371 * ASIN(SQRT(POW(SIN((k.lat - c.lat) * ACOS(-1) / 360), 2)
               + COS(c.lat * ACOS(-1) / 180) * COS(k.lat * ACOS(-1) / 180) * POW(SIN((k.lon - c.lon) * ACOS(-1) / 360), 2))) AS km_kanpur
    FROM `sahyadri_b2b.ip_cities` AS c
    CROSS JOIN (SELECT lat, lon FROM `sahyadri_b2b.ip_cities` WHERE city_key = 'mumbai') AS m
    CROSS JOIN (SELECT lat, lon FROM `sahyadri_b2b.ip_cities` WHERE city_key = 'kanpur') AS k
)
SELECT city_key, km_mumbai, km_kanpur,
       IF(km_kanpur < km_mumbai, 'Kanpur hub', 'Mumbai')                               AS region
FROM distance;

CREATE OR REPLACE TABLE `sahyadri_b2b.ip_order_lines` AS
WITH city_alias AS (
    -- the same alias list as the ship-to / bill-to reconciliation
    SELECT 'ahmadabad' AS raw_key, 'ahmedabad' AS city_key UNION ALL SELECT 'bangalore', 'bengaluru' UNION ALL
    SELECT 'baroda', 'vadodara' UNION ALL SELECT 'bombay', 'mumbai' UNION ALL SELECT 'calcutta', 'kolkata' UNION ALL
    SELECT 'delhi', 'new delhi' UNION ALL SELECT 'gurgaon', 'gurugram' UNION ALL SELECT 'madras', 'chennai' UNION ALL
    SELECT 'mysore', 'mysuru' UNION ALL SELECT 'vizag', 'visakhapatnam'
),
first_city AS (
    SELECT order_id, ARRAY_AGG(shipping_city ORDER BY shipment_date, shipment_id LIMIT 1)[OFFSET(0)] AS shipping_city
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
)
SELECT o.order_id, o.order_date, i.product_id, i.quantity,
       CAST(FLOOR(DATE_DIFF(o.order_date, demand_start, DAY) / 7) AS INT64)           AS week_index,
       r.region
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
JOIN first_city AS f ON f.order_id = o.order_id
LEFT JOIN city_alias AS a ON a.raw_key = LOWER(TRIM(f.shipping_city))
JOIN `sahyadri_b2b.ip_regions` AS r ON r.city_key = IFNULL(a.city_key, LOWER(TRIM(f.shipping_city)))
WHERE o.order_status != 'Cancelled'
  AND o.order_date >= demand_start
  AND DATE_DIFF(o.order_date, demand_start, DAY) < 7 * n_weeks;

-- Weekly units per product and region, with zero weeks filled in
CREATE OR REPLACE TABLE `sahyadri_b2b.ip_weekly` AS
WITH grid AS (
    SELECT p.product_id, w AS week_index
    FROM (SELECT DISTINCT product_id FROM `sahyadri_b2b.ip_order_lines`) AS p
    CROSS JOIN UNNEST(GENERATE_ARRAY(0, n_weeks - 1)) AS w
)
SELECT g.product_id, g.week_index,
       IFNULL(SUM(IF(l.region = 'Mumbai', l.quantity, 0)), 0)                         AS units_mumbai,
       IFNULL(SUM(IF(l.region = 'Kanpur hub', l.quantity, 0)), 0)                     AS units_hub
FROM grid AS g
LEFT JOIN `sahyadri_b2b.ip_order_lines` AS l ON l.product_id = g.product_id AND l.week_index = g.week_index
GROUP BY g.product_id, g.week_index;

-- Per product: demand, variability, correlation and safety stock for one and two locations
CREATE OR REPLACE TABLE `sahyadri_b2b.ip_products` AS
WITH stats AS (
    SELECT product_id,
           SUM(units_mumbai)                                                          AS units_mumbai,
           SUM(units_hub)                                                             AS units_hub,
           STDDEV_SAMP(units_mumbai)                                                  AS sd_mumbai,
           STDDEV_SAMP(units_hub)                                                     AS sd_hub,
           STDDEV_SAMP(units_mumbai + units_hub)                                      AS sd_total,
           CORR(units_mumbai, units_hub)                                              AS correlation
    FROM `sahyadri_b2b.ip_weekly`
    GROUP BY product_id
)
SELECT s.*, p.product_name, c.category_name, p.unit_cost,
       z_service * s.sd_total * SQRT(lead_weeks)                                      AS ss_one_location,
       z_service * s.sd_mumbai * SQRT(lead_weeks)                                     AS ss_mumbai,
       z_service * s.sd_hub * SQRT(lead_weeks)                                        AS ss_hub,
       z_service * (s.sd_mumbai + s.sd_hub) * SQRT(lead_weeks)                        AS ss_two_locations
FROM stats AS s
JOIN `sahyadri_b2b.products` AS p ON p.product_id = s.product_id
JOIN `sahyadri_b2b.product_categories` AS c ON c.category_id = p.category_id;

-- -----------------------------------------------------------------------------
-- Step 2 · One location against two
-- -----------------------------------------------------------------------------
SELECT
    region, COUNT(*) AS cities
FROM `sahyadri_b2b.ip_regions`
GROUP BY region
ORDER BY region;

SELECT
    COUNT(*)                                                                          AS products,
    COUNTIF(unit_cost IS NULL)                                                        AS products_without_cost,
    ROUND(100 * SUM(units_hub) / SUM(units_mumbai + units_hub), 1)                    AS hub_share_of_units_pct,
    ROUND(SUM(ss_one_location * unit_cost) / 1e5, 2)                                  AS safety_stock_one_location_lakh,
    ROUND(SUM(ss_two_locations * unit_cost) / 1e5, 2)                                 AS safety_stock_two_locations_lakh,
    ROUND(SUM((ss_two_locations - ss_one_location) * unit_cost) / 1e5, 2)             AS extra_safety_stock_lakh,
    ROUND(100 * (SUM(ss_two_locations * unit_cost) / SUM(ss_one_location * unit_cost) - 1), 1) AS increase_pct,
    ROUND(holding_rate * SUM((ss_two_locations - ss_one_location) * unit_cost) / 1e5, 2) AS extra_holding_cost_per_year_lakh
FROM `sahyadri_b2b.ip_products`
WHERE unit_cost IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Step 3 · Square-root law against the actual correlation
-- -----------------------------------------------------------------------------
SELECT
    ROUND(AVG(correlation), 3)                                                        AS average_correlation,
    ROUND(APPROX_QUANTILES(correlation, 4)[OFFSET(1)], 3)                             AS correlation_q1,
    ROUND(APPROX_QUANTILES(correlation, 4)[OFFSET(3)], 3)                             AS correlation_q3,
    -- with independent regions the ratio would be (sd1 + sd2) / SQRT(sd1^2 + sd2^2)
    ROUND(SUM(ss_two_locations * unit_cost)
          / SUM(z_service * SQRT(POW(sd_mumbai, 2) + POW(sd_hub, 2)) * SQRT(lead_weeks) * unit_cost), 3) AS ratio_vs_independent_pooling,
    ROUND(SUM(ss_two_locations * unit_cost) / SUM(ss_one_location * unit_cost), 3)    AS ratio_actual
FROM `sahyadri_b2b.ip_products`
WHERE unit_cost IS NOT NULL;

SELECT
    category_name,
    COUNT(*)                                                                          AS products,
    ROUND(100 * SUM(units_hub) / SUM(units_mumbai + units_hub), 1)                    AS hub_share_pct,
    ROUND(SUM(ss_one_location * unit_cost) / 1e5, 2)                                  AS one_location_lakh,
    ROUND(SUM(ss_two_locations * unit_cost) / 1e5, 2)                                 AS two_locations_lakh,
    ROUND(100 * (SUM(ss_two_locations * unit_cost) / SUM(ss_one_location * unit_cost) - 1), 1) AS increase_pct
FROM `sahyadri_b2b.ip_products`
WHERE unit_cost IS NOT NULL
GROUP BY category_name
ORDER BY increase_pct DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Stock only the fast movers at the hub
-- -----------------------------------------------------------------------------
WITH ranked AS (
    SELECT p.*,
           ROW_NUMBER() OVER (ORDER BY units_hub DESC, product_id)                     AS hub_rank,
           SUM(units_hub) OVER (ORDER BY units_hub DESC, product_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(units_hub) OVER ()                                                 AS cumulative_hub_share
    FROM `sahyadri_b2b.ip_products` AS p
    WHERE unit_cost IS NOT NULL
),
ranges AS (
    SELECT n AS products_at_hub FROM UNNEST([10, 20, 40, 60, 100, 150]) AS n
)
SELECT
    g.products_at_hub,
    ROUND(100 * MAX(IF(r.hub_rank = g.products_at_hub, r.cumulative_hub_share, NULL)), 1) AS hub_units_covered_pct,
    -- stocked at the hub: two locations; not stocked: pooled at Mumbai as today
    ROUND(SUM(IF(r.hub_rank <= g.products_at_hub, r.ss_two_locations, r.ss_one_location) * r.unit_cost) / 1e5, 2) AS safety_stock_lakh,
    ROUND(SUM(IF(r.hub_rank <= g.products_at_hub, r.ss_two_locations - r.ss_one_location, 0) * r.unit_cost) / 1e5, 2) AS extra_safety_stock_lakh,
    ROUND(holding_rate * SUM(IF(r.hub_rank <= g.products_at_hub, r.ss_two_locations - r.ss_one_location, 0) * r.unit_cost) / 1e5, 2) AS extra_holding_cost_per_year_lakh
FROM ranges AS g
CROSS JOIN ranked AS r
GROUP BY g.products_at_hub
ORDER BY g.products_at_hub;
