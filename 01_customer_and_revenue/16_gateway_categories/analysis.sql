/* =============================================================================
   Case study · Gateway categories: does the first order predict customer value?
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Marketing is planning next year's acquisition campaigns and wants to lead
   with the product categories that bring in the best customers. A raw
   comparison shows that customers whose first order was a pump or a motor
   spend far more in their first year than those who started with fasteners.
   The commercial head asks whether that is the category, or just bigger
   customers placing bigger first orders:
     1. What do customers buy on their first order?
     2. How much do they spend, and how many come back, in the 12 months
        after it, by gateway category?
     3. Does any difference survive once segment and first-order size are
        held constant?
     4. Which gateway categories lead customers into other categories?

   METHOD
     - Valid orders: not Cancelled or Returned. First order = the earliest
       valid order (date, then order id).
     - Gateway category = the category with the largest net value on the
       first order.
     - Customers whose first order is on or before 30 Sep 2025, so 12 months
       of follow-up are observed.
     - Outcomes over the 365 days after the first order (the first order
       itself excluded): came back (any valid order), revenue, number of
       categories bought, and categories new to the customer.
     - Confounders: segment and first-order size band (thirds of first-order
       value). Each customer's expected outcome is the mean of its segment x
       size cell; a category's residual = mean(outcome - expected).
     - Permutation test: gateway labels are shuffled 1,000 times within each
       segment x size cell. Overall statistic = SUM n x residual^2 over
       categories; per category, the share of shuffles with a residual at
       least as large in absolute value. Revenue is tested in rupees and
       on LN(1 + rupees), so a few large accounts cannot decide the result.
   ============================================================================= */

