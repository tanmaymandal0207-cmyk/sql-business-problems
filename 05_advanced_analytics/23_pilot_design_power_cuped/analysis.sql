/* =============================================================================
   Case study · Designing a sales pilot: how many customers, how long, which metric?
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Sales wants to test a reorder-call programme before rolling it out:
   half of the active customers get a monthly call, the other half do not,
   and revenue is compared at the end. The commercial head expects about a
   10 % uplift. Before the pilot starts, the analytics lead must say whether
   a pilot of this size can detect that at all:
     1. With the customers available, what is the smallest uplift a
        3-month or 6-month pilot could detect?
     2. How much does adjusting for each customer's past revenue (CUPED)
        or capping extreme customers sharpen the test?
     3. How many customers would be needed to detect 10 %?
     4. Does the test give false alarms at the stated 5 % when nothing is
        done (an A/A test on history)?

   METHOD
     - Customers: those with a valid order (not Cancelled or Returned) in
       the 12 months before the pilot window.
     - Pilot windows on history: 3 months (Jul - Sep 2026, pre-period
       Jul 2025 - Jun 2026) and 6 months (Apr - Sep 2026, pre-period
       Apr 2025 - Mar 2026).
     - Outcome Y: revenue in the window (0 if no order). Covariate X:
       revenue in the pre-period. Capped version: Y and X capped at their
       99th percentile.
     - CUPED: Y - theta (X - mean X), theta = cov(X, Y) / var(X); variance
       falls by the factor (1 - corr(X, Y)^2).
     - Two equal arms of n customers each; 5 % two-sided test, 80 % power:
       minimum detectable effect (MDE) = (1.96 + 0.8416) x SD x SQRT(2 / n),
       shown as a % of mean revenue. Customers needed per arm for a 10 %
       uplift = 2 x (2.8016 x SD / (0.10 x mean))^2.
     - A/A test: 500 random 50/50 splits of the real customers on the
       historical window (no treatment), each tested with a two-sample z
       test; the share with |z| > 1.96 should be about 5 %.
   ============================================================================= */

