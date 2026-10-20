/* =============================================================================
   Case study · Baseline revenue forecast with backtesting
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Finance needs a revenue forecast for October-December 2026 to plan
   purchasing, working capital and the year-end. There is no forecasting tool,
   and the current method is "last month plus a bit". The CFO wants:
     1. A simple, explainable baseline forecast that anyone can re-run in SQL.
     2. Evidence of how accurate each candidate method would have been,
        tested on months it did not see (January-September 2026).
     3. A forecast for Q4 2026 with a realistic range, not a single number.

   KEY RULES
     - Revenue: orders not Cancelled or Returned, by order month (order
       intake, the basis used in management reports); NULL discount = 0 %.
     - History: January 2024 - September 2026 (33 months).
     - Candidate methods, each using only data before the month forecast:
         Last month        = revenue of the previous month
         3-month average   = average of the previous 3 months
         12-month average  = average of the previous 12 months
         Seasonal x growth = same month last year x (last 12 months /
                             the 12 months before that)
         Blend             = average of 12-month average and seasonal x growth
     - Accuracy: MAPE (mean absolute % error), bias (mean % error; positive =
       over-forecast) and error on the nine-month total.
   ============================================================================= */

DECLARE history_start  DATE DEFAULT DATE '2024-01-01';
DECLARE last_actual    DATE DEFAULT DATE '2026-09-01';   -- first day of last actual month
DECLARE backtest_start DATE DEFAULT DATE '2026-01-01';
DECLARE forecast_end   DATE DEFAULT DATE '2026-12-01';

-- -----------------------------------------------------------------------------
-- Step 1 · Monthly revenue on a month spine (actuals to Sep 2026, Oct-Dec blank)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.monthly_revenue` AS
WITH months AS (
    SELECT month_start
    FROM UNNEST(GENERATE_DATE_ARRAY(history_start, forecast_end, INTERVAL 1 MONTH)) AS month_start
),
actuals AS (
    SELECT
        DATE_TRUNC(o.order_date, MONTH)                                            AS month_start,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY month_start
)
SELECT
    m.month_start,
    IF(m.month_start <= last_actual, IFNULL(a.revenue, 0), NULL) AS revenue
FROM months AS m
LEFT JOIN actuals AS a ON a.month_start = m.month_start;

-- -----------------------------------------------------------------------------
-- Step 2 · Forecast of every month by each method (rolling, no look-ahead)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.monthly_forecasts` AS
WITH w AS (
    SELECT
        month_start,
        revenue,
        LAG(revenue, 1)  OVER (ORDER BY month_start)                                         AS last_month,
        AVG(revenue)     OVER (ORDER BY month_start ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING)  AS avg_3m,
        AVG(revenue)     OVER (ORDER BY month_start ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING) AS avg_12m,
        LAG(revenue, 12) OVER (ORDER BY month_start)                                         AS same_month_last_year,
        SUM(revenue)     OVER (ORDER BY month_start ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING) AS sum_last_12m,
        SUM(revenue)     OVER (ORDER BY month_start ROWS BETWEEN 24 PRECEDING AND 13 PRECEDING) AS sum_prior_12m,
        COUNT(revenue)   OVER (ORDER BY month_start ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING) AS months_available
    FROM `sahyadri_b2b.monthly_revenue`
    WHERE month_start <= last_actual
),
growth AS (
    -- latest 12-month growth factor, used for the future months
    SELECT SAFE_DIVIDE(
               SUM(IF(month_start >  DATE_SUB(last_actual, INTERVAL 12 MONTH), revenue, 0)),
               SUM(IF(month_start <= DATE_SUB(last_actual, INTERVAL 12 MONTH)
                      AND month_start > DATE_SUB(last_actual, INTERVAL 24 MONTH), revenue, 0))) AS factor
    FROM `sahyadri_b2b.monthly_revenue`
    WHERE month_start <= last_actual
),
history_forecasts AS (
    SELECT
        month_start,
        revenue,
        last_month,
        avg_3m,
        avg_12m,
        same_month_last_year * SAFE_DIVIDE(sum_last_12m, sum_prior_12m)              AS seasonal_growth
    FROM w
    WHERE months_available = 24          -- full two years of history behind the month
),
future_forecasts AS (
    SELECT
        f.month_start,
        CAST(NULL AS FLOAT64)                                                        AS revenue,
        CAST(NULL AS FLOAT64)                                                        AS last_month,
        CAST(NULL AS FLOAT64)                                                        AS avg_3m,
        (SELECT AVG(revenue) FROM `sahyadri_b2b.monthly_revenue`
          WHERE month_start >  DATE_SUB(last_actual, INTERVAL 12 MONTH)
            AND month_start <= last_actual)                                         AS avg_12m,
        ly.revenue * g.factor                                                        AS seasonal_growth
    FROM `sahyadri_b2b.monthly_revenue` AS f
    JOIN `sahyadri_b2b.monthly_revenue` AS ly
        ON ly.month_start = DATE_SUB(f.month_start, INTERVAL 12 MONTH)
    CROSS JOIN growth AS g
    WHERE f.month_start > last_actual
)
SELECT
    *,
    (avg_12m + seasonal_growth) / 2 AS blend
