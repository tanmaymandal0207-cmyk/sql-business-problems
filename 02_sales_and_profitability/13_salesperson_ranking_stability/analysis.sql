/* =============================================================================
   Case study · Salesperson ranking stability (bootstrap)
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The salesperson scorecard (case study 10) ranks 16 salespeople on six
   metrics and a balanced rank, and the sales director wants to use it for
   this year's incentive tiers. HR asks a fair question: how much of each
   rank is skill and how much is the luck of which customers a person
   happened to serve? If one large customer had ordered differently, would
   the ranking change?
     1. How precisely is each salesperson's metric measured?
     2. Which ranks are stable, and which could easily be different?
     3. Which pairs of salespeople can really be told apart?
     4. How should incentive tiers be set so they reflect real differences?

   METHOD
     - Metrics exactly as in the scorecard: net revenue, gross margin %,
       discount %, cancellation rate, on-time delivery % and overdue
       receivable %, for orders dated 1 Jan 2024 - 30 Sep 2026.
     - Each metric is a ratio of sums, so it is built from additive totals
       per salesperson x customer ("cluster").
     - Bootstrap: 500 replicates. In each, every salesperson's customers are
       re-drawn with replacement (same number of clusters), the metrics are
       recomputed, and all 16 salespeople are re-ranked. Resampling whole
       customers keeps each customer's orders together, because orders of
       the same customer are not independent.
     - Random draws come from an integer hash that gives identical results
       in any SQL engine:
         x0 = MOD(b*7919 + j*104729 + employee_id*1299709, 2147483647)
         x1 = MOD(x0*x0 + 12345, 2147483647); x2 = MOD(x1*x1 + 54321, 2147483647)
         drawn cluster = 1 + MOD(x2, clusters of the salesperson).
     - Outputs: 90 % intervals (5th-95th percentile) of each metric and each
       rank; for every pair of salespeople, the share of replicates in which
       one beats the other. A pair is "distinguishable" when one is better
       in at least 95 % of replicates.
   ============================================================================= */

DECLARE as_of_date DATE  DEFAULT DATE '2026-09-30';
DECLARE replicates INT64 DEFAULT 500;
DECLARE prime      INT64 DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Additive totals per salesperson x customer (the resampling unit)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rs_clusters` AS
WITH line_values AS (
    SELECT o.order_id, o.employee_id, o.customer_id, o.order_status,
           i.quantity * i.unit_price                                             AS gross_value,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS net_revenue,
           i.quantity * p.unit_cost                                              AS line_cost
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    WHERE o.employee_id IS NOT NULL
),
sales AS (
    SELECT employee_id, customer_id,
           SUM(net_revenue)                                          AS net_revenue,
           SUM(gross_value)                                          AS gross_value,
           SUM(IF(line_cost IS NOT NULL, net_revenue, 0))            AS costed_revenue,
           SUM(IF(line_cost IS NOT NULL, net_revenue - line_cost, 0)) AS costed_margin
    FROM line_values
    WHERE order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY employee_id, customer_id
),
order_value AS (
    SELECT order_id, employee_id, customer_id, order_status, SUM(net_revenue) AS order_value
    FROM line_values
    GROUP BY order_id, employee_id, customer_id, order_status
),
final_delivery AS (
    SELECT order_id, MAX(delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
paid AS (
    SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` GROUP BY order_id
),
orders AS (
    SELECT
        v.employee_id, v.customer_id,
        COUNT(*)                                                                             AS orders_placed,
        COUNTIF(v.order_status = 'Cancelled')                                                AS cancelled_orders,
        COUNTIF(v.order_status = 'Delivered' AND o.promised_delivery_date IS NOT NULL
                AND d.final_delivery_date IS NOT NULL)                                       AS delivered_measured,
        COUNTIF(v.order_status = 'Delivered' AND d.final_delivery_date <= o.promised_delivery_date) AS on_time_orders,
        SUM(IF(v.order_status = 'Delivered' AND DATE_DIFF(as_of_date, d.final_delivery_date, DAY) > 90,
               v.order_value, 0))                                                            AS aged_order_value,
        SUM(IF(v.order_status = 'Delivered' AND DATE_DIFF(as_of_date, d.final_delivery_date, DAY) > 90,
               GREATEST(v.order_value - IFNULL(p.paid, 0), 0), 0))                           AS overdue_balance
    FROM order_value AS v
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = v.order_id
    LEFT JOIN final_delivery AS d ON d.order_id = v.order_id
    LEFT JOIN paid AS p ON p.order_id = v.order_id
    GROUP BY v.employee_id, v.customer_id
)
SELECT
    o.employee_id, o.customer_id,
    ROW_NUMBER() OVER (PARTITION BY o.employee_id ORDER BY o.customer_id)   AS cluster_no,
    COUNT(*) OVER (PARTITION BY o.employee_id)                              AS clusters,
    IFNULL(s.net_revenue, 0) AS net_revenue, IFNULL(s.gross_value, 0) AS gross_value,
    IFNULL(s.costed_revenue, 0) AS costed_revenue, IFNULL(s.costed_margin, 0) AS costed_margin,
    o.orders_placed, o.cancelled_orders, o.delivered_measured, o.on_time_orders,
    o.aged_order_value, o.overdue_balance
