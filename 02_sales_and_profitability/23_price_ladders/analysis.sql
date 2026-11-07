/* =============================================================================
   Case study · Price ladders: are size variants priced consistently?
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Many products come in a ladder of sizes: motors from 0.5 to 50 HP,
   bearings by bore, valves and hoses by inch, bolts by diameter. Each list
   price was set when the item was added, by whoever added it. The pricing
   manager suspects the ladders are uneven, with some sizes priced too
   cheaply and others too dearly for their place in the range. She asks:
     1. Which products form size ladders, and how does price rise with size?
     2. Which rungs are out of line with the rest of their ladder?
     3. Does margin hold up along each ladder, or do some sizes carry
        thin or negative margins?
     4. What would bringing the out-of-line rungs back to the ladder be
        worth?

   METHOD
     - Families: products whose names differ only in their numbers
       (digits masked), with 3 or more members. Size is read from the name
       with a rule per family (HP, inches including fractions, mm, metric
       thread M, bearing bore = last two digits x 5 mm). Deep groove ball
       and taper roller bearings are split into their series (62 / 63,
       302 / 322), because a wider series is a different product.
     - Ladder: least squares of ln(list price) on ln(size) within each
       family. The slope is the price elasticity to size (1 = price rises
       in proportion to size; below 1 = bigger sizes cost less per unit).
     - Out of line (neighbour test): each inner rung's list price against
       the price interpolated between the next smaller and next larger
       size on the log-log scale. More than 10 % above or below = out of
       line. A single straight line is not used for this, because real
       ladders bend (a 0.5 HP motor carries a fixed cost a line ignores).
     - Margin: (list price - unit cost) / list price.
     - Value: realised revenue in the latest 12 months (October 2025 -
       September 2026, valid orders) x (neighbour price / list price - 1),
       assuming the same volume.
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE band         FLOAT64 DEFAULT 0.10;

-- -----------------------------------------------------------------------------
-- Step 1 · Families and sizes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pl_products` AS
WITH named AS (
    SELECT p.product_id, p.product_name, c.category_name, p.unit_cost, p.selling_price,
           REGEXP_REPLACE(p.product_name, r'[0-9]+(\.[0-9]+)?(/[0-9]+)?', '#')         AS mask,
           -- bearing series (62 / 63, 302 / 322): a wider series is a different product, not a bigger size
           REGEXP_EXTRACT(p.product_name, r'Bearing (6[0-9]|3[0-9]{2})[0-9]{2}') AS bearing_series
    FROM `sahyadri_b2b.products` AS p
    JOIN `sahyadri_b2b.product_categories` AS c ON c.category_id = p.category_id
),
families AS (
    SELECT *,
           IF(bearing_series IS NULL, mask, CONCAT(mask, ' (', bearing_series, ' series)')) AS family
    FROM named
),
sized AS (
    SELECT *,
           CASE
               WHEN REGEXP_CONTAINS(product_name, r' HP') THEN CAST(REGEXP_EXTRACT(product_name, r'([0-9]+(?:\.[0-9]+)?) HP') AS FLOAT64)
               WHEN REGEXP_CONTAINS(product_name, r'Bearing') THEN
                    -- bore code: 00-03 are 10, 12, 15 and 17 mm; from 04 up, code x 5 mm
                    CASE CAST(REGEXP_EXTRACT(product_name, r'([0-9]{2})(?:-2RS)?$') AS INT64)
                         WHEN 0 THEN 10 WHEN 1 THEN 12 WHEN 2 THEN 15 WHEN 3 THEN 17
                         ELSE CAST(REGEXP_EXTRACT(product_name, r'([0-9]{2})(?:-2RS)?$') AS INT64) * 5 END
               WHEN REGEXP_CONTAINS(product_name, r'Cylinder') THEN CAST(REGEXP_EXTRACT(product_name, r'([0-9]+)x') AS FLOAT64)
               WHEN REGEXP_CONTAINS(product_name, r' M[0-9]') THEN CAST(REGEXP_EXTRACT(product_name, r' M([0-9]+)') AS FLOAT64)
               WHEN REGEXP_CONTAINS(product_name, r'[0-9/]+ in') THEN
                    CASE WHEN STRPOS(REGEXP_EXTRACT(product_name, r'([0-9/]+) in'), '/') > 0
                         THEN CAST(REGEXP_EXTRACT(product_name, r'([0-9]+)/[0-9]+ in') AS FLOAT64)
                              / CAST(REGEXP_EXTRACT(product_name, r'[0-9]+/([0-9]+) in') AS FLOAT64)
                         ELSE CAST(REGEXP_EXTRACT(product_name, r'([0-9]+) in') AS FLOAT64) END
               WHEN REGEXP_CONTAINS(product_name, r'[0-9]+ mm') THEN CAST(REGEXP_EXTRACT(product_name, r'([0-9]+) mm') AS FLOAT64)
           END                                                                        AS size
    FROM families
)
SELECT s.*, COUNT(*) OVER (PARTITION BY family)                                       AS family_size
FROM sized AS s;

-- Ladders: families with 3 or more members and a size for every member
CREATE OR REPLACE TABLE `sahyadri_b2b.pl_ladders` AS
WITH members AS (
    SELECT * FROM `sahyadri_b2b.pl_products`
    WHERE family_size >= 3 AND family IN (
        SELECT family FROM `sahyadri_b2b.pl_products` GROUP BY family HAVING COUNTIF(size IS NULL) = 0 AND COUNT(DISTINCT size) = COUNT(*)
    )
),
fit AS (
    SELECT family,
           COVAR_POP(LN(size), LN(selling_price)) / VAR_POP(LN(size))                 AS slope,
           AVG(LN(selling_price)) - COVAR_POP(LN(size), LN(selling_price)) / VAR_POP(LN(size)) * AVG(LN(size)) AS intercept,
           POW(CORR(LN(size), LN(selling_price)), 2)                                  AS r_squared,
           COVAR_POP(LN(size), LN(unit_cost)) / VAR_POP(LN(size))                     AS cost_slope
    FROM members GROUP BY family
)
SELECT m.product_id, m.product_name, m.category_name, m.family, m.size, m.unit_cost, m.selling_price,
       f.slope, f.r_squared, f.cost_slope,
       -- neighbour test: log-log interpolation between the next smaller and next larger size
       EXP(LN(LAG(m.selling_price) OVER w)
           + (LN(LEAD(m.selling_price) OVER w) - LN(LAG(m.selling_price) OVER w))
             * (LN(m.size) - LN(LAG(m.size) OVER w)) / (LN(LEAD(m.size) OVER w) - LN(LAG(m.size) OVER w))) AS neighbour_price,
       (m.selling_price - m.unit_cost) / m.selling_price                              AS margin,
       ROW_NUMBER() OVER w                                                            AS rung
FROM members AS m JOIN fit AS f USING (family)
WINDOW w AS (PARTITION BY m.family ORDER BY m.size);

SELECT
    family, ANY_VALUE(category_name) AS category, COUNT(*) AS sizes,
    MIN(size) AS smallest, MAX(size) AS largest,
    ROUND(ANY_VALUE(slope), 2) AS price_slope, ROUND(ANY_VALUE(r_squared), 3) AS r_squared,
    ROUND(ANY_VALUE(cost_slope), 2) AS cost_slope
FROM `sahyadri_b2b.pl_ladders`
GROUP BY family
ORDER BY sizes DESC, family;

-- -----------------------------------------------------------------------------
-- Step 2 · Rungs out of line with their neighbours
-- -----------------------------------------------------------------------------
SELECT
    family, product_name, size,
    ROUND(selling_price, 0) AS list_price, ROUND(neighbour_price, 0) AS neighbour_price,
    ROUND(100 * (selling_price / neighbour_price - 1), 1) AS gap_pct,
    ROUND(100 * margin, 1) AS margin_pct
FROM `sahyadri_b2b.pl_ladders`
WHERE ABS(selling_price / neighbour_price - 1) > band
ORDER BY gap_pct;

SELECT
    COUNT(*)                                                                          AS ladder_products,
    COUNTIF(neighbour_price IS NOT NULL)                                              AS inner_rungs_tested,
    COUNTIF(ABS(selling_price / neighbour_price - 1) > band)                          AS out_of_line,
    COUNTIF(selling_price / neighbour_price - 1 < -band)                              AS below_neighbours,
    COUNTIF(selling_price / neighbour_price - 1 > band)                               AS above_neighbours,
    COUNTIF(ABS(selling_price / neighbour_price - 1) > 0.05)                          AS out_by_more_than_5_pct,
    ROUND(100 * APPROX_QUANTILES(ABS(selling_price / neighbour_price - 1), 100)[OFFSET(50)], 1) AS median_abs_gap_pct
FROM `sahyadri_b2b.pl_ladders`;

-- Price inversions: a bigger size listed at or below a smaller one in the same family
SELECT
    a.family, a.product_name AS smaller, ROUND(a.selling_price, 0) AS smaller_price,
    b.product_name AS bigger, ROUND(b.selling_price, 0) AS bigger_price
FROM `sahyadri_b2b.pl_ladders` AS a
JOIN `sahyadri_b2b.pl_ladders` AS b ON a.family = b.family AND b.size > a.size AND b.selling_price <= a.selling_price
ORDER BY a.family, a.size;

-- -----------------------------------------------------------------------------
-- Step 3 · Margin along each ladder
-- -----------------------------------------------------------------------------
SELECT
    family,
    ROUND(100 * MIN(margin), 1)                                                       AS lowest_margin_pct,
    ROUND(100 * MAX(margin), 1)                                                       AS highest_margin_pct,
    ROUND(100 * (MAX(margin) - MIN(margin)), 1)                                       AS margin_spread_pts,
    ROUND(CORR(LN(size), margin), 2)                                                  AS corr_size_margin,
    MAX(IF(margin = min_margin, product_name, NULL))                                  AS thinnest_rung
FROM (SELECT *, MIN(margin) OVER (PARTITION BY family) AS min_margin FROM `sahyadri_b2b.pl_ladders`)
GROUP BY family
ORDER BY margin_spread_pts DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · What re-laddering would be worth (latest 12 months)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pl_sales` AS
SELECT i.product_id,
       SUM(i.quantity)                                                                AS units,
       SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))     AS revenue
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN window_start AND window_end
GROUP BY i.product_id;

SELECT
    l.family, l.product_name,
    ROUND(100 * (l.selling_price / l.neighbour_price - 1), 1)                         AS gap_pct,
    IFNULL(s.units, 0)                                                                AS units_last_12_months,
    ROUND(IFNULL(s.revenue, 0) / 1e5, 2)                                              AS revenue_lakh,
    ROUND(IFNULL(s.revenue, 0) * (l.neighbour_price / l.selling_price - 1) / 1e5, 2)   AS to_neighbour_price_lakh
FROM `sahyadri_b2b.pl_ladders` AS l
LEFT JOIN `sahyadri_b2b.pl_sales` AS s USING (product_id)
WHERE ABS(l.selling_price / l.neighbour_price - 1) > band
ORDER BY to_neighbour_price_lakh DESC;

SELECT
    ROUND(SUM(IFNULL(s.revenue, 0)) / 1e7, 2)                                         AS ladder_revenue_crore,
    ROUND(100 * SUM(IFNULL(s.revenue, 0)) / (SELECT SUM(revenue) FROM `sahyadri_b2b.pl_sales`), 1) AS share_of_revenue_pct,
    ROUND(SUM(IF(l.selling_price / l.neighbour_price - 1 < -band, IFNULL(s.revenue, 0) * (l.neighbour_price / l.selling_price - 1), 0)) / 1e5, 2) AS uplift_raising_low_rungs_lakh,
    ROUND(SUM(IF(l.selling_price / l.neighbour_price - 1 > band, IFNULL(s.revenue, 0) * (l.neighbour_price / l.selling_price - 1), 0)) / 1e5, 2) AS cost_of_cutting_high_rungs_lakh
FROM `sahyadri_b2b.pl_ladders` AS l
LEFT JOIN `sahyadri_b2b.pl_sales` AS s USING (product_id);
