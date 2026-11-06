/* =============================================================================
   Case study · Annual rate contracts: who to offer them to, and what
   volume to ask for
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Earlier studies recommended annual rate contracts (a fixed price list
   for a year in return for a committed purchase value) for loyal
   accounts. Before the sales head offers any, he needs to know:
     1. Should a contract be written per product or per category?
     2. Which customer-category pairs buy steadily enough to commit?
     3. What share of last year's value can they safely commit to, judged
        on what customers actually bought the following year?
     4. How much revenue would the contracts cover, and with whom?

   METHOD
     - Valid orders (not Cancelled or Returned), January 2024 - September
       2026 (11 quarters). Revenue after line discounts.
     - Repeat buying: quarters in which a customer bought a product (SKU
       level) or a category (category level), out of 11.
     - Back-tests: two pairs of years, Y1 then Y2:
         A. Calendar 2024 -> calendar 2025
         B. Oct 2024 - Sep 2025 -> Oct 2025 - Sep 2026
       For each customer-category pair active in Y1: quarters active in Y1
       (1 - 4), Y1 value and Y2 value.
     - Commitment = c x Y1 value. Met if Y2 value >= commitment.
       Shortfall = MAX(0, commitment - Y2 value).
     - Qualifying rule tested: bought in all 4 quarters of Y1 and Y1 value
       of at least Rs 2 lakh. The safe level is the highest commitment
       met by at least 80 % of qualifying pairs in both back-tests.
   ============================================================================= */

DECLARE first_day     DATE    DEFAULT DATE '2024-01-01';
DECLARE last_day      DATE    DEFAULT DATE '2026-09-30';
DECLARE min_value     FLOAT64 DEFAULT 200000;
DECLARE target_hit    FLOAT64 DEFAULT 0.80;

-- -----------------------------------------------------------------------------
-- Step 1 · Product or category: how steady is repeat buying?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rc_lines` AS
SELECT o.order_id, o.customer_id, o.order_date, DATE_TRUNC(o.order_date, QUARTER) AS quarter,
       i.product_id, p.category_id, c.category_name,
       i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)          AS value
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
JOIN `sahyadri_b2b.product_categories` AS c ON c.category_id = p.category_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN first_day AND last_day;

WITH sku AS (
    SELECT customer_id, product_id, COUNT(DISTINCT quarter) AS quarters, SUM(value) AS value
    FROM `sahyadri_b2b.rc_lines` GROUP BY customer_id, product_id
),
cat AS (
    SELECT customer_id, category_id, COUNT(DISTINCT quarter) AS quarters, SUM(value) AS value
    FROM `sahyadri_b2b.rc_lines` GROUP BY customer_id, category_id
),
both_levels AS (
    SELECT '1. Customer x product' AS level, quarters, value FROM sku
    UNION ALL
    SELECT '2. Customer x category', quarters, value FROM cat
)
SELECT
    level,
    COUNT(*)                                                                          AS pairs,
    COUNTIF(quarters >= 9)                                                            AS pairs_in_9_plus_quarters,
    ROUND(100 * SUM(IF(quarters >= 9, value, 0)) / SUM(value), 1)                     AS revenue_in_9_plus_quarters_pct,
    ROUND(100 * SUM(IF(quarters = 11, value, 0)) / SUM(value), 1)                     AS revenue_in_all_11_quarters_pct,
    ROUND(100 * SUM(IF(quarters <= 2, value, 0)) / SUM(value), 1)                     AS revenue_in_1_2_quarters_pct
FROM both_levels
GROUP BY level
ORDER BY level;

-- -----------------------------------------------------------------------------
-- Step 2 · Customer-category pairs in two back-tests
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rc_pairs` AS
WITH tests AS (
    SELECT 'A. 2024 -> 2025' AS test, DATE '2024-01-01' AS y1_start, DATE '2025-01-01' AS y2_start, DATE '2025-12-31' AS y2_end
    UNION ALL
    SELECT 'B. Oct 2024-Sep 2025 -> Oct 2025-Sep 2026', DATE '2024-10-01', DATE '2025-10-01', DATE '2026-09-30'
),
by_year AS (
    SELECT t.test, l.customer_id, l.category_id, ANY_VALUE(l.category_name) AS category_name,
           COUNT(DISTINCT IF(l.order_date < t.y2_start, l.quarter, NULL))             AS y1_quarters,
           SUM(IF(l.order_date < t.y2_start, l.value, 0))                             AS y1_value,
           SUM(IF(l.order_date >= t.y2_start, l.value, 0))                            AS y2_value
    FROM `sahyadri_b2b.rc_lines` AS l
    JOIN tests AS t ON l.order_date BETWEEN t.y1_start AND t.y2_end
    GROUP BY t.test, l.customer_id, l.category_id
)
SELECT *,
       y1_quarters = 4 AND y1_value >= min_value                                      AS qualifies
