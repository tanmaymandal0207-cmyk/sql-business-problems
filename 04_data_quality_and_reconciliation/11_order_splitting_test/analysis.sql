/* =============================================================================
   Case study · Order splitting test
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The company is introducing a delegation-of-authority policy: sales
   orders above set values (for example Rs 50,000, Rs 1 lakh, Rs 2 lakh)
   will need a manager's approval, mainly to control discounts and credit.
   Internal audit knows the classic way around such limits: split one
   large order into several smaller ones placed the same day. Before the
   limits go live, audit wants a baseline: is there already any sign of
   order splitting or of values being kept just under round amounts?
     1. Do order values bunch just below round thresholds?
     2. Do customers place more same-day orders than chance would produce?
     3. Are same-day orders more often just below a threshold than other
        orders?
     4. Is the same product ordered twice on the same day more often than
        chance?

   METHOD
     - All orders (any status), order value = quantity x price x (1 - discount).
     - Bunching: for a point t, ratio = orders in [0.95t, t) / orders in
       [t, 1.05t). Thresholds: Rs 25k, 50k, 1 lakh, 2 lakh, 5 lakh. Control
       points: a log-spaced grid from Rs 20,000 to Rs 6 lakh, excluding
       points within 10 % of a threshold. z = (log ratio at threshold - mean
       log ratio of controls) / s.d. of controls.
     - Same-day coincidence: if each customer's orders fell on days in
       proportion to the company's daily order volume, the chance that two
       given orders share a day is q = SUM(share of orders on day d)^2.
       Expected same-day pairs = SUM over customers C(n, 2) x q.
     - Same-day vs other orders at each threshold: odds ratio of
       (below / above) with z = ln(OR) / SQRT(1/a + 1/b + 1/c + 1/d);
       Bonferroni for 5 thresholds (|z| >= 2.58 for 5 % overall).
   ============================================================================= */

DECLARE band   FLOAT64 DEFAULT 0.05;
DECLARE wide   FLOAT64 DEFAULT 0.20;

-- -----------------------------------------------------------------------------
-- Step 1 · Order table with same-day flags
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.split_test_orders` AS
WITH orders AS (
    SELECT
        o.order_id, o.customer_id, o.employee_id, o.order_date, o.order_status,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    GROUP BY o.order_id, o.customer_id, o.employee_id, o.order_date, o.order_status
)
SELECT
    *,
    COUNT(*)         OVER (PARTITION BY customer_id, order_date)                     AS orders_same_day,
    SUM(order_value) OVER (PARTITION BY customer_id, order_date)                     AS value_same_day
FROM orders;

-- -----------------------------------------------------------------------------
-- Step 2 · Bunching below round thresholds, against control points
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.split_test_bunching` AS
WITH thresholds AS (
    SELECT t FROM UNNEST([25000.0, 50000.0, 100000.0, 200000.0, 500000.0]) AS t
),
grid AS (
    SELECT 20000 * POW(1.05, k) AS t FROM UNNEST(GENERATE_ARRAY(0, 70)) AS k
),
points AS (
    SELECT t, 'Threshold' AS point_type FROM thresholds
    UNION ALL
    SELECT g.t, 'Control' FROM grid AS g
    WHERE NOT EXISTS (SELECT 1 FROM thresholds AS h WHERE ABS(g.t / h.t - 1) < 0.10)
),
counts AS (
    SELECT
        p.t,
        p.point_type,
        COUNTIF(o.order_value >= p.t * (1 - band) AND o.order_value < p.t)           AS just_below,
        COUNTIF(o.order_value >= p.t AND o.order_value < p.t * (1 + band))           AS just_above
    FROM points AS p
    CROSS JOIN `sahyadri_b2b.split_test_orders` AS o
    GROUP BY p.t, p.point_type
)
SELECT *, LN(just_below / just_above) AS log_ratio
FROM counts
WHERE just_below > 0 AND just_above > 0;

WITH controls AS (
    SELECT AVG(log_ratio) AS mean_lr, STDDEV_SAMP(log_ratio) AS sd_lr, COUNT(*) AS n
    FROM `sahyadri_b2b.split_test_bunching` WHERE point_type = 'Control'
)
SELECT
    b.t                                                                              AS threshold,
    b.just_below,
    b.just_above,
    ROUND(b.just_below / b.just_above, 2)                                            AS ratio,
    ROUND(EXP(c.mean_lr), 2)                                                         AS typical_ratio_at_controls,
    ROUND((b.log_ratio - c.mean_lr) / c.sd_lr, 2)                                    AS z_vs_controls,
    c.n                                                                              AS control_points
FROM `sahyadri_b2b.split_test_bunching` AS b
CROSS JOIN controls AS c
WHERE b.point_type = 'Threshold'
ORDER BY b.t;

