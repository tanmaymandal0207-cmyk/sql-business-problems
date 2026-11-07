/* =============================================================================
   Case study · Price ladders — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE band         FLOAT64 DEFAULT 0.10;

WITH p AS (SELECT * FROM `sahyadri_b2b.pl_products`),
     l AS (SELECT * FROM `sahyadri_b2b.pl_ladders`),
     s AS (SELECT * FROM `sahyadri_b2b.pl_sales`),

src_window AS (
    SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v, COUNT(DISTINCT i.product_id) AS products
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN window_start AND window_end
),
neighbours AS (
    SELECT product_id, size, selling_price, neighbour_price,
           LAG(size) OVER w AS s0, LEAD(size) OVER w AS s1, LAG(selling_price) OVER w AS p0, LEAD(selling_price) OVER w AS p1
    FROM l WINDOW w AS (PARTITION BY family ORDER BY size)
),
slopes AS (
    -- slope recounted as sum of cross-deviations / sum of squared deviations
    SELECT family, ANY_VALUE(slope) AS stored,
           SUM((LN(size) - mx) * (LN(selling_price) - my)) / SUM(POW(LN(size) - mx, 2)) AS b
    FROM (SELECT *, AVG(LN(size)) OVER (PARTITION BY family) AS mx, AVG(LN(selling_price)) OVER (PARTITION BY family) AS my FROM l)
    GROUP BY family
),

checks AS (
    SELECT '01. Every product in the master is read once' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM p) - (SELECT COUNT(*) FROM `sahyadri_b2b.products`))
         + ABS((SELECT COUNT(*) FROM p) - (SELECT COUNT(DISTINCT product_id) FROM p)) AS actual
    UNION ALL
    SELECT '02. Family size = number of products sharing the family name', 0,
           (SELECT COUNT(*) FROM p JOIN (SELECT family, COUNT(*) AS n FROM p GROUP BY family) AS x USING (family) WHERE p.family_size != x.n)
    UNION ALL
    SELECT '03. Ladders: 12 families, 60 products, 3+ distinct positive sizes each', 0,
           ABS((SELECT COUNT(DISTINCT family) FROM l) - 12) + ABS((SELECT COUNT(*) FROM l) - 60)
         + (SELECT COUNT(*) FROM (SELECT family FROM l GROUP BY family HAVING COUNT(*) < 3 OR COUNT(DISTINCT size) != COUNT(*) OR MIN(size) <= 0))
    UNION ALL
    SELECT '04. Sizes read correctly (spot checks across all rules)', 0,
           (SELECT COUNTIF(NOT (
                   (product_name = 'Deep Groove Ball Bearing 6202-2RS' AND size = 15)
                OR (product_name = 'Deep Groove Ball Bearing 6205-2RS' AND size = 25)
                OR (product_name = 'Hydraulic Hose 2-Wire 3/4 in x 1 m Assembly' AND size = 0.75)
                OR (product_name = '3-Phase Induction Motor 7.5 HP 4 Pole IE2' AND size = 7.5)
                OR (product_name = 'Hex Nut HT M16 (Box of 100)' AND size = 16)
                OR (product_name = 'Pneumatic Cylinder 63x250 mm Double Acting' AND size = 63)
                OR (product_name = 'Ball Valve SS316 1/2 in Screwed' AND size = 0.5)
                OR (product_name = 'Carbide End Mill 4 Flute 12 mm' AND size = 12)))
              FROM l WHERE product_name IN ('Deep Groove Ball Bearing 6202-2RS', 'Deep Groove Ball Bearing 6205-2RS',
                   'Hydraulic Hose 2-Wire 3/4 in x 1 m Assembly', '3-Phase Induction Motor 7.5 HP 4 Pole IE2', 'Hex Nut HT M16 (Box of 100)',
                   'Pneumatic Cylinder 63x250 mm Double Acting', 'Ball Valve SS316 1/2 in Screwed', 'Carbide End Mill 4 Flute 12 mm'))
         + ABS((SELECT COUNT(*) FROM l WHERE product_name IN ('Deep Groove Ball Bearing 6202-2RS', 'Deep Groove Ball Bearing 6205-2RS',
                   'Hydraulic Hose 2-Wire 3/4 in x 1 m Assembly', '3-Phase Induction Motor 7.5 HP 4 Pole IE2', 'Hex Nut HT M16 (Box of 100)',
                   'Pneumatic Cylinder 63x250 mm Double Acting', 'Ball Valve SS316 1/2 in Screwed', 'Carbide End Mill 4 Flute 12 mm')) - 8)
    UNION ALL
    SELECT '05. Wider bearing series are separate families (62 vs 63, taper 302 vs 322 dropped)', 0,
           (SELECT COUNT(*) FROM (SELECT family FROM l WHERE product_name LIKE 'Deep Groove%' GROUP BY family HAVING COUNT(DISTINCT SUBSTR(REGEXP_EXTRACT(product_name, r'(6[0-9]{3})'), 1, 2)) > 1))
         + (SELECT COUNT(*) FROM l WHERE product_name LIKE 'Taper Roller%')
    UNION ALL
    SELECT '06. Ladder slopes = recount', 0,
           (SELECT COUNTIF(ABS(stored - b) > 1e-9) FROM slopes)
    UNION ALL
    SELECT '07. Neighbour price = log-log interpolation, none at the two ends of a ladder', 0,
           (SELECT COUNTIF(s0 IS NOT NULL AND s1 IS NOT NULL AND ABS(LN(neighbour_price)
                - (LN(p0) + (LN(p1) - LN(p0)) * (LN(size) - LN(s0)) / (LN(s1) - LN(s0)))) > 1e-9) FROM neighbours)
         + (SELECT COUNTIF((s0 IS NULL OR s1 IS NULL) != (neighbour_price IS NULL)) FROM neighbours)
         + ABS((SELECT COUNT(neighbour_price) FROM l) - 36)
    UNION ALL
    SELECT '08. Margin = (list price - unit cost) / list price', 0,
           (SELECT COUNTIF(ABS(margin - (selling_price - unit_cost) / selling_price) > 1e-12) FROM l)
    UNION ALL
    SELECT '09. Product sales = source revenue for the latest 12 months', 0,
           IF(ABS((SELECT SUM(revenue) FROM s) - (SELECT v FROM src_window)) > 1, 1, 0)
         + ABS((SELECT COUNT(*) FROM s) - (SELECT products FROM src_window))
    UNION ALL
    SELECT '10. Re-pricing value = revenue x (neighbour price / list - 1) over the flagged rungs', 0,
           IF(ABS((SELECT SUM(IFNULL(s.revenue, 0) * (l.neighbour_price / l.selling_price - 1))
                     FROM l LEFT JOIN s USING (product_id) WHERE l.selling_price / l.neighbour_price - 1 < -band)
                  - (SELECT SUM(x.r * (l.neighbour_price / l.selling_price - 1))
                       FROM l JOIN (SELECT i.product_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS r
                                     FROM `sahyadri_b2b.sales_orders` AS o JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
                                     WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN window_start AND window_end
                                     GROUP BY i.product_id) AS x USING (product_id)
                      WHERE l.selling_price / l.neighbour_price - 1 < -band)) > 1, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