DECLARE z_alpha  FLOAT64 DEFAULT 1.96;
DECLARE z_power  FLOAT64 DEFAULT 0.8416;
DECLARE uplift   FLOAT64 DEFAULT 0.10;
DECLARE splits   INT64   DEFAULT 500;
DECLARE prime    INT64   DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Customer outcome and pre-period revenue for each pilot window
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pd_customers` AS
WITH windows AS (
    SELECT '3 months' AS pilot, DATE '2026-07-01' AS w_start, DATE '2026-09-30' AS w_end,
           DATE '2025-07-01' AS pre_start, DATE '2026-06-30' AS pre_end
    UNION ALL
    SELECT '6 months', DATE '2026-04-01', DATE '2026-09-30', DATE '2025-04-01', DATE '2026-03-31'
),
orders AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, o.order_date
),
per_customer AS (
    SELECT w.pilot, o.customer_id,
           SUM(IF(o.order_date BETWEEN w.w_start AND w.w_end, o.order_value, 0))     AS y_revenue,
           COUNTIF(o.order_date BETWEEN w.w_start AND w.w_end)                        AS y_orders,
           SUM(IF(o.order_date BETWEEN w.pre_start AND w.pre_end, o.order_value, 0)) AS x_revenue,
           COUNTIF(o.order_date BETWEEN w.pre_start AND w.pre_end)                    AS x_orders
    FROM windows AS w
    JOIN orders AS o ON o.order_date BETWEEN w.pre_start AND w.w_end
    GROUP BY w.pilot, o.customer_id
),
active AS (
    SELECT * FROM per_customer WHERE x_orders > 0
),
caps AS (
    SELECT DISTINCT pilot,
           PERCENTILE_CONT(y_revenue, 0.99) OVER (PARTITION BY pilot) AS y_cap,
           PERCENTILE_CONT(x_revenue, 0.99) OVER (PARTITION BY pilot) AS x_cap
    FROM active
)
SELECT a.*,
       LEAST(a.y_revenue, c.y_cap) AS y_capped,
       LEAST(a.x_revenue, c.x_cap) AS x_capped
FROM active AS a
JOIN caps AS c ON c.pilot = a.pilot;

-- -----------------------------------------------------------------------------
-- Step 2 · Variance, CUPED and the minimum detectable effect for each design
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pd_designs` AS
WITH long AS (
    SELECT pilot, customer_id, 'Revenue' AS metric, y_revenue AS y, x_revenue AS x FROM `sahyadri_b2b.pd_customers`
    UNION ALL
    SELECT pilot, customer_id, 'Revenue, capped at 99th percentile', y_capped, x_capped FROM `sahyadri_b2b.pd_customers`
    UNION ALL
    SELECT pilot, customer_id, 'Orders', y_orders, x_orders FROM `sahyadri_b2b.pd_customers`
),
moments AS (
    SELECT pilot, metric, COUNT(*) AS customers, AVG(y) AS mean_y, STDDEV_POP(y) AS sd_y,
           CORR(x, y) AS rho, COVAR_POP(x, y) / VAR_POP(x) AS theta
    FROM long
    GROUP BY pilot, metric
),
designs AS (
    SELECT pilot, metric, 'Plain' AS adjustment, customers, mean_y, sd_y, rho, theta, sd_y AS sd_used FROM moments
    UNION ALL
    SELECT pilot, metric, 'CUPED', customers, mean_y, sd_y, rho, theta, sd_y * SQRT(1 - POW(rho, 2)) FROM moments
)
SELECT
    *,
    FLOOR(customers / 2)                                                                 AS per_arm,
    (z_alpha + z_power) * sd_used * SQRT(2 / FLOOR(customers / 2)) / mean_y              AS mde_relative,
    CEIL(2 * POW((z_alpha + z_power) * sd_used / (uplift * mean_y), 2))                 AS per_arm_needed_for_uplift
FROM designs;

SELECT
    pilot, metric, adjustment, customers,
    ROUND(mean_y, 1)                                       AS mean_per_customer,
    ROUND(sd_used / mean_y, 2)                             AS cv,
    ROUND(rho, 3)                                          AS corr_with_pre_period,
    ROUND(100 * mde_relative, 1)                           AS mde_pct,
    CAST(per_arm_needed_for_uplift AS INT64)               AS per_arm_needed_for_10pct,
    ROUND(per_arm_needed_for_uplift / per_arm, 1)          AS times_available_customers