-- -----------------------------------------------------------------------------
-- Step 3 · Same-day orders: observed against what chance produces
-- -----------------------------------------------------------------------------
WITH day_share AS (
    SELECT SUM(POW(n / total, 2)) AS q
    FROM (SELECT order_date, COUNT(*) AS n, SUM(COUNT(*)) OVER () AS total
          FROM `sahyadri_b2b.split_test_orders` GROUP BY order_date)
),
customer_pairs AS (
    SELECT SUM(n * (n - 1) / 2) AS possible_pairs
    FROM (SELECT customer_id, COUNT(*) AS n FROM `sahyadri_b2b.split_test_orders` GROUP BY customer_id)
),
observed AS (
    SELECT
        COUNT(*)                                                                     AS same_day_groups,
        SUM(orders_same_day)                                                         AS orders_in_groups,
        SUM(orders_same_day * (orders_same_day - 1) / 2)                             AS same_day_pairs
    FROM (SELECT DISTINCT customer_id, order_date, orders_same_day
          FROM `sahyadri_b2b.split_test_orders` WHERE orders_same_day > 1)
)
SELECT
    o.same_day_groups,
    o.orders_in_groups,
    o.same_day_pairs                                                                 AS observed_pairs,
    ROUND(p.possible_pairs * d.q, 0)                                                 AS expected_pairs,
    ROUND(o.same_day_pairs / (p.possible_pairs * d.q), 2)                            AS observed_to_expected,
    ROUND((o.same_day_pairs - p.possible_pairs * d.q) / SQRT(p.possible_pairs * d.q), 2) AS poisson_z
FROM observed AS o CROSS JOIN customer_pairs AS p CROSS JOIN day_share AS d;

-- Same product on two orders of the same customer on the same day
WITH day_share AS (
    SELECT SUM(POW(n / total, 2)) AS q
    FROM (SELECT order_date, COUNT(*) AS n, SUM(COUNT(*)) OVER () AS total
          FROM `sahyadri_b2b.split_test_orders` GROUP BY order_date)
),
customer_product AS (
    SELECT o.customer_id, i.product_id, o.order_date, COUNT(DISTINCT o.order_id) AS orders
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    GROUP BY o.customer_id, i.product_id, o.order_date
),
by_pair AS (
    SELECT customer_id, product_id, SUM(orders) AS n,
           SUM(orders * (orders - 1) / 2) AS same_day_pairs
    FROM customer_product
    GROUP BY customer_id, product_id
)
SELECT
    SUM(same_day_pairs)                                                              AS observed_same_product_pairs,
    ROUND(SUM(n * (n - 1) / 2) * ANY_VALUE(d.q), 0)                                  AS expected_pairs,
    ROUND(SUM(same_day_pairs) / (SUM(n * (n - 1) / 2) * ANY_VALUE(d.q)), 2)          AS observed_to_expected,
    ROUND((SUM(same_day_pairs) - SUM(n * (n - 1) / 2) * ANY_VALUE(d.q))
          / SQRT(SUM(n * (n - 1) / 2) * ANY_VALUE(d.q)), 2)                          AS poisson_z
FROM by_pair CROSS JOIN day_share AS d;

-- -----------------------------------------------------------------------------
-- Step 4 · Are same-day orders more often just below a threshold?
-- -----------------------------------------------------------------------------
WITH thresholds AS (
    SELECT t FROM UNNEST([25000.0, 50000.0, 100000.0, 200000.0, 500000.0]) AS t
),
cells AS (
    SELECT
        h.t,
        COUNTIF(o.orders_same_day > 1  AND o.order_value >= h.t * (1 - wide) AND o.order_value < h.t) AS sd_below,
        COUNTIF(o.orders_same_day > 1  AND o.order_value >= h.t AND o.order_value < h.t * (1 + wide)) AS sd_above,
        COUNTIF(o.orders_same_day = 1  AND o.order_value >= h.t * (1 - wide) AND o.order_value < h.t) AS other_below,
        COUNTIF(o.orders_same_day = 1  AND o.order_value >= h.t AND o.order_value < h.t * (1 + wide)) AS other_above
    FROM thresholds AS h
    CROSS JOIN `sahyadri_b2b.split_test_orders` AS o
    GROUP BY h.t
)
SELECT
    t                                                                                AS threshold,
    sd_below, sd_above, other_below, other_above,
    ROUND((sd_below / sd_above) / (other_below / other_above), 2)                    AS odds_ratio,
    ROUND(LN((sd_below / sd_above) / (other_below / other_above))
          / SQRT(1 / sd_below + 1 / sd_above + 1 / other_below + 1 / other_above), 2) AS z
FROM cells
ORDER BY t;

-- Same-day groups that cross Rs 1 lakh only when added together
SELECT
    COUNT(*)                                                                         AS groups_all_under_1_lakh_total_over,
    COUNT(DISTINCT customer_id)                                                      AS customers,
    ROUND(AVG(value_same_day), 0)                                                    AS avg_day_total
FROM (
    SELECT customer_id, order_date, ANY_VALUE(value_same_day) AS value_same_day
    FROM `sahyadri_b2b.split_test_orders`
    WHERE orders_same_day > 1
    GROUP BY customer_id, order_date
    HAVING MAX(order_value) < 100000 AND ANY_VALUE(value_same_day) >= 100000
);

-- Review list: the same product on two or more orders of one customer on one day
SELECT
    o.customer_id,
    c.customer_name,
    o.order_date,
    i.product_id,
    COUNT(DISTINCT o.order_id)                                                       AS orders,
    STRING_AGG(CAST(o.order_id AS STRING), ', ' ORDER BY o.order_id)                 AS order_ids,
    SUM(i.quantity)                                                                  AS units,
    ROUND(SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)), 0) AS line_value
FROM `sahyadri_b2b.sales_orders`      AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
JOIN `sahyadri_b2b.customers`         AS c ON c.customer_id = o.customer_id
GROUP BY o.customer_id, c.customer_name, o.order_date, i.product_id
HAVING COUNT(DISTINCT o.order_id) > 1
ORDER BY line_value DESC
LIMIT 10;
