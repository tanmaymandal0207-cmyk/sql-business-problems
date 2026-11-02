/* =============================================================================
   Case study · Honest forecast ranges: conformal intervals for product demand
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The planning team forecasts each product's monthly units and sets stock
   to cover "the forecast plus a normal safety margin" - an 80 % range
   built as forecast +/- 1.28 standard deviations. Stock-outs and excess
   stock both keep happening. The supply chain head asks:
     1. Do the 80 % ranges actually contain next month's demand 80 % of
        the time?
     2. Would a distribution-free (conformal) range, built from each
        product's own recent forecast errors, be more honest?
     3. Does pooling errors across products help the many slow movers?
     4. What does each method cost in stock held above the forecast?

   METHOD
     - Units sold per product per month on valid orders, January 2024 -
       September 2026; every product-month, zeros included.
     - Forecast: the average of the previous 6 months (MA6).
     - Back-test months July 2025 - September 2026 (15), for products with
       any demand in the previous 12 months. Each range uses only the 12
       forecast errors (actual - MA6) of the previous 12 months:
         Normal       MA6 +/- 1.2816 x SD of those errors (floored at 0)
         Conformal    MA6 + [smallest, largest] of those errors (split
                      conformal for 80 % with 12 calibration errors:
                      expected coverage at least 11/13 = 84.6 %)
         Pooled       MA6 + (MA6 + 1) x [10th, 90th percentile] of the
                      scaled errors error / (MA6 + 1) of all products in
                      the same 12 months
     - Coverage = share of product-months whose actual units fall inside.
       Stock above forecast = (upper bound - MA6) x unit cost.
   ============================================================================= */

DECLARE first_test DATE    DEFAULT DATE '2025-07-01';
DECLARE last_test  DATE    DEFAULT DATE '2026-09-01';
DECLARE z80        FLOAT64 DEFAULT 1.2816;

-- -----------------------------------------------------------------------------
-- Step 1 · Product-month demand and the MA6 forecast with its errors
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cf_demand` AS
WITH months AS (
    SELECT m FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2024-01-01', DATE '2026-09-01', INTERVAL 1 MONTH)) AS m
),
sold AS (
    SELECT i.product_id, DATE_TRUNC(o.order_date, MONTH) AS m, SUM(i.quantity) AS units
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY i.product_id, m
),
grid AS (
    SELECT p.product_id, p.unit_cost, mo.m, IFNULL(s.units, 0) AS units
    FROM `sahyadri_b2b.products` AS p
    CROSS JOIN months AS mo
    LEFT JOIN sold AS s ON s.product_id = p.product_id AND s.m = mo.m
),
forecast AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY m)                     AS month_no,
           AVG(units) OVER (PARTITION BY product_id ORDER BY m ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING) AS ma6
    FROM grid
)
SELECT *,
       IF(month_no > 6, units - ma6, NULL)                                            AS error,
       IF(month_no > 6, (units - ma6) / (ma6 + 1), NULL)                              AS scaled_error
FROM forecast;

-- -----------------------------------------------------------------------------
-- Step 2 · Three 80 % ranges for every product-month of the back-test
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cf_intervals` AS
WITH calibration AS (
    -- each product's errors in the 12 months before the forecast month
    SELECT *,
           STDDEV_SAMP(error) OVER w                                                   AS sd_error,
           MIN(error) OVER w                                                           AS min_error,
           MAX(error) OVER w                                                           AS max_error,
           COUNT(error) OVER w                                                         AS n_errors,
           SUM(units) OVER w                                                           AS units_last_12,
           COUNTIF(units > 0) OVER w                                                   AS months_with_demand_last_12
    FROM `sahyadri_b2b.cf_demand`
    WINDOW w AS (PARTITION BY product_id ORDER BY m ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING)
),
pooled AS (
    -- scaled errors of all products in the 12 months before each test month
    SELECT t.m,
           APPROX_QUANTILES(d.scaled_error, 100)[OFFSET(10)]                          AS q10,
           APPROX_QUANTILES(d.scaled_error, 100)[OFFSET(90)]                          AS q90,
           COUNT(*)                                                                   AS n_pooled
    FROM (SELECT DISTINCT m FROM `sahyadri_b2b.cf_demand` WHERE m BETWEEN first_test AND last_test) AS t
    JOIN `sahyadri_b2b.cf_demand` AS d
      ON d.m < t.m AND d.m >= DATE_SUB(t.m, INTERVAL 12 MONTH) AND d.scaled_error IS NOT NULL
    GROUP BY t.m
)
SELECT
    c.product_id, c.m, c.units, c.unit_cost, c.ma6,
    IF(c.months_with_demand_last_12 >= 9, 'Regular (9+ of 12 months)', IF(c.months_with_demand_last_12 >= 4, 'Intermittent (4-8)', 'Sparse (1-3)')) AS demand_type,
    GREATEST(c.ma6 - z80 * c.sd_error, 0)                                             AS normal_low,
    c.ma6 + z80 * c.sd_error                                                          AS normal_high,
    GREATEST(c.ma6 + c.min_error, 0)                                                  AS conformal_low,
    c.ma6 + c.max_error                                                               AS conformal_high,
    GREATEST(c.ma6 + (c.ma6 + 1) * p.q10, 0)                                          AS pooled_low,
    c.ma6 + (c.ma6 + 1) * p.q90                                                       AS pooled_high,
    p.n_pooled