FROM `sahyadri_b2b.pd_designs`
ORDER BY pilot, metric DESC, adjustment DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · A/A test: random splits of real customers with no treatment
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pd_aa_tests` AS
WITH base AS (
    SELECT c.*,
           y_revenue - d1.theta * (x_revenue - AVG(x_revenue) OVER (PARTITION BY c.pilot)) AS y_revenue_cuped,
           y_capped  - d2.theta * (x_capped  - AVG(x_capped)  OVER (PARTITION BY c.pilot)) AS y_capped_cuped,
           y_orders  - d3.theta * (x_orders  - AVG(x_orders)  OVER (PARTITION BY c.pilot)) AS y_orders_cuped
    FROM `sahyadri_b2b.pd_customers` AS c
    JOIN `sahyadri_b2b.pd_designs` AS d1 ON d1.pilot = c.pilot AND d1.metric = 'Revenue' AND d1.adjustment = 'Plain'
    JOIN `sahyadri_b2b.pd_designs` AS d2 ON d2.pilot = c.pilot AND d2.metric LIKE 'Revenue, capped%' AND d2.adjustment = 'Plain'
    JOIN `sahyadri_b2b.pd_designs` AS d3 ON d3.pilot = c.pilot AND d3.metric = 'Orders' AND d3.adjustment = 'Plain'
),
assigned AS (
    SELECT b.b, x.*,
           ROW_NUMBER() OVER (PARTITION BY b.b, x.pilot
                              ORDER BY MOD(MOD(b.b * 7919 + x.customer_id * 104729, prime) * MOD(b.b * 7919 + x.customer_id * 104729, prime) + 12345, prime), x.customer_id)
             <= FLOOR(COUNT(*) OVER (PARTITION BY b.b, x.pilot) / 2) AS treated
    FROM base AS x
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, splits)) AS b
),
long AS (
    SELECT b, pilot, treated, 'Revenue' AS metric, 'Plain' AS adjustment, y_revenue AS y FROM assigned
    UNION ALL SELECT b, pilot, treated, 'Revenue', 'CUPED', y_revenue_cuped FROM assigned
    UNION ALL SELECT b, pilot, treated, 'Revenue, capped at 99th percentile', 'Plain', y_capped FROM assigned
    UNION ALL SELECT b, pilot, treated, 'Revenue, capped at 99th percentile', 'CUPED', y_capped_cuped FROM assigned
    UNION ALL SELECT b, pilot, treated, 'Orders', 'Plain', y_orders FROM assigned
    UNION ALL SELECT b, pilot, treated, 'Orders', 'CUPED', y_orders_cuped FROM assigned
)
SELECT
    b, pilot, metric, adjustment,
    AVG(IF(treated, y, NULL)) - AVG(IF(NOT treated, y, NULL))                                    AS diff,
    (AVG(IF(treated, y, NULL)) - AVG(IF(NOT treated, y, NULL)))
      / SQRT(VAR_SAMP(IF(treated, y, NULL)) / COUNTIF(treated) + VAR_SAMP(IF(NOT treated, y, NULL)) / COUNTIF(NOT treated)) AS z
FROM long
GROUP BY b, pilot, metric, adjustment;

SELECT
    a.pilot, a.metric, a.adjustment,
    COUNT(*)                                                                         AS split_count,
    ROUND(100 * AVG(IF(ABS(a.z) > z_alpha, 1, 0)), 1)                                AS false_alarm_pct,
    ROUND(STDDEV_POP(a.diff), 3)                                                     AS sd_of_difference,
    ROUND(ANY_VALUE(d.sd_used) * SQRT(2 / ANY_VALUE(d.per_arm)), 3)                  AS sd_predicted,
    ROUND(100 * MAX(ABS(a.diff)) / ANY_VALUE(d.mean_y), 1)                           AS largest_chance_gap_pct_of_mean
FROM `sahyadri_b2b.pd_aa_tests` AS a
JOIN `sahyadri_b2b.pd_designs` AS d ON d.pilot = a.pilot AND d.metric = a.metric AND d.adjustment = a.adjustment
GROUP BY a.pilot, a.metric, a.adjustment
ORDER BY a.pilot, a.metric DESC, a.adjustment DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · What drives the noise: the share of variance from the largest customers
-- -----------------------------------------------------------------------------
WITH ranked AS (
    SELECT pilot, y_revenue,
           ROW_NUMBER() OVER (PARTITION BY pilot ORDER BY y_revenue DESC) AS rk,
           COUNT(*) OVER (PARTITION BY pilot) AS n,
           AVG(y_revenue) OVER (PARTITION BY pilot) AS m
    FROM `sahyadri_b2b.pd_customers`
)
SELECT
    pilot,
    ANY_VALUE(n)                                                                      AS customers,
    ROUND(100 * SUM(IF(rk <= 10, y_revenue, 0)) / SUM(y_revenue), 1)                  AS top_10_revenue_share_pct,
    ROUND(100 * SUM(IF(rk <= 10, POW(y_revenue - m, 2), 0)) / SUM(POW(y_revenue - m, 2)), 1) AS top_10_variance_share_pct,
    ROUND(100 * AVG(IF(y_revenue = 0, 1, 0)), 1)                                      AS no_order_in_window_pct
FROM ranked
GROUP BY pilot
ORDER BY pilot;
