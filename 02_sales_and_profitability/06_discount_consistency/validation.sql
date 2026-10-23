/* =============================================================================
   Case study · Discount consistency and price leakage — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE band_width   FLOAT64 DEFAULT 0.02;
DECLARE min_lines    INT64   DEFAULT 5;

WITH d AS (SELECT * FROM `sahyadri_b2b.customer_discount_band`),

lines AS (
    SELECT
        o.customer_id,
        o.employee_id,
        i.quantity * i.unit_price                                       AS gross_value,
        i.quantity * i.unit_price * IFNULL(i.discount_percent, 0) / 100 AS discount_amount
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN window_start AND window_end
),
emp_gross AS (
    SELECT customer_id, employee_id, SUM(gross_value) AS g
    FROM lines WHERE employee_id IS NOT NULL
    GROUP BY customer_id, employee_id
),
-- median property: at least half of the banded customers sit on each side of the benchmark
median_test AS (
    SELECT
        customer_segment,
        COUNT(*)                                          AS n,
        COUNTIF(effective_discount <= segment_benchmark + 0.00005) AS at_or_below,
        COUNTIF(effective_discount >= segment_benchmark - 0.00005) AS at_or_above
    FROM d
    WHERE band_status <> 'Not banded (too few lines)'
    GROUP BY customer_segment
),

checks AS (
    SELECT '01. Duplicate customers' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM d) AS actual
    UNION ALL
    SELECT '02. Customers vs active customers in source', 0,
           (SELECT COUNT(*) FROM d) - (SELECT COUNT(DISTINCT customer_id) FROM lines)
    UNION ALL
    SELECT '03. Gross value vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(gross_value) FROM d) - (SELECT SUM(gross_value) FROM lines), 0) AS INT64)
    UNION ALL
    SELECT '04. Discount amount vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(discount_amount) FROM d) - (SELECT SUM(discount_amount) FROM lines), 0) AS INT64)
    UNION ALL
    SELECT '05. Effective discount not equal to discount / gross', 0,
           (SELECT COUNTIF(ABS(effective_discount - discount_amount / gross_value) > 0.0001) FROM d)
    UNION ALL
    SELECT '06. Volume tier inconsistent with gross value', 0,
           (SELECT COUNTIF(
                 (volume_tier = '1. Under 2 lakh'      AND gross_value >= 200000)
              OR (volume_tier = '2. 2-10 lakh'         AND (gross_value < 200000  OR gross_value >= 1000000))
              OR (volume_tier = '3. 10-50 lakh'        AND (gross_value < 1000000 OR gross_value >= 5000000))
              OR (volume_tier = '4. 50 lakh and above' AND gross_value < 5000000)) FROM d)
    UNION ALL
    SELECT '07. Segment benchmark fails the median property', 0,
           (SELECT COUNTIF(at_or_below < n / 2 OR at_or_above < n / 2) FROM median_test)
    UNION ALL
    -- a tolerance of 0.0001 allows for effective_discount being stored to 4 decimals
    SELECT '08. Band status inconsistent with its rule', 0,
           (SELECT COUNTIF(
                 (band_status = 'Not banded (too few lines)' AND order_lines >= min_lines)
              OR (band_status = 'Over-discounted'  AND NOT (order_lines >= min_lines AND effective_discount > segment_benchmark + band_width - 0.0001))
              OR (band_status = 'Under-discounted' AND NOT (order_lines >= min_lines AND effective_discount < segment_benchmark - band_width + 0.0001))
              OR (band_status = 'Within band'      AND NOT (order_lines >= min_lines
                                                            AND effective_discount BETWEEN segment_benchmark - band_width - 0.0001
                                                                                       AND segment_benchmark + band_width + 0.0001))) FROM d)
    UNION ALL
    SELECT '09. Excess discount present only on over-discounted customers', 0,
           (SELECT COUNTIF((excess_discount > 0) <> (band_status = 'Over-discounted')) FROM d)
    UNION ALL
    SELECT '10. Primary salesperson is not the top gross-value salesperson', 0,
           (SELECT COUNT(*) FROM d
              JOIN emp_gross AS e ON e.customer_id = d.customer_id AND e.employee_id = d.primary_employee_id
             WHERE e.g < (SELECT MAX(g) FROM emp_gross AS x WHERE x.customer_id = d.customer_id) - 0.01)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
