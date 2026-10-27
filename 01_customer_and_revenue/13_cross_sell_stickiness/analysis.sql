/* =============================================================================
   Case study · Cross-sell stickiness (category trial-to-repeat)
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Sales managers count a cross-sell as won when an existing customer buys a
   product category for the first time. The commercial head suspects that
   many of these first purchases are one-offs and wants to know which
   categories, once tried, become recurring business:
     1. When an existing customer tries a new category, how often does it buy
        that category again within 12 months?
     2. Which categories repeat more or less often than expected, once the
        customer's own ordering frequency is allowed for?
     3. How much follow-on revenue does a trial bring?
     4. Which recent trials in sticky categories have not repeated yet?

   METHOD
     - Order lines on orders that are not Cancelled or Returned.
     - Trial: a customer's first purchase of a category. It counts as a
       cross-sell trial when it falls at least 90 days after the customer's
       first order in the data (an existing account, not onboarding).
     - Measured trials: trial date on or before 30 Sep 2025, so 12 months of
       follow-up can be observed.
     - Repeat: another order containing the category, on a later date, within
       365 days of the trial.
     - A frequent buyer repeats almost anything. Each trial is put in a
       frequency band by the customer's number of orders (any category) in
       the 365 days after the trial: 0-3, 4-8, 9-15, 16+.
     - Expected repeats for a category = SUM over its trials of the repeat
       rate of all trials in the same frequency band (indirect
       standardisation). O/E = observed / expected.
     - z = (observed - expected) / SQRT(SUM p (1 - p)). With 10 categories
       tested, |z| >= 2.81 is significant (Bonferroni, 5 %).
   ============================================================================= */

DECLARE onboarding_days INT64 DEFAULT 90;
DECLARE follow_days     INT64 DEFAULT 365;
DECLARE last_trial      DATE  DEFAULT DATE '2025-09-30';
DECLARE as_of           DATE  DEFAULT DATE '2026-09-30';
DECLARE z_critical      FLOAT64 DEFAULT 2.81;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per customer x category first purchase
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.xs_trials` AS
WITH lines AS (
    SELECT o.order_id, o.customer_id, o.order_date, c.category_name AS category,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS line_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    JOIN `sahyadri_b2b.product_categories` AS c ON c.category_id = p.category_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
cust_orders AS (
    SELECT DISTINCT customer_id, order_id, order_date FROM lines
),
first_order AS (
    SELECT customer_id, MIN(order_date) AS first_order_date FROM cust_orders GROUP BY customer_id
),
cat_orders AS (
    SELECT customer_id, category, order_id, order_date, SUM(line_value) AS cat_value
    FROM lines
    GROUP BY customer_id, category, order_id, order_date
),
trial AS (
    SELECT customer_id, category, MIN(order_date) AS trial_date
    FROM cat_orders
    GROUP BY customer_id, category
),
trial_value AS (
    SELECT t.customer_id, t.category, SUM(c.cat_value) AS trial_value
    FROM trial AS t
    JOIN cat_orders AS c
      ON c.customer_id = t.customer_id AND c.category = t.category AND c.order_date = t.trial_date
    GROUP BY t.customer_id, t.category
),
follow_cat AS (
    SELECT t.customer_id, t.category,
           COUNT(c.order_id)                 AS repeat_orders,
           IFNULL(SUM(c.cat_value), 0)       AS follow_on_value,
           MIN(c.order_date)                 AS first_repeat_date
    FROM trial AS t
    LEFT JOIN cat_orders AS c
      ON c.customer_id = t.customer_id AND c.category = t.category
     AND c.order_date > t.trial_date
     AND c.order_date <= DATE_ADD(t.trial_date, INTERVAL follow_days DAY)
    GROUP BY t.customer_id, t.category
),
follow_any AS (
    SELECT t.customer_id, t.category, COUNT(o.order_id) AS orders_next_year
    FROM trial AS t
    LEFT JOIN cust_orders AS o
      ON o.customer_id = t.customer_id
     AND o.order_date > t.trial_date
     AND o.order_date <= DATE_ADD(t.trial_date, INTERVAL follow_days DAY)
    GROUP BY t.customer_id, t.category
)
SELECT
    t.customer_id, t.category, t.trial_date, f.first_order_date,
    v.trial_value,
    t.trial_date >= DATE_ADD(f.first_order_date, INTERVAL onboarding_days DAY)  AS is_cross_sell,
    t.trial_date >= DATE_ADD(f.first_order_date, INTERVAL onboarding_days DAY)
      AND t.trial_date <= last_trial                                           AS is_measured,
    fc.repeat_orders, fc.repeat_orders > 0                                     AS repeated,
    fc.follow_on_value, fc.first_repeat_date,
    DATE_DIFF(fc.first_repeat_date, t.trial_date, DAY)                         AS days_to_repeat,
    fa.orders_next_year,
    CASE WHEN fa.orders_next_year <= 3  THEN '1. 0-3 orders'
         WHEN fa.orders_next_year <= 8  THEN '2. 4-8 orders'
         WHEN fa.orders_next_year <= 15 THEN '3. 9-15 orders'
         ELSE                                '4. 16+ orders' END               AS frequency_band
FROM trial AS t
JOIN first_order AS f  ON f.customer_id = t.customer_id
JOIN trial_value AS v  ON v.customer_id = t.customer_id AND v.category = t.category
JOIN follow_cat  AS fc ON fc.customer_id = t.customer_id AND fc.category = t.category
JOIN follow_any  AS fa ON fa.customer_id = t.customer_id AND fa.category = t.category;

SELECT
    COUNT(*)                                                   AS customer_category_pairs,
    COUNTIF(NOT is_cross_sell)                                 AS bought_in_first_90_days,
    COUNTIF(is_cross_sell)                                     AS cross_sell_trials,
    COUNTIF(is_measured)                                       AS measured_trials,
    COUNTIF(is_measured AND repeated)                          AS repeated,
    ROUND(100 * AVG(IF(is_measured, IF(repeated, 1, 0), NULL)), 1) AS repeat_pct
FROM `sahyadri_b2b.xs_trials`;

-- Repeat rate by the customer's ordering frequency after the trial
SELECT
    frequency_band,
    COUNT(*)                                       AS trials,
    COUNTIF(repeated)                              AS repeated,
    ROUND(100 * AVG(IF(repeated, 1, 0)), 1)        AS repeat_pct
FROM `sahyadri_b2b.xs_trials`
WHERE is_measured
GROUP BY frequency_band
ORDER BY frequency_band;

-- -----------------------------------------------------------------------------
-- Step 2 · Observed vs expected repeats by category
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.xs_category` AS
WITH band_rate AS (
    SELECT frequency_band, AVG(IF(repeated, 1, 0)) AS p
    FROM `sahyadri_b2b.xs_trials`
    WHERE is_measured
    GROUP BY frequency_band
),
scored AS (
    SELECT t.*, b.p
    FROM `sahyadri_b2b.xs_trials` AS t
    JOIN band_rate AS b ON b.frequency_band = t.frequency_band
    WHERE t.is_measured
)
SELECT
    category,
    COUNT(*)                                                   AS trials,
    COUNTIF(repeated)                                          AS observed,
    SUM(p)                                                     AS expected,
    SUM(p * (1 - p))                                           AS variance,
    COUNTIF(repeated) / COUNT(*)                               AS repeat_rate,
    COUNTIF(repeated) / SUM(p)                                 AS o_e,
    (COUNTIF(repeated) - SUM(p)) / SQRT(SUM(p * (1 - p)))      AS z,
    AVG(orders_next_year)                                      AS avg_orders_next_year,
    APPROX_QUANTILES(days_to_repeat, 2)[OFFSET(1)]             AS median_days_to_repeat,
    AVG(trial_value)                                           AS avg_trial_value,
    AVG(follow_on_value)                                       AS avg_follow_on_value
