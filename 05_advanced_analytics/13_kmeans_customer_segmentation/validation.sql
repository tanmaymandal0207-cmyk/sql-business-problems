/* =============================================================================
   Case study · k-means customer segmentation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of DATE DEFAULT DATE '2026-09-30';

WITH k AS (SELECT * FROM `sahyadri_b2b.km_customers`),
     c AS (SELECT * FROM `sahyadri_b2b.km_centroids`),
     l AS (SELECT * FROM `sahyadri_b2b.km_log`),

source AS (
    SELECT o.customer_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date > DATE_SUB(as_of, INTERVAL 12 MONTH) AND o.order_date <= as_of
    GROUP BY o.customer_id
),
nearest AS (
    SELECT customer_id, cluster AS nearest_cluster
    FROM (
        SELECT f.customer_id, c.cluster,
               POW(f.z1 - c.z1, 2) + POW(f.z2 - c.z2, 2) + POW(f.z3 - c.z3, 2) + POW(f.z4 - c.z4, 2) + POW(f.z5 - c.z5, 2) AS d
        FROM k AS f CROSS JOIN c
    )
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY d, cluster) = 1
),
means AS (
    SELECT cluster, AVG(z1) AS m1, AVG(z2) AS m2, AVG(z3) AS m3, AVG(z4) AS m4, AVG(z5) AS m5 FROM k GROUP BY cluster
),
final_ss AS (
    SELECT SUM(POW(k.z1 - c.z1, 2) + POW(k.z2 - c.z2, 2) + POW(k.z3 - c.z3, 2) + POW(k.z4 - c.z4, 2) + POW(k.z5 - c.z5, 2)) AS wss
    FROM k JOIN c USING (cluster)
),

checks AS (
    SELECT '01. Customers vs source customers active in 12 months' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM k) - (SELECT COUNT(*) FROM source)
         + (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM k) AS actual
    UNION ALL
    SELECT '02. Revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM k) - (SELECT SUM(revenue) FROM source), 0) AS INT64)
    UNION ALL
    SELECT '03. Standardised features: mean 0 and s.d. 1', 0,
           (SELECT IF(GREATEST(ABS(AVG(z1)), ABS(AVG(z2)), ABS(AVG(z3)), ABS(AVG(z4)), ABS(AVG(z5))) < 1e-9
                  AND GREATEST(ABS(STDDEV_POP(z1) - 1), ABS(STDDEV_POP(z2) - 1), ABS(STDDEV_POP(z3) - 1),
                               ABS(STDDEV_POP(z4) - 1), ABS(STDDEV_POP(z5) - 1)) < 1e-9, 0, 1) FROM k)
    UNION ALL
    SELECT '04. Fixed point: every customer sits in its nearest cluster', 0,
           (SELECT COUNTIF(k.cluster != n.nearest_cluster) FROM k JOIN nearest AS n USING (customer_id))
    UNION ALL
    SELECT '05. Centroids equal the mean of their members', 0,
           (SELECT COUNTIF(GREATEST(ABS(c.z1 - m.m1), ABS(c.z2 - m.m2), ABS(c.z3 - m.m3), ABS(c.z4 - m.m4), ABS(c.z5 - m.m5)) > 1e-9)
              FROM c JOIN means AS m USING (cluster))
    UNION ALL
    SELECT '06. Converged: last iteration changed no customer', 0,
           (SELECT changes FROM l WHERE iteration = (SELECT MAX(iteration) FROM l))
    UNION ALL
    SELECT '07. Final within-cluster SS vs last logged value (x 1000, rounded)', 0,
           CAST(ROUND(1000 * ((SELECT wss FROM final_ss)
                            - (SELECT within_ss FROM l WHERE iteration = (SELECT MAX(iteration) FROM l)))) AS INT64)
    UNION ALL
    SELECT '08. Four non-empty clusters', 4,
           (SELECT COUNT(DISTINCT cluster) FROM k)
    UNION ALL
    SELECT '09. Total sum of squares = 5 x customers (x 1000, rounded)', 0,
           CAST(ROUND(1000 * ((SELECT SUM(z1*z1 + z2*z2 + z3*z3 + z4*z4 + z5*z5) FROM k) - 5 * (SELECT COUNT(*) FROM k))) AS INT64)
    UNION ALL
    SELECT '10. Within-cluster SS never increased between iterations', 0,
           (SELECT COUNT(*) FROM l AS a JOIN l AS b ON b.iteration = a.iteration + 1
             WHERE a.iteration > 1 AND b.within_ss > a.within_ss + 1e-9)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
