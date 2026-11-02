/* =============================================================================
   Case study · A second dispatch hub: where would it cut delivery times most?
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Every order ships from one warehouse. Customers in the north and east
   wait five to seven days in transit, and the promise-date studies show
   transit is the part of the delay dispatch cannot fix. The board is
   considering a second dispatch point and asks:
     1. Where does the warehouse ship from, judging by the data, and how do
        transit time and freight grow with distance?
     2. Which city would cut transit days the most as a second hub?
     3. What would it save in freight, and how many late deliveries would
        it have prevented last year?
     4. What should a hub cost at most to pay for itself in freight alone?

   METHOD
     - Shipments dispatched 1 Oct 2025 - 30 Sep 2026, city names
       standardised (case, spacing and aliases such as Bombay -> Mumbai).
     - Approximate city coordinates (latitude and longitude of each city
       centre) in an inline table; straight-line distance by the haversine
       formula.
     - Origin: the shipping city whose distance best explains transit days
       (highest R-squared across all cities as candidate origins).
     - Transit curve: average transit days by 250 km distance band from
       the origin, made non-decreasing (a running maximum).
     - Freight model: least squares of shipping cost on distance and
       shipment value.
     - Scenario for each candidate hub city H: every destination is served
       from the nearer of origin and H. Predicted transit from either point
       uses the same curve, so the saving is curve(origin distance) -
       curve(hub distance). Freight saving = per-km rate x km saved.
     - Late deliveries prevented: each delivered order's actual delivery
       date moved earlier by its predicted saving, against its promise.
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE band_km      FLOAT64 DEFAULT 250;

-- -----------------------------------------------------------------------------
-- Step 1 · Cities and shipments
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.hb_cities` AS
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

CREATE OR REPLACE TABLE `sahyadri_b2b.hb_shipments` AS
WITH city_alias AS (
    -- the same alias list as the ship-to / bill-to reconciliation
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
)
SELECT
    s.shipment_id, s.order_id, s.shipment_date, s.delivery_date, s.shipping_cost,
    IFNULL(a.city_key, LOWER(TRIM(s.shipping_city)))                                  AS city_key,
    DATE_DIFF(s.delivery_date, s.shipment_date, DAY)                                  AS transit_days,
    v.value / p.shipments                                                             AS shipment_value
FROM `sahyadri_b2b.shipments` AS s
LEFT JOIN city_alias AS a ON a.raw_key = LOWER(TRIM(s.shipping_city))
JOIN order_value AS v ON v.order_id = s.order_id
JOIN per_order AS p ON p.order_id = s.order_id
WHERE s.shipment_date BETWEEN window_start AND window_end;

-- Every city pair with its straight-line distance (haversine, km)
CREATE OR REPLACE TABLE `sahyadri_b2b.hb_distances` AS
SELECT
    a.city_key AS from_city, b.city_key AS to_city,
    2 * 6371 * ASIN(SQRT(
        POW(SIN((b.lat - a.lat) * ACOS(-1) / 360), 2)
        + COS(a.lat * ACOS(-1) / 180) * COS(b.lat * ACOS(-1) / 180) * POW(SIN((b.lon - a.lon) * ACOS(-1) / 360), 2))) AS km
FROM `sahyadri_b2b.hb_cities` AS a
CROSS JOIN `sahyadri_b2b.hb_cities` AS b;

-- -----------------------------------------------------------------------------
-- Step 2 · Where is the warehouse? Distance from each candidate origin against transit
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.hb_origin_fit` AS
SELECT d.from_city AS candidate_origin,
       POW(CORR(d.km, s.transit_days), 2)                                             AS r_squared,
       COUNT(*)                                                                       AS shipments
FROM `sahyadri_b2b.hb_shipments` AS s
JOIN `sahyadri_b2b.hb_distances` AS d ON d.to_city = s.city_key
WHERE s.transit_days IS NOT NULL
GROUP BY d.from_city;

SELECT candidate_origin, ROUND(r_squared, 3) AS r_squared, shipments
FROM `sahyadri_b2b.hb_origin_fit`
ORDER BY r_squared DESC
LIMIT 5;

-- Transit curve by distance band from the origin, and the freight model
CREATE OR REPLACE TABLE `sahyadri_b2b.hb_curve` AS
WITH origin AS (
    SELECT candidate_origin AS city_key FROM `sahyadri_b2b.hb_origin_fit` ORDER BY r_squared DESC LIMIT 1
),
banded AS (
    SELECT CAST(FLOOR(d.km / band_km) AS INT64) AS band, s.transit_days
    FROM `sahyadri_b2b.hb_shipments` AS s
    JOIN `sahyadri_b2b.hb_distances` AS d ON d.to_city = s.city_key
    JOIN origin AS o ON o.city_key = d.from_city
    WHERE s.transit_days IS NOT NULL
),
bands AS (
    SELECT band FROM UNNEST(GENERATE_ARRAY(0, 12)) AS band
),
observed AS (
    SELECT band, AVG(transit_days) AS avg_transit, COUNT(*) AS shipments FROM banded GROUP BY band
)
SELECT
    b.band,
    b.band * band_km                                                                  AS from_km,
    o.shipments,
    o.avg_transit,
    -- non-decreasing curve: a nearer band is never slower than a farther one
    MAX(o.avg_transit) OVER (ORDER BY b.band ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS curve_transit
FROM bands AS b
LEFT JOIN observed AS o ON o.band = b.band;

SELECT band, from_km, shipments, ROUND(avg_transit, 2) AS avg_transit_days, ROUND(curve_transit, 2) AS curve_transit_days
FROM `sahyadri_b2b.hb_curve`
WHERE shipments IS NOT NULL
ORDER BY band;

CREATE OR REPLACE TABLE `sahyadri_b2b.hb_freight_model` AS
WITH origin AS (
    SELECT candidate_origin AS city_key FROM `sahyadri_b2b.hb_origin_fit` ORDER BY r_squared DESC LIMIT 1
),
x AS (
    SELECT s.shipping_cost AS y, d.km / 100 AS x1, s.shipment_value / 1e5 AS x2
    FROM `sahyadri_b2b.hb_shipments` AS s
    JOIN `sahyadri_b2b.hb_distances` AS d ON d.to_city = s.city_key
    JOIN origin AS o ON o.city_key = d.from_city
    WHERE s.shipping_cost IS NOT NULL
),
moments AS (
    SELECT COVAR_POP(x1, y) AS s1y, COVAR_POP(x2, y) AS s2y, VAR_POP(x1) AS s11, VAR_POP(x2) AS s22, COVAR_POP(x1, x2) AS s12,
           AVG(y) AS my, AVG(x1) AS m1, AVG(x2) AS m2, VAR_POP(y) AS syy, COUNT(*) AS n
    FROM x
)
SELECT
    (s1y * s22 - s2y * s12) / (s11 * s22 - s12 * s12)                                 AS per_100km,
    (s2y * s11 - s1y * s12) / (s11 * s22 - s12 * s12)                                 AS per_lakh_value,
    my - m1 * (s1y * s22 - s2y * s12) / (s11 * s22 - s12 * s12)
       - m2 * (s2y * s11 - s1y * s12) / (s11 * s22 - s12 * s12)                       AS intercept,
    n
FROM moments;

SELECT ROUND(intercept, 0) AS fixed_per_shipment, ROUND(per_100km, 1) AS per_100_km, ROUND(per_lakh_value, 0) AS per_lakh_of_value, n AS shipments
FROM `sahyadri_b2b.hb_freight_model`;

-- -----------------------------------------------------------------------------
-- Step 3 · Every city as a candidate second hub
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.hb_scenarios` AS
WITH origin AS (
    SELECT candidate_origin AS city_key FROM `sahyadri_b2b.hb_origin_fit` ORDER BY r_squared DESC LIMIT 1
),
legs AS (
    SELECT s.shipment_id, s.order_id, s.city_key, s.shipping_cost, h.city_key AS hub,
           d0.km AS km_origin, dh.km AS km_hub,
           LEAST(d0.km, dh.km)                                                        AS km_served
    FROM `sahyadri_b2b.hb_shipments` AS s
    CROSS JOIN `sahyadri_b2b.hb_cities` AS h
    CROSS JOIN origin AS o
    JOIN `sahyadri_b2b.hb_distances` AS d0 ON d0.from_city = o.city_key AND d0.to_city = s.city_key
    JOIN `sahyadri_b2b.hb_distances` AS dh ON dh.from_city = h.city_key AND dh.to_city = s.city_key
    WHERE h.city_key != o.city_key
)
SELECT
    l.*,
    l.km_hub < l.km_origin                                                            AS served_by_hub,
    c0.curve_transit                                                                  AS transit_origin,
    c1.curve_transit                                                                  AS transit_served,
    c0.curve_transit - c1.curve_transit                                               AS days_saved,
    f.per_100km * (l.km_origin - l.km_served) / 100                                   AS freight_saved
FROM legs AS l
JOIN `sahyadri_b2b.hb_curve` AS c0 ON c0.band = CAST(FLOOR(l.km_origin / band_km) AS INT64)
JOIN `sahyadri_b2b.hb_curve` AS c1 ON c1.band = CAST(FLOOR(l.km_served / band_km) AS INT64)
CROSS JOIN `sahyadri_b2b.hb_freight_model` AS f;

SELECT
    hub,
    COUNT(*)                                                                          AS shipments,
    COUNTIF(served_by_hub)                                                            AS served_by_hub,
    ROUND(100 * COUNTIF(served_by_hub) / COUNT(*), 1)                                 AS share_served_pct,
    ROUND(AVG(transit_origin), 2)                                                     AS transit_today_model,
    ROUND(AVG(transit_served), 2)                                                     AS transit_with_hub,
    ROUND(SUM(days_saved), 0)                                                         AS transit_days_saved,
    ROUND(SUM(freight_saved) / 1e5, 1)                                                AS freight_saved_lakh,
    ROUND(100 * AVG(IF(transit_served <= 3, 1, 0)), 1)                                AS within_3_days_pct
FROM `sahyadri_b2b.hb_scenarios`
GROUP BY hub
ORDER BY transit_days_saved DESC, hub
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 4 · The leading hubs in detail: late deliveries prevented and break-even
-- -----------------------------------------------------------------------------
WITH ranked AS (
    SELECT hub, SUM(days_saved) AS saved, ROW_NUMBER() OVER (ORDER BY SUM(days_saved) DESC, hub) AS rk
    FROM `sahyadri_b2b.hb_scenarios` GROUP BY hub
),
orders AS (
    -- one saving per order: the largest saving among its shipments, applied to its final delivery
    SELECT sc.hub, sc.order_id, MAX(sc.days_saved) AS days_saved
    FROM `sahyadri_b2b.hb_scenarios` AS sc
    JOIN ranked AS r ON r.hub = sc.hub AND r.rk <= 5
    GROUP BY sc.hub, sc.order_id
),
delivered AS (
    SELECT o.order_id, o.promised_delivery_date, MAX(s.delivery_date) AS delivered_on
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    WHERE o.promised_delivery_date IS NOT NULL
    GROUP BY o.order_id, o.promised_delivery_date
    HAVING COUNT(s.delivery_date) = COUNT(*)
),
joined AS (
    SELECT od.hub, d.delivered_on, d.promised_delivery_date, CAST(ROUND(od.days_saved) AS INT64) AS days_int
    FROM orders AS od
    JOIN delivered AS d ON d.order_id = od.order_id
)
SELECT
    hub,
    COUNT(*)                                                                          AS delivered_orders,
    COUNTIF(delivered_on > promised_delivery_date)                                    AS late_today,
    COUNTIF(DATE_SUB(delivered_on, INTERVAL days_int DAY) > promised_delivery_date)   AS late_with_hub,
    ROUND(100 * COUNTIF(delivered_on > promised_delivery_date) / COUNT(*), 1)         AS late_today_pct,
    ROUND(100 * COUNTIF(DATE_SUB(delivered_on, INTERVAL days_int DAY) > promised_delivery_date) / COUNT(*), 1) AS late_with_hub_pct
FROM joined
GROUP BY hub
ORDER BY late_with_hub;

-- Freight saving per year as the ceiling on a hub's yearly running cost (freight alone)
SELECT
    hub,
    ROUND(SUM(freight_saved) / 1e5, 1)                                                AS freight_saved_lakh_a_year,
    ROUND(100 * SUM(freight_saved) / SUM(shipping_cost), 1)                           AS freight_saved_pct,
    ROUND(SUM(IF(served_by_hub, 1, 0)) / 365, 1)                                      AS hub_shipments_a_day
FROM `sahyadri_b2b.hb_scenarios`
WHERE hub IN (SELECT hub FROM (SELECT hub, ROW_NUMBER() OVER (ORDER BY SUM(days_saved) DESC, hub) AS rk FROM `sahyadri_b2b.hb_scenarios` GROUP BY hub) WHERE rk <= 5)
GROUP BY hub
ORDER BY freight_saved_lakh_a_year DESC;

-- Where the best hub's shipments go
WITH best AS (
    SELECT hub FROM `sahyadri_b2b.hb_scenarios` GROUP BY hub ORDER BY SUM(days_saved) DESC, hub LIMIT 1
)
SELECT
    sc.city_key,
    COUNT(*)                                                                          AS shipments,
    ROUND(ANY_VALUE(sc.km_origin))                                                    AS km_from_origin,
    ROUND(ANY_VALUE(sc.km_hub))                                                       AS km_from_hub,
    ROUND(ANY_VALUE(sc.transit_origin), 1)                                            AS transit_today_model,
    ROUND(ANY_VALUE(sc.transit_served), 1)                                            AS transit_with_hub,
    ROUND(AVG(s.transit_days), 1)                                                     AS transit_today_actual
FROM `sahyadri_b2b.hb_scenarios` AS sc
JOIN best AS b ON b.hub = sc.hub
JOIN `sahyadri_b2b.hb_shipments` AS s ON s.shipment_id = sc.shipment_id
WHERE sc.served_by_hub
GROUP BY sc.city_key
ORDER BY shipments DESC
LIMIT 12;
