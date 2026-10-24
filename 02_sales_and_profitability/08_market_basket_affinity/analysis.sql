/* =============================================================================
   Case study · Market basket affinity with significance testing
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The sales team wants to create product bundles and "customers who bought
   this also buy" prompts in the order system. Bundles only make sense for
   products that are genuinely bought together more often than chance. With
   200 products there are almost 20,000 possible pairs, so some pairs will
   look related purely by luck. The sales head wants to know:
     1. Which product categories and which products are bought together more
        often than chance would explain?
     2. How strong and how reliable are those associations?
     3. Which pairs are good enough for a bundle or an order-entry prompt?

   METHOD — association rules with a chi-square test
     For a pair (A, B) over N orders:
       support(A,B)     = orders with both / N
       confidence(A->B) = orders with both / orders with A
       lift             = support(A,B) / (support(A) * support(B))
                          (1 = independent; above 1 = bought together more)
     2 x 2 table per pair: a = both, b = A only, c = B only, d = neither
       chi-square (1 df) = N * (a d - b c)^2 / ((a+b)(c+d)(a+c)(b+d))
     Multiple testing: many pairs are tested, so the 5 % significance level
     is divided by the number of pairs tested (Bonferroni). The critical
     chi-square values are looked up from the test count in Step 3.

   KEY RULES
     - Baskets: orders not Cancelled or Returned, 1 Jan 2024 - 30 Sep 2026.
     - A product or category counts once per order.
     - Product pairs are tested only if both appear together in at least
       min_pair_orders (15) orders.
     - "Actionable": significant after Bonferroni, lift >= 1.5 and
       confidence >= 10 % in at least one direction.
   ============================================================================= */

DECLARE period_start    DATE  DEFAULT DATE '2024-01-01';
DECLARE period_end      DATE  DEFAULT DATE '2026-09-30';
DECLARE min_pair_orders INT64 DEFAULT 15;

-- -----------------------------------------------------------------------------
-- Step 1 · Baskets: one row per order and item (product and its category)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.basket_items` AS
SELECT DISTINCT
    o.order_id,
    i.product_id,
    p.category_id
FROM `sahyadri_b2b.sales_orders`      AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id   = o.order_id
JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
  AND o.order_date BETWEEN period_start AND period_end;

-- -----------------------------------------------------------------------------
-- Step 2 · Pair statistics at category level and product level
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.basket_pair_stats` AS
WITH n AS (SELECT COUNT(DISTINCT order_id) AS orders FROM `sahyadri_b2b.basket_items`),
category_orders AS (
    SELECT DISTINCT order_id, category_id AS item FROM `sahyadri_b2b.basket_items`
),
product_orders AS (
    SELECT DISTINCT order_id, product_id AS item FROM `sahyadri_b2b.basket_items`
),
items AS (
    SELECT 'Category' AS level, item, COUNT(*) AS orders_with FROM category_orders GROUP BY item
    UNION ALL
    SELECT 'Product', item, COUNT(*) FROM product_orders GROUP BY item
),
pairs AS (
    SELECT 'Category' AS level, x.item AS item_a, y.item AS item_b, COUNT(*) AS both_orders
    FROM category_orders AS x
    JOIN category_orders AS y ON y.order_id = x.order_id AND y.item > x.item
    GROUP BY x.item, y.item
    UNION ALL
    SELECT 'Product', x.item, y.item, COUNT(*)
    FROM product_orders AS x
    JOIN product_orders AS y ON y.order_id = x.order_id AND y.item > x.item
    GROUP BY x.item, y.item
    HAVING COUNT(*) >= min_pair_orders
),
tables AS (
    SELECT
        p.level, p.item_a, p.item_b,
        n.orders                                                  AS total_orders,
        p.both_orders                                             AS a,
        ia.orders_with - p.both_orders                            AS b,
        ib.orders_with - p.both_orders                            AS c,
        n.orders - ia.orders_with - ib.orders_with + p.both_orders AS d,
        ia.orders_with                                            AS orders_a,
        ib.orders_with                                            AS orders_b
    FROM pairs AS p
    CROSS JOIN n
    JOIN items AS ia ON ia.level = p.level AND ia.item = p.item_a
    JOIN items AS ib ON ib.level = p.level AND ib.item = p.item_b
)
SELECT
    level, item_a, item_b, total_orders, orders_a, orders_b,
    a                                                           AS both_orders,
    a / total_orders                                            AS support,
    a / orders_a                                                AS confidence_a_to_b,
    a / orders_b                                                AS confidence_b_to_a,
    a * total_orders / (orders_a * orders_b)                    AS lift,
    orders_a * orders_b / total_orders                          AS expected_both,
    total_orders * POW(a * d - b * c, 2)
        / ((a + b) * (c + d) * (a + c) * (b + d))               AS chi_square