DECLARE follow_days      INT64 DEFAULT 365;
DECLARE last_first_order DATE  DEFAULT DATE '2025-09-30';
DECLARE permutations     INT64 DEFAULT 1000;
DECLARE prime            INT64 DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per customer: first order, gateway category, 12-month outcome
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.gw_customers` AS
WITH lines AS (
    SELECT o.order_id, o.customer_id, o.order_date, p.category_id,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS line_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
orders AS (
    SELECT order_id, customer_id, order_date, SUM(line_value) AS order_value,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS order_seq
    FROM lines
    GROUP BY order_id, customer_id, order_date
),
first_order AS (
    SELECT customer_id, order_id AS first_order_id, order_date AS first_order_date, order_value AS first_order_value
    FROM orders
    WHERE order_seq = 1
),
first_cats AS (
    SELECT l.customer_id, l.category_id, SUM(l.line_value) AS category_value,
           ROW_NUMBER() OVER (PARTITION BY l.customer_id ORDER BY SUM(l.line_value) DESC, l.category_id) AS rk
    FROM lines AS l
    JOIN first_order AS f ON f.first_order_id = l.order_id
    GROUP BY l.customer_id, l.category_id
),
later AS (
    -- valid orders after the first order, within the follow-up window
    SELECT f.customer_id,
           COUNT(DISTINCT l.order_id)          AS orders_12m,
           IFNULL(SUM(l.line_value), 0)        AS revenue_12m,
           COUNT(DISTINCT l.category_id)       AS categories_12m,
           COUNT(DISTINCT IF(fc.category_id IS NULL, l.category_id, NULL)) AS new_categories_12m
    FROM first_order AS f
    JOIN orders AS o ON o.customer_id = f.customer_id AND o.order_seq > 1
                    AND o.order_date <= DATE_ADD(f.first_order_date, INTERVAL follow_days DAY)
    JOIN lines AS l ON l.order_id = o.order_id
    LEFT JOIN first_cats AS fc ON fc.customer_id = f.customer_id AND fc.category_id = l.category_id
    GROUP BY f.customer_id
)
SELECT
    f.customer_id, c.customer_segment, f.first_order_id, f.first_order_date, f.first_order_value,
    g.category_id                                                   AS gateway_category_id,
    pc.category_name                                                AS gateway_category,
    n.first_order_categories,
    IFNULL(l.orders_12m, 0)                                         AS orders_12m,
    IFNULL(l.orders_12m, 0) > 0                                     AS came_back,
    IFNULL(l.revenue_12m, 0)                                        AS revenue_12m,
    LN(1 + IFNULL(l.revenue_12m, 0))                                AS log_revenue_12m,
    IFNULL(l.categories_12m, 0)                                     AS categories_12m,
    IFNULL(l.new_categories_12m, 0)                                 AS new_categories_12m
FROM first_order AS f
JOIN first_cats AS g ON g.customer_id = f.customer_id AND g.rk = 1
JOIN (SELECT customer_id, COUNT(*) AS first_order_categories FROM first_cats GROUP BY customer_id) AS n ON n.customer_id = f.customer_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = g.category_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = f.customer_id
LEFT JOIN later AS l ON l.customer_id = f.customer_id
WHERE f.first_order_date <= last_first_order;

-- Add the size band, the segment x size cell and the expected outcomes
CREATE OR REPLACE TABLE `sahyadri_b2b.gw_scored` AS
WITH banded AS (
    SELECT *, NTILE(3) OVER (ORDER BY first_order_value, customer_id) AS size_band
    FROM `sahyadri_b2b.gw_customers`
)
SELECT
    b.*,
    CONCAT(b.customer_segment, ' | ', CAST(b.size_band AS STRING))                                AS cell,
    AVG(IF(b.came_back, 1, 0)) OVER (PARTITION BY b.customer_segment, b.size_band)                 AS expected_came_back,
    AVG(b.revenue_12m)         OVER (PARTITION BY b.customer_segment, b.size_band)                 AS expected_revenue_12m,
    AVG(b.log_revenue_12m)     OVER (PARTITION BY b.customer_segment, b.size_band)                 AS expected_log_revenue_12m,
    AVG(b.new_categories_12m)  OVER (PARTITION BY b.customer_segment, b.size_band)                 AS expected_new_categories
FROM banded AS b;

SELECT
    COUNT(*)                                                    AS customers,
    ROUND(AVG(first_order_value) / 1e3, 1)                      AS avg_first_order_k,
    ROUND(AVG(first_order_categories), 2)                       AS avg_first_order_categories,
    ROUND(100 * AVG(IF(came_back, 1, 0)), 1)                    AS came_back_pct,
    ROUND(AVG(revenue_12m) / 1e5, 2)                            AS avg_revenue_12m_lakh,
    ROUND(APPROX_QUANTILES(revenue_12m, 100)[OFFSET(50)] / 1e5, 2) AS median_revenue_12m_lakh
FROM `sahyadri_b2b.gw_scored`;

-- -----------------------------------------------------------------------------
-- Step 2 · Raw and adjusted outcomes by gateway category
-- -----------------------------------------------------------------------------
SELECT
    gateway_category,
    COUNT(*)                                                                  AS customers,
    ROUND(AVG(first_order_value) / 1e3, 1)                                    AS avg_first_order_k,
    ROUND(100 * AVG(IF(customer_segment = 'Enterprise', 1, 0)), 0)            AS enterprise_pct,
    ROUND(100 * AVG(IF(came_back, 1, 0)), 1)                                  AS came_back_pct,
    ROUND(100 * AVG(expected_came_back), 1)                                   AS expected_came_back_pct,
    ROUND(AVG(revenue_12m) / 1e5, 2)                                          AS avg_revenue_12m_lakh,
    ROUND(AVG(expected_revenue_12m) / 1e5, 2)                                 AS expected_revenue_12m_lakh,
    ROUND(SUM(revenue_12m) / SUM(expected_revenue_12m), 2)                    AS revenue_o_to_e,
    ROUND(APPROX_QUANTILES(revenue_12m, 100)[OFFSET(50)] / 1e5, 2)            AS median_revenue_12m_lakh,
    ROUND(AVG(new_categories_12m), 2)                                         AS new_categories,
    ROUND(AVG(expected_new_categories), 2)                                    AS expected_new_categories
FROM `sahyadri_b2b.gw_scored`
GROUP BY gateway_category
ORDER BY avg_revenue_12m_lakh DESC;

-- How much of the raw revenue spread is explained by segment and first-order size?
SELECT
    ROUND(VAR_POP(cat_mean) / 1e10, 2)                                        AS spread_raw,
    ROUND(VAR_POP(cat_adjusted) / 1e10, 2)                                    AS spread_adjusted,
    ROUND(100 * (1 - VAR_POP(cat_adjusted) / VAR_POP(cat_mean)), 1)           AS spread_explained_pct
FROM (
    SELECT gateway_category, AVG(revenue_12m) AS cat_mean,
           AVG(revenue_12m - expected_revenue_12m) AS cat_adjusted
    FROM `sahyadri_b2b.gw_scored`
    GROUP BY gateway_category
);

-- First-order size against 12-month revenue
SELECT
    size_band,
    COUNT(*)                                                  AS customers,
    ROUND(MIN(first_order_value) / 1e3, 1)                    AS min_first_order_k,
    ROUND(MAX(first_order_value) / 1e3, 1)                    AS max_first_order_k,
    ROUND(100 * AVG(IF(came_back, 1, 0)), 1)                  AS came_back_pct,
    ROUND(AVG(revenue_12m) / 1e5, 2)                          AS avg_revenue_12m_lakh,
    ROUND(APPROX_QUANTILES(revenue_12m, 100)[OFFSET(50)] / 1e5, 2) AS median_revenue_12m_lakh
FROM `sahyadri_b2b.gw_scored`
GROUP BY size_band
ORDER BY size_band;

-- -----------------------------------------------------------------------------
-- Step 3 · Permutation test: shuffle gateway labels within segment x size cells
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.gw_permutation_stats` AS
WITH base AS (
    SELECT customer_id, cell, gateway_category,
           IF(came_back, 1, 0) - expected_came_back           AS resid_came_back,
           revenue_12m - expected_revenue_12m                 AS resid_revenue,
           log_revenue_12m - expected_log_revenue_12m         AS resid_log_revenue,
           new_categories_12m - expected_new_categories       AS resid_new_categories,
           ROW_NUMBER() OVER (PARTITION BY cell ORDER BY customer_id) AS pos
    FROM `sahyadri_b2b.gw_scored`
),
reps AS (
    SELECT 0 AS b UNION ALL SELECT b FROM UNNEST(GENERATE_ARRAY(1, permutations)) AS b
),
shuffled AS (
    -- b = 0 keeps the real labels; b >= 1 gives the label at a hashed position in the same cell
    SELECT r.b, x.customer_id, x.cell, x.resid_came_back, x.resid_revenue, x.resid_log_revenue, x.resid_new_categories,
           IF(r.b = 0, x.pos,
              ROW_NUMBER() OVER (PARTITION BY r.b, x.cell
                                 ORDER BY MOD(MOD(r.b * 7919 + x.customer_id * 104729, prime) * MOD(r.b * 7919 + x.customer_id * 104729, prime) + 12345, prime), x.customer_id)) AS label_pos
    FROM reps AS r
    CROSS JOIN base AS x
),
labelled AS (
    SELECT s.*, l.gateway_category
    FROM shuffled AS s
    JOIN base AS l ON l.cell = s.cell AND l.pos = s.label_pos
)
SELECT b, gateway_category, COUNT(*) AS n,
       AVG(resid_came_back)       AS resid_came_back,
       AVG(resid_revenue)         AS resid_revenue,
       AVG(resid_log_revenue)     AS resid_log_revenue,
       AVG(resid_new_categories)  AS resid_new_categories