FROM orders AS o
LEFT JOIN sales AS s ON s.employee_id = o.employee_id AND s.customer_id = o.customer_id;

SELECT
    employee_id, MAX(clusters) AS customers, SUM(orders_placed) AS orders,
    ROUND(MAX(net_revenue) / SUM(net_revenue) * 100, 1) AS largest_customer_share_pct
FROM `sahyadri_b2b.rs_clusters`
GROUP BY employee_id
ORDER BY employee_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Bootstrap replicates (replicate 0 = the actual data)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rs_replicates` AS
WITH draws AS (
    SELECT b, c.employee_id, c.cluster_no AS slot, c.clusters,
           MOD(b * 7919 + c.cluster_no * 104729 + c.employee_id * 1299709, prime) AS x0
    FROM `sahyadri_b2b.rs_clusters` AS c
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, replicates)) AS b
),
hashed AS (
    SELECT *, MOD(x0 * x0 + 12345, prime) AS x1 FROM draws
),
picked AS (
    SELECT b, employee_id, 1 + MOD(MOD(x1 * x1 + 54321, prime), clusters) AS cluster_no FROM hashed
    UNION ALL
    SELECT 0, employee_id, cluster_no FROM `sahyadri_b2b.rs_clusters`
),
totals AS (
    SELECT p.b, p.employee_id,
           SUM(c.net_revenue) AS net_revenue, SUM(c.gross_value) AS gross_value,
           SUM(c.costed_revenue) AS costed_revenue, SUM(c.costed_margin) AS costed_margin,
           SUM(c.orders_placed) AS orders_placed, SUM(c.cancelled_orders) AS cancelled_orders,
           SUM(c.delivered_measured) AS delivered_measured, SUM(c.on_time_orders) AS on_time_orders,
           SUM(c.aged_order_value) AS aged_order_value, SUM(c.overdue_balance) AS overdue_balance,
           COUNT(*) AS clusters_drawn
    FROM picked AS p
    JOIN `sahyadri_b2b.rs_clusters` AS c ON c.employee_id = p.employee_id AND c.cluster_no = p.cluster_no
    GROUP BY p.b, p.employee_id
),
metrics AS (
    SELECT b, employee_id, clusters_drawn, net_revenue,
           100 * costed_margin / costed_revenue                 AS gross_margin_pct,
           100 * (gross_value - net_revenue) / gross_value      AS discount_pct,
           100 * cancelled_orders / orders_placed               AS cancellation_rate_pct,
           100 * on_time_orders / delivered_measured            AS on_time_pct,
           100 * overdue_balance / aged_order_value             AS overdue_receivable_pct
    FROM totals
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY b ORDER BY net_revenue DESC)            AS rank_revenue,
           RANK() OVER (PARTITION BY b ORDER BY gross_margin_pct DESC)       AS rank_margin,
           RANK() OVER (PARTITION BY b ORDER BY discount_pct ASC)            AS rank_discount,
           RANK() OVER (PARTITION BY b ORDER BY cancellation_rate_pct ASC)   AS rank_cancellation,
           RANK() OVER (PARTITION BY b ORDER BY on_time_pct DESC)            AS rank_on_time,
           RANK() OVER (PARTITION BY b ORDER BY overdue_receivable_pct ASC)  AS rank_collection
    FROM metrics
)
SELECT *,
       rank_revenue + rank_margin + rank_discount + rank_cancellation + rank_on_time + rank_collection AS rank_sum,
       RANK() OVER (PARTITION BY b ORDER BY rank_revenue + rank_margin + rank_discount
                                            + rank_cancellation + rank_on_time + rank_collection)    AS balanced_rank
FROM ranked;

-- -----------------------------------------------------------------------------
-- Step 3 · Long table: one row per replicate x salesperson x metric
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rs_long` AS
          SELECT b, employee_id, '1. Net revenue'       AS metric, net_revenue           AS value, rank_revenue      AS rnk FROM `sahyadri_b2b.rs_replicates`
