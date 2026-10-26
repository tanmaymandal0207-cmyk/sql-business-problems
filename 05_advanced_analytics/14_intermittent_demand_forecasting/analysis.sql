/* =============================================================================
   Case study · Intermittent demand forecasting (Croston and SBA)
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The safety stock study found that most products sell in irregular lumps
   week to week: several weeks with nothing, then a large order. Standard
   forecasts (moving averages, exponential smoothing) handle this badly.
   The supply chain team wants to know whether the methods designed for
   intermittent demand - Croston's method and its bias-corrected version
   (Syntetos-Boylan approximation, SBA) - would forecast lead-time demand
   better, before buying a planning tool that uses them:
     1. How intermittent is weekly demand, product by product?
     2. Which method forecasts 4-week lead-time demand best in a back-test?
     3. Does the answer differ by demand pattern?
     4. Which methods are biased (systematically over- or under-forecast)?

   METHOD
     - Weekly units per product (ISO weeks, zero-filled), orders not
       Cancelled or Returned, January 2024 - September 2026.
     - Demand pattern (Syntetos-Boylan): ADI = weeks / weeks with demand;
       CV2 = squared coefficient of variation of non-zero weekly demand.
       Smooth (ADI < 1.32, CV2 < 0.49), Erratic (ADI < 1.32), Intermittent
       (CV2 < 0.49), Lumpy (both high).
     - Methods (alpha = 0.1), each giving a per-week forecast at origin t:
         Naive  : last week's demand
         MA13   : mean of the last 13 weeks
         SES    : simple exponential smoothing on all weeks
         Croston: smoothed demand size z / smoothed interval p, updated only
                  in weeks with demand
         SBA    : (1 - alpha / 2) x Croston
       Smoothing is computed in closed form with window sums, e.g.
         s_t = (1-a)^(t-1) y_1 + a * SUM_{i=2..t} (1-a)^(t-i) y_i.
     - Back-test: every origin from week 52 to the last week with 4 weeks
       of actuals after it. Lead-time demand = units in the next 4 weeks;
       forecast = 4 x per-week forecast.
     - Metrics over all origins and products: WAPE = SUM|F - A| / SUM A,
       bias = SUM(F - A) / SUM A, and RMSE.
   ============================================================================= */

DECLARE alpha          FLOAT64 DEFAULT 0.1;
DECLARE lead_weeks     INT64   DEFAULT 4;
DECLARE first_origin   INT64   DEFAULT 52;