FROM calibration AS c
JOIN pooled AS p ON p.m = c.m
WHERE c.n_errors = 12 AND c.units_last_12 > 0;

-- -----------------------------------------------------------------------------
-- Step 3 · Coverage and width
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cf_scores` AS
SELECT product_id, m, demand_type, units, unit_cost, ma6, 'Normal' AS method, normal_low AS low, normal_high AS high FROM `sahyadri_b2b.cf_intervals`
UNION ALL
SELECT product_id, m, demand_type, units, unit_cost, ma6, 'Conformal (own errors)', conformal_low, conformal_high FROM `sahyadri_b2b.cf_intervals`
UNION ALL
SELECT product_id, m, demand_type, units, unit_cost, ma6, 'Conformal (pooled, scaled)', pooled_low, pooled_high FROM `sahyadri_b2b.cf_intervals`;

SELECT
    method,
    COUNT(*)                                                                          AS product_months,
    ROUND(100 * AVG(IF(units BETWEEN low AND high, 1, 0)), 1)                          AS coverage_pct,
    ROUND(100 * AVG(IF(units > high, 1, 0)), 1)                                       AS above_range_pct,
    ROUND(100 * AVG(IF(units < low, 1, 0)), 1)                                        AS below_range_pct,
    ROUND(AVG(high - low), 1)                                                         AS avg_width_units,
    ROUND(SUM(GREATEST(high - ma6, 0) * IFNULL(unit_cost, 0)) / COUNT(DISTINCT m) / 1e5, 1) AS stock_above_forecast_lakh_per_month
FROM `sahyadri_b2b.cf_scores`
GROUP BY method
ORDER BY method;

SELECT
    demand_type, method,
    COUNT(*)                                                                          AS product_months,
    ROUND(100 * AVG(IF(units BETWEEN low AND high, 1, 0)), 1)                          AS coverage_pct,
    ROUND(100 * AVG(IF(units > high, 1, 0)), 1)                                       AS above_range_pct,
    ROUND(AVG(high - low), 1)                                                         AS avg_width_units
FROM `sahyadri_b2b.cf_scores`
GROUP BY demand_type, method
ORDER BY demand_type, method;

-- Coverage month by month: does any method drift?
SELECT
    m,
    ROUND(100 * AVG(IF(method = 'Normal' AND units BETWEEN low AND high, 1, IF(method = 'Normal', 0, NULL))), 1)                       AS normal_pct,
    ROUND(100 * AVG(IF(method = 'Conformal (own errors)' AND units BETWEEN low AND high, 1, IF(method = 'Conformal (own errors)', 0, NULL))), 1) AS conformal_own_pct,
    ROUND(100 * AVG(IF(method = 'Conformal (pooled, scaled)' AND units BETWEEN low AND high, 1, IF(method = 'Conformal (pooled, scaled)', 0, NULL))), 1) AS conformal_pooled_pct
FROM `sahyadri_b2b.cf_scores`
GROUP BY m
ORDER BY m;

-- -----------------------------------------------------------------------------
-- Step 4 · Why the normal range misses: the shape of the errors
-- -----------------------------------------------------------------------------
SELECT
    ROUND(AVG(IF(error > 0, 1, 0)) * 100, 1)                                          AS errors_positive_pct,
    ROUND(AVG(error), 2)                                                              AS mean_error_units,
    APPROX_QUANTILES(scaled_error, 20)[OFFSET(1)]                                     AS scaled_p5,
    APPROX_QUANTILES(scaled_error, 20)[OFFSET(10)]                                    AS scaled_median,
    APPROX_QUANTILES(scaled_error, 20)[OFFSET(19)]                                    AS scaled_p95,
    ROUND(100 * AVG(IF(units = 0, 1, 0)), 1)                                          AS zero_demand_months_pct
FROM `sahyadri_b2b.cf_demand`
WHERE m BETWEEN DATE '2024-07-01' AND last_test AND error IS NOT NULL;
