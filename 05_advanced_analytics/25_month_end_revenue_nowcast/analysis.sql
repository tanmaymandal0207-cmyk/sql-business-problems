/* =============================================================================
   Case study · Nowcasting month-end revenue from the first days of the month
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The CFO reports an expected month-end revenue figure to the promoters
   every Monday. Today it is the budget, unchanged until the month closes.
   She asks the analytics team:
     1. How early in the month do the orders booked so far say more about
        month-end revenue than the forecast made before the month began?
     2. Which simple method is most accurate on each day: a calendar
        run-rate, a run-rate that knows weekends are quiet, or "booked so
        far plus the usual rate for the days left"?
     3. How wide should the range around the figure be on each day?
     4. What makes the nowcast miss?

   METHOD
     - Booked revenue of valid orders (not Cancelled or Returned) by order
       date, January 2024 - September 2026, every calendar day.
     - Back-test: every month from April 2024 to September 2026 (30), on
       each day N = 1 .. 28, using only information available on day N.
     - Prior: the average of the previous 3 months (known before day 1).
     - Calendar run-rate: revenue to day N x days in month / N.
     - Weekday run-rate: revenue to day N x W(month) / W(N), where W adds
       up weekday weights (average revenue on that weekday / average daily
       revenue, from all days before the month).
     - Blend: revenue to day N + prior x share of the month's weekday
       weight still to come.
     - Error = nowcast / actual - 1; accuracy = mean absolute error. The
       same back-test without orders of Rs 5 lakh or more isolates the
       effect of large deals.
   ============================================================================= */

DECLARE history_start   DATE    DEFAULT DATE '2024-01-01';
DECLARE history_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE backtest_start  DATE    DEFAULT DATE '2024-04-01';
DECLARE large_order     FLOAT64 DEFAULT 500000;

