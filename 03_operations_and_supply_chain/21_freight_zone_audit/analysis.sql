/* =============================================================================
   Case study · Freight zone audit: does the carrier's zone map match distance?
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The carrier contract is up for renewal. The freight invoice audit showed
   that charges follow a card: a fixed charge per destination plus a share
   of the consignment value, applied consistently. Procurement now wants to
   know whether the card itself is fair before negotiating:
     1. What zones does the card use, and what does each zone charge?
     2. Do the zones follow distance from the warehouse?
     3. Which destinations are charged well above what their distance
        would suggest?
     4. Where is the money in the freight bill, and what is each
        negotiating lever worth?

   METHOD
     - Shipments January 2024 - September 2026 with a recorded cost, city
       names standardised (case, spacing and the usual aliases). Shipment
       value = order value / shipments of the order. Consignments of Rs 20
       lakh or more are left out of the fit (the card caps their charge).
     - Card: cost = fixed charge of the destination + r x value. r is the
       within-city slope of cost on value (one rate for all cities); a
       city's fixed charge = average of (cost - r x value).
     - Zones: cities sorted by fixed charge; a new zone starts wherever the
       next city is Rs 50 or more dearer than the previous one.
     - Distance: straight-line (haversine) km from Mumbai, the origin found
       in the second-hub study.
     - Distance benchmark: least squares of city fixed charge on km,
       weighted by shipments. Flagged lane: fixed charge at least 15 % and
       Rs 100 above the benchmark.
     - Bill and levers: latest 12 months (October 2025 - September 2026).
   ============================================================================= */

DECLARE first_day     DATE    DEFAULT DATE '2024-01-01';
DECLARE last_day      DATE    DEFAULT DATE '2026-09-30';
DECLARE recent_start  DATE    DEFAULT DATE '2025-10-01';
DECLARE value_cap     FLOAT64 DEFAULT 2000000;
DECLARE zone_gap      FLOAT64 DEFAULT 50;
DECLARE flag_share    FLOAT64 DEFAULT 0.15;
DECLARE flag_rupees   FLOAT64 DEFAULT 100;

-- -----------------------------------------------------------------------------
-- Step 1 · Shipments, distances and the card
-- -----------------------------------------------------------------------------
-- Approximate city-centre coordinates (the same table as the second-hub study)
CREATE OR REPLACE TABLE `sahyadri_b2b.fz_cities` AS
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