-- -----------------------------------------------------------------------------
-- Step 1 · Weekly demand grid and demand pattern per product
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.idf_weekly` AS
WITH weekly AS (
    SELECT i.product_id, DATE_TRUNC(o.order_date, ISOWEEK) AS week_start, SUM(i.quantity) AS units
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY i.product_id, week_start
),
weeks AS (
    SELECT week_start, ROW_NUMBER() OVER (ORDER BY week_start) AS week_index
    FROM (SELECT DISTINCT week_start FROM weekly)
),
products AS (
    SELECT DISTINCT product_id FROM weekly
)
SELECT p.product_id, w.week_start, w.week_index, IFNULL(x.units, 0) AS units
FROM products AS p
CROSS JOIN weeks AS w
LEFT JOIN weekly AS x ON x.product_id = p.product_id AND x.week_start = w.week_start;

CREATE OR REPLACE TABLE `sahyadri_b2b.idf_pattern` AS
SELECT
    product_id,
    COUNT(*) / COUNTIF(units > 0)                                                   AS adi,
    POW(STDDEV_POP(IF(units > 0, units, NULL)) / AVG(IF(units > 0, units, NULL)), 2) AS cv2,
    CASE WHEN COUNT(*) / COUNTIF(units > 0) < 1.32
              AND POW(STDDEV_POP(IF(units > 0, units, NULL)) / AVG(IF(units > 0, units, NULL)), 2) < 0.49 THEN 'Smooth'
         WHEN COUNT(*) / COUNTIF(units > 0) < 1.32                                                     THEN 'Erratic'
         WHEN POW(STDDEV_POP(IF(units > 0, units, NULL)) / AVG(IF(units > 0, units, NULL)), 2) < 0.49  THEN 'Intermittent'
         ELSE 'Lumpy' END                                                          AS pattern,
    SUM(units)                                                                     AS total_units
FROM `sahyadri_b2b.idf_weekly`
GROUP BY product_id;

SELECT
    pattern,
    COUNT(*)                                                                       AS products,
    ROUND(AVG(adi), 2)                                                             AS avg_adi,
    ROUND(AVG(cv2), 2)                                                             AS avg_cv2,
    ROUND(100 * SUM(total_units) / SUM(SUM(total_units)) OVER (), 1)               AS share_of_units_pct
FROM `sahyadri_b2b.idf_pattern`
GROUP BY pattern
ORDER BY products DESC;

-- -----------------------------------------------------------------------------
-- Step 2 · Forecast state of every method at every week (closed form)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.idf_states` AS
WITH ses_parts AS (
    SELECT
        *,
        FIRST_VALUE(units) OVER (PARTITION BY product_id ORDER BY week_index)      AS y1,
        SUM(IF(week_index >= 2, units * POW(1 - alpha, -week_index), 0))
            OVER (PARTITION BY product_id ORDER BY week_index ROWS UNBOUNDED PRECEDING) AS ses_sum
    FROM `sahyadri_b2b.idf_weekly`
),
occurrences AS (
    -- weeks with demand, numbered; q = weeks since the previous demand
    SELECT
        product_id, week_index, units,
        ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY week_index)            AS j,
        week_index - IFNULL(LAG(week_index) OVER (PARTITION BY product_id ORDER BY week_index), 0) AS q
    FROM `sahyadri_b2b.idf_weekly`
    WHERE units > 0
),
croston_parts AS (
    SELECT
        *,
        FIRST_VALUE(units) OVER (PARTITION BY product_id ORDER BY j)               AS x1,
        FIRST_VALUE(q)     OVER (PARTITION BY product_id ORDER BY j)               AS q1,
        SUM(IF(j >= 2, units * POW(1 - alpha, -j), 0)) OVER (PARTITION BY product_id ORDER BY j ROWS UNBOUNDED PRECEDING) AS z_sum,
        SUM(IF(j >= 2, q     * POW(1 - alpha, -j), 0)) OVER (PARTITION BY product_id ORDER BY j ROWS UNBOUNDED PRECEDING) AS p_sum
    FROM occurrences
),
croston AS (
    SELECT
        product_id, week_index,
        POW(1 - alpha, j - 1) * x1 + alpha * POW(1 - alpha, j) * z_sum             AS z,
        POW(1 - alpha, j - 1) * q1 + alpha * POW(1 - alpha, j) * p_sum             AS p
    FROM croston_parts
)
SELECT
    s.product_id,
    s.week_index,
    s.units,
    s.units                                                                        AS f_naive,
    AVG(s.units) OVER (PARTITION BY s.product_id ORDER BY s.week_index ROWS BETWEEN 12 PRECEDING AND CURRENT ROW) AS f_ma13,
    POW(1 - alpha, s.week_index - 1) * s.y1 + alpha * POW(1 - alpha, s.week_index) * s.ses_sum AS f_ses,
    -- Croston state carried forward through weeks without demand
    LAST_VALUE(c.z IGNORE NULLS) OVER (PARTITION BY s.product_id ORDER BY s.week_index ROWS UNBOUNDED PRECEDING)
      / LAST_VALUE(c.p IGNORE NULLS) OVER (PARTITION BY s.product_id ORDER BY s.week_index ROWS UNBOUNDED PRECEDING) AS f_croston
FROM ses_parts AS s
LEFT JOIN croston AS c ON c.product_id = s.product_id AND c.week_index = s.week_index;

