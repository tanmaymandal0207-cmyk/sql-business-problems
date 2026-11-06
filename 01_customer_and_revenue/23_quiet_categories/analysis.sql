/* =============================================================================
   Case study · Quiet categories: are customers moving categories to
   competitors?
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Customer churn reports only flag customers who stop buying altogether.
   The sales head suspects a quieter leak: customers who still buy from us
   but have taken one category, say bearings or pumps, to a competitor. He
   wants a "quiet category" alert and asks:
     1. How often does a category a customer bought regularly go quiet
        while the customer keeps ordering other things?
     2. Is that more than the customer's normal gaps would produce?
     3. How many quiet categories come back, and how quickly?
     4. Which categories go quiet most, how much revenue is really lost,
        and which pairs should sales call now?

   METHOD
     - Valid orders (not Cancelled or Returned), January 2024 - September
       2026: 11 quarters (q = 0 .. 10). Revenue after line discounts.
     - Panel: every customer-category pair ever bought x every quarter.
     - Established pair at quarter t: bought in at least 3 of the 4
       quarters t-4 .. t-1, including t-1.
     - Quiet spell starting at t: an established pair not bought in t,
       t+1 and t+2, while the customer ordered something in each of those
       three quarters. Starts t = 4 .. 8 (2025 Q1 - 2026 Q1) can be
       observed in full.
     - Expected by chance: for each established pair-quarter, (1 - p)^3,
       where p = the pair's share of the customer's active quarters in
       which it bought the category (all 11 quarters). That is the quiet
       rate if each quarter were an independent draw.
     - Came back: the pair bought the category again after the spell,
       by September 2026.
   ============================================================================= */

DECLARE first_day DATE DEFAULT DATE '2024-01-01';
DECLARE last_day  DATE DEFAULT DATE '2026-09-30';
DECLARE n_quarters INT64 DEFAULT 11;

