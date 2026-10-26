/* =============================================================================
   Case study · Warehouse slotting by pick frequency — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start DATE    DEFAULT DATE '2025-10-01';
DECLARE period_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE zone1_metres FLOAT64 DEFAULT 10;
DECLARE zone2_metres FLOAT64 DEFAULT 25;
DECLARE zone3_metres FLOAT64 DEFAULT 45;

WITH s AS (SELECT * FROM `sahyadri_b2b.slotting_products`),

source_lines AS (
    SELECT i.order_id, i.product_id,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN period_start AND period_end
),
class_bounds AS (
    -- cumulative pick share before each product, by class
    SELECT pick_class, MAX(cum_pick_share - picks / (SELECT SUM(picks) FROM s)) AS max_before,
           MIN(cum_pick_share - picks / (SELECT SUM(picks) FROM s)) AS min_before
    FROM s GROUP BY pick_class
),
zone_travel AS (
    SELECT
        SUM(n_rev * 2 * m)   AS by_revenue,
        SUM(n_pick * 2 * m)  AS by_picks
    FROM (
        SELECT zone_by_revenue AS z, SUM(picks) AS n_rev, 0 AS n_pick FROM s GROUP BY zone_by_revenue
        UNION ALL
        SELECT zone_by_picks, 0, SUM(picks) FROM s GROUP BY zone_by_picks
    ) AS x
    JOIN (SELECT 1 AS z, zone1_metres AS m UNION ALL SELECT 2, zone2_metres UNION ALL SELECT 3, zone3_metres) AS d USING (z)
),
top_pair AS (
    SELECT COUNT(*) AS n FROM (
        SELECT order_id FROM source_lines WHERE product_id IN (2106, 2169)
        GROUP BY order_id HAVING COUNT(DISTINCT product_id) = 2)
),

checks AS (
    SELECT '01. One row per product picked in the period' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM s) - (SELECT COUNT(DISTINCT product_id) FROM source_lines)
         + (SELECT COUNT(*) - COUNT(DISTINCT product_id) FROM s) AS actual
    UNION ALL
    SELECT '02. Picks vs source order lines', 0,
           (SELECT SUM(picks) FROM s) - (SELECT COUNT(*) FROM source_lines)
    UNION ALL
    SELECT '03. Revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM s) - (SELECT SUM(revenue) FROM source_lines), 0) AS INT64)
    UNION ALL
    SELECT '04. Pick and revenue ranks are 1..n without gaps', 0,
           (SELECT COUNT(DISTINCT pick_rank) + COUNT(DISTINCT revenue_rank) - 2 * COUNT(*)
                 + (MAX(pick_rank) - COUNT(*)) + (MAX(revenue_rank) - COUNT(*)) FROM s)
    UNION ALL
    SELECT '05. Pick classes follow the 80 / 95 % cut-offs', 0,
           (SELECT COUNTIF((pick_class = 'A' AND max_before >= 0.80)
                        OR (pick_class = 'B' AND (min_before < 0.80 OR max_before >= 0.95))
                        OR (pick_class = 'C' AND min_before < 0.95)) FROM class_bounds)
    UNION ALL
    SELECT '06. Zone capacities equal under both slotting rules', 0,
           (SELECT COUNTIF(a != b) FROM (
               SELECT z, COUNTIF(zone_by_revenue = z) AS a, COUNTIF(zone_by_picks = z) AS b
               FROM s CROSS JOIN UNNEST([1, 2, 3]) AS z GROUP BY z))
    UNION ALL
    SELECT '07. Pick-based slotting walks no further than revenue-based', 0,
           (SELECT IF(by_picks <= by_revenue, 0, 1) FROM zone_travel)
    UNION ALL
    SELECT '08. Zone 1 under pick slotting holds the most-picked products', 0,
           (SELECT COUNTIF(zone_by_picks = 1 AND picks < (SELECT MAX(picks) FROM s WHERE zone_by_picks = 2)) FROM s)
    UNION ALL
    SELECT '09. Never-picked products vs product master', 0,
           (SELECT COUNT(*) FROM `sahyadri_b2b.products`) - (SELECT COUNT(*) FROM s)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.products` WHERE product_id NOT IN (SELECT product_id FROM source_lines))
    UNION ALL
    SELECT '10. Top co-pick pair (2106, 2169) recount', 144, (SELECT n FROM top_pair)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
