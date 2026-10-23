/* =============================================================================
   Case study · Period-end sales push
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Sales targets are monthly, quarterly and annual (financial year to 31
   March). A common side effect is the "hockey stick": orders bunch in the
   last days of a period, closed with extra discount, and some of them are
   cancelled or returned afterwards. The CFO wants evidence, not anecdotes:
     1. Do orders bunch at the end of the month, quarter or financial year?
     2. Are period-end orders discounted more deeply, and is the difference
        larger than chance?
     3. Are period-end orders cancelled, returned or delivered late more often?
     4. What does any extra period-end discount cost?

   KEY RULES
     - Period: orders dated 1 Jan 2024 - 30 Sep 2026.
     - Month position: "Last 5 days" (the final 5 calendar days of the month),
       "First 5 days", or "Mid-month".
     - Quarter-end months: March, June, September, December. Financial
       year-end month: March.
     - Orders per day are normalised by the number of calendar days in each
       bucket over the period, so longer buckets do not look busier.
     - Discount: weighted = discount amount / gross value (quantity *
       unit_price), orders not Cancelled or Returned; NULL discount = 0 %.
     - Significance: two-sample z-test on line-level discount_percent,
       z = (mean1 - mean2) / SQRT(var1 / n1 + var2 / n2). |z| >= 2 flagged.
     - Cancellation and return rates use closed orders (Delivered, Cancelled,
       Returned). Late = final delivery after the promised date.
   ============================================================================= */

