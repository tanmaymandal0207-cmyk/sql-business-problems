/* =============================================================================
   Case study · Salesperson ranking stability — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE replicates INT64 DEFAULT 500;

WITH c AS (SELECT * FROM `sahyadri_b2b.rs_clusters`),
     r AS (SELECT * FROM `sahyadri_b2b.rs_replicates`),
     i AS (SELECT * FROM `sahyadri_b2b.rs_intervals`),
     p AS (SELECT * FROM `sahyadri_b2b.rs_pairs`),

-- independent recomputation of two scorecard metrics straight from source
src_margin AS (
    SELECT o.employee_id,
           100 * SUM(IF(pr.unit_cost IS NOT NULL, i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) - i.quantity * pr.unit_cost, 0))
               / SUM(IF(pr.unit_cost IS NOT NULL, i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100), 0)) AS gross_margin_pct
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.products` AS pr ON pr.product_id = i.product_id
    WHERE o.employee_id IS NOT NULL AND o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.employee_id
),
src_on_time AS (
    SELECT o.employee_id, 100 * COUNTIF(s.d <= o.promised_delivery_date) / COUNT(*) AS on_time_pct
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN (SELECT order_id, MAX(delivery_date) AS d FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS s ON s.order_id = o.order_id
    WHERE o.employee_id IS NOT NULL AND o.order_status = 'Delivered'
      AND o.promised_delivery_date IS NOT NULL AND s.d IS NOT NULL
    GROUP BY o.employee_id
),
boot_mean AS (
    SELECT employee_id, AVG(net_revenue) AS m, STDDEV(net_revenue) AS sd
    FROM r WHERE b > 0 GROUP BY employee_id
),
-- pair probabilities for the balanced rank, recounted from the replicate table
pair_recount AS (
    SELECT x.employee_id AS employee_a, y.employee_id AS employee_b,
           AVG(IF(x.balanced_rank < y.balanced_rank, 1, IF(x.balanced_rank = y.balanced_rank, 0.5, 0))) AS p
    FROM r AS x JOIN r AS y ON y.b = x.b AND y.employee_id > x.employee_id
    WHERE x.b > 0
    GROUP BY x.employee_id, y.employee_id
),

checks AS (
    SELECT '01. Clusters = distinct salesperson x customer pairs in source' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM c)
         - (SELECT COUNT(DISTINCT CONCAT(CAST(employee_id AS STRING), '-', CAST(customer_id AS STRING)))
              FROM `sahyadri_b2b.sales_orders` WHERE employee_id IS NOT NULL) AS actual
    UNION ALL
    SELECT '02. Cluster net revenue = source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(net_revenue) FROM c)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
                        WHERE o.employee_id IS NOT NULL AND o.order_status NOT IN ('Cancelled', 'Returned')), 0) AS INT64)
    UNION ALL
    SELECT '03. Replicate 0 margin and on-time = source recomputation', 0,
           (SELECT COUNTIF(ABS(r.gross_margin_pct - m.gross_margin_pct) > 1e-9 OR ABS(r.on_time_pct - t.on_time_pct) > 1e-9)
              FROM r JOIN src_margin AS m USING (employee_id) JOIN src_on_time AS t USING (employee_id) WHERE r.b = 0)
    UNION ALL
    SELECT '04. Rows = (bootstrap runs + 1) x 16 salespeople', 0,
           (SELECT COUNT(*) FROM r) - (replicates + 1) * 16
    UNION ALL
    SELECT '05. Every replicate draws exactly as many customers as each salesperson has', 0,
           (SELECT COUNT(*) FROM r JOIN (SELECT employee_id, MAX(clusters) AS k FROM c GROUP BY employee_id) AS k USING (employee_id)
             WHERE r.clusters_drawn != k.k)
    UNION ALL
    SELECT '06. Bootstrap mean revenue within 4 standard errors of actual', 0,
           (SELECT COUNTIF(ABS(m.m - r.net_revenue) > 4 * m.sd / SQRT(replicates))
              FROM boot_mean AS m JOIN r USING (employee_id) WHERE r.b = 0)
    UNION ALL
    SELECT '07. Ranks lie in 1-16 and every replicate has a rank 1 on each metric', 0,
           (SELECT COUNTIF(LEAST(rank_revenue, rank_margin, rank_discount, rank_cancellation, rank_on_time, rank_collection, balanced_rank) < 1
                        OR GREATEST(rank_revenue, rank_margin, rank_discount, rank_cancellation, rank_on_time, rank_collection, balanced_rank) > 16) FROM r)
         + (SELECT COUNTIF(n = 0) FROM (SELECT b, LEAST(COUNTIF(rank_revenue = 1), COUNTIF(rank_margin = 1), COUNTIF(rank_discount = 1),
                                                        COUNTIF(rank_cancellation = 1), COUNTIF(rank_on_time = 1), COUNTIF(rank_collection = 1),
                                                        COUNTIF(balanced_rank = 1)) AS n FROM r GROUP BY b))
    UNION ALL
    SELECT '08. Rank sum = sum of the six metric ranks', 0,
           (SELECT COUNTIF(rank_sum != rank_revenue + rank_margin + rank_discount + rank_cancellation + rank_on_time + rank_collection) FROM r)
    UNION ALL
    SELECT '09. Pair table = 7 metrics x 120 pairs, probabilities in 0-1', 0,
           (SELECT COUNT(*) FROM p) - 840 + (SELECT COUNTIF(p_a_better < 0 OR p_a_better > 1) FROM p)
    UNION ALL
    SELECT '10. Balanced-rank pair probabilities = recount from the run table', 0,
           (SELECT COUNT(*) FROM p JOIN pair_recount AS x USING (employee_a, employee_b)
             WHERE p.metric = '7. Balanced rank' AND ABS(p.p_a_better - x.p) > 1e-12)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