CREATE OR REPLACE TABLE `sahyadri_b2b.fz_shipments` AS
WITH city_alias AS (
    SELECT 'ahmadabad' AS raw_key, 'ahmedabad' AS city_key UNION ALL SELECT 'bangalore', 'bengaluru' UNION ALL
    SELECT 'baroda', 'vadodara' UNION ALL SELECT 'bombay', 'mumbai' UNION ALL SELECT 'calcutta', 'kolkata' UNION ALL
    SELECT 'delhi', 'new delhi' UNION ALL SELECT 'gurgaon', 'gurugram' UNION ALL SELECT 'madras', 'chennai' UNION ALL
    SELECT 'mysore', 'mysuru' UNION ALL SELECT 'vizag', 'visakhapatnam'
),
order_value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS value
    FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id
),
per_order AS (
    SELECT order_id, COUNT(*) AS shipments FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
origin AS (
    SELECT lat, lon FROM `sahyadri_b2b.fz_cities` WHERE city_key = 'mumbai'
)
SELECT
    s.shipment_id, s.order_id, s.shipment_date, s.shipping_cost,
    IFNULL(a.city_key, LOWER(TRIM(s.shipping_city)))                                  AS city_key,
    v.value / p.shipments                                                             AS shipment_value,
    2 * 6371 * ASIN(SQRT(
        POW(SIN((c.lat - o.lat) * ACOS(-1) / 360), 2)
        + COS(o.lat * ACOS(-1) / 180) * COS(c.lat * ACOS(-1) / 180) * POW(SIN((c.lon - o.lon) * ACOS(-1) / 360), 2))) AS km
FROM `sahyadri_b2b.shipments` AS s
LEFT JOIN city_alias AS a ON a.raw_key = LOWER(TRIM(s.shipping_city))
JOIN order_value AS v ON v.order_id = s.order_id
JOIN per_order AS p ON p.order_id = s.order_id
LEFT JOIN `sahyadri_b2b.fz_cities` AS c ON c.city_key = IFNULL(a.city_key, LOWER(TRIM(s.shipping_city)))
CROSS JOIN origin AS o
WHERE s.shipment_date BETWEEN first_day AND last_day;

-- One value rate for all cities: the within-city slope of cost on value
CREATE OR REPLACE TABLE `sahyadri_b2b.fz_rate` AS
WITH fit AS (
    SELECT * FROM `sahyadri_b2b.fz_shipments` WHERE shipping_cost IS NOT NULL AND shipment_value < value_cap
),
centred AS (
    SELECT shipping_cost - AVG(shipping_cost) OVER (PARTITION BY city_key)            AS dc,
           shipment_value - AVG(shipment_value) OVER (PARTITION BY city_key)          AS dv
    FROM fit
)
SELECT SUM(dc * dv) / SUM(dv * dv) AS value_rate, COUNT(*) AS shipments
FROM centred;

-- Lanes: fixed charge (whole period and each half), distance, zone, benchmark
CREATE OR REPLACE TABLE `sahyadri_b2b.fz_lanes` AS
WITH fit AS (
    SELECT s.*, s.shipping_cost - r.value_rate * s.shipment_value AS fixed_part
    FROM `sahyadri_b2b.fz_shipments` AS s CROSS JOIN `sahyadri_b2b.fz_rate` AS r
    WHERE s.shipping_cost IS NOT NULL AND s.shipment_value < value_cap
),
lanes AS (
    SELECT city_key, ANY_VALUE(km) AS km, COUNT(*) AS shipments,
           AVG(fixed_part)                                                            AS fixed_charge,
           AVG(IF(shipment_date < DATE '2025-05-16', fixed_part, NULL))               AS fixed_first_half,
           AVG(IF(shipment_date >= DATE '2025-05-16', fixed_part, NULL))              AS fixed_second_half,
           STDDEV_POP(fixed_part)                                                     AS spread
    FROM fit GROUP BY city_key
),
gaps AS (
    SELECT *, IF(fixed_charge - LAG(fixed_charge) OVER (ORDER BY fixed_charge) >= zone_gap, 1, 0) AS new_zone
    FROM lanes
),
zoned AS (
    SELECT *, 1 + SUM(new_zone) OVER (ORDER BY fixed_charge ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS zone
    FROM gaps
),
benchmark AS (
    -- weighted least squares of fixed charge on km (weights = shipments)
    SELECT (SUM(shipments * km * fixed_charge) / SUM(shipments) - (SUM(shipments * km) / SUM(shipments)) * (SUM(shipments * fixed_charge) / SUM(shipments)))
           / (SUM(shipments * km * km) / SUM(shipments) - POW(SUM(shipments * km) / SUM(shipments), 2)) AS per_km,
           SUM(shipments * km) / SUM(shipments)                                       AS mean_km,
           SUM(shipments * fixed_charge) / SUM(shipments)                             AS mean_fixed
    FROM lanes
)
SELECT z.city_key, z.km, z.shipments, z.fixed_charge, z.fixed_first_half, z.fixed_second_half, z.spread, z.zone,
       b.mean_fixed + b.per_km * (z.km - b.mean_km)                                   AS benchmark,
       z.fixed_charge - (b.mean_fixed + b.per_km * (z.km - b.mean_km))                AS premium
FROM zoned AS z CROSS JOIN benchmark AS b;

SELECT
    ROUND(100 * ANY_VALUE(r.value_rate), 3)                                           AS value_rate_pct,
    ANY_VALUE(r.shipments)                                                            AS shipments_in_fit,
    COUNT(*)                                                                          AS destinations,
    ROUND(CORR(l.fixed_first_half, l.fixed_second_half), 3)                           AS fixed_charge_corr_between_halves,
    ROUND(MAX(ABS(l.fixed_first_half - l.fixed_second_half)), 0)                      AS largest_change_between_halves
FROM `sahyadri_b2b.fz_lanes` AS l CROSS JOIN `sahyadri_b2b.fz_rate` AS r;

-- How well the card explains each shipment's charge
SELECT
    COUNT(*)                                                                          AS shipments,
    ROUND(1 - SUM(POW(s.shipping_cost - l.fixed_charge - r.value_rate * s.shipment_value, 2))
            / SUM(POW(s.shipping_cost - avg_cost, 2)), 3)                             AS r_squared,
    ROUND(APPROX_QUANTILES(ABS(s.shipping_cost - l.fixed_charge - r.value_rate * s.shipment_value), 100)[OFFSET(50)], 0) AS median_abs_error_rupees
FROM `sahyadri_b2b.fz_shipments` AS s
JOIN `sahyadri_b2b.fz_lanes` AS l USING (city_key)
CROSS JOIN `sahyadri_b2b.fz_rate` AS r
CROSS JOIN (SELECT AVG(shipping_cost) AS avg_cost FROM `sahyadri_b2b.fz_shipments` WHERE shipping_cost IS NOT NULL AND shipment_value < value_cap) AS m
WHERE s.shipping_cost IS NOT NULL AND s.shipment_value < value_cap;

-- -----------------------------------------------------------------------------
-- Step 2 · The zones
-- -----------------------------------------------------------------------------
SELECT
    zone,
    COUNT(*)                                                                          AS cities,
    SUM(shipments)                                                                    AS shipments,
    ROUND(SUM(shipments * fixed_charge) / SUM(shipments), 0)                          AS fixed_charge,
    ROUND(MIN(fixed_charge), 0)                                                       AS lowest_city,
    ROUND(MAX(fixed_charge), 0)                                                       AS highest_city,
    ROUND(MIN(km), 0)                                                                 AS nearest_km,
    ROUND(MAX(km), 0)                                                                 AS farthest_km,
    STRING_AGG(city_key, ', ' ORDER BY km)                                            AS cities_by_distance
FROM `sahyadri_b2b.fz_lanes`
GROUP BY zone
ORDER BY zone;

-- -----------------------------------------------------------------------------
-- Step 3 · Lanes against distance
-- -----------------------------------------------------------------------------
SELECT
    ROUND(ANY_VALUE(mean_fixed - per_km * mean_km), 0)                                AS benchmark_at_0_km,
    ROUND(100 * ANY_VALUE(per_km), 1)                                                 AS benchmark_per_100_km,
    ROUND(POW(CORR(km, fixed_charge), 2), 3)                                          AS r_squared_unweighted
FROM `sahyadri_b2b.fz_lanes`
CROSS JOIN (
    SELECT (SUM(shipments * km * fixed_charge) / SUM(shipments) - (SUM(shipments * km) / SUM(shipments)) * (SUM(shipments * fixed_charge) / SUM(shipments)))
           / (SUM(shipments * km * km) / SUM(shipments) - POW(SUM(shipments * km) / SUM(shipments), 2)) AS per_km,
           SUM(shipments * km) / SUM(shipments) AS mean_km, SUM(shipments * fixed_charge) / SUM(shipments) AS mean_fixed
    FROM `sahyadri_b2b.fz_lanes`
);

-- Flagged lanes and the most under-priced lanes, with the premium paid in the latest 12 months
WITH recent AS (
    SELECT city_key, COUNT(*) AS recent_shipments
    FROM `sahyadri_b2b.fz_shipments`
    WHERE shipment_date >= recent_start AND shipping_cost IS NOT NULL
    GROUP BY city_key
)
SELECT
    l.city_key, l.zone, ROUND(l.km, 0) AS km, l.shipments,
    ROUND(l.fixed_charge, 0) AS fixed_charge, ROUND(l.benchmark, 0) AS benchmark,
    ROUND(l.premium, 0) AS premium_rupees, ROUND(100 * l.premium / l.benchmark, 1) AS premium_pct,
    l.premium >= flag_share * l.benchmark AND l.premium >= flag_rupees                AS flagged,
    IFNULL(r.recent_shipments, 0)                                                     AS shipments_last_12_months,
    ROUND(IFNULL(r.recent_shipments, 0) * l.premium, 0)                               AS premium_last_12_months
FROM `sahyadri_b2b.fz_lanes` AS l
LEFT JOIN recent AS r USING (city_key)
WHERE l.premium >= flag_share * l.benchmark AND l.premium >= flag_rupees
   OR l.premium <= -flag_share * l.benchmark
ORDER BY premium_pct DESC;

-- Lanes charged Rs 100 or more above a farther lane (both with 30+ shipments): the cheapest farther lane for each
WITH pairs AS (
    SELECT near.city_key AS city, near.zone, near.km, near.fixed_charge,
           far.city_key AS farther_city, far.zone AS farther_zone, far.km AS farther_km, far.fixed_charge AS farther_charge,
           ROW_NUMBER() OVER (PARTITION BY near.city_key ORDER BY far.fixed_charge, far.km)  AS rk,
           COUNT(*) OVER (PARTITION BY near.city_key)                                 AS farther_cheaper_lanes
    FROM `sahyadri_b2b.fz_lanes` AS near
    JOIN `sahyadri_b2b.fz_lanes` AS far ON far.km > near.km
    WHERE near.shipments >= 30 AND far.shipments >= 30
      AND far.fixed_charge <= near.fixed_charge - 100
)
SELECT city, zone, ROUND(km, 0) AS km, ROUND(fixed_charge, 0) AS fixed_charge, farther_cheaper_lanes,
       farther_city AS cheapest_farther_lane, farther_zone, ROUND(farther_km, 0) AS farther_km, ROUND(farther_charge, 0) AS farther_charge
FROM pairs
WHERE rk = 1
ORDER BY fixed_charge - farther_charge DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · The freight bill and what each lever is worth (latest 12 months)
-- -----------------------------------------------------------------------------
WITH recent AS (
    SELECT s.*, l.fixed_charge, l.benchmark, l.premium, l.zone, r.value_rate,
           l.premium >= flag_share * l.benchmark AND l.premium >= flag_rupees          AS flagged
    FROM `sahyadri_b2b.fz_shipments` AS s
    JOIN `sahyadri_b2b.fz_lanes` AS l USING (city_key)
    CROSS JOIN `sahyadri_b2b.fz_rate` AS r
    WHERE s.shipment_date >= recent_start AND s.shipping_cost IS NOT NULL
)
SELECT
    COUNT(*)                                                                          AS shipments,
    ROUND(SUM(shipping_cost) / 1e5, 2)                                                AS freight_lakh,
    ROUND(100 * SUM(shipping_cost) / SUM(shipment_value), 2)                          AS freight_pct_of_value,
    -- fixed part = the lane's fixed charge; the rest of each charge is the value-based part
    ROUND(100 * SUM(fixed_charge) / SUM(shipping_cost), 1)                            AS fixed_charges_pct,
    ROUND(100 * SUM(shipping_cost - fixed_charge) / SUM(shipping_cost), 1)            AS value_charges_pct,
    ROUND(SUM(IF(flagged, premium, 0)) / 1e5, 2)                                      AS lever_flagged_lanes_to_benchmark_lakh,
    ROUND(SUM(fixed_charge) * 0.05 / 1e5, 2)                                          AS lever_5pct_off_all_fixed_lakh,
    ROUND(SUM(IF(shipment_value < value_cap, 0.001 * shipment_value, 0)) / 1e5, 2)    AS lever_value_rate_down_0_1_point_lakh
FROM recent;

-- The bill by zone
SELECT
    l.zone,
    COUNT(*)                                                                          AS shipments,
    ROUND(SUM(s.shipping_cost) / 1e5, 2)                                              AS freight_lakh,
    ROUND(100 * SUM(s.shipping_cost) / SUM(SUM(s.shipping_cost)) OVER (), 1)          AS share_of_bill_pct,
    ROUND(AVG(s.shipping_cost), 0)                                                    AS average_charge
FROM `sahyadri_b2b.fz_shipments` AS s
JOIN `sahyadri_b2b.fz_lanes` AS l USING (city_key)
WHERE s.shipment_date >= recent_start AND s.shipping_cost IS NOT NULL
GROUP BY l.zone
ORDER BY l.zone;