FROM by_year
WHERE y1_quarters > 0;

-- How often is a commitment met, by quarters active in Y1?
SELECT
    test, y1_quarters,
    COUNT(*)                                                                          AS pairs,
    ROUND(SUM(y1_value) / 1e7, 2)                                                     AS y1_value_crore,
    ROUND(100 * COUNTIF(y2_value >= 0.5 * y1_value) / COUNT(*), 1)                    AS met_at_50_pct,
    ROUND(100 * COUNTIF(y2_value >= 0.7 * y1_value) / COUNT(*), 1)                    AS met_at_70_pct,
    ROUND(100 * COUNTIF(y2_value >= 0.8 * y1_value) / COUNT(*), 1)                    AS met_at_80_pct,
    ROUND(100 * COUNTIF(y2_value >= y1_value) / COUNT(*), 1)                          AS met_at_100_pct
FROM `sahyadri_b2b.rc_pairs`
GROUP BY test, y1_quarters
ORDER BY test, y1_quarters DESC;

-- Among pairs bought in all 4 quarters: does Y1 size matter?
SELECT
    test,
    CASE WHEN y1_value < 100000 THEN '1. Below Rs 1 lakh'
         WHEN y1_value < 200000 THEN '2. Rs 1-2 lakh'
         WHEN y1_value < 500000 THEN '3. Rs 2-5 lakh'
         ELSE '4. Rs 5 lakh and above' END                                            AS y1_value_band,
    COUNT(*)                                                                          AS pairs,
    ROUND(100 * COUNTIF(y2_value >= 0.5 * y1_value) / COUNT(*), 1)                    AS met_at_50_pct,
    ROUND(100 * COUNTIF(y2_value >= 0.7 * y1_value) / COUNT(*), 1)                    AS met_at_70_pct,
    ROUND(100 * COUNTIF(y2_value >= 0.8 * y1_value) / COUNT(*), 1)                    AS met_at_80_pct,
    ROUND(100 * COUNTIF(y2_value = 0) / COUNT(*), 1)                                  AS stopped_buying_pct
FROM `sahyadri_b2b.rc_pairs`
WHERE y1_quarters = 4
GROUP BY test, y1_value_band
ORDER BY test, y1_value_band;