-- -----------------------------------------------------------------------------
-- Step 3 · Back-test on 4-week lead-time demand
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.idf_backtest` AS
WITH actuals AS (
    SELECT
        product_id, week_index,
        SUM(units) OVER (PARTITION BY product_id ORDER BY week_index
                         ROWS BETWEEN 1 FOLLOWING AND 4 FOLLOWING)                 AS lead_demand,
        COUNT(*)   OVER (PARTITION BY product_id ORDER BY week_index
                         ROWS BETWEEN 1 FOLLOWING AND 4 FOLLOWING)                 AS weeks_ahead
    FROM `sahyadri_b2b.idf_weekly`
),
base AS (
    SELECT s.*, a.lead_demand
    FROM `sahyadri_b2b.idf_states` AS s
    JOIN actuals AS a ON a.product_id = s.product_id AND a.week_index = s.week_index
    WHERE s.week_index >= first_origin
      AND a.weeks_ahead = lead_weeks
)
          SELECT product_id, week_index AS origin, lead_demand, '1. Naive'   AS method, lead_weeks * f_naive AS forecast FROM base
UNION ALL SELECT product_id, week_index, lead_demand, '2. MA13',    lead_weeks * f_ma13                                  FROM base
UNION ALL SELECT product_id, week_index, lead_demand, '3. SES',     lead_weeks * f_ses                                   FROM base
UNION ALL SELECT product_id, week_index, lead_demand, '4. Croston', lead_weeks * IFNULL(f_croston, 0)                    FROM base
UNION ALL SELECT product_id, week_index, lead_demand, '5. SBA',     lead_weeks * (1 - alpha / 2) * IFNULL(f_croston, 0)  FROM base;

SELECT
    method,
    COUNT(*)                                                                       AS forecasts,
    ROUND(100 * SUM(ABS(forecast - lead_demand)) / SUM(lead_demand), 1)            AS wape_pct,
    ROUND(100 * SUM(forecast - lead_demand) / SUM(lead_demand), 1)                 AS bias_pct,
    ROUND(SQRT(AVG(POW(forecast - lead_demand, 2))), 1)                            AS rmse_units
FROM `sahyadri_b2b.idf_backtest`
GROUP BY method
ORDER BY method;

-- -----------------------------------------------------------------------------
-- Step 4 · By demand pattern
-- -----------------------------------------------------------------------------
SELECT
    p.pattern,
    b.method,
    COUNT(DISTINCT b.product_id)                                                   AS products,
    ROUND(100 * SUM(ABS(b.forecast - b.lead_demand)) / SUM(b.lead_demand), 1)      AS wape_pct,
    ROUND(100 * SUM(b.forecast - b.lead_demand) / SUM(b.lead_demand), 1)           AS bias_pct,
    ROUND(SQRT(AVG(POW(b.forecast - b.lead_demand, 2))), 1)                        AS rmse_units
FROM `sahyadri_b2b.idf_backtest` AS b
JOIN `sahyadri_b2b.idf_pattern`  AS p ON p.product_id = b.product_id
GROUP BY p.pattern, b.method
ORDER BY p.pattern, rmse_units;

-- Best method per product (lowest RMSE), counted by pattern
WITH per_product AS (
    SELECT product_id, method, SQRT(AVG(POW(forecast - lead_demand, 2))) AS rmse
    FROM `sahyadri_b2b.idf_backtest`
    GROUP BY product_id, method
),
best AS (
    SELECT * FROM per_product
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY rmse, method) = 1
)
SELECT
    p.pattern,
    COUNTIF(b.method = '1. Naive')                                                 AS naive_best,
    COUNTIF(b.method = '2. MA13')                                                  AS ma13_best,
    COUNTIF(b.method = '3. SES')                                                   AS ses_best,
    COUNTIF(b.method = '4. Croston')                                               AS croston_best,
    COUNTIF(b.method = '5. SBA')                                                   AS sba_best,
    COUNT(*)                                                                       AS products
FROM best AS b
JOIN `sahyadri_b2b.idf_pattern` AS p ON p.product_id = b.product_id
GROUP BY p.pattern
ORDER BY products DESC;