FROM (
    SELECT * FROM history_forecasts
    UNION ALL
    SELECT * FROM future_forecasts
);

-- -----------------------------------------------------------------------------
-- Step 3 · Backtest accuracy, January-September 2026
-- -----------------------------------------------------------------------------
WITH test AS (
    SELECT * FROM `sahyadri_b2b.monthly_forecasts`
    WHERE month_start BETWEEN backtest_start AND last_actual
),
long_format AS (
    SELECT month_start, revenue, 'Last month'        AS method, last_month      AS forecast FROM test UNION ALL
    SELECT month_start, revenue, '3-month average',            avg_3m                      FROM test UNION ALL
    SELECT month_start, revenue, '12-month average',           avg_12m                     FROM test UNION ALL
    SELECT month_start, revenue, 'Seasonal x growth',          seasonal_growth             FROM test UNION ALL
    SELECT month_start, revenue, 'Blend',                      blend                       FROM test
)
SELECT
    method,
    COUNT(*)                                                         AS months_tested,
    ROUND(100 * AVG(ABS(forecast - revenue) / revenue), 1)           AS mape_pct,
    ROUND(100 * AVG((forecast - revenue) / revenue), 1)              AS bias_pct,
    ROUND(100 * MAX(ABS(forecast - revenue) / revenue), 1)           AS worst_month_error_pct,
    ROUND(100 * (SUM(forecast) / SUM(revenue) - 1), 1)               AS nine_month_total_error_pct
FROM long_format
GROUP BY method
ORDER BY mape_pct;

-- -----------------------------------------------------------------------------
-- Step 4 · Month-by-month backtest for the blend (for the chart in the README)
-- -----------------------------------------------------------------------------
SELECT
    month_start,
    ROUND(revenue, 0)                                   AS actual,
    ROUND(blend, 0)                                     AS blend_forecast,
    ROUND(100 * (blend - revenue) / revenue, 1)         AS error_pct
FROM `sahyadri_b2b.monthly_forecasts`
WHERE month_start BETWEEN backtest_start AND last_actual
ORDER BY month_start;

-- -----------------------------------------------------------------------------
-- Step 5 · Q4 2026 forecast with a range based on backtest error, plus a
--          bias-adjusted version (the backtest shows systematic under-forecast)
-- -----------------------------------------------------------------------------
WITH accuracy AS (
    SELECT
        AVG(ABS(blend - revenue) / revenue) AS mape,
        AVG((blend - revenue) / revenue)    AS bias
    FROM `sahyadri_b2b.monthly_forecasts`
    WHERE month_start BETWEEN backtest_start AND last_actual
)
SELECT
    f.month_start,
    ROUND(f.avg_12m, 0)                                 AS forecast_12m_average,
    ROUND(f.seasonal_growth, 0)                         AS forecast_seasonal_growth,
    ROUND(f.blend, 0)                                   AS forecast_blend,
    ROUND(f.blend * (1 - a.mape), 0)                    AS range_low,
    ROUND(f.blend * (1 + a.mape), 0)                    AS range_high,
    ROUND(f.blend / (1 + a.bias), 0)                    AS forecast_bias_adjusted
FROM `sahyadri_b2b.monthly_forecasts` AS f
CROSS JOIN accuracy AS a
WHERE f.month_start > last_actual
ORDER BY f.month_start;
