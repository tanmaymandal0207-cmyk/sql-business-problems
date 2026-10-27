/* =============================================================================
   Case study · Collaborative filtering recommender — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE train_start DATE  DEFAULT DATE '2024-01-01';
DECLARE test_start  DATE  DEFAULT DATE '2025-10-01';
DECLARE test_end    DATE  DEFAULT DATE '2026-09-30';
DECLARE top_k       INT64 DEFAULT 5;

WITH p AS (SELECT * FROM `sahyadri_b2b.rec_purchases`),
     s AS (SELECT * FROM `sahyadri_b2b.rec_similarity`),
     r AS (SELECT * FROM `sahyadri_b2b.rec_scores`),
     e AS (SELECT * FROM `sahyadri_b2b.rec_customer_eval`),

src AS (
    SELECT DISTINCT o.customer_id, i.product_id, IF(o.order_date < test_start, 'Train', 'Test') AS period
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN train_start AND test_end
),
train AS (SELECT customer_id, product_id FROM p WHERE period = 'Train'),
test  AS (SELECT customer_id, product_id FROM p WHERE period = 'Test'),
item_n AS (SELECT product_id, COUNT(*) AS n FROM train GROUP BY product_id),
eval_customers AS (
    SELECT DISTINCT customer_id FROM train WHERE customer_id IN (SELECT customer_id FROM test)
),
-- CF score of each customer's top recommendation, rebuilt from raw purchases
top1 AS (SELECT customer_id, product_id, cf_score FROM r WHERE rank_cf = 1),
top1_recount AS (
    SELECT t.customer_id, t.product_id,
           SUM(co.n / SQRT(ni.n * nj.n)) AS score
    FROM top1 AS t
    JOIN train AS mine ON mine.customer_id = t.customer_id
    JOIN (SELECT a.product_id AS i, b.product_id AS j, COUNT(*) AS n
            FROM train AS a JOIN train AS b ON b.customer_id = a.customer_id AND b.product_id != a.product_id
           GROUP BY a.product_id, b.product_id) AS co
      ON co.i = mine.product_id AND co.j = t.product_id
    JOIN item_n AS ni ON ni.product_id = mine.product_id
    JOIN item_n AS nj ON nj.product_id = t.product_id
    GROUP BY t.customer_id, t.product_id
),
new_buys AS (
    SELECT COUNT(*) AS n
    FROM test AS x
    JOIN eval_customers AS c ON c.customer_id = x.customer_id
    JOIN item_n AS i ON i.product_id = x.product_id
    LEFT JOIN train AS t ON t.customer_id = x.customer_id AND t.product_id = x.product_id
    WHERE t.customer_id IS NULL
),

checks AS (
    SELECT '01. Purchase sets = distinct source customer x product x period' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM p) - (SELECT COUNT(*) FROM src) AS actual
    UNION ALL
    SELECT '02. Similarity is symmetric', 0,
           (SELECT COUNT(*) FROM s AS a LEFT JOIN s AS b ON b.product_i = a.product_j AND b.product_j = a.product_i
             WHERE b.product_i IS NULL OR ABS(a.cosine - b.cosine) > 1e-12 OR a.co_customers != b.co_customers)
    UNION ALL
    SELECT '03. Cosine = co-customers / SQRT(n_i x n_j), between 0 and 1', 0,
           (SELECT COUNTIF(ABS(s.cosine - s.co_customers / SQRT(x.n * y.n)) > 1e-12 OR s.cosine <= 0 OR s.cosine > 1 + 1e-12)
              FROM s JOIN item_n AS x ON x.product_id = s.product_i JOIN item_n AS y ON y.product_id = s.product_j)
    UNION ALL
    SELECT '04. No candidate was already bought in training', 0,
           (SELECT COUNT(*) FROM r JOIN train AS t USING (customer_id, product_id))
    UNION ALL
    SELECT '05. Candidates = customers x products - training purchases', 0,
           (SELECT COUNT(*) FROM r)
         - ((SELECT COUNT(*) FROM eval_customers) * (SELECT COUNT(*) FROM item_n)
            - (SELECT COUNT(*) FROM train WHERE customer_id IN (SELECT customer_id FROM eval_customers)))
    UNION ALL
    SELECT '06. Ranks run 1..n for every customer and method', 0,
           (SELECT COUNTIF(mx_cf != n OR mx_pop != n OR mx_seg != n OR d_cf != n OR d_pop != n OR d_seg != n)
              FROM (SELECT customer_id, COUNT(*) AS n, MAX(rank_cf) AS mx_cf, MAX(rank_popularity) AS mx_pop, MAX(rank_segment) AS mx_seg,
                           COUNT(DISTINCT rank_cf) AS d_cf, COUNT(DISTINCT rank_popularity) AS d_pop, COUNT(DISTINCT rank_segment) AS d_seg
                      FROM r GROUP BY customer_id))
    UNION ALL
    SELECT '07. Hit flag = purchase in the test period (recount)', 0,
           (SELECT COUNTIF(r.bought_in_test != (x.customer_id IS NOT NULL))
              FROM r LEFT JOIN test AS x USING (customer_id, product_id))
    UNION ALL
    SELECT '08. Top CF score = recount from raw co-purchases', 0,
           (SELECT COUNT(*) FROM top1 AS t LEFT JOIN top1_recount AS c USING (customer_id, product_id)
             WHERE ABS(t.cf_score - IFNULL(c.score, 0)) > 1e-9)
    UNION ALL
    SELECT '09. New products bought = test purchases outside training sets', 0,
           (SELECT SUM(new_products_bought) FROM e) - (SELECT n FROM new_buys)
    UNION ALL
    SELECT '10. Hits per method = recount from the score table', 0,
           (SELECT SUM(hits_cf) + SUM(hits_popularity) + SUM(hits_segment) FROM e)
         - (SELECT COUNTIF(bought_in_test AND rank_cf <= top_k) + COUNTIF(bought_in_test AND rank_popularity <= top_k)
                 + COUNTIF(bought_in_test AND rank_segment <= top_k) FROM r)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
