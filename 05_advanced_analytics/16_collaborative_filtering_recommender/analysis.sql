/* =============================================================================
   Case study · Product recommendations: collaborative filtering vs simple rules
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   A software vendor has offered the sales team a recommendation engine
   that suggests, for each customer, the products it is most likely to buy
   next but has not bought before ("customers like you also buy"). Before
   paying for it, the commercial head wants the idea tested on the
   company's own history with a method he can audit:
     1. How well would item-based collaborative filtering have predicted
        the new products customers bought the following year?
     2. Does it beat simple rules: the best sellers overall, or the best
        sellers in the customer's segment?
     3. What, if anything, does personalisation add?
     4. What should the sales team use?

   METHOD
     - Orders not Cancelled or Returned. Training period: 1 Jan 2024 -
       30 Sep 2025. Test period: 1 Oct 2025 - 30 Sep 2026.
     - Customers evaluated: bought in both periods.
     - Candidates: every product sold in training that the customer did
       NOT buy in training. A hit = the customer buys the candidate in the
       test period.
     - Item similarity (cosine): sim(i, j) = customers who bought both /
       SQRT(customers who bought i x customers who bought j), training only.
     - Collaborative filtering score for customer u and candidate j =
       SUM over products i bought by u of sim(i, j).
     - Baselines: popularity (number of training customers who bought the
       product) and segment popularity (the same within the customer's
       segment); a random pick hits at the base rate.
     - Each method recommends its top K = 5 candidates per customer (ties
       broken by product id). Precision@5 = hits / 5; hit rate = customers
       with at least one hit; recall = hits / all new products bought.
     - Paired test across customers: t on the per-customer difference in
       hits, and McNemar on "at least one hit".
   ============================================================================= */

DECLARE train_start DATE  DEFAULT DATE '2024-01-01';
DECLARE test_start  DATE  DEFAULT DATE '2025-10-01';
DECLARE test_end    DATE  DEFAULT DATE '2026-09-30';
DECLARE top_k       INT64 DEFAULT 5;

-- -----------------------------------------------------------------------------
-- Step 1 · Purchase sets and item-item similarity (training period)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rec_purchases` AS
SELECT DISTINCT
    o.customer_id, i.product_id,
    IF(o.order_date < test_start, 'Train', 'Test') AS period
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
  AND o.order_date BETWEEN train_start AND test_end;

CREATE OR REPLACE TABLE `sahyadri_b2b.rec_similarity` AS
WITH train AS (
    SELECT customer_id, product_id FROM `sahyadri_b2b.rec_purchases` WHERE period = 'Train'
),
item_customers AS (
    SELECT product_id, COUNT(*) AS customers FROM train GROUP BY product_id
)
SELECT
    a.product_id AS product_i, b.product_id AS product_j,
    COUNT(*)                                                         AS co_customers,
    COUNT(*) / SQRT(ANY_VALUE(x.customers) * ANY_VALUE(y.customers)) AS cosine
FROM train AS a
JOIN train AS b ON b.customer_id = a.customer_id AND b.product_id != a.product_id
JOIN item_customers AS x ON x.product_id = a.product_id
JOIN item_customers AS y ON y.product_id = b.product_id
GROUP BY a.product_id, b.product_id;

SELECT
    COUNT(DISTINCT product_i)                                        AS products,
    COUNT(*)                                                         AS product_pairs_with_overlap,
    ROUND(AVG(cosine), 3)                                            AS avg_cosine,
    ROUND(MAX(cosine), 3)                                            AS max_cosine
FROM `sahyadri_b2b.rec_similarity`;

-- -----------------------------------------------------------------------------
-- Step 2 · Score every candidate under each method
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rec_scores` AS
WITH train AS (
    SELECT customer_id, product_id FROM `sahyadri_b2b.rec_purchases` WHERE period = 'Train'
),
test AS (
    SELECT customer_id, product_id FROM `sahyadri_b2b.rec_purchases` WHERE period = 'Test'
),
eval_customers AS (
    SELECT DISTINCT t.customer_id, c.customer_segment
    FROM train AS t
    JOIN (SELECT DISTINCT customer_id FROM test) AS s ON s.customer_id = t.customer_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = t.customer_id
),
products AS (
    SELECT product_id, COUNT(*) AS popularity FROM train GROUP BY product_id
),
segment_popularity AS (
    SELECT c.customer_segment, t.product_id, COUNT(*) AS segment_popularity
    FROM train AS t JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = t.customer_id
    GROUP BY c.customer_segment, t.product_id
),
candidates AS (
    SELECT e.customer_id, e.customer_segment, p.product_id, p.popularity
    FROM eval_customers AS e
    CROSS JOIN products AS p
    LEFT JOIN train AS t ON t.customer_id = e.customer_id AND t.product_id = p.product_id
    WHERE t.customer_id IS NULL
),
cf AS (
    SELECT c.customer_id, c.product_id, SUM(s.cosine) AS cf_score
    FROM candidates AS c
    JOIN train AS t ON t.customer_id = c.customer_id
    JOIN `sahyadri_b2b.rec_similarity` AS s ON s.product_i = t.product_id AND s.product_j = c.product_id
    GROUP BY c.customer_id, c.product_id
)
SELECT
    c.customer_id, c.customer_segment, c.product_id,
    IFNULL(f.cf_score, 0)                                              AS cf_score,
    c.popularity,
    IFNULL(sp.segment_popularity, 0)                                   AS segment_popularity,
    x.customer_id IS NOT NULL                                          AS bought_in_test,
    ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY IFNULL(f.cf_score, 0) DESC, c.product_id)                     AS rank_cf,
    ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY c.popularity DESC, c.product_id)                              AS rank_popularity,
    ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY IFNULL(sp.segment_popularity, 0) DESC, c.popularity DESC, c.product_id) AS rank_segment
