/* =============================================================================
   Case study · Working-day adjustment: how much of each month's change is
   just the calendar?
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Every month the management pack reports revenue growth against the
   previous month and the same month last year, and every month someone
   explains a dip by "there were more Sundays". Nobody knows how large the
   calendar effect really is. The financial controller asks:
     1. How much revenue does each weekday bring, and how much do months
        differ in trading days?
     2. How much of the month-on-month change in revenue is the calendar?
     3. Does adjusting for it change the story in particular months?
     4. Does an adjustment estimated on one year work on the next?

   METHOD
     - Daily booked revenue of valid orders (not Cancelled or Returned),
       January 2024 - September 2026, every calendar day.
     - Weekday weight = average revenue on that weekday / average daily
       revenue. Estimated on 2024 only, then applied to every month, so
       2025 - 2026 is an out-of-sample test.
     - Trading-day index (TDI) of a month = sum of its days' weights /
       average of that sum over all 33 months.
     - Adjusted revenue = revenue / TDI.
     - Month-on-month: ln change in revenue = ln change in TDI + ln change
       in adjusted revenue. The slope of the revenue change on the TDI
       change (expected about 1) and its R-squared measure how much the
       calendar explains.
   ============================================================================= */

DECLARE first_day DATE DEFAULT DATE '2024-01-01';
DECLARE last_day  DATE DEFAULT DATE '2026-09-30';
DECLARE train_end DATE DEFAULT DATE '2024-12-31';

-- -----------------------------------------------------------------------------
-- Step 1 · Daily revenue and weekday weights (estimated on 2024)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.wd_days` AS
WITH calendar AS (
    SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(first_day, last_day)) AS d
),
revenue AS (
    SELECT o.order_date AS d, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_date
)
SELECT c.d, DATE_TRUNC(c.d, MONTH) AS month, FORMAT_DATE('%a', c.d) AS weekday,
       IFNULL(r.revenue, 0) AS revenue
FROM calendar AS c LEFT JOIN revenue AS r ON r.d = c.d;

CREATE OR REPLACE TABLE `sahyadri_b2b.wd_weights` AS
SELECT weekday,
       AVG(revenue) / (SELECT AVG(revenue) FROM `sahyadri_b2b.wd_days` WHERE d <= train_end) AS weight,
       COUNT(*) AS days_in_training
FROM `sahyadri_b2b.wd_days`
WHERE d <= train_end
GROUP BY weekday;

-- The same weights measured on 2025 - 2026, for comparison
WITH later AS (
    SELECT weekday, AVG(revenue) / ANY_VALUE(overall) AS weight_later
    FROM `sahyadri_b2b.wd_days`
    CROSS JOIN (SELECT AVG(revenue) AS overall FROM `sahyadri_b2b.wd_days` WHERE d > train_end)
    WHERE d > train_end
    GROUP BY weekday
)
SELECT w.weekday, ROUND(w.weight, 3) AS weight_2024, w.days_in_training, ROUND(l.weight_later, 3) AS weight_2025_2026
FROM `sahyadri_b2b.wd_weights` AS w JOIN later AS l USING (weekday)
ORDER BY w.weight DESC;

-- -----------------------------------------------------------------------------
-- Step 2 · Trading-day index and adjusted revenue by month
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.wd_months` AS
WITH monthly AS (
    SELECT d.month, SUM(d.revenue) AS revenue, SUM(w.weight) AS weighted_days, COUNT(*) AS days,
           COUNTIF(d.weekday = 'Sun') AS sundays, COUNTIF(d.weekday = 'Sat') AS saturdays
    FROM `sahyadri_b2b.wd_days` AS d JOIN `sahyadri_b2b.wd_weights` AS w USING (weekday)
    GROUP BY d.month
)
SELECT *,
       weighted_days / AVG(weighted_days) OVER ()                                     AS tdi,
       revenue / (weighted_days / AVG(weighted_days) OVER ())                         AS adjusted_revenue,
       LN(revenue) - LAG(LN(revenue)) OVER (ORDER BY month)                           AS d_ln_revenue,
       LN(weighted_days) - LAG(LN(weighted_days)) OVER (ORDER BY month)               AS d_ln_tdi
FROM monthly;

SELECT
    ROUND(MIN(tdi), 3)                                                                AS lowest_tdi,
    ROUND(MAX(tdi), 3)                                                                AS highest_tdi,
    ROUND(100 * (MAX(tdi) / MIN(tdi) - 1), 1)                                         AS spread_pct,
    ROUND(100 * STDDEV_POP(d_ln_tdi), 2)                                              AS sd_month_change_from_calendar_pct,
    ROUND(100 * STDDEV_POP(d_ln_revenue), 2)                                          AS sd_month_change_in_revenue_pct