-- -----------------------------------------------------------------------------
-- Step 1 · Daily revenue for two series: all orders, and without large orders
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.nc_days` AS
WITH orders AS (
    SELECT o.order_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN history_start AND history_end
    GROUP BY o.order_id, o.order_date
),
calendar AS (
    SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(history_start, history_end)) AS d
),
series AS (
    SELECT 'All orders' AS series UNION ALL SELECT 'Excluding large orders'
)
SELECT
    s.series, c.d AS day,
    DATE_TRUNC(c.d, MONTH)                                                           AS month,
    EXTRACT(DAY FROM c.d)                                                            AS day_of_month,
    EXTRACT(DAYOFWEEK FROM c.d)                                                      AS weekday,
    FORMAT_DATE('%a', c.d)                                                           AS weekday_name,
    EXTRACT(DAY FROM LAST_DAY(c.d))                                                  AS days_in_month,
    IFNULL(SUM(IF(s.series = 'All orders' OR o.value < large_order, o.value, 0)), 0) AS revenue
FROM calendar AS c
CROSS JOIN series AS s
LEFT JOIN orders AS o ON o.order_date = c.d
GROUP BY s.series, c.d;

-- -----------------------------------------------------------------------------
-- Step 2 · Months, priors and weekday weights known before each month
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.nc_months` AS
WITH monthly AS (
    SELECT series, month, SUM(revenue) AS revenue FROM `sahyadri_b2b.nc_days` GROUP BY series, month
)
SELECT
    series, month, revenue,
    AVG(revenue) OVER (PARTITION BY series ORDER BY month ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS prior,
    COUNT(*) OVER (PARTITION BY series ORDER BY month ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING)     AS prior_months
FROM monthly;

CREATE OR REPLACE TABLE `sahyadri_b2b.nc_weights` AS
WITH history AS (
    SELECT m.series, m.month, d.weekday, d.revenue
    FROM `sahyadri_b2b.nc_months` AS m
    JOIN `sahyadri_b2b.nc_days` AS d ON d.series = m.series AND d.day < m.month
    WHERE m.month >= backtest_start
)
SELECT h.series, h.month, h.weekday, AVG(h.revenue) / ANY_VALUE(a.avg_daily) AS weight
FROM history AS h
JOIN (SELECT series, month, AVG(revenue) AS avg_daily FROM history GROUP BY series, month) AS a
  ON a.series = h.series AND a.month = h.month
GROUP BY h.series, h.month, h.weekday;

-- How revenue builds through the month, and the weekday pattern
SELECT
    d.day_of_month,
    ROUND(100 * AVG(d.to_date / m.revenue), 1)                                       AS avg_share_of_month_pct,
    ROUND(100 * STDDEV(d.to_date / m.revenue), 1)                                    AS sd_share_pct,
    ROUND(100 * AVG(d.day_of_month / d.days_in_month), 1)                            AS calendar_share_pct
FROM (
    SELECT series, month, day_of_month, days_in_month,
           SUM(revenue) OVER (PARTITION BY series, month ORDER BY day_of_month) AS to_date
    FROM `sahyadri_b2b.nc_days`
) AS d
JOIN `sahyadri_b2b.nc_months` AS m ON m.series = d.series AND m.month = d.month
WHERE d.series = 'All orders' AND d.day_of_month IN (5, 10, 15, 20, 25)
GROUP BY d.day_of_month
ORDER BY d.day_of_month;

SELECT weekday, ANY_VALUE(weekday_name) AS weekday_name,
       ROUND(AVG(revenue) / (SELECT AVG(revenue) FROM `sahyadri_b2b.nc_days` WHERE series = 'All orders'), 2) AS weekday_index
FROM `sahyadri_b2b.nc_days`
WHERE series = 'All orders'
GROUP BY weekday
ORDER BY weekday;

-- -----------------------------------------------------------------------------
-- Step 3 · Nowcasts on every day 1-28 of every back-test month
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.nc_nowcasts` AS
WITH weighted AS (
    SELECT d.series, d.month, d.day_of_month, d.days_in_month, d.revenue, w.weight,
           SUM(d.revenue) OVER (PARTITION BY d.series, d.month ORDER BY d.day_of_month) AS to_date,
           SUM(w.weight)  OVER (PARTITION BY d.series, d.month ORDER BY d.day_of_month) AS weight_to_date,
           SUM(w.weight)  OVER (PARTITION BY d.series, d.month)                         AS weight_month
    FROM `sahyadri_b2b.nc_days` AS d
    JOIN `sahyadri_b2b.nc_weights` AS w ON w.series = d.series AND w.month = d.month AND w.weekday = d.weekday
)
SELECT
    x.series, x.month, x.day_of_month AS day_n, m.revenue AS actual, m.prior, x.to_date,
    x.to_date * x.days_in_month / x.day_of_month                                     AS calendar_run_rate,
    x.to_date * x.weight_month / x.weight_to_date                                    AS weekday_run_rate,
    x.to_date + m.prior * (1 - x.weight_to_date / x.weight_month)                    AS blend,
    x.weight_to_date / x.weight_month                                                AS elapsed_weight
FROM weighted AS x
JOIN `sahyadri_b2b.nc_months` AS m ON m.series = x.series AND m.month = x.month
WHERE x.day_of_month <= 28 AND m.prior_months = 3;

-- Accuracy by day: mean absolute error of each method (all orders)
SELECT
    day_n,
    COUNT(*)                                                                         AS months,
    ROUND(100 * AVG(ABS(prior / actual - 1)), 1)                                     AS prior_mape,
    ROUND(100 * AVG(ABS(calendar_run_rate / actual - 1)), 1)                         AS calendar_run_rate_mape,
    ROUND(100 * AVG(ABS(weekday_run_rate / actual - 1)), 1)                          AS weekday_run_rate_mape,
    ROUND(100 * AVG(ABS(blend / actual - 1)), 1)                                     AS blend_mape,
    ROUND(100 * AVG(weekday_run_rate / actual - 1), 1)                               AS weekday_run_rate_bias,
    ROUND(100 * APPROX_QUANTILES(ABS(weekday_run_rate / actual - 1), 10)[OFFSET(8)], 1) AS weekday_run_rate_p80_error
FROM `sahyadri_b2b.nc_nowcasts`
WHERE series = 'All orders' AND day_n IN (1, 3, 5, 7, 10, 15, 20, 25, 28)
GROUP BY day_n
ORDER BY day_n;

-- From which day does each method beat the prior?
WITH by_day AS (
    SELECT day_n,
           AVG(ABS(prior / actual - 1))                                              AS prior_e,
           AVG(ABS(calendar_run_rate / actual - 1))                                  AS cal_e,
           AVG(ABS(weekday_run_rate / actual - 1))                                   AS wk_e,
           AVG(ABS(blend / actual - 1))                                              AS blend_e
    FROM `sahyadri_b2b.nc_nowcasts`
    WHERE series = 'All orders'
    GROUP BY day_n
)
SELECT
    MIN(IF(cal_e < prior_e, day_n, NULL))                                            AS calendar_run_rate_beats_prior_from_day,
    MIN(IF(wk_e < prior_e, day_n, NULL))                                             AS weekday_run_rate_beats_prior_from_day,
    MIN(IF(blend_e < prior_e, day_n, NULL))                                          AS blend_beats_prior_from_day,
    MIN(IF(wk_e < blend_e, day_n, NULL))                                             AS weekday_run_rate_beats_blend_from_day,
    COUNTIF(blend_e < prior_e)                                                       AS days_blend_beats_prior
FROM by_day;

-- -----------------------------------------------------------------------------
-- Step 4 · What makes the nowcast miss?
-- -----------------------------------------------------------------------------
-- (a) Large orders
SELECT
    day_n,
    ROUND(100 * AVG(IF(series = 'All orders', ABS(weekday_run_rate / actual - 1), NULL)), 1)             AS all_orders_mape,
    ROUND(100 * AVG(IF(series = 'Excluding large orders', ABS(weekday_run_rate / actual - 1), NULL)), 1) AS excluding_large_mape,
    ROUND(100 * AVG(IF(series = 'Excluding large orders', ABS(prior / actual - 1), NULL)), 1)            AS excluding_large_prior_mape
FROM `sahyadri_b2b.nc_nowcasts`
WHERE day_n IN (5, 10, 15, 20, 25)
GROUP BY day_n
ORDER BY day_n;

SELECT
    COUNTIF(value >= large_order)                                                    AS large_orders,
    ROUND(100 * SUM(IF(value >= large_order, value, 0)) / SUM(value), 1)             AS large_share_of_revenue_pct
FROM (
    SELECT o.order_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN backtest_start AND history_end
    GROUP BY o.order_id
);

-- (b) March, the year-end month
SELECT
    month, day_n,
    ROUND(actual / 1e5, 1)                                                           AS actual_lakh,
    ROUND(100 * (prior / actual - 1), 1)                                             AS prior_error_pct,
    ROUND(100 * (weekday_run_rate / actual - 1), 1)                                  AS weekday_run_rate_error_pct,
    ROUND(100 * (blend / actual - 1), 1)                                             AS blend_error_pct
FROM `sahyadri_b2b.nc_nowcasts`
WHERE series = 'All orders' AND EXTRACT(MONTH FROM month) = 3 AND day_n IN (10, 15, 20, 25)
ORDER BY month, day_n;

-- Share of each month booked in its last days (from day 26)
SELECT
    IF(EXTRACT(MONTH FROM month) = 3, 'March', 'Other months')                       AS months,
    COUNT(DISTINCT month)                                                            AS n,
    ROUND(100 * SUM(IF(day_of_month >= 26, revenue, 0)) / SUM(revenue), 1)           AS share_from_day_26_pct,
    ROUND(100 * AVG(IF(day_of_month >= 26, 1, 0)), 1)                                AS share_of_days_pct
FROM `sahyadri_b2b.nc_days`
WHERE series = 'All orders' AND month >= backtest_start
GROUP BY months
ORDER BY months;

-- (c) The other 28 months: accuracy without the March effect
SELECT
    day_n,
    ROUND(100 * AVG(ABS(prior / actual - 1)), 1)                                     AS prior_mape,
    ROUND(100 * AVG(ABS(weekday_run_rate / actual - 1)), 1)                          AS weekday_run_rate_mape,
    ROUND(100 * AVG(ABS(blend / actual - 1)), 1)                                     AS blend_mape
FROM `sahyadri_b2b.nc_nowcasts`
WHERE series = 'All orders' AND EXTRACT(MONTH FROM month) != 3 AND day_n IN (5, 10, 15, 20)
GROUP BY day_n
ORDER BY day_n;
