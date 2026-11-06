/* =============================================================================
   Case study · How big can one order get? Extreme value analysis of order
   size for approval limits
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   In March 2026 a single distributor order of Rs 1.19 crore went through
   on the salesperson's approval alone. The CFO wants an approval ladder
   for large orders (credit check, director sign-off, MD sign-off), with
   each step set by how often orders of that size actually occur. A normal
   average-and-spread view of order sizes is useless for this, because a
   handful of orders dominate the tail. She asks:
     1. How heavy is the tail of order sizes?
     2. How often should we expect orders above Rs 10 lakh, 20 lakh,
        50 lakh and 1 crore?
     3. What order size is exceeded about once a month, quarter, year and
        five years?
     4. Would a model fitted on 2024 - 2025 have predicted 2026?

   METHOD (peaks over threshold)
     - Valid orders (not Cancelled or Returned), January 2024 - September
       2026 (2.75 years). Order value after line discounts.
     - Exceedances y = value - u over a threshold u (Rs 5 lakh; Rs 3 and
       8 lakh to check stability). Their distribution is modelled as a
       generalised Pareto (GPD): P(Y > y) = (1 + xi * y / sigma)^(-1/xi).
     - Fit by probability-weighted moments (Hosking and Wallis): with the
       exceedances sorted ascending y(1) .. y(n),
         a0 = mean(y), a1 = (1/n) * SUM((n - i) / (n - 1) * y(i))
         k = a0 / (a0 - 2 a1) - 2,  sigma = 2 a0 a1 / (a0 - 2 a1),  xi = -k
     - Expected orders a year above x = lambda * P(Y > x - u), where
       lambda = exceedances per year.
     - Return level (exceeded once every T years):
         x(T) = u + sigma / xi * ((lambda * T)^xi - 1)
     - Uncertainty: 500 bootstrap resamples of the exceedances (integer
       hash), refitted each time; 5 - 95 % range.
     - Back-test: fit on 2024 - 2025, predict January - September 2026.
   ============================================================================= */

DECLARE first_day  DATE    DEFAULT DATE '2024-01-01';
DECLARE last_day   DATE    DEFAULT DATE '2026-09-30';
DECLARE train_end  DATE    DEFAULT DATE '2025-12-31';
DECLARE u_threshold FLOAT64 DEFAULT 500000;
DECLARE resamples  INT64   DEFAULT 500;

