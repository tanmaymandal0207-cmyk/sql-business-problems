/* =============================================================================
   Case study · E-way bills: how many consignments need one, and how many
   outlive it?
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Under GST, goods above a value threshold cannot move without an e-way
   bill, and the bill is valid for one day per 200 km. A truck stopped
   with an expired bill can be detained and the goods penalised. The
   dispatch team raises the bills by hand and has never checked how many
   it needs or whether deliveries arrive within validity. After a
   detention at a check post last month, the finance controller asks:
     1. How many shipments need an e-way bill, and how many a day?
     2. How many would have arrived after their bill expired, and on which
        lanes?
     3. How sensitive is that to the distance assumption?
     4. What should dispatch change: validity extensions, or a rule per
        lane?

   RULES APPLIED (CGST Rule 138, as summarised by GST practitioners)
     - Required for inter-state movement when the consignment value,
       including tax, exceeds Rs 50,000. Within Maharashtra the threshold
       is Rs 1 lakh (Notification 15E/2018-State Tax).
     - Validity for normal cargo: 1 day per 200 km or part of it. Each day
       ends at midnight, so a bill generated on the dispatch date with n
       days of validity covers delivery up to dispatch date + n.

   METHOD AND ASSUMPTIONS
     - Shipments dispatched October 2025 - September 2026, city names
       standardised. Shipment value = order value / shipments of the order;
       consignment value = shipment value x 1.18 (GST assumed at 18 % on
       all products).
     - Origin Mumbai (as in the second-hub study). Distance = straight-line
       (haversine) km x a road factor of 1.3; 1.15 and 1.5 as sensitivities.
     - Destinations in Maharashtra: Mumbai, Pune, Nashik, Aurangabad,
       Nagpur. Every other city is inter-state.
     - A shipment outlives its bill when transit days (delivery date -
       shipment date) exceed its validity days.
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE gst_rate     FLOAT64 DEFAULT 0.18;
DECLARE main_road_factor FLOAT64 DEFAULT 1.3;

-- -----------------------------------------------------------------------------
-- Step 1 · Shipments with consignment value, state and road distance
-- -----------------------------------------------------------------------------
-- Approximate city-centre coordinates (the same table as the second-hub study)
CREATE OR REPLACE TABLE `sahyadri_b2b.ew_cities` AS
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

CREATE OR REPLACE TABLE `sahyadri_b2b.ew_shipments` AS
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
    SELECT lat, lon FROM `sahyadri_b2b.ew_cities` WHERE city_key = 'mumbai'
),
base AS (
    SELECT
        s.shipment_id, s.order_id, s.shipment_date, s.delivery_date, s.shipment_status,
        IFNULL(a.city_key, LOWER(TRIM(s.shipping_city)))                              AS city_key,
        v.value / p.shipments                                                         AS shipment_value
    FROM `sahyadri_b2b.shipments` AS s
    LEFT JOIN city_alias AS a ON a.raw_key = LOWER(TRIM(s.shipping_city))
    JOIN order_value AS v ON v.order_id = s.order_id
    JOIN per_order AS p ON p.order_id = s.order_id
    WHERE s.shipment_date BETWEEN window_start AND window_end
)
SELECT
    b.*,
    b.shipment_value * (1 + gst_rate)                                                 AS consignment_value,
    b.city_key IN ('mumbai', 'pune', 'nashik', 'aurangabad', 'nagpur')                AS intra_state,
    2 * 6371 * ASIN(SQRT(
        POW(SIN((c.lat - o.lat) * ACOS(-1) / 360), 2)
        + COS(o.lat * ACOS(-1) / 180) * COS(c.lat * ACOS(-1) / 180) * POW(SIN((c.lon - o.lon) * ACOS(-1) / 360), 2))) AS straight_km,
    DATE_DIFF(b.delivery_date, b.shipment_date, DAY)                                  AS transit_days
FROM base AS b
LEFT JOIN `sahyadri_b2b.ew_cities` AS c ON c.city_key = b.city_key
CROSS JOIN origin AS o;

-- Bill needed, validity days at three road factors, and whether delivery fell outside validity
CREATE OR REPLACE TABLE `sahyadri_b2b.ew_bills` AS
WITH factors AS (
    SELECT f FROM UNNEST([1.15, main_road_factor, 1.5]) AS f
)
SELECT
    s.shipment_id, s.order_id, s.shipment_date, s.delivery_date, s.city_key, s.intra_state,
    s.consignment_value, s.straight_km, s.transit_days, fa.f AS road_factor,
    s.straight_km * fa.f                                                              AS road_km,
    -- 1 day per 200 km or part of it; a bill is needed for any movement, so at least 1 day
    GREATEST(1, CAST(CEIL(s.straight_km * fa.f / 200) AS INT64))                      AS validity_days,
    s.transit_days > GREATEST(1, CAST(CEIL(s.straight_km * fa.f / 200) AS INT64))     AS outlived
FROM `sahyadri_b2b.ew_shipments` AS s
CROSS JOIN factors AS fa
WHERE s.consignment_value > IF(s.intra_state, 100000, 50000);

-- -----------------------------------------------------------------------------
-- Step 2 · How many bills, and how many a day?
-- -----------------------------------------------------------------------------
SELECT
    IF(intra_state, 'Within Maharashtra (Rs 1 lakh)', 'Inter-state (Rs 50,000)')      AS movement,
    COUNT(*)                                                                          AS shipments,
    COUNTIF(consignment_value > IF(intra_state, 100000, 50000))                       AS need_a_bill,
    ROUND(100 * COUNTIF(consignment_value > IF(intra_state, 100000, 50000)) / COUNT(*), 1) AS need_a_bill_pct,
    ROUND(100 * SUM(IF(consignment_value > IF(intra_state, 100000, 50000), shipment_value, 0)) / SUM(shipment_value), 1) AS share_of_value_pct
FROM `sahyadri_b2b.ew_shipments`
GROUP BY ROLLUP(movement)
ORDER BY movement;

-- Bills per dispatch day
WITH days AS (
    SELECT shipment_date, COUNT(*) AS bills
    FROM `sahyadri_b2b.ew_bills` WHERE ABS(road_factor - main_road_factor) < 1e-9
    GROUP BY shipment_date
)
SELECT
    COUNT(*)                                                                          AS dispatch_days_with_a_bill,
    ROUND(AVG(bills), 1)                                                              AS average_bills_a_day,
    APPROX_QUANTILES(bills, 100)[OFFSET(90)]                                          AS p90_bills_a_day,
    MAX(bills)                                                                        AS busiest_day
FROM days;

-- -----------------------------------------------------------------------------
-- Step 3 · Deliveries after the bill expired, by lane
-- -----------------------------------------------------------------------------
SELECT
    road_factor,
    COUNTIF(delivery_date IS NOT NULL)                                                AS delivered_bills,
    COUNTIF(outlived)                                                                 AS outlived,
    ROUND(100 * COUNTIF(outlived) / COUNTIF(delivery_date IS NOT NULL), 1)            AS outlived_pct,
    ROUND(100 * COUNTIF(outlived AND validity_days = 1) / NULLIF(COUNTIF(outlived), 0), 1) AS of_which_one_day_bills_pct
FROM `sahyadri_b2b.ew_bills`
GROUP BY road_factor
ORDER BY road_factor;

-- Lanes (main road factor)
SELECT
    city_key, intra_state,
    ROUND(ANY_VALUE(road_km), 0)                                                      AS road_km,
    ANY_VALUE(validity_days)                                                          AS validity_days,
    COUNT(*)                                                                          AS bills,
    ROUND(AVG(transit_days), 1)                                                       AS average_transit_days,
    COUNTIF(outlived)                                                                 AS outlived,
    ROUND(100 * COUNTIF(outlived) / COUNTIF(delivery_date IS NOT NULL), 1)            AS outlived_pct
FROM `sahyadri_b2b.ew_bills`
WHERE ABS(road_factor - main_road_factor) < 1e-9
GROUP BY city_key, intra_state
HAVING COUNTIF(outlived) > 0
ORDER BY outlived DESC
LIMIT 15;

-- By validity band: how much slack does each band of lanes have?
SELECT
    validity_days,
    COUNT(*)                                                                          AS bills,
    COUNT(DISTINCT city_key)                                                          AS lanes,
    ROUND(AVG(transit_days), 2)                                                       AS average_transit_days,
    APPROX_QUANTILES(transit_days, 100)[OFFSET(90)]                                   AS p90_transit_days,
    ROUND(100 * COUNTIF(outlived) / COUNTIF(delivery_date IS NOT NULL), 1)            AS outlived_pct
FROM `sahyadri_b2b.ew_bills`
WHERE ABS(road_factor - main_road_factor) < 1e-9
GROUP BY validity_days
ORDER BY validity_days;

-- -----------------------------------------------------------------------------
-- Step 4 · What dispatch should do: extensions needed, and a per-lane rule
-- -----------------------------------------------------------------------------
-- Extension days that would have been needed, and the lane rule "extend if not delivered by day n"
SELECT
    COUNTIF(outlived)                                                                 AS bills_needing_extension,
    SUM(IF(outlived, transit_days - validity_days, 0))                                AS extension_days,
    ROUND(AVG(IF(outlived, transit_days - validity_days, NULL)), 2)                   AS average_days_over,
    MAX(IF(outlived, transit_days - validity_days, NULL))                             AS most_days_over,
    COUNTIF(delivery_date IS NULL)                                                    AS bills_not_delivered_by_sep_2026
FROM `sahyadri_b2b.ew_bills`
WHERE ABS(road_factor - main_road_factor) < 1e-9;
