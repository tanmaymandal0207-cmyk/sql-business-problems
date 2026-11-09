/* =============================================================================
   Case study · Inventory pooling with a second hub — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE demand_start  DATE    DEFAULT DATE '2024-10-01';
DECLARE n_weeks       INT64   DEFAULT 104;
DECLARE z_service     FLOAT64 DEFAULT 1.645;
DECLARE lead_weeks    FLOAT64 DEFAULT 2;

WITH c AS (SELECT * FROM `sahyadri_b2b.ip_cities`),
     r AS (SELECT * FROM `sahyadri_b2b.ip_regions`),
     l AS (SELECT * FROM `sahyadri_b2b.ip_order_lines`),
     w AS (SELECT * FROM `sahyadri_b2b.ip_weekly`),
     p AS (SELECT * FROM `sahyadri_b2b.ip_products`),

window_lines AS (
    SELECT COUNT(*) AS n, SUM(i.quantity) AS units
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status != 'Cancelled' AND o.order_date >= demand_start
      AND DATE_DIFF(o.order_date, demand_start, DAY) < 7 * n_weeks
      AND o.order_id IN (SELECT order_id FROM `sahyadri_b2b.shipments`)
),

checks AS (
    SELECT '01. 51 cities, each served from the nearer of Mumbai and Kanpur' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM r) - 51)
         + (SELECT COUNTIF(region != IF(km_kanpur < km_mumbai, 'Kanpur hub', 'Mumbai')) FROM r)
         + (SELECT COUNTIF((city_key = 'mumbai' AND region != 'Mumbai') OR (city_key = 'kanpur' AND region != 'Kanpur hub')) FROM r) AS actual
    UNION ALL
    SELECT '02. Order lines = every shipped, non-cancelled line in the 104 weeks, every city mapped to a region', 0,
           ABS((SELECT COUNT(*) FROM l) - (SELECT n FROM window_lines))
         + ABS((SELECT SUM(quantity) FROM l) - (SELECT units FROM window_lines))
         + (SELECT COUNTIF(region IS NULL) FROM l)
    UNION ALL
    SELECT '03. Week index between 0 and 103 = whole weeks since 1 October 2024', 0,
           (SELECT COUNTIF(week_index < 0 OR week_index >= n_weeks
                        OR week_index != DIV(DATE_DIFF(order_date, demand_start, DAY), 7)) FROM l)
    UNION ALL
    SELECT '04. Weekly grid: 104 weeks for every product, units by region = order lines', 0,
           (SELECT COUNT(*) FROM (SELECT product_id, COUNT(*) AS n FROM w GROUP BY product_id) WHERE n != n_weeks)
         + ABS((SELECT SUM(units_mumbai) FROM w) - (SELECT SUM(IF(region = 'Mumbai', quantity, 0)) FROM l))
         + ABS((SELECT SUM(units_hub) FROM w) - (SELECT SUM(IF(region = 'Kanpur hub', quantity, 0)) FROM l))
    UNION ALL
    SELECT '05. Variance identity: sd(total)^2 = sd(Mumbai)^2 + sd(hub)^2 + 2 x correlation x sd(Mumbai) x sd(hub)', 0,
           (SELECT COUNTIF(ABS(POW(sd_total, 2) - (POW(sd_mumbai, 2) + POW(sd_hub, 2)
                                + 2 * IFNULL(correlation, 0) * sd_mumbai * sd_hub)) > 1e-6 * GREATEST(1, POW(sd_total, 2))) FROM p)
    UNION ALL
    SELECT '06. Safety stock = 1.645 x sd x SQRT(2 weeks), two locations = Mumbai + hub', 0,
           (SELECT COUNTIF(ABS(ss_one_location - z_service * sd_total * SQRT(lead_weeks)) > 1e-9
                        OR ABS(ss_two_locations - (ss_mumbai + ss_hub)) > 1e-9
                        OR ABS(ss_hub - z_service * sd_hub * SQRT(lead_weeks)) > 1e-9) FROM p)
    UNION ALL
    SELECT '07. Two locations never need less safety stock than one (sd of a sum <= sum of sds)', 0,
           (SELECT COUNTIF(ss_two_locations < ss_one_location - 1e-9) FROM p)
    UNION ALL
    SELECT '08. Product totals by region = weekly grid totals', 0,
           ABS((SELECT SUM(units_mumbai + units_hub) FROM p) - (SELECT SUM(units_mumbai + units_hub) FROM w))
    UNION ALL
    SELECT '09. Every product with demand has a cost row and a category', 0,
           (SELECT COUNTIF(category_name IS NULL) FROM p)
         + ABS((SELECT COUNT(*) FROM p) - (SELECT COUNT(DISTINCT product_id) FROM l))
    UNION ALL
    SELECT '10. City table: one row per city, coordinates within India', 0,
           ABS((SELECT COUNT(*) FROM c) - (SELECT COUNT(DISTINCT city_key) FROM c))
         + (SELECT COUNTIF(lat NOT BETWEEN 6 AND 37 OR lon NOT BETWEEN 68 AND 98) FROM c)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
