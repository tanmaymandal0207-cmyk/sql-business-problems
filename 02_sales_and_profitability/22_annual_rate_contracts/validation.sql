/* =============================================================================
   Case study · Annual rate contracts — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_day  DATE    DEFAULT DATE '2024-01-01';
DECLARE last_day   DATE    DEFAULT DATE '2026-09-30';
DECLARE min_value  FLOAT64 DEFAULT 200000;
DECLARE target_hit FLOAT64 DEFAULT 0.80;

WITH l AS (SELECT * FROM `sahyadri_b2b.rc_lines`),
     p AS (SELECT * FROM `sahyadri_b2b.rc_pairs`),
     lv AS (SELECT * FROM `sahyadri_b2b.rc_levels`),
     f AS (SELECT * FROM `sahyadri_b2b.rc_offers`),

src AS (
    SELECT COUNT(*) AS n, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN first_day AND last_day
),
windows AS (
    SELECT 'A. 2024 -> 2025' AS test, DATE '2024-01-01' AS y1_start, DATE '2025-01-01' AS y2_start, DATE '2025-12-31' AS y2_end
    UNION ALL
    SELECT 'B. Oct 2024-Sep 2025 -> Oct 2025-Sep 2026', DATE '2024-10-01', DATE '2025-10-01', DATE '2026-09-30'
),
window_totals AS (
    -- Y2 revenue of pairs that were active in Y1, and all Y1 revenue
    SELECT w.test,
           SUM(IF(l.order_date < w.y2_start, l.value, 0)) AS y1
    FROM l JOIN windows AS w ON l.order_date BETWEEN w.y1_start AND w.y2_end
    GROUP BY w.test
),
quarters_recount AS (
    SELECT w.test, l.customer_id, l.category_id, COUNT(DISTINCT l.quarter) AS q
    FROM l JOIN windows AS w ON l.order_date >= w.y1_start AND l.order_date < w.y2_start
    GROUP BY w.test, l.customer_id, l.category_id
),
y2_recount AS (
    SELECT w.test, l.customer_id, l.category_id, SUM(l.value) AS v
    FROM l JOIN windows AS w ON l.order_date >= w.y2_start AND l.order_date <= w.y2_end
    GROUP BY w.test, l.customer_id, l.category_id
),
safe AS (
    SELECT MAX(c) AS c FROM (SELECT c FROM lv GROUP BY c HAVING MIN(met_share) >= target_hit)
),
latest AS (
    SELECT customer_id, category_id, COUNT(DISTINCT quarter) AS q, SUM(value) AS v
    FROM l WHERE order_date >= DATE '2025-10-01' GROUP BY customer_id, category_id
),

checks AS (
    SELECT '01. Order lines and revenue = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM l) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(value) FROM l) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. One row per test, customer and category, 1-4 quarters in Y1', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(test, '|', CAST(customer_id AS STRING), '|', CAST(category_id AS STRING))) FROM p)
         + (SELECT COUNTIF(y1_quarters NOT BETWEEN 1 AND 4) FROM p)
    UNION ALL
    SELECT '03. Y1 value = all Y1 revenue of the window, both tests', 0,
           (SELECT COUNT(*) FROM window_totals AS w JOIN (SELECT test, SUM(y1_value) AS y1 FROM p GROUP BY test) AS x USING (test)
             WHERE ABS(w.y1 - x.y1) > 1)
         + ABS((SELECT COUNT(DISTINCT test) FROM p) - 2)
    UNION ALL
    SELECT '04. Quarters active in Y1 = recount', 0,
           (SELECT COUNT(*) FROM p LEFT JOIN quarters_recount AS r USING (test, customer_id, category_id) WHERE IFNULL(r.q, 0) != p.y1_quarters)
    UNION ALL
    SELECT '05. Y2 value = recount (zero if the pair did not buy in Y2)', 0,
           (SELECT COUNT(*) FROM p LEFT JOIN y2_recount AS r USING (test, customer_id, category_id) WHERE ABS(IFNULL(r.v, 0) - p.y2_value) > 1e-6)
    UNION ALL
    SELECT '06. Qualifying = all 4 quarters and at least Rs 2 lakh in Y1', 0,
           (SELECT COUNTIF(qualifies != (y1_quarters = 4 AND y1_value >= min_value)) FROM p)
    UNION ALL
    SELECT '07. Commitment levels: met share, commitment and shortfall = recount', 0,
           (SELECT COUNT(*) FROM lv JOIN (
               SELECT pp.test, x.c, COUNT(*) AS n, COUNTIF(pp.y2_value >= x.c * pp.y1_value) / COUNT(*) AS m,
                      SUM(x.c * pp.y1_value) AS cm, SUM(GREATEST(0, x.c * pp.y1_value - pp.y2_value)) AS sf
               FROM p AS pp CROSS JOIN (SELECT DISTINCT c FROM lv) AS x WHERE pp.qualifies GROUP BY pp.test, x.c) AS r
             USING (test, c)
             WHERE lv.pairs != r.n OR ABS(lv.met_share - r.m) > 1e-12 OR ABS(lv.committed - r.cm) > 1e-3 OR ABS(lv.shortfall - r.sf) > 1e-3)
         + ABS((SELECT COUNT(*) FROM lv) - 2 * 15)
    UNION ALL
    SELECT '08. Safe level met by 80 % in both tests, the next level up is not', 0,
           (SELECT COUNTIF(met_share < target_hit) FROM lv WHERE ABS(c - (SELECT c FROM safe)) < 1e-9)
         + IF((SELECT MIN(met_share) FROM lv WHERE ABS(c - ((SELECT c FROM safe) + 0.05)) < 1e-9) >= target_hit, 1, 0)
    UNION ALL
    SELECT '09. Offers = latest-year pairs with 4 quarters and Rs 2 lakh+, commitment = safe level x value', 0,
           ABS((SELECT COUNT(*) FROM f) - (SELECT COUNTIF(q = 4 AND v >= min_value) FROM latest))
         + (SELECT COUNTIF(ABS(commitment - (SELECT c FROM safe) * last_year_value) > 1e-6) FROM f)
    UNION ALL
    SELECT '10. Offer values = test B Y2 values for the same pairs', 0,
           (SELECT COUNT(*) FROM f JOIN p ON p.test LIKE 'B.%' AND p.customer_id = f.customer_id AND p.category_id = f.category_id
             WHERE ABS(p.y2_value - f.last_year_value) > 1e-6)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