-- -----------------------------------------------------------------------------
-- Step 1 · Orders and the shape of the tail
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ev_orders` AS
SELECT o.order_id, o.customer_id, o.order_date,
       SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))     AS value
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN first_day AND last_day
GROUP BY o.order_id, o.customer_id, o.order_date;

SELECT
    COUNT(*)                                                                          AS orders,
    ROUND(APPROX_QUANTILES(value, 100)[OFFSET(50)] / 1e5, 2)                          AS median_lakh,
    ROUND(APPROX_QUANTILES(value, 100)[OFFSET(90)] / 1e5, 2)                          AS p90_lakh,
    ROUND(APPROX_QUANTILES(value, 100)[OFFSET(99)] / 1e5, 2)                          AS p99_lakh,
    ROUND(MAX(value) / 1e5, 2)                                                        AS largest_lakh,
    ROUND(100 * SUM(IF(value >= u_threshold, value, 0)) / SUM(value), 1)                AS revenue_from_5_lakh_plus_pct,
    -- share of revenue in the ten largest orders
    ROUND(100 * (SELECT SUM(value) FROM (SELECT value FROM `sahyadri_b2b.ev_orders` ORDER BY value DESC LIMIT 10)) / SUM(value), 1) AS revenue_in_top_10_orders_pct
FROM `sahyadri_b2b.ev_orders`;

-- -----------------------------------------------------------------------------
-- Step 2 · Generalised Pareto fits (probability-weighted moments)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ev_fits` AS
WITH fits AS (
    SELECT 'Full period, Rs 3 lakh' AS fit, 300000 AS u, first_day AS d0, last_day AS d1
    UNION ALL SELECT 'Full period, Rs 5 lakh', u_threshold, first_day, last_day
    UNION ALL SELECT 'Full period, Rs 8 lakh', 800000, first_day, last_day
    UNION ALL SELECT 'Train 2024-2025, Rs 5 lakh', u_threshold, first_day, train_end
),
exceedances AS (
    SELECT f.fit, f.u, f.d0, f.d1, o.value - f.u AS y,
           ROW_NUMBER() OVER (PARTITION BY f.fit ORDER BY o.value, o.order_id)         AS i,
           COUNT(*) OVER (PARTITION BY f.fit)                                         AS n
    FROM fits AS f
    JOIN `sahyadri_b2b.ev_orders` AS o ON o.order_date BETWEEN f.d0 AND f.d1 AND o.value > f.u
),
moments AS (
    SELECT fit, ANY_VALUE(u) AS u, ANY_VALUE(n) AS n,
           (DATE_DIFF(ANY_VALUE(d1), ANY_VALUE(d0), DAY) + 1) / 365.25                AS years,
           AVG(y)                                                                     AS a0,
           SUM((n - i) / (n - 1) * y) / ANY_VALUE(n)                                  AS a1,
           MAX(y)                                                                     AS max_y
    FROM exceedances GROUP BY fit
)
SELECT fit, u, n, years, n / years AS per_year, a0, a1, max_y,
       -(a0 / (a0 - 2 * a1) - 2)                                                      AS xi,
       2 * a0 * a1 / (a0 - 2 * a1)                                                    AS sigma
FROM moments;

SELECT fit, ROUND(u / 1e5, 0) AS threshold_lakh, n AS exceedances, ROUND(per_year, 1) AS per_year,
       ROUND(xi, 3) AS shape_xi, ROUND(sigma / 1e5, 2) AS scale_sigma_lakh
FROM `sahyadri_b2b.ev_fits`
ORDER BY fit;

-- Uncertainty: bootstrap of the full-period Rs 5 lakh exceedances, refitted each time
CREATE OR REPLACE TABLE `sahyadri_b2b.ev_bootstrap` AS
WITH base AS (
    SELECT o.value - u_threshold AS y, ROW_NUMBER() OVER (ORDER BY o.value, o.order_id) AS j, COUNT(*) OVER () AS n
    FROM `sahyadri_b2b.ev_orders` AS o WHERE o.value > u_threshold
),
picks AS (
    SELECT b, t,
           1 + MOD(MOD(MOD(b * 104729 + t * 1299709 + 7919, 2147483647) * MOD(b * 104729 + t * 1299709 + 7919, 2147483647) + 12345, 2147483647),
                   (SELECT MAX(n) FROM base))                                         AS j
    FROM UNNEST(GENERATE_ARRAY(1, resamples)) AS b
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, (SELECT MAX(n) FROM base))) AS t
),
resampled AS (
    SELECT p.b, bs.y, ROW_NUMBER() OVER (PARTITION BY p.b ORDER BY bs.y, p.t) AS i, bs.n
    FROM picks AS p JOIN base AS bs USING (j)
),
moments AS (
    SELECT b, AVG(y) AS a0, SUM((n - i) / (n - 1) * y) / ANY_VALUE(n) AS a1
    FROM resampled GROUP BY b
)
SELECT b, -(a0 / (a0 - 2 * a1) - 2) AS xi, 2 * a0 * a1 / (a0 - 2 * a1) AS sigma
FROM moments;

SELECT
    COUNT(*)                                                                          AS bootstrap_fits,
    ROUND(APPROX_QUANTILES(xi, 100)[OFFSET(5)], 3)                                    AS shape_p05,
    ROUND(APPROX_QUANTILES(xi, 100)[OFFSET(50)], 3)                                   AS shape_median,
    ROUND(APPROX_QUANTILES(xi, 100)[OFFSET(95)], 3)                                   AS shape_p95,
    ROUND(100 * COUNTIF(xi > 0.5) / COUNT(*), 1)                                      AS shape_above_half_pct