FROM tables;

-- -----------------------------------------------------------------------------
-- Step 3 · Significance after Bonferroni correction
--          The per-test level is 0.05 / tests. The critical chi-square (1 df)
--          is taken from the next stricter standard level (0.01, 0.001,
--          0.0001, ...), which is slightly conservative: for 45 category tests
--          the exact value is 10.66 and the script uses 10.83.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.basket_pair_results` AS
WITH tests AS (
    SELECT level, COUNT(*) AS tests FROM `sahyadri_b2b.basket_pair_stats` GROUP BY level
),
-- chi-square (1 df) critical values; the square of the two-sided normal quantile
critical AS (
    SELECT level, tests,
        CASE
            WHEN 0.05 / tests >= 0.01    THEN 6.63
            WHEN 0.05 / tests >= 0.001   THEN 10.83
            WHEN 0.05 / tests >= 0.0001  THEN 15.14
            WHEN 0.05 / tests >= 0.00001 THEN 19.51
            ELSE 23.93
        END AS chi_square_critical
    FROM tests
)
SELECT
    s.*,
    c.tests,
    c.chi_square_critical,
    s.chi_square >= c.chi_square_critical                              AS significant,
    s.chi_square >= c.chi_square_critical AND s.lift >= 1.5
      AND GREATEST(s.confidence_a_to_b, s.confidence_b_to_a) >= 0.10   AS actionable
FROM `sahyadri_b2b.basket_pair_stats` AS s
JOIN critical                         AS c ON c.level = s.level;

SELECT
    level,
    ANY_VALUE(tests)                                     AS pairs_tested,
    ANY_VALUE(chi_square_critical)                       AS chi_square_critical,
    COUNTIF(chi_square >= 3.84)                          AS significant_without_correction,
    COUNTIF(significant)                                 AS significant_after_bonferroni,
    COUNTIF(significant AND lift > 1)                    AS significant_positive,
    COUNTIF(actionable)                                  AS actionable,
    ROUND(MIN(lift), 2)                                  AS min_lift,
    ROUND(MAX(lift), 2)                                  AS max_lift
FROM `sahyadri_b2b.basket_pair_results`
GROUP BY level
ORDER BY level;

-- -----------------------------------------------------------------------------
-- Step 4 · Category pairs, strongest first
-- -----------------------------------------------------------------------------
SELECT
    ca.category_name                                     AS category_a,
    cb.category_name                                     AS category_b,
    r.both_orders,
    ROUND(r.expected_both, 0)                            AS expected_if_independent,
    ROUND(r.lift, 3)                                     AS lift,
    ROUND(100 * r.confidence_a_to_b, 1)                  AS confidence_a_to_b_pct,
    ROUND(100 * r.confidence_b_to_a, 1)                  AS confidence_b_to_a_pct,
    ROUND(r.chi_square, 2)                               AS chi_square,
    r.significant
FROM `sahyadri_b2b.basket_pair_results` AS r
JOIN `sahyadri_b2b.product_categories`  AS ca ON ca.category_id = r.item_a
JOIN `sahyadri_b2b.product_categories`  AS cb ON cb.category_id = r.item_b
WHERE r.level = 'Category'
ORDER BY r.chi_square DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 5 · Product pairs that pass the test (bundle and prompt candidates)
-- -----------------------------------------------------------------------------
SELECT
    pa.product_name                                      AS product_a,
    pb.product_name                                      AS product_b,
    r.both_orders,
    ROUND(r.expected_both, 1)                            AS expected_if_independent,
    ROUND(r.lift, 2)                                     AS lift,
    ROUND(100 * r.confidence_a_to_b, 1)                  AS confidence_a_to_b_pct,
    ROUND(100 * r.confidence_b_to_a, 1)                  AS confidence_b_to_a_pct,
    ROUND(r.chi_square, 1)                               AS chi_square,
    r.actionable
FROM `sahyadri_b2b.basket_pair_results` AS r
JOIN `sahyadri_b2b.products`            AS pa ON pa.product_id = r.item_a
JOIN `sahyadri_b2b.products`            AS pb ON pb.product_id = r.item_b
WHERE r.level = 'Product' AND r.significant
ORDER BY r.chi_square DESC;
