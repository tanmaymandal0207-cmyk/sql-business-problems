/* =============================================================================
   Case study · A second dispatch hub — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE band_km      FLOAT64 DEFAULT 250;

WITH s AS (SELECT * FROM `sahyadri_b2b.hb_shipments`),
     c AS (SELECT * FROM `sahyadri_b2b.hb_cities`),
     d AS (SELECT * FROM `sahyadri_b2b.hb_distances`),
     f AS (SELECT * FROM `sahyadri_b2b.hb_origin_fit`),
     cu AS (SELECT * FROM `sahyadri_b2b.hb_curve`),
     fm AS (SELECT * FROM `sahyadri_b2b.hb_freight_model`),
     sc AS (SELECT * FROM `sahyadri_b2b.hb_scenarios`),

origin AS (
    SELECT candidate_origin AS city_key FROM f ORDER BY r_squared DESC LIMIT 1
),
origin_pairs AS (
    SELECT d.km, s.transit_days, s.shipping_cost, s.shipment_value
    FROM s JOIN d ON d.to_city = s.city_key JOIN origin AS o ON o.city_key = d.from_city
),
residuals AS (
    SELECT shipping_cost - (fm.intercept + fm.per_100km * km / 100 + fm.per_lakh_value * shipment_value / 1e5) AS r,
           km / 100 AS x1, shipment_value / 1e5 AS x2
    FROM origin_pairs CROSS JOIN fm
    WHERE shipping_cost IS NOT NULL
),
band_recount AS (
    SELECT CAST(FLOOR(km / band_km) AS INT64) AS band, AVG(transit_days) AS avg_transit
    FROM origin_pairs WHERE transit_days IS NOT NULL GROUP BY band
),
curve_steps AS (
    SELECT band, curve_transit, LAG(curve_transit) OVER (ORDER BY band) AS previous FROM cu WHERE curve_transit IS NOT NULL
),

checks AS (
    SELECT '01. Shipments = shipments dispatched in the window, every city has coordinates' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM s) - (SELECT COUNT(*) FROM `sahyadri_b2b.shipments` WHERE shipment_date BETWEEN window_start AND window_end))
         + (SELECT COUNT(*) FROM s LEFT JOIN c USING (city_key) WHERE c.city_key IS NULL) AS actual
    UNION ALL
    SELECT '02. Distances symmetric, zero to itself, Mumbai-Pune 100-140 km, Mumbai-Kolkata 1,600-1,700 km', 0,
           (SELECT COUNT(*) FROM d AS a JOIN d AS b ON a.from_city = b.to_city AND a.to_city = b.from_city WHERE ABS(a.km - b.km) > 1e-6)
         + (SELECT COUNTIF(from_city = to_city AND km > 1e-6) FROM d)
         + (SELECT COUNTIF(km NOT BETWEEN 100 AND 140) FROM d WHERE from_city = 'mumbai' AND to_city = 'pune')
         + (SELECT COUNTIF(km NOT BETWEEN 1600 AND 1700) FROM d WHERE from_city = 'mumbai' AND to_city = 'kolkata')
    UNION ALL
    SELECT '03. Origin has the highest R-squared, recomputed as cov^2 / (var x var)', 0,
           (SELECT IF(ABS(POW(COVAR_POP(km, transit_days), 2) / (VAR_POP(km) * VAR_POP(transit_days))
                         - (SELECT MAX(r_squared) FROM f)) > 1e-9, 1, 0) FROM origin_pairs WHERE transit_days IS NOT NULL)
         + ABS((SELECT COUNT(*) FROM f) - (SELECT COUNT(*) FROM c))
    UNION ALL
    SELECT '04. Band averages = recount, curve never falls', 0,
           (SELECT COUNT(*) FROM cu JOIN band_recount AS b USING (band) WHERE ABS(cu.avg_transit - b.avg_transit) > 1e-9)
         + (SELECT COUNTIF(previous IS NOT NULL AND curve_transit < previous) FROM curve_steps)
    UNION ALL
    SELECT '05. Freight model residuals average zero and are uncorrelated with distance and value', 0,
           (SELECT IF(ABS(AVG(r)) > 1e-6 OR ABS(SUM(r * x1)) > 1e-3 * COUNT(*) OR ABS(SUM(r * x2)) > 1e-3 * COUNT(*), 1, 0) FROM residuals)
    UNION ALL
    SELECT '06. One scenario row per shipment per candidate hub', 0,
           ABS((SELECT COUNT(*) FROM sc) - (SELECT COUNT(*) FROM s) * ((SELECT COUNT(*) FROM c) - 1))
    UNION ALL
    SELECT '07. Each shipment is served from the nearer point, savings never negative', 0,
           (SELECT COUNTIF(km_served != LEAST(km_origin, km_hub) OR served_by_hub != (km_hub < km_origin)
                           OR days_saved < -1e-9 OR freight_saved < -1e-9) FROM sc)
    UNION ALL
    SELECT '08. Transit with the hub = curve at the served distance', 0,
           (SELECT COUNT(*) FROM sc JOIN cu ON cu.band = CAST(FLOOR(sc.km_served / band_km) AS INT64)
             WHERE ABS(sc.transit_served - cu.curve_transit) > 1e-9)
    UNION ALL
    SELECT '09. Shipments not served by the hub save nothing', 0,
           (SELECT COUNTIF(NOT served_by_hub AND (days_saved != 0 OR freight_saved != 0)) FROM sc)
    UNION ALL
    SELECT '10. Freight saving = per-km rate x km saved', 0,
           (SELECT COUNTIF(ABS(sc.freight_saved - fm.per_100km * (sc.km_origin - sc.km_served) / 100) > 1e-6) FROM sc CROSS JOIN fm)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
