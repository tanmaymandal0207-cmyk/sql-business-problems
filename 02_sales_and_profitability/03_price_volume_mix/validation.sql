/* =============================================================================
   Case study · Price-volume-mix analysis — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE py_start DATE DEFAULT DATE '2025-01-01';
DECLARE py_end   DATE DEFAULT DATE '2025-09-30';
DECLARE cy_start DATE DEFAULT DATE '2026-01-01';
DECLARE cy_end   DATE DEFAULT DATE '2026-09-30';

WITH p AS (
    SELECT * FROM `sahyadri_b2b.product_price_volume`
),

source_lines AS (
    SELECT
        i.product_id,
        IF(o.order_date BETWEEN py_start AND py_end, 'PY', 'CY') AS period,
        i.quantity,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND (o.order_date BETWEEN py_start AND py_end OR o.order_date BETWEEN cy_start AND cy_end)
),

cont AS (
    SELECT SUM(qty_py) AS qty_py, SUM(qty_cy) AS qty_cy, SUM(revenue_py) AS rev_py,
           SUM(price_effect) AS price_effect, SUM(quantity_effect) AS quantity_effect
    FROM p WHERE product_status = 'Continuing'
),

bridge AS (
    SELECT
        (SELECT price_effect FROM cont)
      + (SELECT (qty_cy - qty_py) * (rev_py / qty_py) FROM cont)
      + (SELECT quantity_effect - (qty_cy - qty_py) * (rev_py / qty_py) FROM cont)
      + (SELECT SUM(IF(product_status = 'New', revenue_cy, 0)) FROM p)
      - (SELECT SUM(IF(product_status = 'Discontinued', revenue_py, 0)) FROM p)  AS parts,
        (SELECT SUM(revenue_cy) - SUM(revenue_py) FROM p)                         AS total_change
),

checks AS (
    SELECT '01. Rows minus distinct products' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT product_id) FROM p) AS actual
    UNION ALL
    SELECT '02. Products vs products sold in either period', 0,
           (SELECT COUNT(*) FROM p) - (SELECT COUNT(DISTINCT product_id) FROM source_lines)
    UNION ALL
    SELECT '03. PY revenue vs source (paise)', 0,
           CAST(ROUND((SELECT SUM(revenue_py) FROM p)
                    - (SELECT SUM(revenue) FROM source_lines WHERE period = 'PY'), 2) * 100 AS INT64)
    UNION ALL
    SELECT '04. CY revenue vs source (paise)', 0,
           CAST(ROUND((SELECT SUM(revenue_cy) FROM p)
                    - (SELECT SUM(revenue) FROM source_lines WHERE period = 'CY'), 2) * 100 AS INT64)
    UNION ALL
    SELECT '05. Quantity vs source', 0,
           (SELECT SUM(qty_py + qty_cy) FROM p) - (SELECT SUM(quantity) FROM source_lines)
    UNION ALL
    SELECT '06. Bridge parts vs total change (paise)', 0,
           CAST(ROUND((SELECT parts - total_change FROM bridge), 2) * 100 AS INT64)
    UNION ALL
    SELECT '07. Continuing products where price + quantity effect <> revenue change', 0,
           (SELECT COUNTIF(ABS(price_effect + quantity_effect - (revenue_cy - revenue_py)) > 0.01)
            FROM p WHERE product_status = 'Continuing')
    UNION ALL
    SELECT '08. Product status inconsistent with quantities', 0,
           (SELECT COUNTIF(
                (product_status = 'Continuing'   AND (qty_py = 0 OR qty_cy = 0))
             OR (product_status = 'New'          AND qty_py > 0)
             OR (product_status = 'Discontinued' AND qty_cy > 0)) FROM p)
    UNION ALL
    SELECT '09. Missing price where quantity exists', 0,
           (SELECT COUNTIF((qty_py > 0 AND price_py IS NULL) OR (qty_cy > 0 AND price_cy IS NULL)) FROM p)
    UNION ALL
    SELECT '10. Category effects vs total effects (paise)', 0,
           CAST(ROUND((SELECT SUM(e) FROM (SELECT SUM(price_effect + quantity_effect) AS e
                                           FROM p GROUP BY category_name))
                    - (SELECT SUM(price_effect + quantity_effect) FROM p), 2) * 100 AS INT64)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