UNION ALL SELECT b, employee_id, '2. Gross margin %',               gross_margin_pct,               rank_margin              FROM `sahyadri_b2b.rs_replicates`
UNION ALL SELECT b, employee_id, '3. Discount %',                   discount_pct,                   rank_discount            FROM `sahyadri_b2b.rs_replicates`
UNION ALL SELECT b, employee_id, '4. Cancellation rate',            cancellation_rate_pct,          rank_cancellation        FROM `sahyadri_b2b.rs_replicates`
UNION ALL SELECT b, employee_id, '5. On-time delivery %',           on_time_pct,                    rank_on_time             FROM `sahyadri_b2b.rs_replicates`
UNION ALL SELECT b, employee_id, '6. Overdue receivable %',         overdue_receivable_pct,         rank_collection          FROM `sahyadri_b2b.rs_replicates`
UNION ALL SELECT b, employee_id, '7. Balanced rank',                rank_sum,                       balanced_rank            FROM `sahyadri_b2b.rs_replicates`;

CREATE OR REPLACE TABLE `sahyadri_b2b.rs_intervals` AS
SELECT
    l.metric, l.employee_id,
    ANY_VALUE(a.value)                                         AS actual_value,
    ANY_VALUE(a.rnk)                                           AS actual_rank,
    APPROX_QUANTILES(l.value, 20)[OFFSET(1)]                   AS value_p05,
    APPROX_QUANTILES(l.value, 20)[OFFSET(19)]                  AS value_p95,
    APPROX_QUANTILES(l.rnk, 20)[OFFSET(1)]                     AS rank_p05,
    APPROX_QUANTILES(l.rnk, 20)[OFFSET(19)]                    AS rank_p95,
    AVG(IF(l.rnk <= 3, 1, 0))                                  AS p_top3,
    AVG(IF(l.rnk >= 14, 1, 0))                                 AS p_bottom3
FROM `sahyadri_b2b.rs_long` AS l
JOIN `sahyadri_b2b.rs_long` AS a ON a.metric = l.metric AND a.employee_id = l.employee_id AND a.b = 0
WHERE l.b > 0
GROUP BY l.metric, l.employee_id;

-- How wide are the rank intervals for each metric?
SELECT
    metric,
    ROUND(AVG(rank_p95 - rank_p05 + 1), 1)                     AS avg_rank_interval_width,
    COUNTIF(rank_p95 - rank_p05 + 1 <= 3)                      AS salespeople_within_3_places,
    COUNTIF(rank_p95 - rank_p05 + 1 >= 8)                      AS salespeople_spanning_half_the_table
FROM `sahyadri_b2b.rs_intervals`
GROUP BY metric
ORDER BY metric;