FROM scored
GROUP BY category;

SELECT
    category, trials, observed, ROUND(expected, 1) AS expected,
    ROUND(100 * repeat_rate, 1)                      AS repeat_pct,
    ROUND(o_e, 2)                                    AS o_e,
    ROUND(z, 2)                                      AS z,
    CASE WHEN z >=  z_critical THEN 'Sticky'
         WHEN z <= -z_critical THEN 'One-off'
         ELSE 'As expected' END                      AS verdict,
    ROUND(avg_orders_next_year, 1)                   AS avg_orders_next_year,
    median_days_to_repeat,
    ROUND(avg_trial_value)                           AS avg_trial_value,
    ROUND(avg_follow_on_value)                       AS avg_follow_on_value_12m,
    ROUND(avg_follow_on_value / avg_trial_value, 2)  AS follow_on_multiple
FROM `sahyadri_b2b.xs_category`
ORDER BY o_e DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · Sensitivity: trials at least 180 days after the first order
-- (guards against "trials" that are really purchases made before 2024)
-- -----------------------------------------------------------------------------
WITH s AS (
    SELECT * FROM `sahyadri_b2b.xs_trials`
    WHERE is_measured AND trial_date >= DATE_ADD(first_order_date, INTERVAL 180 DAY)
),
band_rate AS (
    SELECT frequency_band, AVG(IF(repeated, 1, 0)) AS p FROM s GROUP BY frequency_band
)
SELECT
    s.category,
    COUNT(*)                                                                 AS trials,
    ROUND(COUNTIF(s.repeated) / SUM(b.p), 2)                                 AS o_e,
    ROUND((COUNTIF(s.repeated) - SUM(b.p)) / SQRT(SUM(b.p * (1 - b.p))), 2)  AS z
FROM s
JOIN band_rate AS b ON b.frequency_band = s.frequency_band
GROUP BY s.category
ORDER BY o_e DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Follow-up list: recent trials in sticky categories not yet repeated
-- -----------------------------------------------------------------------------
WITH sticky AS (
    SELECT category, median_days_to_repeat FROM `sahyadri_b2b.xs_category` WHERE z >= z_critical
)
SELECT
    c.customer_name, c.customer_segment, t.category, t.trial_date,
    ROUND(t.trial_value)                                   AS trial_value,
    DATE_DIFF(as_of, t.trial_date, DAY)                    AS days_since_trial,
    s.median_days_to_repeat
FROM `sahyadri_b2b.xs_trials` AS t
JOIN sticky AS s ON s.category = t.category
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = t.customer_id
WHERE t.is_cross_sell
  AND t.trial_date > last_trial
  AND NOT t.repeated
  AND DATE_DIFF(as_of, t.trial_date, DAY) > s.median_days_to_repeat
ORDER BY t.trial_value DESC;
