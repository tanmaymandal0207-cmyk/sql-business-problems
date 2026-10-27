/* =============================================================================
   Case study · Key-account selection and regression to the mean
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Each October the sales director picks the 30 largest customers of the
   year to date as "key accounts" and gives each a growth target equal to
   the company's planned growth. Account managers complain that the targets
   on the biggest accounts are never met, while small accounts beat theirs
   easily. The director asks:
     1. How stable is the top of the customer list from one year to the next?
     2. Do last year's biggest customers grow more slowly than the rest
        (regression to the mean), and is the effect consistent?
     3. Which simple rule picks the key-account list that holds the most
        revenue next year?
     4. Where do next year's top customers come from?

   METHOD
     - Net revenue on orders not Cancelled or Returned, in comparable
       January-September windows: 2024, 2025 and 2026.
     - Two pairs: 2024 -> 2025 and 2025 -> 2026. In each pair, customers
       with revenue in the first year are ranked and put in deciles (1 =
       largest).
     - Growth = second-year revenue / first-year revenue - 1 (lost customers
       count with zero).
     - Regression to the mean: least-squares slope of LN(year 2) on
       LN(year 1) for customers active in both years; a slope below 1
       means large customers grow less, in proportion, than small ones.
     - Selection back-test (pair 2025 -> 2026): pick 30 accounts by
       (a) 2025 revenue, (b) 2024 + 2025 revenue, (c) 2025 order count,
       (d) 2025 revenue among customers who also bought in 2024; measure the
       share of all 2026 revenue they deliver, against the best possible 30.
   ============================================================================= */

DECLARE top_n INT64 DEFAULT 30;

-- -----------------------------------------------------------------------------
-- Step 1 · Customer revenue in three comparable windows
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ka_customer_years` AS
WITH orders AS (
    SELECT o.customer_id, o.order_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND EXTRACT(MONTH FROM o.order_date) <= 9
    GROUP BY o.customer_id, o.order_id, o.order_date
)
SELECT
    customer_id,
    SUM(IF(EXTRACT(YEAR FROM order_date) = 2024, order_value, 0))    AS rev_2024,
    SUM(IF(EXTRACT(YEAR FROM order_date) = 2025, order_value, 0))    AS rev_2025,
    SUM(IF(EXTRACT(YEAR FROM order_date) = 2026, order_value, 0))    AS rev_2026,
    COUNTIF(EXTRACT(YEAR FROM order_date) = 2025)                    AS orders_2025
FROM orders
GROUP BY customer_id;

-- Long form: one row per customer per pair, with first-year rank and decile
CREATE OR REPLACE TABLE `sahyadri_b2b.ka_pairs` AS
WITH long AS (
              SELECT '2024 -> 2025' AS pair, customer_id, rev_2024 AS y1, rev_2025 AS y2 FROM `sahyadri_b2b.ka_customer_years`
    UNION ALL SELECT '2025 -> 2026',          customer_id, rev_2025,       rev_2026       FROM `sahyadri_b2b.ka_customer_years`
),
ranked AS (
    SELECT *,
           IF(y1 > 0, ROW_NUMBER() OVER (PARTITION BY pair, y1 > 0 ORDER BY y1 DESC, customer_id), NULL) AS rank_y1,
           IF(y2 > 0, ROW_NUMBER() OVER (PARTITION BY pair, y2 > 0 ORDER BY y2 DESC, customer_id), NULL) AS rank_y2,
           COUNTIF(y1 > 0) OVER (PARTITION BY pair)                                                       AS active_y1
    FROM long
)
SELECT *,
       IF(rank_y1 IS NULL, NULL, CAST(CEIL(10 * rank_y1 / active_y1) AS INT64)) AS decile_y1
FROM ranked;

-- -----------------------------------------------------------------------------
-- Step 2 · Growth by first-year decile: regression to the mean
-- -----------------------------------------------------------------------------
SELECT
    pair, decile_y1,
    COUNT(*)                                                       AS customers,
    ROUND(SUM(y1) / 1e5, 1)                                        AS revenue_y1_lakh,
    ROUND(SUM(y2) / 1e5, 1)                                        AS revenue_y2_lakh,
    ROUND(100 * (SUM(y2) / SUM(y1) - 1), 1)                        AS growth_pct,
    COUNTIF(y2 = 0)                                                AS lost
FROM `sahyadri_b2b.ka_pairs`
WHERE decile_y1 IS NOT NULL
GROUP BY pair, decile_y1
ORDER BY pair, decile_y1;

-- Top decile against everyone, and the log-log slope
SELECT
    pair,
    ROUND(100 * (SUM(IF(decile_y1 = 1, y2, 0)) / SUM(IF(decile_y1 = 1, y1, 0)) - 1), 1)      AS top_decile_growth_pct,
    ROUND(100 * (SUM(IF(decile_y1 > 1, y2, 0)) / SUM(IF(decile_y1 > 1, y1, 0)) - 1), 1)      AS other_deciles_growth_pct,
    ROUND(100 * (SUM(IF(decile_y1 IS NOT NULL, y2, 0)) / SUM(y1) - 1), 1)                   AS existing_customers_growth_pct,
    ROUND(100 * (SUM(y2) / SUM(y1) - 1), 1)                                                 AS total_growth_incl_new_pct,
    ROUND(COVAR_SAMP(IF(y1 > 0 AND y2 > 0, LN(y1), NULL), IF(y1 > 0 AND y2 > 0, LN(y2), NULL))
          / VAR_SAMP(IF(y1 > 0 AND y2 > 0, LN(y1), NULL)), 3)                               AS log_slope,
    ROUND(CORR(IF(y1 > 0 AND y2 > 0, LN(y1), NULL), IF(y1 > 0 AND y2 > 0, LN(y2), NULL)), 3) AS log_correlation
FROM `sahyadri_b2b.ka_pairs`
GROUP BY pair
ORDER BY pair;

-- -----------------------------------------------------------------------------
-- Step 3 · How stable is the top of the list?
-- -----------------------------------------------------------------------------
SELECT
    p.pair, n AS top_n_size,
    COUNTIF(p.rank_y1 <= n)                                                    AS top_in_y1,
    COUNTIF(p.rank_y1 <= n AND p.rank_y2 <= n)                                 AS still_top_in_y2,
    COUNTIF(p.rank_y1 <= n AND p.y2 = 0)                                       AS stopped_buying,
    ROUND(100 * (SUM(IF(p.rank_y1 <= n, p.y2, 0)) / SUM(IF(p.rank_y1 <= n, p.y1, 0)) - 1), 1) AS their_growth_pct
FROM `sahyadri_b2b.ka_pairs` AS p
CROSS JOIN UNNEST([10, 20, 30, 50]) AS n
GROUP BY p.pair, n
ORDER BY p.pair, n;

-- Where do next year's top 30 come from?
SELECT
    pair,
    CASE WHEN rank_y1 IS NULL THEN '5. Not a customer in year 1'
         WHEN rank_y1 <= 30   THEN '1. Already top 30'
         WHEN rank_y1 <= 60   THEN '2. Ranked 31-60'
         WHEN rank_y1 <= 100  THEN '3. Ranked 61-100'
         ELSE                      '4. Ranked below 100' END                  AS rank_in_year_1,
    COUNT(*)                                                                    AS customers,
    ROUND(SUM(y2) / 1e5, 1)                                                     AS revenue_y2_lakh
FROM `sahyadri_b2b.ka_pairs`
WHERE rank_y2 <= top_n
GROUP BY pair, rank_in_year_1
ORDER BY pair, rank_in_year_1;

-- -----------------------------------------------------------------------------
-- Step 4 · Which rule picks the best key-account list? (2025 -> 2026)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ka_selection` AS
WITH c AS (SELECT * FROM `sahyadri_b2b.ka_customer_years`),
rules AS (
              SELECT 'A. 2025 revenue'                      AS rule, customer_id, rev_2026,
                     ROW_NUMBER() OVER (ORDER BY rev_2025 DESC, customer_id) AS pick_rank FROM c WHERE rev_2025 > 0
    UNION ALL SELECT 'B. 2024 + 2025 revenue',                customer_id, rev_2026,
                     ROW_NUMBER() OVER (ORDER BY rev_2024 + rev_2025 DESC, customer_id) FROM c WHERE rev_2024 + rev_2025 > 0
    UNION ALL SELECT 'C. 2025 order count',                   customer_id, rev_2026,
                     ROW_NUMBER() OVER (ORDER BY orders_2025 DESC, rev_2025 DESC, customer_id) FROM c WHERE orders_2025 > 0
    UNION ALL SELECT 'D. 2025 revenue, bought in both years',  customer_id, rev_2026,
                     ROW_NUMBER() OVER (ORDER BY rev_2025 DESC, customer_id) FROM c WHERE rev_2025 > 0 AND rev_2024 > 0
    UNION ALL SELECT 'Z. Best possible (hindsight)',           customer_id, rev_2026,
                     ROW_NUMBER() OVER (ORDER BY rev_2026 DESC, customer_id) FROM c WHERE rev_2026 > 0
)
SELECT * FROM rules WHERE pick_rank <= top_n;

