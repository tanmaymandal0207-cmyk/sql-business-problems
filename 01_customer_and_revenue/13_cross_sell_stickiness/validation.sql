/* =============================================================================
   Case study · Cross-sell stickiness — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE onboarding_days INT64 DEFAULT 90;
DECLARE follow_days     INT64 DEFAULT 365;
DECLARE last_trial      DATE  DEFAULT DATE '2025-09-30';
DECLARE z_critical      FLOAT64 DEFAULT 2.81;

WITH t AS (SELECT * FROM `sahyadri_b2b.xs_trials`),
     k AS (SELECT * FROM `sahyadri_b2b.xs_category`),

src AS (
    SELECT o.order_id, o.customer_id, o.order_date, c.category_name AS category,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS line_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    JOIN `sahyadri_b2b.product_categories` AS c ON c.category_id = p.category_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
src_first AS (
    SELECT customer_id, category, MIN(order_date) AS d FROM src GROUP BY customer_id, category
),
src_trial_value AS (
    SELECT s.customer_id, s.category, SUM(s.line_value) AS v
    FROM src AS s JOIN src_first AS f
      ON f.customer_id = s.customer_id AND f.category = s.category AND f.d = s.order_date
    GROUP BY s.customer_id, s.category
),
-- repeat recount: distinct later order dates of the category inside the window
recount AS (
    SELECT t.customer_id, t.category,
           COUNT(DISTINCT IF(s.order_date > t.trial_date
                             AND s.order_date <= DATE_ADD(t.trial_date, INTERVAL follow_days DAY), s.order_id, NULL)) AS n
    FROM t LEFT JOIN src AS s ON s.customer_id = t.customer_id AND s.category = t.category
    GROUP BY t.customer_id, t.category
),
measured AS (SELECT * FROM t WHERE is_measured),

checks AS (
    SELECT '01. One row per source customer x category' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM t) - (SELECT COUNT(*) FROM src_first)
         + (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), category)) FROM t) AS actual
    UNION ALL
    SELECT '02. Trial date = first source purchase date', 0,
           (SELECT COUNT(*) FROM t JOIN src_first AS f USING (customer_id, category) WHERE t.trial_date != f.d)
    UNION ALL
    SELECT '03. Trial value = source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(trial_value) FROM t) - (SELECT SUM(v) FROM src_trial_value), 0) AS INT64)
    UNION ALL
    SELECT '04. Cross-sell and measured flags follow the rules', 0,
           (SELECT COUNTIF(is_cross_sell != (trial_date >= DATE_ADD(first_order_date, INTERVAL onboarding_days DAY))
                        OR is_measured != (is_cross_sell AND trial_date <= last_trial)) FROM t)
    UNION ALL
    SELECT '05. Repeat orders = independent recount', 0,
           (SELECT COUNT(*) FROM t JOIN recount AS r USING (customer_id, category) WHERE t.repeat_orders != r.n)
    UNION ALL
    SELECT '06. Repeat orders never exceed all orders next year', 0,
           (SELECT COUNTIF(repeat_orders > orders_next_year) FROM t)
    UNION ALL
    SELECT '07. Frequency band agrees with orders next year', 0,
           (SELECT COUNTIF(frequency_band != CASE WHEN orders_next_year <= 3 THEN '1. 0-3 orders'
                                                  WHEN orders_next_year <= 8 THEN '2. 4-8 orders'
                                                  WHEN orders_next_year <= 15 THEN '3. 9-15 orders'
                                                  ELSE '4. 16+ orders' END) FROM t)
    UNION ALL
    SELECT '08. Category trials add up to measured trials', 0,
           (SELECT SUM(trials) FROM k) - (SELECT COUNT(*) FROM measured)
    UNION ALL
    SELECT '09. Total expected = total observed (x1000, rounded)', 0,
           CAST(ROUND(1000 * ((SELECT SUM(expected) FROM k) - (SELECT SUM(observed) FROM k)), 0) AS INT64)
    UNION ALL
    SELECT '10. z recomputed from observed, expected and variance', 0,
           (SELECT COUNTIF(ABS(z - (observed - expected) / SQRT(variance)) > 1e-9) FROM k)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
