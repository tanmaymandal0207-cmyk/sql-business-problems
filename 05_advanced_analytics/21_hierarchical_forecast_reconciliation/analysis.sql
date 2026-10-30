/* =============================================================================
   Case study · Hierarchical forecasting: forecast the total, the categories, or both?
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   From next year each category manager will own a monthly revenue
   forecast for their category, and finance wants the ten category
   forecasts to add up to the company forecast. Two approaches are
   proposed: each manager forecasts the category and finance adds them up
   (bottom-up), or finance forecasts the total and splits it by recent
   category shares (top-down). The planning lead asks:
     1. Which approach forecasts the company total better?
     2. Which forecasts the categories better?
     3. How much less accurate is a category forecast than the total?
     4. Does any category deserve its own model?

   METHOD
     - Monthly net revenue of valid orders (not Cancelled or Returned) for
       the 10 categories and the total, January 2024 - September 2026.
     - Base model for every series: simple exponential smoothing,
       F(t) = alpha x y(t-1) + (1 - alpha) x F(t-1), F(2) = y(1), written in
       closed form as a weighted sum of earlier months. Alpha (0.1 - 0.9)
       is chosen per series on 2024 (minimum mean absolute error for
       February - December 2024) and then fixed.
     - Evaluation: one-month-ahead forecasts for January 2025 -
       September 2026 (21 months), never using the target month.
         Bottom-up   - category = its own forecast; total = sum of categories
         Top-down    - total = its own forecast; category = total x the
                       category's share of the previous 12 months
         Combined    - average of bottom-up and top-down (still adds up)
         Naive       - last month's actual (benchmark)
     - Accuracy: total - MAPE; categories - WAPE = SUM |error| / SUM actual.
   ============================================================================= */

DECLARE start_month  DATE  DEFAULT DATE '2024-01-01';
DECLARE end_month    DATE  DEFAULT DATE '2026-09-01';
DECLARE fit_last_t   INT64 DEFAULT 12;     -- alpha chosen on months 2-12 (2024)
DECLARE share_months INT64 DEFAULT 12;

-- -----------------------------------------------------------------------------
-- Step 1 · Monthly series: 10 categories and the total
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.hf_series` AS
WITH months AS (
    SELECT m AS month, ROW_NUMBER() OVER (ORDER BY m) AS t
    FROM UNNEST(GENERATE_DATE_ARRAY(start_month, end_month, INTERVAL 1 MONTH)) AS m
),
cats AS (
    SELECT category_name AS series FROM `sahyadri_b2b.product_categories`
),
revenue AS (
    SELECT DATE_TRUNC(o.order_date, MONTH) AS month, pc.category_name AS series,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY month, series
),
by_category AS (
    SELECT c.series, m.month, m.t, IFNULL(r.revenue, 0) AS revenue, FALSE AS is_total
    FROM months AS m
    CROSS JOIN cats AS c
    LEFT JOIN revenue AS r ON r.month = m.month AND r.series = c.series
)
SELECT * FROM by_category
UNION ALL
SELECT 'Total', month, t, SUM(revenue), TRUE FROM by_category GROUP BY month, t;

SELECT
    series,
    ROUND(SUM(revenue) / 1e7, 2)                                           AS revenue_crore,
    ROUND(100 * SUM(revenue) / SUM(SUM(IF(is_total, 0, revenue))) OVER (), 1) AS share_pct,
    ROUND(STDDEV_POP(revenue) / AVG(revenue), 2)                           AS monthly_cv
FROM `sahyadri_b2b.hf_series`
GROUP BY series
ORDER BY revenue_crore DESC;

-- -----------------------------------------------------------------------------
-- Step 2 · Exponential smoothing for every series and alpha (closed form)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.hf_ses` AS
WITH alphas AS (
    SELECT a / 10 AS alpha FROM UNNEST(GENERATE_ARRAY(1, 9)) AS a
),
first_value AS (
    SELECT series, revenue AS y1 FROM `sahyadri_b2b.hf_series` WHERE t = 1
)
SELECT
    s.series, al.alpha, s.t, s.month, s.revenue AS actual,
    -- F(t) = sum over u < t of alpha (1 - alpha)^(t - 1 - u) y(u)  +  (1 - alpha)^(t - 1) y(1)
    SUM(al.alpha * POW(1 - al.alpha, s.t - 1 - u.t) * u.revenue) + POW(1 - al.alpha, s.t - 1) * ANY_VALUE(f.y1) AS forecast
