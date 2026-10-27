/* =============================================================================
   Case study · Data drift monitoring — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE baseline_start DATE DEFAULT DATE '2024-01-01';
DECLARE monitor_start  DATE DEFAULT DATE '2025-01-01';
DECLARE as_of          DATE DEFAULT DATE '2026-09-30';

WITH o AS (SELECT * FROM `sahyadri_b2b.dd_observations`),
     b AS (SELECT * FROM `sahyadri_b2b.dd_binned`),
     k AS (SELECT * FROM `sahyadri_b2b.dd_cuts`),
     p AS (SELECT * FROM `sahyadri_b2b.dd_psi`),

field_counts AS (
    SELECT field, COUNT(*) AS n FROM o GROUP BY field
),
src AS (
              SELECT '01. Order value' AS field, COUNT(*) AS n FROM `sahyadri_b2b.sales_orders` WHERE order_date BETWEEN baseline_start AND as_of
    UNION ALL SELECT '08. Product category', COUNT(*) FROM `sahyadri_b2b.sales_order_items` AS i
              JOIN `sahyadri_b2b.sales_orders` AS s ON s.order_id = i.order_id WHERE s.order_date BETWEEN baseline_start AND as_of
    UNION ALL SELECT '13. Payment method', COUNT(*) FROM `sahyadri_b2b.payments` WHERE payment_date BETWEEN baseline_start AND as_of
    UNION ALL SELECT '14. Shipping cost', COUNT(*) FROM `sahyadri_b2b.shipments` WHERE shipment_date BETWEEN baseline_start AND as_of
),
ref_deciles AS (
    SELECT field, bin, COUNT(*) AS n, SUM(COUNT(*)) OVER (PARTITION BY field) AS total
    FROM b
    WHERE is_reference AND field IN ('01. Order value', '11. Price ratio (unit price / list)') AND bin != 'NULL'
    GROUP BY field, bin
),
-- PSI recomputed with conditional aggregation (one pass per field and month)
recount AS (
    SELECT m.field, m.month_start,
           SUM(((m.n + 0.5) / (m.tot + 0.5 * m.bins) - (r.n + 0.5) / (r.tot + 0.5 * m.bins))
               * LN(((m.n + 0.5) / (m.tot + 0.5 * m.bins)) / ((r.n + 0.5) / (r.tot + 0.5 * m.bins)))) AS psi
    FROM (
        SELECT fb.field, mm.month_start, fb.bin,
               SUM(IF(NOT x.is_reference AND x.month_start = mm.month_start AND x.bin = fb.bin, 1, 0)) AS n,
               ANY_VALUE(t.tot)                                                                          AS tot,
               ANY_VALUE(fbn.bins)                                                                       AS bins
        FROM (SELECT DISTINCT field, bin FROM b) AS fb
        JOIN (SELECT DISTINCT field, month_start FROM b WHERE NOT is_reference) AS mm ON mm.field = fb.field
        JOIN (SELECT field, month_start, COUNT(*) AS tot FROM b WHERE NOT is_reference GROUP BY field, month_start) AS t
          ON t.field = mm.field AND t.month_start = mm.month_start
        JOIN (SELECT field, COUNT(DISTINCT bin) AS bins FROM b GROUP BY field) AS fbn ON fbn.field = fb.field
        LEFT JOIN b AS x ON x.field = fb.field AND x.bin = fb.bin AND (x.is_reference OR x.month_start = mm.month_start)
        GROUP BY fb.field, mm.month_start, fb.bin
    ) AS m
    JOIN (SELECT field, bin, COUNTIF(is_reference) AS n, SUM(COUNTIF(is_reference)) OVER (PARTITION BY field) AS tot
          FROM b GROUP BY field, bin) AS r
      ON r.field = m.field AND r.bin = m.bin
    GROUP BY m.field, m.month_start
),

checks AS (
    SELECT '01. Observations = source records for each grain' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM src AS s JOIN field_counts AS f USING (field) WHERE s.n != f.n) AS actual
    UNION ALL
    SELECT '02. Reference flag = event before the monitoring start', 0,
           (SELECT COUNTIF(is_reference != (event_date < monitor_start)) FROM o)
    UNION ALL
    SELECT '03. Decile cut points are in ascending order', 0,
           (SELECT COUNTIF(NOT (c1 <= c2 AND c2 <= c3 AND c3 <= c4 AND c4 <= c5 AND c5 <= c6 AND c6 <= c7 AND c7 <= c8 AND c8 <= c9)) FROM k)
    UNION ALL
    SELECT '04. Continuous fields: each reference decile holds 10 % (within 1 record)', 0,
           (SELECT COUNTIF(ABS(n - total / 10) > 1) FROM ref_deciles)
    UNION ALL
    SELECT '05. Every observation has exactly one bin', 0,
           (SELECT COUNT(*) FROM b) - (SELECT COUNT(*) FROM o) + (SELECT COUNTIF(bin IS NULL) FROM b)
    UNION ALL
    SELECT '06. PSI = independent recount (to 1e-9)', 0,
           (SELECT COUNT(*) FROM p JOIN recount AS r USING (field, month_start) WHERE ABS(p.psi - r.psi) > 1e-9)
    UNION ALL
    SELECT '07. PSI is never negative', 0,
           (SELECT COUNTIF(psi < 0) FROM p)
    UNION ALL
    SELECT '08. Bins per field = distinct bins observed, df = bins - 1', 0,
           (SELECT COUNT(*) FROM p JOIN (SELECT field, COUNT(DISTINCT bin) AS n FROM b GROUP BY field) AS x USING (field)
             WHERE p.bins != x.n OR p.df != p.bins - 1)
    UNION ALL
    SELECT '09. z recomputed from the order-based statistic', 0,
           (SELECT COUNTIF(ABS(z - (POW(chi_orders / df, 1 / 3) - (1 - 2 / (9 * df))) / SQRT(2 / (9 * df))) > 1e-9) FROM p)
    UNION ALL
    SELECT '10. Order-grain fields: records = orders, so both tests agree', 0,
           (SELECT COUNTIF(month_records != month_orders OR ABS(chi_orders - chi_records_naive) > 1e-9) FROM p WHERE grain = 'A. Order')
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