DECLARE period_start DATE  DEFAULT DATE '2024-01-01';
DECLARE period_end   DATE  DEFAULT DATE '2026-09-30';
DECLARE end_days     INT64 DEFAULT 5;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per order with its position in the month, quarter and year
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.order_period_position` AS
WITH order_value AS (
    SELECT
        order_id,
        COUNT(*)                                                         AS lines,
        SUM(quantity * unit_price)                                       AS gross_value,
        SUM(quantity * unit_price * IFNULL(discount_percent, 0) / 100)   AS discount_amount
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
final_delivery AS (
    SELECT order_id, MAX(delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.order_date,
    o.order_status,
    o.employee_id,
    DATE_DIFF(LAST_DAY(o.order_date), o.order_date, DAY) + 1               AS days_to_month_end,
    CASE
        WHEN DATE_DIFF(LAST_DAY(o.order_date), o.order_date, DAY) < end_days THEN '3. Last 5 days'
        WHEN EXTRACT(DAY FROM o.order_date) <= end_days                     THEN '1. First 5 days'
        ELSE '2. Mid-month'
    END                                                                     AS month_position,
    EXTRACT(MONTH FROM o.order_date) IN (3, 6, 9, 12)                       AS is_quarter_end_month,
    EXTRACT(MONTH FROM o.order_date) = 3                                    AS is_year_end_month,
    v.lines,
    v.gross_value,
    v.discount_amount,
    IF(o.order_status IN ('Delivered', 'Cancelled', 'Returned'), TRUE, FALSE) AS is_closed,
    IF(o.order_status = 'Delivered' AND o.promised_delivery_date IS NOT NULL AND f.final_delivery_date IS NOT NULL,
       f.final_delivery_date > o.promised_delivery_date, NULL)              AS was_late
FROM `sahyadri_b2b.sales_orders` AS o
JOIN order_value                 AS v ON v.order_id = o.order_id
LEFT JOIN final_delivery         AS f ON f.order_id = o.order_id
WHERE o.order_date BETWEEN period_start AND period_end;

-- -----------------------------------------------------------------------------
-- Step 2 · Do orders bunch at month-end? Orders and value per calendar day
-- -----------------------------------------------------------------------------
WITH calendar AS (
    SELECT
        d,
        CASE
            WHEN DATE_DIFF(LAST_DAY(d), d, DAY) < end_days THEN '3. Last 5 days'
            WHEN EXTRACT(DAY FROM d) <= end_days          THEN '1. First 5 days'
            ELSE '2. Mid-month'
        END AS month_position
    FROM UNNEST(GENERATE_DATE_ARRAY(period_start, period_end)) AS d
),
days AS (SELECT month_position, COUNT(*) AS calendar_days FROM calendar GROUP BY month_position)
SELECT
    p.month_position,
    ANY_VALUE(d.calendar_days)                                               AS calendar_days,
    COUNT(*)                                                                 AS orders,
    ROUND(COUNT(*) / ANY_VALUE(d.calendar_days), 2)                          AS orders_per_day,
    ROUND(SUM(p.gross_value) / ANY_VALUE(d.calendar_days), 0)                AS gross_value_per_day,
    ROUND(SUM(p.gross_value) / COUNT(*), 0)                                  AS average_order_gross
FROM `sahyadri_b2b.order_period_position` AS p
JOIN days                                 AS d ON d.month_position = p.month_position
GROUP BY p.month_position
ORDER BY p.month_position;

-- -----------------------------------------------------------------------------
-- Step 3 · Discount, cancellation, return and lateness by month position,
--          separately for ordinary months, quarter-ends and the year-end
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN is_year_end_month    THEN '3. Year-end month (March)'
        WHEN is_quarter_end_month THEN '2. Other quarter-end months'
        ELSE '1. Other months'
    END                                                                       AS month_type,
    month_position,
    COUNT(*)                                                                  AS orders,
    ROUND(100 * SUM(IF(order_status NOT IN ('Cancelled', 'Returned'), discount_amount, 0))
              / SUM(IF(order_status NOT IN ('Cancelled', 'Returned'), gross_value, 0)), 2) AS weighted_discount_pct,
    ROUND(100 * COUNTIF(order_status = 'Cancelled') / COUNTIF(is_closed), 2)  AS cancel_rate_pct,
    ROUND(100 * COUNTIF(order_status = 'Returned')  / COUNTIF(is_closed), 2)  AS return_rate_pct,
    ROUND(100 * COUNTIF(was_late) / COUNTIF(was_late IS NOT NULL), 1)         AS late_rate_pct
FROM `sahyadri_b2b.order_period_position`
GROUP BY month_type, month_position
ORDER BY month_type, month_position;

-- -----------------------------------------------------------------------------
-- Step 4 · Is the period-end discount difference larger than chance?
--          Line-level discount_percent, last 5 days vs the rest of the month
-- -----------------------------------------------------------------------------
WITH lines AS (
    SELECT
        p.month_position = '3. Last 5 days'    AS is_period_end,
        p.is_quarter_end_month,
        IFNULL(i.discount_percent, 0)          AS discount_percent
    FROM `sahyadri_b2b.sales_order_items`      AS i
    JOIN `sahyadri_b2b.order_period_position`  AS p ON p.order_id = i.order_id
    WHERE p.order_status NOT IN ('Cancelled', 'Returned')
),
stats AS (
    SELECT
        scope,
        AVG(IF(is_period_end, discount_percent, NULL))           AS mean_end,
        AVG(IF(NOT is_period_end, discount_percent, NULL))       AS mean_rest,
        VAR_SAMP(IF(is_period_end, discount_percent, NULL))      AS var_end,
        VAR_SAMP(IF(NOT is_period_end, discount_percent, NULL))  AS var_rest,
        COUNTIF(is_period_end)                                   AS n_end,
        COUNTIF(NOT is_period_end)                               AS n_rest
    FROM (
        SELECT 'All months' AS scope, * FROM lines
        UNION ALL
        SELECT 'Quarter-end months', * FROM lines WHERE is_quarter_end_month
        UNION ALL
        SELECT 'Other months', * FROM lines WHERE NOT is_quarter_end_month
    )
    GROUP BY scope
)
SELECT
    scope,
    n_end,
    n_rest,
    ROUND(mean_end, 2)                                                 AS mean_discount_last_5_days,
    ROUND(mean_rest, 2)                                                AS mean_discount_rest_of_month,
    ROUND(mean_end - mean_rest, 2)                                     AS difference_points,
    ROUND((mean_end - mean_rest) / SQRT(var_end / n_end + var_rest / n_rest), 2) AS z_score
FROM stats
ORDER BY scope;

-- Cancellation rate, last 5 days vs the rest of the month (two-proportion z-test)
WITH closed AS (
    SELECT
        month_position = '3. Last 5 days'      AS is_period_end,
        is_quarter_end_month,
        order_status = 'Cancelled'             AS is_cancelled
    FROM `sahyadri_b2b.order_period_position`
    WHERE is_closed
),
scoped AS (
    SELECT 'All months' AS scope, * FROM closed
    UNION ALL
    SELECT 'Quarter-end months', * FROM closed WHERE is_quarter_end_month
    UNION ALL
    SELECT 'Other months', * FROM closed WHERE NOT is_quarter_end_month
),
counts AS (
    SELECT
        scope,
        COUNTIF(is_period_end)                         AS n_end,
        COUNTIF(NOT is_period_end)                     AS n_rest,
        COUNTIF(is_period_end AND is_cancelled)        AS c_end,
        COUNTIF(NOT is_period_end AND is_cancelled)    AS c_rest
    FROM scoped
    GROUP BY scope
)
SELECT
    scope,
    n_end,
    n_rest,
    ROUND(100 * c_end  / n_end,  2)                                    AS cancel_rate_last_5_days_pct,
    ROUND(100 * c_rest / n_rest, 2)                                    AS cancel_rate_rest_of_month_pct,
    ROUND((c_end / n_end - c_rest / n_rest)
          / SQRT((c_end + c_rest) / (n_end + n_rest)
                 * (1 - (c_end + c_rest) / (n_end + n_rest))
                 * (1 / n_end + 1 / n_rest)), 2)                       AS z_score
FROM counts
ORDER BY scope;

-- The largest orders placed in the last 5 days of the financial year
SELECT
    p.order_id,
    o.customer_id,
    c.customer_name,
    p.order_date,
    ROUND(p.gross_value, 2)                                AS gross_value,
    ROUND(100 * p.discount_amount / p.gross_value, 2)      AS discount_pct,
    ROUND(p.discount_amount, 2)                            AS discount_amount
FROM `sahyadri_b2b.order_period_position` AS p
JOIN `sahyadri_b2b.sales_orders`          AS o ON o.order_id    = p.order_id
JOIN `sahyadri_b2b.customers`             AS c ON c.customer_id = o.customer_id
WHERE p.is_year_end_month
  AND p.month_position = '3. Last 5 days'
  AND p.order_status NOT IN ('Cancelled', 'Returned')
ORDER BY p.gross_value DESC
LIMIT 5;

-- -----------------------------------------------------------------------------
-- Step 5 · What does the extra period-end discount cost?
--          (period-end weighted rate - rest-of-month weighted rate) x period-end gross
-- -----------------------------------------------------------------------------
WITH rates AS (
    SELECT
        EXTRACT(YEAR FROM order_date)                                                     AS order_year,
        SUM(IF(month_position = '3. Last 5 days',  discount_amount, 0))                    AS end_discount,
        SUM(IF(month_position = '3. Last 5 days',  gross_value,     0))                    AS end_gross,
        SUM(IF(month_position <> '3. Last 5 days', discount_amount, 0))                    AS rest_discount,
        SUM(IF(month_position <> '3. Last 5 days', gross_value,     0))                    AS rest_gross
    FROM `sahyadri_b2b.order_period_position`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY order_year
)
SELECT
    CAST(order_year AS STRING)                                                AS order_year,
    ROUND(100 * end_discount  / end_gross,  2)                                AS last_5_days_discount_pct,
    ROUND(100 * rest_discount / rest_gross, 2)                                AS rest_of_month_discount_pct,
    ROUND(end_gross, 2)                                                       AS last_5_days_gross,
    ROUND((end_discount / end_gross - rest_discount / rest_gross) * end_gross, 2) AS extra_discount_cost
FROM rates
ORDER BY order_year;
