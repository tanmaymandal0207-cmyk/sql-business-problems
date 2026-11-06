/* =============================================================================
   Case study · Freight zone audit — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_day    DATE    DEFAULT DATE '2024-01-01';
DECLARE last_day     DATE    DEFAULT DATE '2026-09-30';
DECLARE recent_start DATE    DEFAULT DATE '2025-10-01';
DECLARE value_cap    FLOAT64 DEFAULT 2000000;
DECLARE zone_gap     FLOAT64 DEFAULT 50;
DECLARE flag_share   FLOAT64 DEFAULT 0.15;
DECLARE flag_rupees  FLOAT64 DEFAULT 100;

WITH s AS (SELECT * FROM `sahyadri_b2b.fz_shipments`),
     l AS (SELECT * FROM `sahyadri_b2b.fz_lanes`),
     r AS (SELECT * FROM `sahyadri_b2b.fz_rate`),

src AS (
    SELECT COUNT(*) AS n, SUM(IFNULL(shipping_cost, 0)) AS cost
    FROM `sahyadri_b2b.shipments` WHERE shipment_date BETWEEN first_day AND last_day
),
order_values AS (
    SELECT i.order_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_order_items` AS i
    WHERE i.order_id IN (SELECT order_id FROM `sahyadri_b2b.shipments`)
    GROUP BY i.order_id
),
all_shipments AS (
    -- shipment value over every shipment of each order, to reconcile with order value
    SELECT x.order_id, SUM(v.v / c.n) AS split_value, ANY_VALUE(v.v) AS order_value
    FROM `sahyadri_b2b.shipments` AS x
    JOIN order_values AS v ON v.order_id = x.order_id
    JOIN (SELECT order_id, COUNT(*) AS n FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS c ON c.order_id = x.order_id
    GROUP BY x.order_id
),
fit AS (
    SELECT * FROM s WHERE shipping_cost IS NOT NULL AND shipment_value < value_cap
),
city_means AS (
    SELECT city_key, AVG(shipping_cost) AS mc, AVG(shipment_value) AS mv FROM fit GROUP BY city_key
),
lane_recount AS (
    SELECT f.city_key, COUNT(*) AS n, AVG(f.shipping_cost - r.value_rate * f.shipment_value) AS fixed_charge,
           AVG(IF(f.shipment_date < DATE '2025-05-16', f.shipping_cost - r.value_rate * f.shipment_value, NULL)) AS h1,
           AVG(IF(f.shipment_date >= DATE '2025-05-16', f.shipping_cost - r.value_rate * f.shipment_value, NULL)) AS h2
    FROM fit AS f CROSS JOIN r GROUP BY f.city_key
),
ordered AS (
    SELECT zone, fixed_charge, fixed_charge - LAG(fixed_charge) OVER (ORDER BY fixed_charge) AS gap,
           zone - LAG(zone) OVER (ORDER BY fixed_charge) AS step
    FROM l
),
recent AS (
    SELECT x.*, l.fixed_charge, l.premium, l.benchmark
    FROM s AS x JOIN l USING (city_key)
    WHERE x.shipment_date >= recent_start AND x.shipping_cost IS NOT NULL
),

checks AS (
    SELECT '01. Shipments and freight = source, every city has coordinates' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM s) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(IFNULL(shipping_cost, 0)) FROM s) - (SELECT cost FROM src)) > 1, 1, 0)
         + (SELECT COUNTIF(km IS NULL) FROM s) AS actual
    UNION ALL
    SELECT '02. Shipment values add up to order value for every shipped order', 0,
           (SELECT COUNTIF(ABS(split_value - order_value) > 1e-6) FROM all_shipments)
    UNION ALL
    SELECT '03. Value rate = within-city slope (recount)', 0,
           IF(ABS((SELECT value_rate FROM r)
                  - (SELECT SUM((f.shipping_cost - m.mc) * f.shipment_value) / SUM((f.shipment_value - m.mv) * f.shipment_value)
                       FROM fit AS f JOIN city_means AS m USING (city_key))) > 1e-12, 1, 0)
         + ABS((SELECT shipments FROM r) - (SELECT COUNT(*) FROM fit))
    UNION ALL
    SELECT '04. Lane fixed charges and shipments = recount, both halves', 0,
           (SELECT COUNT(*) FROM l JOIN lane_recount AS x USING (city_key)
             WHERE l.shipments != x.n OR ABS(l.fixed_charge - x.fixed_charge) > 1e-6
                OR ABS(l.fixed_first_half - x.h1) > 1e-6 OR ABS(l.fixed_second_half - x.h2) > 1e-6)
         + ABS((SELECT COUNT(*) FROM l) - (SELECT COUNT(DISTINCT city_key) FROM fit))
    UNION ALL
    SELECT '05. A new zone starts exactly where the next city is Rs 50 or more dearer', 0,
           (SELECT COUNTIF(gap IS NOT NULL AND (step = 1) != (gap >= zone_gap)) FROM ordered)
         + (SELECT COUNTIF(step NOT IN (0, 1)) FROM ordered)
         + IF((SELECT MIN(zone) FROM l) != 1, 1, 0)
    UNION ALL
    SELECT '06. Benchmark residuals satisfy the weighted normal equations', 0,
           IF(ABS((SELECT SUM(shipments * premium) FROM l)) > 1e-3, 1, 0)
         + IF(ABS((SELECT SUM(shipments * premium * km) FROM l)) > 1e-1, 1, 0)
    UNION ALL
    SELECT '07. Distances: Mumbai 0 km, Pune 110-130 km, Kolkata 1,500-1,700 km', 0,
           (SELECT COUNTIF((city_key = 'mumbai' AND km > 1e-6)
                        OR (city_key = 'pune' AND km NOT BETWEEN 110 AND 130)
                        OR (city_key = 'kolkata' AND km NOT BETWEEN 1500 AND 1700)) FROM l)
         + ABS((SELECT COUNT(*) FROM l WHERE city_key IN ('mumbai', 'pune', 'kolkata')) - 3)
    UNION ALL
    SELECT '08. Every shipment of a lane carries the same distance', 0,
           (SELECT COUNT(*) FROM (SELECT city_key FROM s GROUP BY city_key HAVING MAX(km) - MIN(km) > 1e-9))
    UNION ALL
    SELECT '09. Latest-12-month bill: fixed + value parts = freight', 0,
           IF(ABS((SELECT SUM(fixed_charge) + SUM(shipping_cost - fixed_charge) - SUM(shipping_cost) FROM recent)) > 1e-3, 1, 0)
         + ABS((SELECT COUNT(*) FROM recent)
               - (SELECT COUNT(*) FROM `sahyadri_b2b.shipments` WHERE shipment_date BETWEEN recent_start AND last_day AND shipping_cost IS NOT NULL))
    UNION ALL
    SELECT '10. Flagged-lane premium = premium x latest-year shipments of the flagged lanes', 0,
           IF(ABS((SELECT SUM(premium) FROM recent WHERE premium >= flag_share * benchmark AND premium >= flag_rupees)
                  - (SELECT SUM(l.premium * c.n) FROM l JOIN (SELECT city_key, COUNT(*) AS n FROM recent GROUP BY city_key) AS c USING (city_key)
                      WHERE l.premium >= flag_share * l.benchmark AND l.premium >= flag_rupees)) > 1e-3, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