FROM candidates AS c
LEFT JOIN cf AS f ON f.customer_id = c.customer_id AND f.product_id = c.product_id
LEFT JOIN segment_popularity AS sp ON sp.customer_segment = c.customer_segment AND sp.product_id = c.product_id
LEFT JOIN test AS x ON x.customer_id = c.customer_id AND x.product_id = c.product_id;

-- -----------------------------------------------------------------------------
-- Step 3 · Back-test: precision, hit rate, recall and coverage
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rec_customer_eval` AS
SELECT
    customer_id, customer_segment,
    COUNT(*)                                                          AS candidates,
    COUNTIF(bought_in_test)                                           AS new_products_bought,
    COUNTIF(rank_cf <= top_k AND bought_in_test)                      AS hits_cf,
    COUNTIF(rank_popularity <= top_k AND bought_in_test)              AS hits_popularity,
    COUNTIF(rank_segment <= top_k AND bought_in_test)                 AS hits_segment
FROM `sahyadri_b2b.rec_scores`
GROUP BY customer_id, customer_segment;

WITH m AS (
              SELECT 'Collaborative filtering' AS method, hits_cf AS hits, new_products_bought, candidates FROM `sahyadri_b2b.rec_customer_eval`
    UNION ALL SELECT 'Best sellers overall',            hits_popularity,         new_products_bought, candidates FROM `sahyadri_b2b.rec_customer_eval`
    UNION ALL SELECT 'Best sellers in segment',         hits_segment,            new_products_bought, candidates FROM `sahyadri_b2b.rec_customer_eval`
)
SELECT
    method,
    COUNT(*)                                                          AS customers,
    SUM(hits)                                                         AS hits,
    ROUND(100 * SUM(hits) / (top_k * COUNT(*)), 1)                    AS precision_at_5_pct,
    ROUND(100 * AVG(IF(hits > 0, 1, 0)), 1)                           AS hit_rate_pct,
    ROUND(100 * SUM(hits) / SUM(new_products_bought), 1)              AS recall_pct
FROM m
GROUP BY method
UNION ALL
SELECT
    'Random pick (base rate)', COUNT(*), NULL,
    ROUND(100 * SUM(new_products_bought) / SUM(candidates), 1), NULL, NULL
FROM `sahyadri_b2b.rec_customer_eval`
ORDER BY precision_at_5_pct DESC;

-- Coverage: how many different products each method recommends
SELECT
    COUNT(DISTINCT IF(rank_cf <= top_k, product_id, NULL))            AS products_recommended_cf,
    COUNT(DISTINCT IF(rank_popularity <= top_k, product_id, NULL))    AS products_recommended_popularity,
    COUNT(DISTINCT IF(rank_segment <= top_k, product_id, NULL))       AS products_recommended_segment,
    COUNT(DISTINCT product_id)                                        AS products_available
FROM `sahyadri_b2b.rec_scores`;

-- Paired comparison: collaborative filtering vs best sellers overall
WITH d AS (
    SELECT hits_cf - hits_popularity AS diff,
           IF(hits_cf > 0, 1, 0) AS any_cf, IF(hits_popularity > 0, 1, 0) AS any_pop
    FROM `sahyadri_b2b.rec_customer_eval`
)
SELECT
    COUNT(*)                                                          AS customers,
    ROUND(AVG(diff), 3)                                               AS mean_hit_difference,
    ROUND(AVG(diff) / (STDDEV(diff) / SQRT(COUNT(*))), 2)             AS paired_t,
    COUNTIF(any_cf = 1 AND any_pop = 0)                               AS only_cf_hit,
    COUNTIF(any_cf = 0 AND any_pop = 1)                               AS only_popularity_hit,
    ROUND((COUNTIF(any_cf = 1 AND any_pop = 0) - COUNTIF(any_cf = 0 AND any_pop = 1))
          / SQRT(COUNTIF(any_cf = 1 AND any_pop = 0) + COUNTIF(any_cf = 0 AND any_pop = 1)), 2) AS mcnemar_z
FROM d;

-- -----------------------------------------------------------------------------
-- Step 4 · What does personalisation add? Recommendations unique to each method
-- -----------------------------------------------------------------------------
SELECT
    CASE WHEN rank_cf <= top_k AND rank_popularity <= top_k THEN '1. Recommended by both'
         WHEN rank_cf <= top_k                                THEN '2. Collaborative filtering only'
         ELSE                                                      '3. Best sellers only' END AS recommendation,
    COUNT(*)                                                          AS recommendations,
    COUNTIF(bought_in_test)                                           AS hits,
    ROUND(100 * COUNTIF(bought_in_test) / COUNT(*), 1)                AS precision_pct,
    ROUND(AVG(popularity), 1)                                         AS avg_product_popularity
FROM `sahyadri_b2b.rec_scores`
WHERE rank_cf <= top_k OR rank_popularity <= top_k
GROUP BY recommendation
ORDER BY recommendation;

-- Precision of the best-seller rule at different list lengths
SELECT
    k,
    ROUND(100 * COUNTIF(s.rank_popularity <= k AND s.bought_in_test) / (k * COUNT(DISTINCT s.customer_id)), 1) AS precision_best_sellers_pct,
    ROUND(100 * COUNTIF(s.rank_cf <= k AND s.bought_in_test) / (k * COUNT(DISTINCT s.customer_id)), 1)         AS precision_cf_pct
FROM `sahyadri_b2b.rec_scores` AS s
CROSS JOIN UNNEST([1, 3, 5, 10, 20]) AS k
GROUP BY k
ORDER BY k;

-- The best-seller list itself, with the share of candidates who went on to buy
SELECT
    p.product_id, pr.product_name, ANY_VALUE(p.popularity) AS training_customers,
    COUNT(*)                                                          AS customers_not_yet_buying,
    COUNTIF(p.bought_in_test)                                         AS bought_next_year,
    ROUND(100 * COUNTIF(p.bought_in_test) / COUNT(*), 1)              AS conversion_pct
FROM `sahyadri_b2b.rec_scores` AS p
JOIN `sahyadri_b2b.products` AS pr ON pr.product_id = p.product_id
GROUP BY p.product_id, pr.product_name
ORDER BY training_customers DESC, p.product_id
LIMIT 10;