FROM `sahyadri_b2b.hf_series` AS s
CROSS JOIN alphas AS al
JOIN `sahyadri_b2b.hf_series` AS u ON u.series = s.series AND u.t < s.t
JOIN first_value AS f ON f.series = s.series
WHERE s.t >= 2
GROUP BY s.series, al.alpha, s.t, s.month, s.revenue;

CREATE OR REPLACE TABLE `sahyadri_b2b.hf_alpha` AS
SELECT series, alpha, mae_2024
FROM (
    SELECT series, alpha, AVG(ABS(forecast - actual)) AS mae_2024,
           ROW_NUMBER() OVER (PARTITION BY series ORDER BY AVG(ABS(forecast - actual)), alpha) AS rk
    FROM `sahyadri_b2b.hf_ses`
    WHERE t <= fit_last_t
    GROUP BY series, alpha
)
WHERE rk = 1;

-- -----------------------------------------------------------------------------
-- Step 3 · Bottom-up, top-down, combined and naive forecasts (2025 - 2026)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.hf_forecasts` AS
WITH own AS (
    SELECT f.series, f.t, f.month, f.actual, f.forecast
    FROM `sahyadri_b2b.hf_ses` AS f
    JOIN `sahyadri_b2b.hf_alpha` AS a ON a.series = f.series AND a.alpha = f.alpha
    WHERE f.t > fit_last_t
),
shares AS (
    -- share of the previous 12 months, known at the forecast origin
    SELECT c.series, c.t,
           SUM(h.revenue) / SUM(tot.revenue) AS share
    FROM `sahyadri_b2b.hf_series` AS c
    JOIN `sahyadri_b2b.hf_series` AS h   ON h.series = c.series AND h.t BETWEEN c.t - share_months AND c.t - 1
    JOIN `sahyadri_b2b.hf_series` AS tot ON tot.series = 'Total' AND tot.t = h.t
    WHERE NOT c.is_total AND c.t > fit_last_t
    GROUP BY c.series, c.t
),
naive AS (
    SELECT series, t + 1 AS t, revenue AS naive FROM `sahyadri_b2b.hf_series`
),
category AS (
    SELECT o.series, o.t, o.month, o.actual,
           o.forecast                                   AS bottom_up,
           sh.share * tot.forecast                      AS top_down,
           (o.forecast + sh.share * tot.forecast) / 2   AS combined,
           n.naive,
           sh.share
    FROM own AS o
    JOIN shares AS sh ON sh.series = o.series AND sh.t = o.t
    JOIN own AS tot ON tot.series = 'Total' AND tot.t = o.t
    JOIN naive AS n ON n.series = o.series AND n.t = o.t
)
SELECT *, FALSE AS is_total FROM category
UNION ALL
SELECT 'Total', c.t, c.month, ANY_VALUE(tot.actual),
       SUM(c.bottom_up), SUM(c.top_down), SUM(c.combined), ANY_VALUE(n.naive), 1.0, TRUE
FROM category AS c
JOIN own AS tot ON tot.series = 'Total' AND tot.t = c.t
JOIN naive AS n ON n.series = 'Total' AND n.t = c.t
GROUP BY c.t, c.month;

SELECT series, alpha, ROUND(mae_2024 / 1e5, 2) AS mae_2024_lakh
FROM `sahyadri_b2b.hf_alpha`
ORDER BY series;

-- -----------------------------------------------------------------------------
-- Step 4 · Accuracy at the total and at category level
-- -----------------------------------------------------------------------------
SELECT
    'Total (MAPE)'                                                                           AS level,
    ROUND(100 * AVG(ABS(bottom_up - actual) / actual), 1)                                    AS bottom_up_pct,
    ROUND(100 * AVG(ABS(top_down  - actual) / actual), 1)                                    AS top_down_pct,
    ROUND(100 * AVG(ABS(combined  - actual) / actual), 1)                                    AS combined_pct,
    ROUND(100 * AVG(ABS(naive     - actual) / actual), 1)                                    AS naive_pct
FROM `sahyadri_b2b.hf_forecasts` WHERE is_total
UNION ALL
SELECT
    'Categories (WAPE)',
    ROUND(100 * SUM(ABS(bottom_up - actual)) / SUM(actual), 1),
    ROUND(100 * SUM(ABS(top_down  - actual)) / SUM(actual), 1),
    ROUND(100 * SUM(ABS(combined  - actual)) / SUM(actual), 1),
    ROUND(100 * SUM(ABS(naive     - actual)) / SUM(actual), 1)
FROM `sahyadri_b2b.hf_forecasts` WHERE NOT is_total
UNION ALL
SELECT
    'Total (WAPE)',
    ROUND(100 * SUM(ABS(bottom_up - actual)) / SUM(actual), 1),
    ROUND(100 * SUM(ABS(top_down  - actual)) / SUM(actual), 1),
    ROUND(100 * SUM(ABS(combined  - actual)) / SUM(actual), 1),
    ROUND(100 * SUM(ABS(naive     - actual)) / SUM(actual), 1)
FROM `sahyadri_b2b.hf_forecasts` WHERE is_total;

-- By category: which approach wins?
SELECT
    f.series,
    ANY_VALUE(a.alpha)                                                          AS own_alpha,
    ROUND(100 * SUM(ABS(f.bottom_up - f.actual)) / SUM(f.actual), 1)            AS bottom_up_wape,
    ROUND(100 * SUM(ABS(f.top_down  - f.actual)) / SUM(f.actual), 1)            AS top_down_wape,
    ROUND(100 * SUM(ABS(f.combined  - f.actual)) / SUM(f.actual), 1)            AS combined_wape,
    ROUND(100 * SUM(ABS(f.naive     - f.actual)) / SUM(f.actual), 1)            AS naive_wape,
    ROUND(100 * MIN(f.share), 1)                                                AS min_share_pct,
    ROUND(100 * MAX(f.share), 1)                                                AS max_share_pct,
    CASE WHEN SUM(ABS(f.top_down - f.actual)) < SUM(ABS(f.bottom_up - f.actual)) THEN 'Top-down' ELSE 'Bottom-up' END AS better
FROM `sahyadri_b2b.hf_forecasts` AS f
JOIN `sahyadri_b2b.hf_alpha` AS a ON a.series = f.series
WHERE NOT f.is_total
GROUP BY f.series
ORDER BY bottom_up_wape;

-- Does top-down win month by month? (category-months where top-down is closer)
SELECT
    COUNT(*)                                                                    AS category_months,
    COUNTIF(ABS(top_down - actual) < ABS(bottom_up - actual))                   AS top_down_closer,
    ROUND(100 * COUNTIF(ABS(top_down - actual) < ABS(bottom_up - actual)) / COUNT(*), 1) AS top_down_closer_pct
FROM `sahyadri_b2b.hf_forecasts`
WHERE NOT is_total;

-- Was the 2024 choice of alpha a good one? Evaluation error at the chosen alpha and at the best alpha in hindsight
WITH eval AS (
    SELECT series, alpha, SUM(ABS(forecast - actual)) / SUM(actual) AS wape
    FROM `sahyadri_b2b.hf_ses`
    WHERE t > fit_last_t
    GROUP BY series, alpha
)
SELECT
    e.series,
    ANY_VALUE(a.alpha)                                                           AS chosen_alpha,
    ROUND(100 * MAX(IF(e.alpha = a.alpha, e.wape, NULL)), 1)                     AS wape_at_chosen,
    ARRAY_AGG(e.alpha ORDER BY e.wape LIMIT 1)[OFFSET(0)]                        AS best_alpha_in_hindsight,
    ROUND(100 * MIN(e.wape), 1)                                                  AS wape_at_best,
    ROUND(100 * MAX(IF(e.alpha = 0.1, e.wape, NULL)), 1)                         AS wape_at_alpha_0_1
FROM eval AS e
JOIN `sahyadri_b2b.hf_alpha` AS a ON a.series = e.series
GROUP BY e.series
ORDER BY e.series;
