/* =============================================================================
   Case study · Benford's law forensic test — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE min_amount FLOAT64 DEFAULT 10;

WITH bv AS (SELECT * FROM `sahyadri_b2b.benford_values`),
     f1 AS (SELECT * FROM `sahyadri_b2b.benford_first_digit`),
     f2 AS (SELECT * FROM `sahyadri_b2b.benford_first_two`),

checks AS (
    SELECT '01. Payment records vs source payments of at least ₹10' AS check_name, 0 AS expected,
           (SELECT COUNTIF(population = 'Payments') FROM bv)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.payments` WHERE amount >= min_amount) AS actual
    UNION ALL
    SELECT '02. Order-line records vs source lines of at least ₹10', 0,
           (SELECT COUNTIF(population = 'Order lines') FROM bv)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_order_items` WHERE quantity * unit_price >= min_amount)
    UNION ALL
    SELECT '03. Leading digits outside 1-9 or 10-99', 0,
           (SELECT COUNTIF(first_digit NOT BETWEEN 1 AND 9 OR first_two_digits NOT BETWEEN 10 AND 99) FROM bv)
    UNION ALL
    SELECT '04. First digit is not the first digit of the first two', 0,
           (SELECT COUNTIF(first_digit <> DIV(first_two_digits, 10)) FROM bv)
    UNION ALL
    -- independent arithmetic method: scale into [1, 10) with LOG10, allowing for float error
    SELECT '05. First digit vs LOG10 scaling method', 0,
           (SELECT COUNTIF(first_digit <> CAST(FLOOR(FLOOR(amount) / POW(10, FLOOR(LOG10(FLOOR(amount))) ) + 1e-9) AS INT64)) FROM bv)
    UNION ALL
    SELECT '06. Expected first-digit shares do not sum to 1', 0,
           (SELECT COUNTIF(ABS(t - 1) > 1e-12) FROM (SELECT population, SUM(expected_share) AS t FROM f1 GROUP BY population))
    UNION ALL
    SELECT '07. Expected first-two-digit shares do not sum to 1', 0,
           (SELECT COUNTIF(ABS(t - 1) > 1e-12) FROM (SELECT population, SUM(expected_share) AS t FROM f2 GROUP BY population))
    UNION ALL
    SELECT '08. Observed first-digit counts do not sum to records', 0,
           (SELECT COUNTIF(c <> n) FROM (SELECT population, SUM(observed_count) AS c, ANY_VALUE(n) AS n FROM f1 GROUP BY population))
    UNION ALL
    SELECT '09. First-two-digit counts roll up to first-digit counts', 0,
           (SELECT COUNT(*) FROM f1 JOIN (SELECT population, DIV(digits, 10) AS d, SUM(observed_count) AS c FROM f2 GROUP BY population, d) AS r
              ON r.population = f1.population AND r.d = f1.digit
             WHERE r.c <> f1.observed_count)
    UNION ALL
    SELECT '10. Rows per population: 9 first-digit and 90 first-two-digit', 0,
           (SELECT COUNTIF(k <> 9) FROM (SELECT population, COUNT(*) AS k FROM f1 GROUP BY population))
         + (SELECT COUNTIF(k <> 90) FROM (SELECT population, COUNT(*) AS k FROM f2 GROUP BY population))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