-- Balanced rank and margin rank, with 90 % intervals
SELECT
    i.employee_id, e.employee_name, e.designation,
    i.actual_rank                                              AS balanced_rank,
    CONCAT(CAST(i.rank_p05 AS STRING), '-', CAST(i.rank_p95 AS STRING)) AS balanced_rank_90pct,
    ROUND(100 * i.p_top3, 1)                                   AS pct_top3,
    ROUND(100 * i.p_bottom3, 1)                                AS pct_bottom3,
    m.actual_rank                                              AS margin_rank,
    CONCAT(CAST(m.rank_p05 AS STRING), '-', CAST(m.rank_p95 AS STRING)) AS margin_rank_90pct,
    ROUND(m.actual_value, 2)                                   AS margin_pct,
    CONCAT(CAST(ROUND(m.value_p05, 2) AS STRING), ' to ', CAST(ROUND(m.value_p95, 2) AS STRING)) AS margin_90pct
FROM `sahyadri_b2b.rs_intervals` AS i
JOIN `sahyadri_b2b.rs_intervals` AS m ON m.employee_id = i.employee_id AND m.metric = '2. Gross margin %'
JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = i.employee_id
WHERE i.metric = '7. Balanced rank'
ORDER BY i.actual_rank, i.employee_id;

-- -----------------------------------------------------------------------------
-- Step 4 · Which pairs can be told apart?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rs_pairs` AS
SELECT
    a.metric, a.employee_id AS employee_a, b.employee_id AS employee_b,
    AVG(IF(a.rnk < b.rnk, 1, IF(a.rnk = b.rnk, 0.5, 0)))       AS p_a_better
FROM `sahyadri_b2b.rs_long` AS a
JOIN `sahyadri_b2b.rs_long` AS b
  ON b.metric = a.metric AND b.b = a.b AND b.employee_id > a.employee_id
WHERE a.b > 0
GROUP BY a.metric, a.employee_id, b.employee_id;

SELECT
    metric,
    COUNT(*)                                                          AS pairs,
    COUNTIF(p_a_better >= 0.95 OR p_a_better <= 0.05)                 AS distinguishable_pairs,
    ROUND(100 * AVG(IF(p_a_better >= 0.95 OR p_a_better <= 0.05, 1, 0)), 1) AS distinguishable_pct
FROM `sahyadri_b2b.rs_pairs`
GROUP BY metric
ORDER BY metric;

-- Tiers that only separate people who can be told apart: for the balanced
-- rank, how many others is each salesperson reliably better or worse than?
WITH both_ways AS (
    SELECT employee_a AS employee_id, IF(p_a_better >= 0.95, 1, 0) AS beats, IF(p_a_better <= 0.05, 1, 0) AS beaten_by
    FROM `sahyadri_b2b.rs_pairs` WHERE metric = '7. Balanced rank'
    UNION ALL
    SELECT employee_b, IF(p_a_better <= 0.05, 1, 0), IF(p_a_better >= 0.95, 1, 0)
    FROM `sahyadri_b2b.rs_pairs` WHERE metric = '7. Balanced rank'
)
SELECT
    w.employee_id, e.employee_name, i.actual_rank AS balanced_rank,
    SUM(w.beats)                                         AS reliably_better_than,
    SUM(w.beaten_by)                                     AS reliably_worse_than,
    15 - SUM(w.beats) - SUM(w.beaten_by)                 AS indistinguishable_from,
    CASE WHEN SUM(w.beats) >= 8 THEN 'A. Clearly above most'
         WHEN SUM(w.beaten_by) >= 8 THEN 'C. Clearly below most'
         ELSE 'B. Middle (not separable)' END            AS evidence_tier
FROM both_ways AS w
JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = w.employee_id
JOIN `sahyadri_b2b.rs_intervals` AS i ON i.employee_id = w.employee_id AND i.metric = '7. Balanced rank'
GROUP BY w.employee_id, e.employee_name, i.actual_rank
ORDER BY i.actual_rank, w.employee_id;