FROM labelled
GROUP BY b, gateway_category;

-- Overall test: does the gateway category matter at all?
WITH stat AS (
    SELECT b,
           SUM(n * POW(resid_came_back, 2))       AS s_came_back,
           SUM(n * POW(resid_revenue, 2))         AS s_revenue,
           SUM(n * POW(resid_log_revenue, 2))     AS s_log_revenue,
           SUM(n * POW(resid_new_categories, 2))  AS s_new_categories
    FROM `sahyadri_b2b.gw_permutation_stats`
    GROUP BY b
)
SELECT
    ROUND((1 + COUNTIF(p.s_came_back      >= o.s_came_back      - 1e-12)) / (1 + COUNT(*)), 3) AS p_came_back,
    ROUND((1 + COUNTIF(p.s_revenue        >= o.s_revenue        - 1e-6))  / (1 + COUNT(*)), 3) AS p_revenue_rupees,
    ROUND((1 + COUNTIF(p.s_log_revenue    >= o.s_log_revenue    - 1e-12)) / (1 + COUNT(*)), 3) AS p_revenue_log,
    ROUND((1 + COUNTIF(p.s_new_categories >= o.s_new_categories - 1e-12)) / (1 + COUNT(*)), 3) AS p_new_categories
FROM stat AS p
CROSS JOIN (SELECT * FROM stat WHERE b = 0) AS o
WHERE p.b > 0;

-- Per category: adjusted effect and permutation p-value (10 tests: Bonferroni 0.005)
SELECT
    o.gateway_category,
    o.n                                                                                   AS customers,
    ROUND(100 * o.resid_came_back, 1)                                                     AS came_back_vs_expected_pts,
    ROUND(o.resid_revenue / 1e5, 2)                                                       AS revenue_vs_expected_lakh,
    ROUND(o.resid_new_categories, 2)                                                      AS new_categories_vs_expected,
    ROUND((1 + COUNTIF(ABS(p.resid_came_back)   >= ABS(o.resid_came_back)   - 1e-12)) / (1 + COUNT(*)), 3) AS p_came_back,
    ROUND((1 + COUNTIF(ABS(p.resid_revenue)     >= ABS(o.resid_revenue)     - 1e-6))  / (1 + COUNT(*)), 3) AS p_revenue_rupees,
    ROUND((1 + COUNTIF(ABS(p.resid_log_revenue) >= ABS(o.resid_log_revenue) - 1e-12)) / (1 + COUNT(*)), 3) AS p_revenue_log,
    ROUND((1 + COUNTIF(ABS(p.resid_new_categories) >= ABS(o.resid_new_categories) - 1e-12)) / (1 + COUNT(*)), 3) AS p_new_categories
FROM (SELECT * FROM `sahyadri_b2b.gw_permutation_stats` WHERE b = 0) AS o
JOIN `sahyadri_b2b.gw_permutation_stats` AS p ON p.gateway_category = o.gateway_category AND p.b > 0
GROUP BY o.gateway_category, o.n, o.resid_came_back, o.resid_revenue, o.resid_log_revenue, o.resid_new_categories
ORDER BY revenue_vs_expected_lakh DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Where do customers go next? Categories bought later, by gateway
-- -----------------------------------------------------------------------------
SELECT
    gateway_category,
    COUNT(*)                                                              AS customers,
    ROUND(AVG(categories_12m), 2)                                         AS categories_bought_12m,
    ROUND(100 * AVG(IF(new_categories_12m >= 1, 1, 0)), 1)                AS bought_a_new_category_pct,
    ROUND(100 * AVG(IF(new_categories_12m >= 3, 1, 0)), 1)                AS bought_3plus_new_pct
FROM `sahyadri_b2b.gw_scored`
GROUP BY gateway_category
ORDER BY categories_bought_12m DESC;
