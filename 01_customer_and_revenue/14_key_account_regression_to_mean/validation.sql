/* =============================================================================
   Case study · Key-account selection and regression to the mean — validation
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE top_n INT64 DEFAULT 30;

WITH c AS (SELECT * FROM `sahyadri_b2b.ka_customer_years`),
     p AS (SELECT * FROM `sahyadri_b2b.ka_pairs`),
     s AS (SELECT * FROM `sahyadri_b2b.ka_selection`),

src AS (
    SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND EXTRACT(MONTH FROM o.order_date) <= 9
),
decile_bounds AS (
    SELECT pair, decile_y1, COUNT(*) AS n, MIN(y1) AS lo, MAX(y1) AS hi
    FROM p WHERE decile_y1 IS NOT NULL GROUP BY pair, decile_y1
),
-- slope from raw sums: (n Sxy - Sx Sy) / (n Sxx - Sx^2)
slope_check AS (
    SELECT pair,
           (COUNT(*) * SUM(LN(y1) * LN(y2)) - SUM(LN(y1)) * SUM(LN(y2)))
         / (COUNT(*) * SUM(LN(y1) * LN(y1)) - POW(SUM(LN(y1)), 2))                          AS slope_sums,
           COVAR_SAMP(LN(y1), LN(y2)) / VAR_SAMP(LN(y1))                                   AS slope_cov
    FROM p WHERE y1 > 0 AND y2 > 0 GROUP BY pair
),

checks AS (
    SELECT '01. Window revenue = source January-September revenue (rupees)' AS check_name, 0 AS expected,
           CAST(ROUND((SELECT SUM(rev_2024 + rev_2025 + rev_2026) FROM c) - (SELECT v FROM src), 0) AS INT64) AS actual
    UNION ALL
    SELECT '02. Two pair rows per customer', 0,
           (SELECT COUNT(*) FROM p) - 2 * (SELECT COUNT(*) FROM c)
    UNION ALL
    SELECT '03. First-year ranks run 1..n in each pair', 0,
           (SELECT COUNTIF(mx != n OR d != n) FROM (SELECT pair, MAX(rank_y1) AS mx, COUNT(rank_y1) AS n, COUNT(DISTINCT rank_y1) AS d FROM p GROUP BY pair))
    UNION ALL
    SELECT '04. Decile = CEIL(10 x rank / active customers)', 0,
           (SELECT COUNTIF(decile_y1 != CAST(CEIL(10 * rank_y1 / active_y1) AS INT64)) FROM p WHERE rank_y1 IS NOT NULL)
    UNION ALL
    SELECT '05. Deciles differ in size by at most 1 and do not overlap', 0,
           (SELECT COUNTIF(mx - mn > 1) FROM (SELECT pair, MAX(n) AS mx, MIN(n) AS mn FROM decile_bounds GROUP BY pair))
         + (SELECT COUNT(*) FROM decile_bounds AS a JOIN decile_bounds AS b
              ON b.pair = a.pair AND b.decile_y1 = a.decile_y1 + 1 WHERE b.hi > a.lo)
    UNION ALL
    SELECT '06. Year 2 of the first pair = year 1 of the second pair', 0,
           (SELECT COUNT(*) FROM p AS a JOIN p AS b ON b.customer_id = a.customer_id
             WHERE a.pair = '2024 -> 2025' AND b.pair = '2025 -> 2026' AND ABS(a.y2 - b.y1) > 1e-6)
    UNION ALL
    SELECT '07. Log slope = recount from raw sums', 0,
           (SELECT COUNTIF(ABS(slope_sums - slope_cov) > 1e-9) FROM slope_check)
    UNION ALL
    SELECT '08. Each rule selects exactly 30 distinct accounts', 0,
           (SELECT COUNTIF(n != top_n OR d != top_n) FROM (SELECT rule, COUNT(*) AS n, COUNT(DISTINCT customer_id) AS d FROM s GROUP BY rule))
    UNION ALL
    SELECT '09. Hindsight selection captures at least as much as any rule', 0,
           (SELECT COUNTIF(v > (SELECT SUM(rev_2026) FROM s WHERE rule LIKE 'Z.%'))
              FROM (SELECT rule, SUM(rev_2026) AS v FROM s GROUP BY rule))
    UNION ALL
    SELECT '10. Rule A = top 30 by first-year rank in the 2025 -> 2026 pair', 0,
           (SELECT COUNT(*) FROM s FULL OUTER JOIN (SELECT customer_id FROM p WHERE pair = '2025 -> 2026' AND rank_y1 <= top_n) AS t
              ON t.customer_id = s.customer_id AND s.rule = 'A. 2025 revenue'
             WHERE (s.rule = 'A. 2025 revenue' OR s.rule IS NULL) AND (s.customer_id IS NULL OR t.customer_id IS NULL))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
