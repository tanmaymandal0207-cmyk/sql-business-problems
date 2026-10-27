/* =============================================================================
   Case study · Empirical Bayes for operational rates — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

WITH c AS (SELECT * FROM `sahyadri_b2b.eb_counts`),
     m AS (SELECT * FROM `sahyadri_b2b.eb_measures`),
     e AS (SELECT * FROM `sahyadri_b2b.eb_members`),

closed AS (
    SELECT COUNT(*) AS n, COUNTIF(order_status = 'Cancelled') AS k
    FROM `sahyadri_b2b.sales_orders` WHERE order_status IN ('Delivered', 'Cancelled', 'Returned')
),
closed_lines AS (
    SELECT COUNT(*) AS n, COUNTIF(o.order_status = 'Cancelled') AS k
    FROM `sahyadri_b2b.sales_order_items` AS i JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    WHERE o.order_status IN ('Delivered', 'Cancelled', 'Returned')
),
ships AS (
    SELECT COUNT(*) AS n, COUNTIF(shipment_status = 'Returned') AS k FROM `sahyadri_b2b.shipments`
),
totals AS (
    SELECT measure, SUM(n) AS n, SUM(k) AS k FROM c GROUP BY measure
),

checks AS (
    SELECT '01. Customer and salesperson cancellation counts = closed orders' AS check_name, 0 AS expected,
           (SELECT COUNTIF(t.n != closed.n OR t.k != closed.k) FROM totals AS t CROSS JOIN closed
             WHERE t.measure IN ('1. Cancellation by customer', '2. Cancellation by salesperson')) AS actual
    UNION ALL
    SELECT '02. Product cancellation counts = lines of closed orders', 0,
           (SELECT COUNTIF(t.n != l.n OR t.k != l.k) FROM totals AS t CROSS JOIN closed_lines AS l
             WHERE t.measure = '3. Cancellation by product')
    UNION ALL
    SELECT '03. City return counts = all shipments and returned shipments', 0,
           (SELECT COUNTIF(t.n != s.n OR t.k != s.k) FROM totals AS t CROSS JOIN ships AS s WHERE t.measure = '4. Return by city')
    UNION ALL
    SELECT '04. Late delivery: customer and city views count the same orders', 0,
           (SELECT COUNT(*) FROM totals AS a JOIN totals AS b
              ON a.measure = '5. Late delivery by customer' AND b.measure = '6. Late delivery by city'
             WHERE a.n != b.n OR a.k != b.k)
    UNION ALL
    SELECT '05. Overall rate = events / records for every measure', 0,
           (SELECT COUNTIF(ABS(p - events / records) > 1e-12) FROM m)
    UNION ALL
    SELECT '06. Q = recount as SUM (k - n p)^2 / (n p (1 - p))', 0,
           (SELECT COUNTIF(ABS(m.q_stat - x.q) > 1e-6) FROM m JOIN (
                SELECT c.measure, SUM(POW(c.k - c.n * mm.p, 2) / (c.n * mm.p * (1 - mm.p))) AS q
                FROM c JOIN m AS mm ON mm.measure = c.measure GROUP BY c.measure) AS x USING (measure))
    UNION ALL
    SELECT '07. tau^2 is zero exactly when Q <= degrees of freedom', 0,
           (SELECT COUNTIF(tau2 < 0 OR ((q_stat <= members - 1) != (tau2 = 0))) FROM m)
    UNION ALL
    SELECT '08. Shrinkage in 0-1, credible rate between raw rate and overall rate', 0,
           (SELECT COUNTIF(shrinkage < 0 OR shrinkage > 1
                        OR credible_rate < LEAST(raw_rate, p) - 1e-12 OR credible_rate > GREATEST(raw_rate, p) + 1e-12) FROM e)
    UNION ALL
    SELECT '09. With no real variation, every credible rate equals the overall rate', 0,
           (SELECT COUNTIF(ABS(credible_rate - p) > 1e-12) FROM e WHERE tau2 = 0)
    UNION ALL
    SELECT '10. Raw z = (rate - p) / standard error (recount)', 0,
           (SELECT COUNTIF(ABS(raw_z - (k / n - p) / SQRT(p * (1 - p) / n)) > 1e-9) FROM e)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
