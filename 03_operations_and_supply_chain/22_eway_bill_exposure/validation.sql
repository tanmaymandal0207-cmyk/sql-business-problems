/* =============================================================================
   Case study · E-way bill exposure — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start     DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end       DATE    DEFAULT DATE '2026-09-30';
DECLARE gst_rate         FLOAT64 DEFAULT 0.18;
DECLARE main_road_factor FLOAT64 DEFAULT 1.3;

WITH s AS (SELECT * FROM `sahyadri_b2b.ew_shipments`),
     b AS (SELECT * FROM `sahyadri_b2b.ew_bills`),
     main AS (SELECT * FROM `sahyadri_b2b.ew_bills` WHERE ABS(road_factor - main_road_factor) < 1e-9),

src AS (
    SELECT COUNT(*) AS n FROM `sahyadri_b2b.shipments` WHERE shipment_date BETWEEN window_start AND window_end
),
value_recount AS (
    SELECT x.shipment_id, v.v / c.n AS sv
    FROM `sahyadri_b2b.shipments` AS x
    JOIN (SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS v FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id) AS v
      ON v.order_id = x.order_id
    JOIN (SELECT order_id, COUNT(*) AS n FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS c ON c.order_id = x.order_id
    WHERE x.shipment_date BETWEEN window_start AND window_end
),

checks AS (
    SELECT '01. Shipments = source for the window, every city has coordinates' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM s) - (SELECT n FROM src)) + (SELECT COUNTIF(straight_km IS NULL) FROM s) AS actual
    UNION ALL
    SELECT '02. Shipment value = order value / shipments, consignment value = value x 1.18', 0,
           (SELECT COUNTIF(ABS(s.shipment_value - r.sv) > 1e-6 OR ABS(s.consignment_value - s.shipment_value * (1 + gst_rate)) > 1e-6)
              FROM s JOIN value_recount AS r USING (shipment_id))
    UNION ALL
    SELECT '03. Intra-state = the five Maharashtra destinations only', 0,
           (SELECT COUNTIF(intra_state != (city_key IN ('mumbai', 'pune', 'nashik', 'aurangabad', 'nagpur'))) FROM s)
         + ABS((SELECT COUNT(DISTINCT city_key) FROM s WHERE intra_state) - 5)
    UNION ALL
    SELECT '04. A bill for every shipment above its threshold, at each of 3 road factors, and none below', 0,
           ABS((SELECT COUNT(*) FROM b) - 3 * (SELECT COUNTIF(consignment_value > IF(intra_state, 100000, 50000)) FROM s))
         + (SELECT COUNTIF(consignment_value <= IF(intra_state, 100000, 50000)) FROM b)
         + (SELECT COUNT(*) FROM (SELECT shipment_id FROM b GROUP BY shipment_id HAVING COUNT(DISTINCT road_factor) != 3))
    UNION ALL
    SELECT '05. Validity = 1 day per 200 road km or part of it, at least 1 day', 0,
           (SELECT COUNTIF(validity_days != GREATEST(1, CAST(CEIL(straight_km * road_factor / 200) AS INT64))
                        OR ABS(road_km - straight_km * road_factor) > 1e-9) FROM b)
    UNION ALL
    SELECT '06. Validity never shrinks as the road factor grows', 0,
           (SELECT COUNT(*) FROM (
               SELECT shipment_id, validity_days - LAG(validity_days) OVER (PARTITION BY shipment_id ORDER BY road_factor) AS step FROM b)
             WHERE step < 0)
    UNION ALL
    SELECT '07. Outlived = transit days > validity, unknown when not yet delivered', 0,
           (SELECT COUNTIF((outlived IS NULL) != (delivery_date IS NULL)
                        OR (delivery_date IS NOT NULL AND outlived != (DATE_DIFF(delivery_date, shipment_date, DAY) > validity_days))) FROM b)
    UNION ALL
    SELECT '08. Distances: Mumbai 0 km, Pune 110-130 km straight line', 0,
           (SELECT COUNTIF((city_key = 'mumbai' AND straight_km > 1e-6) OR (city_key = 'pune' AND straight_km NOT BETWEEN 110 AND 130)) FROM s)
    UNION ALL
    SELECT '09. Bills per day add up to all bills, on at most 365 days', 0,
           ABS((SELECT SUM(n) FROM (SELECT shipment_date, COUNT(*) AS n FROM main GROUP BY shipment_date)) - (SELECT COUNT(*) FROM main))
         + IF((SELECT COUNT(DISTINCT shipment_date) FROM main) > 365, 1, 0)
    UNION ALL
    SELECT '10. Extension days = sum of days past validity on outlived bills', 0,
           ABS((SELECT SUM(IF(outlived, transit_days - validity_days, 0)) FROM main)
               - (SELECT SUM(DATE_DIFF(delivery_date, shipment_date, DAY) - validity_days) FROM main
                   WHERE DATE_DIFF(delivery_date, shipment_date, DAY) > validity_days))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