FROM `sahyadri_b2b.ev_bootstrap`;

-- -----------------------------------------------------------------------------
-- Step 3 · Does the fit match the orders we saw? Expected against actual counts
-- -----------------------------------------------------------------------------
WITH f AS (SELECT * FROM `sahyadri_b2b.ev_fits` WHERE fit = 'Full period, Rs 5 lakh'),
levels AS (
    SELECT x FROM UNNEST([750000, 1000000, 1500000, 2000000, 3000000, 5000000, 10000000]) AS x
)
SELECT
    ROUND(lv.x / 1e5, 1)                                                              AS order_size_lakh,
    COUNTIF(o.value > lv.x)                                                           AS actual_orders,
    ROUND(ANY_VALUE(f.n) * POW(1 + ANY_VALUE(f.xi) * (lv.x - ANY_VALUE(f.u)) / ANY_VALUE(f.sigma), -1 / ANY_VALUE(f.xi)), 1) AS fitted_orders
FROM levels AS lv CROSS JOIN f CROSS JOIN `sahyadri_b2b.ev_orders` AS o
GROUP BY lv.x
ORDER BY lv.x;

-- -----------------------------------------------------------------------------
-- Step 4 · How often, and how big: rates and return levels
-- -----------------------------------------------------------------------------
-- Expected orders a year above each size, with the bootstrap range
WITH f AS (SELECT * FROM `sahyadri_b2b.ev_fits` WHERE fit = 'Full period, Rs 5 lakh'),
levels AS (
    SELECT x FROM UNNEST([1000000, 2000000, 5000000, 10000000, 20000000]) AS x
),
boot AS (
    SELECT lv.x, bt.b, f.per_year * POW(1 + bt.xi * (lv.x - f.u) / bt.sigma, -1 / bt.xi) AS rate
    FROM levels AS lv CROSS JOIN `sahyadri_b2b.ev_bootstrap` AS bt CROSS JOIN f
)
SELECT
    ROUND(lv.x / 1e5, 0)                                                              AS order_size_lakh,
    ROUND(f.per_year * POW(1 + f.xi * (lv.x - f.u) / f.sigma, -1 / f.xi), 2)          AS expected_per_year,
    ROUND(APPROX_QUANTILES(bo.rate, 100)[OFFSET(5)], 2)                               AS per_year_p05,
    ROUND(APPROX_QUANTILES(bo.rate, 100)[OFFSET(95)], 2)                              AS per_year_p95,
    ROUND(12 / (f.per_year * POW(1 + f.xi * (lv.x - f.u) / f.sigma, -1 / f.xi)), 1)   AS one_every_months
FROM levels AS lv CROSS JOIN f JOIN boot AS bo ON bo.x = lv.x
GROUP BY lv.x, f.per_year, f.xi, f.u, f.sigma
ORDER BY lv.x;

-- Return levels: the order size exceeded about once every T years
WITH f AS (SELECT * FROM `sahyadri_b2b.ev_fits` WHERE fit = 'Full period, Rs 5 lakh'),
periods AS (
    SELECT 'Once a month' AS period, 1 / 12 AS t UNION ALL
    SELECT 'Once a quarter', 0.25 UNION ALL
    SELECT 'Once a year', 1.0 UNION ALL
    SELECT 'Once in 5 years', 5.0 UNION ALL
    SELECT 'Once in 10 years', 10.0
),
boot AS (
    SELECT pr.period, f.u + bt.sigma / bt.xi * (POW(f.per_year * pr.t, bt.xi) - 1) AS level
    FROM periods AS pr CROSS JOIN `sahyadri_b2b.ev_bootstrap` AS bt CROSS JOIN f
)
SELECT
    pr.period,
    ROUND((f.u + f.sigma / f.xi * (POW(f.per_year * pr.t, f.xi) - 1)) / 1e5, 1)       AS order_size_lakh,
    ROUND(APPROX_QUANTILES(bo.level, 100)[OFFSET(5)] / 1e5, 1)                        AS p05_lakh,
    ROUND(APPROX_QUANTILES(bo.level, 100)[OFFSET(95)] / 1e5, 1)                       AS p95_lakh