-- -----------------------------------------------------------------------------
-- Step 1 · Customer-category-quarter panel
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.qc_panel` AS
WITH lines AS (
    SELECT o.customer_id, p.category_id, c.category_name,
           (EXTRACT(YEAR FROM o.order_date) - 2024) * 4 + EXTRACT(QUARTER FROM o.order_date) - 1 AS q,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)       AS value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    JOIN `sahyadri_b2b.product_categories` AS c ON c.category_id = p.category_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN first_day AND last_day
),
pair_quarter AS (
    SELECT customer_id, category_id, ANY_VALUE(category_name) AS category_name, q, SUM(value) AS value
    FROM lines GROUP BY customer_id, category_id, q
),
customer_quarter AS (
    SELECT customer_id, q, SUM(value) AS value FROM lines GROUP BY customer_id, q
),
pairs AS (
    SELECT customer_id, category_id, ANY_VALUE(category_name) AS category_name FROM pair_quarter GROUP BY customer_id, category_id
)
SELECT pr.customer_id, pr.category_id, pr.category_name, g.q,
       IFNULL(pq.value, 0)                                                            AS value,
       cq.customer_id IS NOT NULL                                                     AS customer_active
FROM pairs AS pr
CROSS JOIN UNNEST(GENERATE_ARRAY(0, n_quarters - 1)) AS g
LEFT JOIN pair_quarter AS pq ON pq.customer_id = pr.customer_id AND pq.category_id = pr.category_id AND pq.q = g.q
LEFT JOIN customer_quarter AS cq ON cq.customer_id = pr.customer_id AND cq.q = g.q;

-- -----------------------------------------------------------------------------
-- Step 2 · Established pair-quarters and quiet spells
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.qc_events` AS
WITH windows AS (
    SELECT *,
           COUNTIF(value > 0) OVER (PARTITION BY customer_id, category_id ORDER BY q ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS prior_quarters,
           SUM(value)          OVER (PARTITION BY customer_id, category_id ORDER BY q ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS prior_value,
           LAG(value)          OVER (PARTITION BY customer_id, category_id ORDER BY q)                                    AS last_quarter_value,
           COUNTIF(value > 0)      OVER (PARTITION BY customer_id, category_id ORDER BY q ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS bought_next_3,
           COUNTIF(customer_active) OVER (PARTITION BY customer_id, category_id ORDER BY q ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS active_next_3,
           -- first quarter after the three-quarter spell in which the pair bought again
           MIN(IF(value > 0, q, NULL)) OVER (PARTITION BY customer_id, category_id ORDER BY q ROWS BETWEEN 3 FOLLOWING AND UNBOUNDED FOLLOWING) AS next_purchase_q
    FROM `sahyadri_b2b.qc_panel`
),
pair_rate AS (
    -- share of the customer's active quarters in which the pair bought the category
    SELECT customer_id, category_id, COUNTIF(value > 0) / COUNTIF(customer_active) AS p
    FROM `sahyadri_b2b.qc_panel` GROUP BY customer_id, category_id
)
SELECT w.customer_id, w.category_id, w.category_name, w.q AS start_q, w.prior_quarters, w.prior_value,
       pr.p                                                                           AS pair_buy_rate,
       POW(1 - pr.p, 3)                                                               AS chance_quiet,
       w.bought_next_3 = 0                                                            AS quiet,
       w.next_purchase_q,
       w.next_purchase_q IS NOT NULL AND w.bought_next_3 = 0                          AS came_back,
       w.next_purchase_q - (w.q + 2)                                                  AS quarters_to_return
FROM windows AS w
JOIN pair_rate AS pr USING (customer_id, category_id)
WHERE w.q BETWEEN 4 AND n_quarters - 3
  AND w.prior_quarters >= 3 AND w.last_quarter_value > 0
  AND w.active_next_3 = 3;

-- How often an established category goes quiet, against chance
SELECT
    start_q,
    FORMAT('%d Q%d', 2024 + DIV(start_q, 4), MOD(start_q, 4) + 1)                     AS quiet_from,
    COUNT(*)                                                                          AS established_pairs,
    COUNTIF(quiet)                                                                    AS quiet_spells,
    ROUND(100 * COUNTIF(quiet) / COUNT(*), 1)                                         AS quiet_pct,
    ROUND(100 * AVG(chance_quiet), 2)                                                 AS expected_by_chance_pct,
    ROUND(SUM(chance_quiet), 1)                                                       AS expected_spells,
    -- spells are independent Bernoulli draws under chance: z = (observed - expected) / SD
    ROUND((COUNTIF(quiet) - SUM(chance_quiet)) / SQRT(SUM(chance_quiet * (1 - chance_quiet))), 2) AS z_score
FROM `sahyadri_b2b.qc_events`
GROUP BY ROLLUP(start_q)
ORDER BY start_q;

-- -----------------------------------------------------------------------------
-- Step 3 · Do quiet categories come back?
-- -----------------------------------------------------------------------------
-- Follow-up after the spell: quarters from the end of the spell to September 2026
SELECT
    FORMAT('%d Q%d', 2024 + DIV(start_q, 4), MOD(start_q, 4) + 1)                     AS quiet_from,
    (n_quarters - 1) - (start_q + 2)                                                    AS quarters_of_follow_up,
    COUNT(*)                                                                          AS quiet_spells,
    COUNTIF(quarters_to_return = 1)                                                   AS back_next_quarter,
    COUNTIF(came_back)                                                                AS back_by_sep_2026,
    ROUND(100 * COUNTIF(came_back) / COUNT(*), 1)                                     AS back_pct
FROM `sahyadri_b2b.qc_events`
WHERE quiet
GROUP BY start_q
ORDER BY start_q;

-- Spells with at least two quarters of follow-up: how soon do they come back?
SELECT
    COUNT(*)                                                                          AS quiet_spells,
    ROUND(100 * COUNTIF(quarters_to_return = 1) / COUNT(*), 1)                        AS back_within_1_quarter_pct,
    ROUND(100 * COUNTIF(quarters_to_return <= 2) / COUNT(*), 1)                       AS back_within_2_quarters_pct
FROM `sahyadri_b2b.qc_events`
WHERE quiet AND start_q <= n_quarters - 5;

-- -----------------------------------------------------------------------------
-- Step 4 · Which categories, how much is lost, and whom to call
-- -----------------------------------------------------------------------------
SELECT
    category_name,
    COUNT(*)                                                                          AS established_pair_quarters,
    COUNTIF(quiet)                                                                    AS quiet_spells,
    ROUND(100 * COUNTIF(quiet) / COUNT(*), 1)                                         AS quiet_pct,
    ROUND(100 * AVG(chance_quiet), 2)                                                 AS expected_by_chance_pct,
    COUNTIF(quiet AND came_back)                                                      AS came_back
FROM `sahyadri_b2b.qc_events`
GROUP BY category_name
ORDER BY quiet_pct DESC;

-- Revenue: value of the quiet pairs in the year before the spell, split by how long they have been watched since
SELECT
    IF(start_q <= n_quarters - 5, '1. Two or more quarters of follow-up', '2. Less than two quarters of follow-up') AS follow_up,
    COUNT(*)                                                                          AS quiet_spells,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(SUM(prior_value) / 1e5, 1)                                                  AS value_in_the_year_before_lakh,
    COUNTIF(NOT came_back)                                                            AS not_back_yet,
    ROUND(SUM(IF(NOT came_back, prior_value, 0)) / 1e5, 1)                            AS not_back_value_lakh
FROM `sahyadri_b2b.qc_events`
WHERE quiet
GROUP BY ROLLUP(follow_up)
ORDER BY follow_up;

-- Call list: pairs quiet since the spell began and still quiet in September 2026
SELECT
    cu.customer_name, cu.customer_segment, e.category_name,
    FORMAT('%d Q%d', 2024 + DIV(e.start_q, 4), MOD(e.start_q, 4) + 1)                 AS quiet_since,
    ROUND(e.prior_value / 1e5, 2)                                                     AS value_in_the_year_before_lakh,
    ROUND(100 * e.pair_buy_rate, 0)                                                   AS share_of_active_quarters_bought_pct
FROM `sahyadri_b2b.qc_events` AS e
JOIN `sahyadri_b2b.customers` AS cu ON cu.customer_id = e.customer_id
WHERE e.quiet AND NOT e.came_back
ORDER BY e.prior_value DESC
LIMIT 15;
