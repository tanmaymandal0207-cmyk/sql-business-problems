/* =============================================================================
   Case study · January price increase and price discipline — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE min_purchases INT64 DEFAULT 4;

WITH l AS (SELECT * FROM `sahyadri_b2b.pi_lines`),
     s AS (SELECT * FROM `sahyadri_b2b.pi_product_steps`),
     d AS (SELECT * FROM `sahyadri_b2b.pi_dispersion`),
     r AS (SELECT * FROM `sahyadri_b2b.pi_repeat_purchases`),

factor_split AS (
    -- the median factor should split each year's lines in half
    SELECT price_year,
           COUNTIF(price_ratio < price_factor) AS below, COUNTIF(price_ratio > price_factor) AS above, COUNT(*) AS n
    FROM l GROUP BY price_year
),
eligible_pairs AS (
    SELECT customer_id, product_id, COUNT(*) AS n
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY customer_id, product_id
    HAVING COUNT(*) >= min_purchases
),
next_recount AS (
    -- next purchase date recomputed with a self-join instead of LEAD()
    SELECT a.order_id, a.product_id, MIN(b.order_date) AS next_date
    FROM r AS a
    LEFT JOIN r AS b
      ON b.customer_id = a.customer_id AND b.product_id = a.product_id
     AND (b.order_date > a.order_date OR (b.order_date = a.order_date AND b.order_id > a.order_id))
    GROUP BY a.order_id, a.product_id
),
customer_recount AS (
    SELECT customer_id, COUNT(*) AS n, AVG(price_deviation) AS m FROM l GROUP BY customer_id
),

checks AS (
    SELECT '01. Line table = source order lines' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM l) - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_order_items`)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_item_id) FROM l) AS actual
    UNION ALL
    SELECT '02. Price factor is the median of each year (split within 1 line)', 0,
           (SELECT COUNTIF(ABS(below - above) > 1) FROM factor_split)
    UNION ALL
    SELECT '03. Deviation = unit price / list in force - 1', 0,
           (SELECT COUNTIF(ABS(price_deviation - (unit_price / (selling_price * price_factor) - 1)) > 1e-12) FROM l)
    UNION ALL
    SELECT '04. Below-list + above-list = net difference (paise)', 0,
           CAST(ROUND(100 * (SELECT SUM(IF(unit_price < list_in_force, -quantity * (list_in_force - unit_price), 0))
                                  + SUM(IF(unit_price > list_in_force,  quantity * (unit_price - list_in_force), 0))
                                  - SUM(quantity * (unit_price - list_in_force)) FROM l)) AS INT64)
    UNION ALL
    SELECT '05. Product steps exist for every product sold (2+ lines) in consecutive years', 0,
           (SELECT COUNT(*) FROM (SELECT product_id, price_year FROM l GROUP BY product_id, price_year HAVING COUNT(*) >= 2) AS a
              JOIN (SELECT product_id, price_year FROM l GROUP BY product_id, price_year HAVING COUNT(*) >= 2) AS b
                ON b.product_id = a.product_id AND b.price_year = a.price_year - 1)
         - (SELECT COUNT(*) FROM s)
    UNION ALL
    SELECT '06. Product step z recomputed', 0,
           (SELECT COUNTIF(ABS(z - (product_step - company_step) / step_se) > 1e-9) FROM s)
    UNION ALL
    SELECT '07. Dispersion members cover every line in each dimension', 0,
           (SELECT COUNTIF(n != (SELECT COUNT(*) FROM l)) FROM (SELECT dimension, SUM(n) AS n FROM d GROUP BY dimension))
    UNION ALL
    SELECT '08. Customer means = independent recount', 0,
           (SELECT COUNT(*) FROM d JOIN customer_recount AS c ON CAST(c.customer_id AS STRING) = d.member
             WHERE d.dimension = 'Customer' AND (d.n != c.n OR ABS(d.mean_dev - c.m) > 1e-12))
    UNION ALL
    SELECT '09. Repeat-purchase rows = pairs bought 4+ times', 0,
           (SELECT COUNT(*) FROM r) - (SELECT SUM(n) FROM eligible_pairs)
    UNION ALL
    SELECT '10. Next purchase date (LEAD) = self-join recount', 0,
           (SELECT COUNT(*) FROM r JOIN next_recount AS x USING (order_id, product_id)
             WHERE IFNULL(r.next_date, DATE '1900-01-01') != IFNULL(x.next_date, DATE '1900-01-01'))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