SELECT
    rule,
    COUNT(*)                                                                    AS accounts,
    ROUND(SUM(rev_2026) / 1e7, 2)                                               AS revenue_2026_crore,
    ROUND(100 * SUM(rev_2026) / (SELECT SUM(rev_2026) FROM `sahyadri_b2b.ka_customer_years`), 1) AS share_of_2026_revenue_pct,
    COUNTIF(rev_2026 = 0)                                                       AS bought_nothing_in_2026
FROM `sahyadri_b2b.ka_selection`
GROUP BY rule
ORDER BY rule;

-- What a uniform target (existing-customer growth applied to every account) implies
WITH k AS (SELECT * FROM `sahyadri_b2b.ka_pairs` WHERE pair = '2025 -> 2026'),
g AS (SELECT SUM(y2) / SUM(y1) AS company_growth FROM k WHERE rank_y1 IS NOT NULL)  -- growth of existing customers
SELECT
    IF(rank_y1 <= top_n, 'Key accounts (top 30)', 'Other customers')            AS grp,
    COUNT(*)                                                                    AS customers,
    ROUND(SUM(y1) * ANY_VALUE(g.company_growth) / 1e5, 1)                       AS uniform_target_lakh,
    ROUND(SUM(y2) / 1e5, 1)                                                     AS actual_lakh,
    ROUND(100 * (SUM(y2) / (SUM(y1) * ANY_VALUE(g.company_growth)) - 1), 1)     AS actual_vs_target_pct,
    COUNTIF(y2 >= y1 * g.company_growth)                                        AS customers_meeting_target
FROM k CROSS JOIN g
WHERE rank_y1 IS NOT NULL
GROUP BY grp
ORDER BY grp;
