/* =============================================================================
   Case study · Monetary unit sampling — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE fy_start       DATE    DEFAULT DATE '2025-04-01';
DECLARE fy_end         DATE    DEFAULT DATE '2026-03-31';
DECLARE reliability    FLOAT64 DEFAULT 3.0;
DECLARE trivial_amount FLOAT64 DEFAULT 10;

WITH p AS (SELECT * FROM `sahyadri_b2b.mus_population`),
     d AS (SELECT * FROM `sahyadri_b2b.mus_design`),
     s AS (SELECT * FROM `sahyadri_b2b.mus_selection`),
     e AS (SELECT * FROM `sahyadri_b2b.mus_evaluation`),

source_population AS (
    SELECT o.order_id, o.payment_status
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN (SELECT order_id, MAX(delivery_date) AS dd FROM `sahyadri_b2b.shipments`
          GROUP BY order_id HAVING COUNT(delivery_date) = COUNT(*)) AS x ON x.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND x.dd BETWEEN fy_start AND fy_end
),
-- selection recomputed from explicit selection points r + m*J
points AS (
    SELECT st.replicate, st.random_start + m * d.sampling_interval AS point
    FROM (SELECT DISTINCT replicate, random_start FROM s) AS st
    CROSS JOIN d
    CROSS JOIN UNNEST(GENERATE_ARRAY(0, d.sample_size - 1)) AS m
),
point_hits AS (
    SELECT pt.replicate, p.order_id
    FROM points AS pt
    JOIN p ON pt.point > p.cum_before AND pt.point <= p.cum_after
),

checks AS (
    SELECT '01. Population vs source delivered orders in the year' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM p) - (SELECT COUNT(*) FROM source_population)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM p) AS actual
    UNION ALL
    SELECT '02. Book value vs source line items (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(book_value) FROM p)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i JOIN source_population AS sp ON sp.order_id = i.order_id), 0) AS INT64)
    UNION ALL
    SELECT '03. Cumulative values consistent (rupees, rounded)', 0,
           CAST(ROUND((SELECT MAX(cum_after) FROM p) - (SELECT book_value FROM d), 0) AS INT64)
         + (SELECT COUNTIF(ABS(cum_after - cum_before - book_value) > 0.01) FROM p)
    UNION ALL
    SELECT '04. Sample size x interval = book value, 3 x interval <= tolerable', 0,
           (SELECT IF(ABS(sample_size * sampling_interval - book_value) < 0.01
                      AND ROUND(reliability * sampling_interval) <= ROUND(tolerable_misstatement), 0, 1) FROM d)
    UNION ALL
    SELECT '05. Every replicate has exactly n selection hits', 0,
           (SELECT COUNTIF(hits != (SELECT sample_size FROM d)) FROM e)
    UNION ALL
    SELECT '06. Top-stratum items selected in every replicate', 0,
           (SELECT COUNT(*) FROM p CROSS JOIN d
             WHERE p.book_value >= d.sampling_interval)
           * (SELECT COUNT(*) FROM e)
         - (SELECT COUNT(*) FROM s WHERE top_stratum)
    UNION ALL
    SELECT '07. Selected items vs explicit selection-point recount', 0,
           (SELECT COUNT(*) FROM s)
         - (SELECT COUNT(*) FROM (SELECT DISTINCT replicate, order_id FROM point_hits))
    UNION ALL
    SELECT '08. Misstatement vs independent status test (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(misstatement) FROM p)
                    - (SELECT SUM(CASE WHEN payment_status = 'Paid'   AND actual_outstanding > trivial_amount THEN actual_outstanding
                                       WHEN payment_status = 'Unpaid' AND book_value - actual_outstanding > trivial_amount THEN book_value - actual_outstanding
                                       ELSE 0 END) FROM p), 0) AS INT64)
    UNION ALL
    SELECT '09. Upper limit below basic precision, or projection with no errors', 0,
           (SELECT COUNTIF(ROUND(upper_limit) < ROUND(reliability * (SELECT sampling_interval FROM d))
                        OR (errors_found = 0 AND projected_misstatement != 0)) FROM e)
    UNION ALL
    SELECT '10. Errors found per replicate vs recount', 0,
           (SELECT COUNTIF(e.errors_found != IFNULL(x.n, 0)) FROM e
              LEFT JOIN (SELECT s.replicate, COUNT(*) AS n FROM s JOIN p USING (order_id)
                          WHERE p.misstatement > 0 GROUP BY s.replicate) AS x USING (replicate))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