FROM `sahyadri_b2b.wd_months`;

-- Months with the highest and lowest trading-day index
SELECT month, days, sundays, saturdays, ROUND(tdi, 3) AS tdi
FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY tdi) AS lo, ROW_NUMBER() OVER (ORDER BY tdi DESC) AS hi FROM `sahyadri_b2b.wd_months`)
WHERE lo <= 3 OR hi <= 3
ORDER BY tdi;

-- -----------------------------------------------------------------------------
-- Step 3 · How much of the month-on-month change is the calendar?
-- -----------------------------------------------------------------------------
-- In-sample (2024 changes) and out-of-sample (2025 - 2026 changes), March and April months excluded
-- as well, since the year-end peak dominates those two changes
SELECT
    IF(month <= train_end, '1. 2024 (weights fitted here)', '2. 2025-2026 (out of sample)')  AS period,
    COUNT(*)                                                                          AS month_changes,
    ROUND(COVAR_POP(d_ln_tdi, d_ln_revenue) / VAR_POP(d_ln_tdi), 2)                   AS slope_on_calendar,
    ROUND(POW(CORR(d_ln_tdi, d_ln_revenue), 2), 3)                                    AS r_squared,
    ROUND(COVAR_POP(IF(EXTRACT(MONTH FROM month) IN (3, 4), NULL, d_ln_tdi), IF(EXTRACT(MONTH FROM month) IN (3, 4), NULL, d_ln_revenue))
          / VAR_POP(IF(EXTRACT(MONTH FROM month) IN (3, 4), NULL, d_ln_tdi)), 2)      AS slope_without_march_april,
    ROUND(POW(CORR(IF(EXTRACT(MONTH FROM month) IN (3, 4), NULL, d_ln_tdi), IF(EXTRACT(MONTH FROM month) IN (3, 4), NULL, d_ln_revenue)), 2), 3) AS r_squared_without_march_april
FROM `sahyadri_b2b.wd_months`
WHERE d_ln_revenue IS NOT NULL
GROUP BY period
ORDER BY period;

-- -----------------------------------------------------------------------------
-- Step 4 · Months where the calendar changes the story
-- -----------------------------------------------------------------------------
WITH changes AS (
    SELECT month, revenue, adjusted_revenue, tdi,
           revenue / LAG(revenue) OVER (ORDER BY month) - 1                           AS raw_mom,
           adjusted_revenue / LAG(adjusted_revenue) OVER (ORDER BY month) - 1         AS adjusted_mom,
           revenue / LAG(revenue, 12) OVER (ORDER BY month) - 1                       AS raw_yoy,
           adjusted_revenue / LAG(adjusted_revenue, 12) OVER (ORDER BY month) - 1     AS adjusted_yoy
    FROM `sahyadri_b2b.wd_months`
)
SELECT
    COUNTIF(raw_mom IS NOT NULL)                                                      AS month_changes,
    COUNTIF(SIGN(raw_mom) != SIGN(adjusted_mom))                                      AS month_on_month_sign_flips,
    COUNTIF(ABS(raw_mom - adjusted_mom) >= 0.05)                                      AS month_on_month_gaps_5_points,
    COUNTIF(raw_yoy IS NOT NULL)                                                      AS year_on_year_comparisons,
    COUNTIF(SIGN(raw_yoy) != SIGN(adjusted_yoy))                                      AS year_on_year_sign_flips,
    ROUND(100 * MAX(ABS(raw_yoy - adjusted_yoy)), 1)                                  AS largest_year_on_year_gap_pts
FROM changes;

WITH changes AS (
    SELECT month, tdi, revenue,
           revenue / LAG(revenue) OVER (ORDER BY month) - 1                           AS raw_mom,
           adjusted_revenue / LAG(adjusted_revenue) OVER (ORDER BY month) - 1         AS adjusted_mom,
           revenue / LAG(revenue, 12) OVER (ORDER BY month) - 1                       AS raw_yoy,
           adjusted_revenue / LAG(adjusted_revenue, 12) OVER (ORDER BY month) - 1     AS adjusted_yoy
    FROM `sahyadri_b2b.wd_months`
)
SELECT month, ROUND(tdi, 3) AS tdi, ROUND(revenue / 1e5, 1) AS revenue_lakh,
       ROUND(100 * raw_mom, 1) AS raw_mom_pct, ROUND(100 * adjusted_mom, 1) AS adjusted_mom_pct,
       ROUND(100 * raw_yoy, 1) AS raw_yoy_pct, ROUND(100 * adjusted_yoy, 1) AS adjusted_yoy_pct
FROM changes
WHERE month >= DATE '2025-10-01' OR SIGN(raw_mom) != SIGN(adjusted_mom)
ORDER BY month;
