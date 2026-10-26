/* =============================================================================
   Case study · Customer segmentation with k-means in SQL
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script with a
              WHILE loop - run the whole script at once)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Every customer carries a segment label (Distributor, Enterprise,
   Mid-Market, SMB) set at registration. Pricing, discount bands and sales
   coverage all follow the label. The commercial head suspects the labels
   no longer describe how customers actually buy. Instead of another
   rule-based segmentation, he wants the data to find natural groups:
     1. If customers are grouped purely by buying behaviour, what groups
        appear?
     2. How well do the official segments line up with those groups?
     3. Which customers behave unlike their label, and should be reviewed?

   METHOD
     - Customers with an order in the last 12 months (to 30 Sep 2026).
     - Five behaviour features, each standardised (z-score):
         ln(revenue), ln(orders), categories bought, average discount %,
         average order value (ln).
     - k-means with k = 4 (the same number as the official segments),
       written as a BigQuery scripting WHILE loop:
         assign each customer to the nearest centroid (squared Euclidean
         distance), recompute each centroid as the mean of its members,
         repeat until no customer changes cluster (max 30 iterations).
     - Deterministic start: the initial centroids are the customers at the
       12.5th, 37.5th, 62.5th and 87.5th percentiles of revenue.
     - Comparison: R-squared = 1 - within-group sum of squares / total sum
       of squares, for the clusters and for the official segments, on the
       same standardised features.
   ============================================================================= */

DECLARE as_of     DATE  DEFAULT DATE '2026-09-30';
DECLARE max_iter  INT64 DEFAULT 30;
DECLARE iter      INT64 DEFAULT 0;
DECLARE changed   INT64 DEFAULT 1;

-- -----------------------------------------------------------------------------
-- Step 1 · Behaviour features, standardised
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.km_features` AS
WITH lines AS (
    SELECT o.customer_id, o.order_id, p.category_id,
           i.quantity * i.unit_price                                              AS gross,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)  AS net
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date >  DATE_SUB(as_of, INTERVAL 12 MONTH)
      AND o.order_date <= as_of
),
raw AS (
    SELECT
        customer_id,
        SUM(net)                                                                  AS revenue,
        COUNT(DISTINCT order_id)                                                  AS orders,
        COUNT(DISTINCT category_id)                                               AS categories,
        100 * (1 - SUM(net) / SUM(gross))                                         AS discount_pct,
        SUM(net) / COUNT(DISTINCT order_id)                                       AS avg_order_value
    FROM lines
    GROUP BY customer_id
),
transformed AS (
    SELECT *, LN(revenue) AS x1, LN(orders) AS x2, categories AS x3, discount_pct AS x4, LN(avg_order_value) AS x5
    FROM raw
)
SELECT
    t.customer_id,
    c.customer_segment,
    c.customer_name,
    t.revenue, t.orders, t.categories, t.discount_pct, t.avg_order_value,
    (t.x1 - AVG(t.x1) OVER ()) / STDDEV_POP(t.x1) OVER ()                         AS z1,
    (t.x2 - AVG(t.x2) OVER ()) / STDDEV_POP(t.x2) OVER ()                         AS z2,
    (t.x3 - AVG(t.x3) OVER ()) / STDDEV_POP(t.x3) OVER ()                         AS z3,
    (t.x4 - AVG(t.x4) OVER ()) / STDDEV_POP(t.x4) OVER ()                         AS z4,
    (t.x5 - AVG(t.x5) OVER ()) / STDDEV_POP(t.x5) OVER ()                         AS z5
FROM transformed AS t
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = t.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Initial centroids and assignment
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.km_centroids` AS
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY revenue, customer_id) AS rn, COUNT(*) OVER () AS n
    FROM `sahyadri_b2b.km_features`
)
SELECT
    CASE WHEN rn = CAST(CEIL(0.125 * n) AS INT64) THEN 1
         WHEN rn = CAST(CEIL(0.375 * n) AS INT64) THEN 2
         WHEN rn = CAST(CEIL(0.625 * n) AS INT64) THEN 3
         ELSE 4 END                                                               AS cluster,
    z1, z2, z3, z4, z5
