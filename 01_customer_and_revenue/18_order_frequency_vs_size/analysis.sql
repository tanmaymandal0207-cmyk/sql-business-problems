/* =============================================================================
   Case study · Order frequency vs order size: do customers batch their orders?
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The revenue driver tree showed that orders per customer is the steadiest
   growth driver, and sales wants to push it further with reorder calls and
   reminders. Finance objects: if customers simply split the same need into
   more, smaller orders, frequency rises but revenue does not, and freight
   and handling costs go up. Before funding the programme the commercial
   head asks:
     1. Do customers who order more often place smaller orders?
     2. Within the same customer, is an order placed soon after the last one
        smaller, and one after a long gap bigger?
     3. Is any relation more than chance?
     4. Would more frequent ordering add revenue, or just more orders?

   METHOD
     - Valid orders (not Cancelled or Returned); order value = net line
       value. Customers with 6 or more valid orders.
     - Between customers: ordering rate = orders x 365 / days from first
       order to 30 Sep 2026 (at least 90), against the customer's average
       ln(order value). Correlation and slope, overall and within segment.
     - Within customer: gap before each order (days since the customer's
       previous order) against the order's ln value minus the customer's
       average ln value. Pooled within-customer slope on ln(1 + gap).
     - Permutation test: order values shuffled 500 times among each
       customer's own orders (gaps fixed). p = share of shuffles with a
       slope at least as far from zero as observed.
   ============================================================================= */

DECLARE as_of        DATE  DEFAULT DATE '2026-09-30';
DECLARE min_orders   INT64 DEFAULT 6;
DECLARE min_span     INT64 DEFAULT 90;
DECLARE permutations INT64 DEFAULT 500;
DECLARE prime        INT64 DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Orders of customers with 6+ valid orders, with the gap before each
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.fs_orders` AS
WITH orders AS (
    SELECT o.order_id, o.customer_id, c.customer_segment, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, c.customer_segment, o.order_date
),
eligible AS (
    SELECT customer_id FROM orders GROUP BY customer_id HAVING COUNT(*) >= min_orders
)
SELECT
    o.*,
    ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id)                       AS seq,
    DATE_DIFF(o.order_date, LAG(o.order_date) OVER (PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id), DAY) AS gap_days,
    LN(o.order_value)                                                                                      AS ln_value,
    LN(o.order_value) - AVG(LN(o.order_value)) OVER (PARTITION BY o.customer_id)                           AS ln_value_vs_own_avg
FROM orders AS o
JOIN eligible AS e ON e.customer_id = o.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Between customers: do frequent buyers place smaller orders?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.fs_customers` AS
SELECT
    customer_id, customer_segment,
    COUNT(*)                                                                                   AS orders,
    COUNT(*) * 365 / GREATEST(DATE_DIFF(as_of, MIN(order_date), DAY), min_span)               AS orders_per_year,
    EXP(AVG(ln_value))                                                                         AS typical_order_value,
    SUM(order_value)                                                                           AS revenue
FROM `sahyadri_b2b.fs_orders`
GROUP BY customer_id, customer_segment;

SELECT
    IFNULL(customer_segment, 'All customers')                                                  AS scope,
    COUNT(*)                                                                                   AS customers,
    ROUND(CORR(LN(orders_per_year), LN(typical_order_value)), 3)                               AS correlation,
    ROUND(COVAR_POP(LN(orders_per_year), LN(typical_order_value)) / VAR_POP(LN(orders_per_year)), 3) AS elasticity_of_size_to_frequency,
    ROUND(AVG(orders_per_year), 1)                                                             AS avg_orders_per_year,
    ROUND(EXP(AVG(LN(typical_order_value))) / 1e3, 1)                                          AS typical_order_k
FROM `sahyadri_b2b.fs_customers`
GROUP BY ROLLUP(customer_segment)
ORDER BY customer_segment IS NULL, customer_segment;

-- Frequency bands across all customers
SELECT
    CASE WHEN orders_per_year < 6 THEN '1. Under 6 a year' WHEN orders_per_year < 12 THEN '2. 6-12'
         WHEN orders_per_year < 24 THEN '3. 12-24' WHEN orders_per_year < 52 THEN '4. 24-52' ELSE '5. 52+' END AS frequency_band,
    COUNT(*)                                                                                   AS customers,
    ROUND(100 * AVG(IF(customer_segment = 'Enterprise', 1, 0)), 0)                             AS enterprise_pct,
    ROUND(EXP(AVG(LN(typical_order_value))) / 1e3, 1)                                          AS typical_order_k,
    ROUND(AVG(revenue) / 1e5, 1)                                                               AS avg_revenue_lakh
FROM `sahyadri_b2b.fs_customers`
GROUP BY frequency_band
ORDER BY frequency_band;