-- -----------------------------------------------------------------------------
-- Step 3 · The safe commitment level for qualifying pairs
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rc_levels` AS
WITH levels AS (
    SELECT c / 100 AS c FROM UNNEST(GENERATE_ARRAY(30, 100, 5)) AS c
)
SELECT
    p.test, lv.c,
    COUNT(*)                                                                          AS pairs,
    COUNTIF(p.y2_value >= lv.c * p.y1_value) / COUNT(*)                               AS met_share,
    SUM(lv.c * p.y1_value)                                                            AS committed,
    SUM(GREATEST(0, lv.c * p.y1_value - p.y2_value))                                  AS shortfall,
    SUM(p.y1_value)                                                                   AS y1_value,
    SUM(p.y2_value)                                                                   AS y2_value
FROM `sahyadri_b2b.rc_pairs` AS p CROSS JOIN levels AS lv
WHERE p.qualifies
GROUP BY p.test, lv.c;

SELECT
    test,
    ROUND(100 * c, 0)                                                                 AS commitment_pct_of_y1,
    pairs,
    ROUND(100 * met_share, 1)                                                         AS met_pct,
    ROUND(committed / 1e7, 2)                                                         AS committed_crore,
    ROUND(100 * shortfall / committed, 1)                                             AS shortfall_pct_of_committed
FROM `sahyadri_b2b.rc_levels`
WHERE c IN (0.5, 0.6, 0.7, 0.8, 1.0)
ORDER BY test, c;

-- Highest level met by at least target_hit of qualifying pairs in both back-tests
SELECT
    ROUND(100 * MAX(c), 0)                                                            AS safe_commitment_pct_of_y1
FROM (
    SELECT c FROM `sahyadri_b2b.rc_levels`
    GROUP BY c
    HAVING MIN(met_share) >= target_hit
);

-- Would one contract per customer, pooling its qualifying categories, be safer?
WITH pooled AS (
    SELECT test, customer_id, COUNT(*) AS categories, SUM(y1_value) AS y1_value, SUM(y2_value) AS y2_value
    FROM `sahyadri_b2b.rc_pairs` WHERE qualifies
    GROUP BY test, customer_id
)
SELECT
    test,
    COUNT(*)                                                                          AS customers,
    ROUND(AVG(categories), 1)                                                         AS categories_per_customer,
    ROUND(100 * COUNTIF(y2_value >= 0.5 * y1_value) / COUNT(*), 1)                    AS met_at_50_pct,
    ROUND(100 * COUNTIF(y2_value >= 0.7 * y1_value) / COUNT(*), 1)                    AS met_at_70_pct,
    ROUND(100 * COUNTIF(y2_value >= 0.8 * y1_value) / COUNT(*), 1)                    AS met_at_80_pct
FROM pooled
GROUP BY test
ORDER BY test;

-- -----------------------------------------------------------------------------
-- Step 4 · Contracts that would be offered now (latest year, Oct 2025 - Sep 2026)
-- -----------------------------------------------------------------------------
-- In test B the latest year is Y2; qualification for the next contract uses its own quarters.
CREATE OR REPLACE TABLE `sahyadri_b2b.rc_offers` AS
WITH latest AS (
    SELECT customer_id, category_id, ANY_VALUE(category_name) AS category_name,
           COUNT(DISTINCT quarter) AS quarters, SUM(value) AS value
    FROM `sahyadri_b2b.rc_lines`
    WHERE order_date BETWEEN DATE '2025-10-01' AND last_day
    GROUP BY customer_id, category_id
),
safe AS (
    SELECT MAX(c) AS c FROM (SELECT c FROM `sahyadri_b2b.rc_levels` GROUP BY c HAVING MIN(met_share) >= target_hit)
)
SELECT l.customer_id, cu.customer_name, cu.customer_segment, l.category_id, l.category_name,
       l.value AS last_year_value, s.c AS commitment_share, s.c * l.value AS commitment
FROM latest AS l
JOIN `sahyadri_b2b.customers` AS cu ON cu.customer_id = l.customer_id
CROSS JOIN safe AS s
WHERE l.quarters = 4 AND l.value >= min_value;

SELECT
    COUNT(*)                                                                          AS contracts,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(SUM(last_year_value) / 1e7, 2)                                              AS last_year_value_crore,
    ROUND(100 * SUM(last_year_value) / (SELECT SUM(value) FROM `sahyadri_b2b.rc_lines` WHERE order_date >= DATE '2025-10-01'), 1) AS share_of_latest_year_pct,
    ROUND(SUM(commitment) / 1e7, 2)                                                   AS committed_crore
FROM `sahyadri_b2b.rc_offers`;

-- By segment and by category
SELECT 'Segment' AS dimension, customer_segment AS item, COUNT(*) AS contracts, COUNT(DISTINCT customer_id) AS customers,
       ROUND(SUM(last_year_value) / 1e7, 2) AS last_year_value_crore, ROUND(SUM(commitment) / 1e7, 2) AS committed_crore
FROM `sahyadri_b2b.rc_offers` GROUP BY customer_segment
UNION ALL
SELECT 'Category', category_name, COUNT(*), COUNT(DISTINCT customer_id),
       ROUND(SUM(last_year_value) / 1e7, 2), ROUND(SUM(commitment) / 1e7, 2)
FROM `sahyadri_b2b.rc_offers` GROUP BY category_name
ORDER BY dimension DESC, last_year_value_crore DESC;

-- Customers with the most contract value
SELECT customer_name, customer_segment, COUNT(*) AS categories,
       ROUND(SUM(last_year_value) / 1e5, 1) AS last_year_value_lakh,
       ROUND(SUM(commitment) / 1e5, 1)      AS committed_lakh
FROM `sahyadri_b2b.rc_offers`
GROUP BY customer_name, customer_segment
ORDER BY SUM(last_year_value) DESC
LIMIT 10;