FROM ranked
WHERE rn IN (CAST(CEIL(0.125 * n) AS INT64), CAST(CEIL(0.375 * n) AS INT64),
             CAST(CEIL(0.625 * n) AS INT64), CAST(CEIL(0.875 * n) AS INT64));

CREATE OR REPLACE TABLE `sahyadri_b2b.km_assign` AS
SELECT customer_id, 0 AS cluster FROM `sahyadri_b2b.km_features`;

CREATE OR REPLACE TABLE `sahyadri_b2b.km_log` (iteration INT64, changes INT64, within_ss FLOAT64);

-- -----------------------------------------------------------------------------
-- Step 3 · k-means iterations
-- -----------------------------------------------------------------------------
WHILE iter < max_iter AND changed > 0 DO
    -- assignment step: nearest centroid
    CREATE OR REPLACE TABLE `sahyadri_b2b.km_new_assign` AS
    SELECT customer_id, cluster, dist
    FROM (
        SELECT f.customer_id, c.cluster,
               POW(f.z1 - c.z1, 2) + POW(f.z2 - c.z2, 2) + POW(f.z3 - c.z3, 2)
             + POW(f.z4 - c.z4, 2) + POW(f.z5 - c.z5, 2)                          AS dist
        FROM `sahyadri_b2b.km_features` AS f
        CROSS JOIN `sahyadri_b2b.km_centroids` AS c
    )
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY dist, cluster) = 1;

    INSERT INTO `sahyadri_b2b.km_log` (iteration, changes, within_ss)
    SELECT iter + 1, COUNTIF(n.cluster != o.cluster), SUM(n.dist)
    FROM `sahyadri_b2b.km_new_assign` AS n
    JOIN `sahyadri_b2b.km_assign`     AS o ON o.customer_id = n.customer_id;

    SET changed = (SELECT changes FROM `sahyadri_b2b.km_log` WHERE iteration = iter + 1);

    CREATE OR REPLACE TABLE `sahyadri_b2b.km_assign` AS
    SELECT customer_id, cluster FROM `sahyadri_b2b.km_new_assign`;

    -- update step: centroid = mean of members
    CREATE OR REPLACE TABLE `sahyadri_b2b.km_centroids` AS
    SELECT a.cluster, AVG(f.z1) AS z1, AVG(f.z2) AS z2, AVG(f.z3) AS z3, AVG(f.z4) AS z4, AVG(f.z5) AS z5
    FROM `sahyadri_b2b.km_assign`   AS a
    JOIN `sahyadri_b2b.km_features` AS f ON f.customer_id = a.customer_id
    GROUP BY a.cluster;

    SET iter = iter + 1;
END WHILE;

SELECT iteration, changes, ROUND(within_ss, 2) AS within_ss
FROM `sahyadri_b2b.km_log`
WHERE changes > 0 OR iteration = (SELECT MIN(iteration) FROM `sahyadri_b2b.km_log` WHERE changes = 0)
ORDER BY iteration;