-- -----------------------------------------------------------------------------
-- Step 3 · Within customers: is a quick re-order smaller?
-- -----------------------------------------------------------------------------
SELECT
    CASE WHEN gap_days = 0 THEN '1. Same day' WHEN gap_days <= 3 THEN '2. 1-3 days'
         WHEN gap_days <= 7 THEN '3. 4-7 days' WHEN gap_days <= 30 THEN '4. 8-30 days'
         WHEN gap_days <= 90 THEN '5. 31-90 days' ELSE '6. Over 90 days' END                   AS gap_before_order,
    COUNT(*)                                                                                   AS orders,
    ROUND(100 * (EXP(AVG(ln_value_vs_own_avg)) - 1), 1)                                        AS size_vs_customer_typical_pct,
    ROUND(STDDEV_SAMP(ln_value_vs_own_avg) / SQRT(COUNT(*)), 3)                                AS standard_error_ln
FROM `sahyadri_b2b.fs_orders`
WHERE gap_days IS NOT NULL
GROUP BY gap_before_order
ORDER BY gap_before_order;

-- Pooled within-customer slope and its permutation test
CREATE OR REPLACE TABLE `sahyadri_b2b.fs_permutation_slopes` AS
WITH base AS (
    -- orders with a previous order; x and y centred within the customer
    SELECT customer_id,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY seq)                       AS r,
           LN(1 + gap_days) - AVG(LN(1 + gap_days)) OVER (PARTITION BY customer_id)         AS x,
           ln_value - AVG(ln_value) OVER (PARTITION BY customer_id)                         AS y
    FROM `sahyadri_b2b.fs_orders`
    WHERE gap_days IS NOT NULL
),
reps AS (
    SELECT 0 AS b UNION ALL SELECT b FROM UNNEST(GENERATE_ARRAY(1, permutations)) AS b
),
positions AS (
    -- b = 0 keeps each order's own value; otherwise the value of the order at a hashed rank
    SELECT r.b, x.customer_id, x.r, x.x,
           IF(r.b = 0, x.r,
              ROW_NUMBER() OVER (PARTITION BY r.b, x.customer_id
                                 ORDER BY MOD(MOD(r.b * 7919 + x.r * 104729 + x.customer_id * 1299709, prime)
                                            * MOD(r.b * 7919 + x.r * 104729 + x.customer_id * 1299709, prime) + 12345, prime), x.r)) AS take_r
    FROM reps AS r CROSS JOIN base AS x
)
SELECT p.b, SUM(p.x * k.y) / SUM(p.x * p.x) AS slope, COUNT(*) AS orders
FROM positions AS p
JOIN base AS k ON k.customer_id = p.customer_id AND k.r = p.take_r
GROUP BY p.b;

SELECT
    ROUND(MAX(IF(b = 0, slope, NULL)), 4)                                                      AS within_customer_slope,
    ROUND(100 * (EXP(MAX(IF(b = 0, slope, NULL)) * LN(2)) - 1), 2)                             AS size_change_pct_when_gap_doubles,
    ROUND(APPROX_QUANTILES(IF(b > 0, slope, NULL), 1000)[OFFSET(25)], 4)                       AS shuffled_2_5th,
    ROUND(APPROX_QUANTILES(IF(b > 0, slope, NULL), 1000)[OFFSET(975)], 4)                      AS shuffled_97_5th,
    ROUND((1 + COUNTIF(b > 0 AND ABS(slope) >= (SELECT ABS(slope) FROM `sahyadri_b2b.fs_permutation_slopes` WHERE b = 0) - 1e-12))
          / (1 + COUNTIF(b > 0)), 3)                                                           AS p_value
FROM `sahyadri_b2b.fs_permutation_slopes`;

-- -----------------------------------------------------------------------------
-- Step 4 · What extra frequency would be worth: revenue = orders x size
-- -----------------------------------------------------------------------------
WITH by_year AS (
    SELECT customer_id, EXTRACT(YEAR FROM order_date) AS yr, COUNT(*) AS orders, AVG(ln_value) AS ln_size
    FROM `sahyadri_b2b.fs_orders`
    WHERE order_date < DATE '2026-01-01'
    GROUP BY customer_id, yr
),
pairs AS (
    SELECT a.customer_id, LN(b.orders / a.orders) AS d_ln_orders, b.ln_size - a.ln_size AS d_ln_size
    FROM by_year AS a
    JOIN by_year AS b ON b.customer_id = a.customer_id AND b.yr = a.yr + 1
)
SELECT
    COUNT(*)                                                                                   AS customers_2024_2025,
    ROUND(CORR(d_ln_orders, d_ln_size), 3)                                                     AS corr_change_in_orders_vs_size,
    ROUND(COVAR_POP(d_ln_orders, d_ln_size) / VAR_POP(d_ln_orders), 3)                         AS size_response_to_order_change,
    ROUND(CORR(d_ln_orders, d_ln_size) * SQRT((COUNT(*) - 2) / (1 - POW(CORR(d_ln_orders, d_ln_size), 2))), 2) AS t_statistic,
    ROUND(100 * AVG(IF(d_ln_orders > 0, 1, 0)), 1)                                             AS ordered_more_often_pct,
    ROUND(100 * (EXP(AVG(IF(d_ln_orders > 0, d_ln_size, NULL))) - 1), 1)                       AS size_change_if_more_orders_pct,
    ROUND(100 * (EXP(AVG(IF(d_ln_orders < 0, d_ln_size, NULL))) - 1), 1)                       AS size_change_if_fewer_orders_pct
FROM pairs;
