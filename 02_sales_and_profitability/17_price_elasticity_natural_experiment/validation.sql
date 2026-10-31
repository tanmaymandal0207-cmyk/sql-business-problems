/* =============================================================================
   Case study · Price elasticity natural experiment — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE repeat_days      INT64 DEFAULT 180;
DECLARE last_repeat_line DATE  DEFAULT DATE '2026-03-31';

WITH l AS (SELECT * FROM `sahyadri_b2b.pe_lines`),
     c AS (SELECT * FROM `sahyadri_b2b.pe_centred`),
     e AS (SELECT * FROM `sahyadri_b2b.pe_elasticity`),

src AS (
    SELECT COUNT(*) AS n
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
factors AS (
    SELECT price_year, COUNT(DISTINCT ROUND(list_in_force / selling_price, 12)) AS k,
           ANY_VALUE(list_in_force / selling_price) AS f
    FROM l GROUP BY price_year
),
-- check 07: the elasticity rebuilt with an explicit regression on product-year dummies removed by demeaning a second way
cells AS (
    SELECT product_id, price_year, AVG(ln_qty) AS my, AVG(ln_price_dev) AS mx, COUNT(*) AS n
    FROM l GROUP BY product_id, price_year
),
direct AS (
    SELECT SUM((l.ln_price_dev - k.mx) * (l.ln_qty - k.my)) / SUM(POW(l.ln_price_dev - k.mx, 2)) AS slope
    FROM l JOIN cells AS k ON k.product_id = l.product_id AND k.price_year = l.price_year
    WHERE k.n >= 2
),

checks AS (
    SELECT '01. One line per valid order line' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM l) - (SELECT n FROM src)) + (SELECT COUNT(*) - COUNT(DISTINCT order_item_id) FROM l) AS actual
    UNION ALL
    SELECT '02. One price factor per year, and it is the median invoice / list ratio', 0,
           (SELECT COUNTIF(k != 1) FROM factors)
         + (SELECT COUNTIF(ABS(f.f - m.med) > 1e-9)
              FROM factors AS f
              JOIN (SELECT DISTINCT price_year, PERCENTILE_CONT(unit_price / selling_price, 0.5) OVER (PARTITION BY price_year) AS med FROM l) AS m
                USING (price_year))
    UNION ALL
    SELECT '03. Deviation = invoice / list in force - 1, within +/- 3.1 %', 0,
           (SELECT COUNTIF(ABS(price_deviation - (unit_price / list_in_force - 1)) > 1e-12 OR ABS(price_deviation) > 0.031) FROM l)
    UNION ALL
    SELECT '04. Log columns agree with the raw values', 0,
           (SELECT COUNTIF(ABS(ln_qty - LN(quantity)) > 1e-12 OR ABS(ln_price_dev - LN(1 + price_deviation)) > 1e-12
                           OR ABS(ln_discount_factor - LN(1 - discount_pct / 100)) > 1e-12) FROM l)
    UNION ALL
    SELECT '05. Centred values average zero in every product-year', 0,
           (SELECT COUNTIF(ABS(ay) > 1e-9 OR ABS(ax) > 1e-9 OR ABS(ad) > 1e-9)
              FROM (SELECT product_id, price_year, AVG(y) AS ay, AVG(x_price) AS ax, AVG(x_discount) AS ad FROM c GROUP BY product_id, price_year))
    UNION ALL
    SELECT '06. Centred table has one row per line', 0,
           ABS((SELECT COUNT(*) FROM c) - (SELECT COUNT(*) FROM l))
    UNION ALL
    SELECT '07. Price elasticity = direct recount', 0,
           (SELECT IF(ABS(e.slope - d.slope) > 1e-9, 1, 0) FROM e CROSS JOIN direct AS d WHERE e.driver LIKE 'Price%')
    UNION ALL
    SELECT '08. Standard errors positive, two drivers estimated on the same lines', 0,
           (SELECT COUNTIF(standard_error <= 0 OR standard_error IS NULL) FROM e)
         + ABS(2 - (SELECT COUNT(*) FROM e)) + (SELECT COUNT(DISTINCT n) - 1 FROM e)
    UNION ALL
    SELECT '09. Below- and above-list amounts add up to the net difference from list', 0,
           IF(ABS((SELECT SUM(IF(price_deviation > 0, quantity * (unit_price - list_in_force), 0))
                         - SUM(IF(price_deviation < 0, quantity * (list_in_force - unit_price), 0)) FROM l)
                  - (SELECT SUM(quantity * (unit_price - list_in_force)) FROM l)) > 0.01, 1, 0)
    UNION ALL
    SELECT '10. Only product-years with 2+ lines enter the elasticity', 0,
           (SELECT ABS(MAX(n) - (SELECT COUNTIF(cell_lines >= 2) FROM c)) FROM e)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