FROM periods AS pr CROSS JOIN f JOIN boot AS bo ON bo.period = pr.period
GROUP BY pr.period, pr.t, f.u, f.sigma, f.xi, f.per_year
ORDER BY pr.t;

-- -----------------------------------------------------------------------------
-- Step 5 · Back-test: fit on 2024 - 2025, predict January - September 2026
-- -----------------------------------------------------------------------------
WITH f AS (SELECT * FROM `sahyadri_b2b.ev_fits` WHERE fit = 'Train 2024-2025, Rs 5 lakh'),
levels AS (
    SELECT x FROM UNNEST([500000, 1000000, 2000000, 5000000, 10000000]) AS x
),
test_years AS (
    SELECT (DATE_DIFF(last_day, train_end, DAY)) / 365.25 AS years
),
c26 AS (
    -- Rs 5 lakh+ orders that January - September 2026 actually had
    SELECT COUNT(*) AS n FROM `sahyadri_b2b.ev_orders` WHERE order_date > train_end AND value > u_threshold
)
SELECT
    ROUND(lv.x / 1e5, 0)                                                              AS order_size_lakh,
    ROUND(ANY_VALUE(f.per_year) * ANY_VALUE(ty.years)
          * POW(1 + ANY_VALUE(f.xi) * (lv.x - ANY_VALUE(f.u)) / ANY_VALUE(f.sigma), -1 / ANY_VALUE(f.xi)), 1) AS gpd_expected_2026,
    ROUND(ANY_VALUE(c26.n) * POW(1 + ANY_VALUE(f.xi) * (lv.x - ANY_VALUE(f.u)) / ANY_VALUE(f.sigma), -1 / ANY_VALUE(f.xi)), 1) AS gpd_given_2026_count,
    ROUND(COUNTIF(o.value > lv.x AND o.order_date <= train_end) / ANY_VALUE(f.years) * ANY_VALUE(ty.years), 1) AS naive_expected_2026,
    COUNTIF(o.value > lv.x AND o.order_date > train_end)                              AS actual_2026
FROM levels AS lv CROSS JOIN f CROSS JOIN test_years AS ty CROSS JOIN c26 CROSS JOIN `sahyadri_b2b.ev_orders` AS o
GROUP BY lv.x
ORDER BY lv.x;

-- -----------------------------------------------------------------------------
-- Step 6 · Approval ladder from the return levels, and who would have hit it
-- -----------------------------------------------------------------------------
WITH f AS (SELECT * FROM `sahyadri_b2b.ev_fits` WHERE fit = 'Full period, Rs 5 lakh'),
ladder AS (
    SELECT '1. Credit check (about once a month)' AS step, 1 / 12 AS t UNION ALL
    SELECT '2. Director sign-off (about once a quarter)', 0.25 UNION ALL
    SELECT '3. MD sign-off (about once a year)', 1.0
),
levels AS (
    SELECT l.step, l.t, f.u + f.sigma / f.xi * (POW(f.per_year * l.t, f.xi) - 1) AS level
    FROM ladder AS l CROSS JOIN f
)
SELECT
    lv.step,
    ROUND(lv.level / 1e5, 1)                                                          AS from_lakh,
    COUNTIF(o.value > lv.level)                                                       AS orders_since_jan_2024,
    COUNT(DISTINCT IF(o.value > lv.level, o.customer_id, NULL))                       AS customers,
    ROUND(SUM(IF(o.value > lv.level, o.value, 0)) / 1e7, 2)                           AS value_crore
FROM levels AS lv CROSS JOIN `sahyadri_b2b.ev_orders` AS o
GROUP BY lv.step, lv.level
ORDER BY lv.step;
