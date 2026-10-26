/* =============================================================================
   Case study · Freight invoice audit — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE fit_max_value      FLOAT64 DEFAULT 1000000;
DECLARE tolerance_band     FLOAT64 DEFAULT 0.15;
DECLARE min_city_shipments INT64   DEFAULT 30;

WITH b AS (SELECT * FROM `sahyadri_b2b.freight_audit_base`),
     a AS (SELECT * FROM `sahyadri_b2b.freight_audit`),
     r AS (SELECT * FROM `sahyadri_b2b.freight_rate_card`),

fitting AS (
    SELECT a.card_city, a.order_value AS x, a.shipping_cost AS y
    FROM a
    WHERE a.shipments_in_order = 1 AND a.shipping_cost IS NOT NULL AND a.order_value <= fit_max_value
),
-- slope and intercept recomputed with explicit sums of squares
sums AS (
    SELECT f.card_city,
           SUM((f.x - m.mx) * (f.y - m.my)) / SUM(POW(f.x - m.mx, 2)) AS slope,
           ANY_VALUE(m.my) - SUM((f.x - m.mx) * (f.y - m.my)) / SUM(POW(f.x - m.mx, 2)) * ANY_VALUE(m.mx) AS intercept,
           COUNT(*) AS n
    FROM fitting AS f
    JOIN (SELECT card_city, AVG(x) AS mx, AVG(y) AS my FROM fitting GROUP BY card_city) AS m USING (card_city)
    GROUP BY f.card_city
),
city_fit_counts AS (
    SELECT city, COUNTIF(shipments_in_order = 1 AND shipping_cost IS NOT NULL AND order_value <= fit_max_value) AS n,
           ANY_VALUE(card_city) AS card_city, COUNT(DISTINCT card_city) AS card_cities
    FROM a GROUP BY city
),

checks AS (
    SELECT '01. Base rows vs source shipments, one per shipment' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM b) - (SELECT COUNT(*) FROM `sahyadri_b2b.shipments`)
         + (SELECT COUNT(*) - COUNT(DISTINCT shipment_id) FROM b) AS actual
    UNION ALL
    SELECT '02. Audit rows vs base rows, one per shipment', 0,
           (SELECT COUNT(*) FROM a) - (SELECT COUNT(*) FROM b)
         + (SELECT COUNT(*) - COUNT(DISTINCT shipment_id) FROM a)
    UNION ALL
    SELECT '03. Rate card slope and intercept vs sums-of-squares recount', 0,
           (SELECT COUNTIF(ABS(r.variable_rate - s.slope) > 1e-9 OR ABS(r.fixed_charge - s.intercept) > 1e-4)
              FROM r JOIN sums AS s USING (card_city))
    UNION ALL
    SELECT '04. Fitting shipments per card vs recount', 0,
           (SELECT COUNTIF(r.fitting_shipments != s.n) FROM r JOIN sums AS s USING (card_city))
         + ABS((SELECT COUNT(*) FROM r) - (SELECT COUNT(*) FROM sums))
    UNION ALL
    SELECT '05. Status inconsistent with rules', 0,
           (SELECT COUNTIF(audit_status != CASE
                WHEN shipments_in_order > 1 THEN '6. Split shipment (not audited)'
                WHEN shipping_cost IS NULL THEN '5. Missing cost'
                WHEN order_value > fit_max_value THEN '4. Above card range'
                WHEN shipping_cost > card_charge * (1 + tolerance_band) THEN '2. Over-charged'
                WHEN shipping_cost < card_charge * (1 - tolerance_band) THEN '3. Under-charged'
                ELSE '1. Within tolerance' END) FROM a)
    UNION ALL
    SELECT '06. Variance != charged - card on audited shipments', 0,
           (SELECT COUNTIF(ABS(variance - (shipping_cost - card_charge)) > 0.01) FROM a WHERE shipping_cost IS NOT NULL AND shipments_in_order = 1)
    UNION ALL
    SELECT '07. Split-shipment rows vs source orders with 2+ shipments', 0,
           (SELECT COUNTIF(audit_status = '6. Split shipment (not audited)') FROM a)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.shipments`
             WHERE order_id IN (SELECT order_id FROM `sahyadri_b2b.shipments` GROUP BY order_id HAVING COUNT(*) > 1))
    UNION ALL
    SELECT '08. Missing-cost shipments vs source nulls', 0,
           (SELECT COUNTIF(shipping_cost IS NULL) FROM a) - (SELECT COUNTIF(shipping_cost IS NULL) FROM `sahyadri_b2b.shipments`)
    UNION ALL
    SELECT '09. Recorded freight vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(shipping_cost) FROM a) - (SELECT SUM(shipping_cost) FROM `sahyadri_b2b.shipments`), 0) AS INT64)
    UNION ALL
    SELECT '10. Card assignment: own card if 30+ fitting shipments, else pooled', 0,
           (SELECT COUNTIF(card_cities != 1
                        OR (n >= min_city_shipments AND card_city != city)
                        OR (n <  min_city_shipments AND card_city != 'Pooled (small cities)')) FROM city_fit_counts)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