-- -----------------------------------------------------------------------------
-- Step 4 · Cluster profiles, in the original units
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.km_customers` AS
SELECT f.*, a.cluster
FROM `sahyadri_b2b.km_features` AS f
JOIN `sahyadri_b2b.km_assign`   AS a ON a.customer_id = f.customer_id;

SELECT
    cluster,
    COUNT(*)                                                                      AS customers,
    ROUND(SUM(revenue) / 1e7, 2)                                                  AS revenue_crore,
    ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)                      AS revenue_share_pct,
    ROUND(EXP(AVG(LN(revenue))) / 1e5, 2)                                         AS typical_revenue_lakh,
    ROUND(EXP(AVG(LN(orders))), 1)                                                AS typical_orders,
    ROUND(AVG(categories), 1)                                                     AS avg_categories,
    ROUND(AVG(discount_pct), 1)                                                   AS avg_discount_pct,
    ROUND(EXP(AVG(LN(avg_order_value))), 0)                                       AS typical_order_value
FROM `sahyadri_b2b.km_customers`
GROUP BY cluster
ORDER BY revenue_crore DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Do the official segments match the clusters?
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNTIF(cluster = 1)                                                          AS cluster_1,
    COUNTIF(cluster = 2)                                                          AS cluster_2,
    COUNTIF(cluster = 3)                                                          AS cluster_3,
    COUNTIF(cluster = 4)                                                          AS cluster_4,
    COUNT(*)                                                                      AS customers
FROM `sahyadri_b2b.km_customers`
GROUP BY customer_segment
ORDER BY customer_segment;

-- Share of behavioural variation explained: clusters vs official segments
WITH grand AS (
    SELECT AVG(z1) AS m1, AVG(z2) AS m2, AVG(z3) AS m3, AVG(z4) AS m4, AVG(z5) AS m5
    FROM `sahyadri_b2b.km_customers`
),
total AS (
    SELECT SUM(POW(z1 - m1, 2) + POW(z2 - m2, 2) + POW(z3 - m3, 2) + POW(z4 - m4, 2) + POW(z5 - m5, 2)) AS tss
    FROM `sahyadri_b2b.km_customers` CROSS JOIN grand
),
by_cluster AS (
    SELECT SUM(POW(z1 - c1, 2) + POW(z2 - c2, 2) + POW(z3 - c3, 2) + POW(z4 - c4, 2) + POW(z5 - c5, 2)) AS wss
    FROM (
        SELECT *,
               AVG(z1) OVER (PARTITION BY cluster) AS c1, AVG(z2) OVER (PARTITION BY cluster) AS c2,
               AVG(z3) OVER (PARTITION BY cluster) AS c3, AVG(z4) OVER (PARTITION BY cluster) AS c4,
               AVG(z5) OVER (PARTITION BY cluster) AS c5
        FROM `sahyadri_b2b.km_customers`
    )
),
by_segment AS (
    SELECT SUM(POW(z1 - c1, 2) + POW(z2 - c2, 2) + POW(z3 - c3, 2) + POW(z4 - c4, 2) + POW(z5 - c5, 2)) AS wss
    FROM (
        SELECT *,
               AVG(z1) OVER (PARTITION BY customer_segment) AS c1, AVG(z2) OVER (PARTITION BY customer_segment) AS c2,
               AVG(z3) OVER (PARTITION BY customer_segment) AS c3, AVG(z4) OVER (PARTITION BY customer_segment) AS c4,
               AVG(z5) OVER (PARTITION BY customer_segment) AS c5
        FROM `sahyadri_b2b.km_customers`
    )
)
SELECT
    ROUND(1 - c.wss / t.tss, 3)                                                   AS r_squared_clusters,
    ROUND(1 - s.wss / t.tss, 3)                                                   AS r_squared_segments
FROM total AS t CROSS JOIN by_cluster AS c CROSS JOIN by_segment AS s;

-- Customers who behave unlike their label: in a cluster where their segment is rare
WITH seg_cluster AS (
    SELECT customer_segment, cluster, COUNT(*) AS n,
           COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY customer_segment) AS share_of_segment
    FROM `sahyadri_b2b.km_customers`
    GROUP BY customer_segment, cluster
)
SELECT
    k.customer_id,
    k.customer_name,
    k.customer_segment,
    k.cluster,
    ROUND(100 * s.share_of_segment, 1)                                            AS pct_of_segment_in_this_cluster,
    ROUND(k.revenue / 1e5, 1)                                                     AS revenue_lakh,
    k.orders,
    k.categories,
    ROUND(k.discount_pct, 1)                                                      AS discount_pct
FROM `sahyadri_b2b.km_customers` AS k
JOIN seg_cluster AS s ON s.customer_segment = k.customer_segment AND s.cluster = k.cluster
WHERE s.share_of_segment < 0.10
ORDER BY k.revenue DESC
LIMIT 12;
