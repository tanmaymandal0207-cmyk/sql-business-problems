/* =============================================================================
   Case study · Logistic regression churn model, trained in SQL
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script with a
              WHILE loop: run it as one script)

   BUSINESS PROBLEM
   The customer health score study replaced a seven-signal score with a
   simple "activity score" (the average percentile of recency, order
   frequency and category breadth). The CRM team now asks whether a fitted
   statistical model would do better, and wants it built where the data
   lives, without exporting to another tool:
     1. Can a logistic regression be trained inside the warehouse?
     2. Which signals carry weight once they are fitted together?
     3. Does the fitted model rank churners better than the activity score
        on a period it has not seen?
     4. Are its probabilities trustworthy enough to forecast how many
        customers will be lost?

   METHOD
     - Customers active in the 12 months before a quarter-end snapshot.
       Churned = no order (not Cancelled or Returned) in the next 12 months.
     - Training snapshots: 31 Dec 2024, 31 Mar 2025, 30 Jun 2025.
       Test snapshot: 30 Sep 2025. Scoring snapshot: 30 Sep 2026.
     - Features, all known at the snapshot (12-month look-back):
         x1 LN(1 + days since last order)   x2 LN(orders)
         x3 product categories bought       x4 share of revenue in the last 6 months
         x5 LN(revenue)                     x6 share of orders cancelled or returned
       Each standardised with the training mean and standard deviation.
     - Logistic regression: P(churn) = 1 / (1 + EXP(-(b0 + SUM bj xj))),
       fitted by batch gradient descent on the average log-loss:
       bj <- bj - learning_rate x AVG((p - y) x xj), 600 iterations,
       learning rate 2.0, in a BigQuery WHILE loop (about 600 short
       queries: allow several minutes).
     - Activity score: average PERCENT_RANK of recency (reversed), orders and
       categories within each snapshot; lower = more likely to churn.
     - AUC (Mann-Whitney, average ranks) on the test snapshot; calibration =
       predicted against actual churners by risk band.
   ============================================================================= */

DECLARE learning_rate FLOAT64 DEFAULT 2.0;
DECLARE max_iter      INT64   DEFAULT 600;
DECLARE iter          INT64   DEFAULT 0;

-- -----------------------------------------------------------------------------
-- Step 1 · Point-in-time features and outcomes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.lr_features` AS
WITH snaps AS (
              SELECT DATE '2024-12-31' AS snapshot_date, 'Train' AS sample
    UNION ALL SELECT DATE '2025-03-31', 'Train'
    UNION ALL SELECT DATE '2025-06-30', 'Train'
    UNION ALL SELECT DATE '2025-09-30', 'Test'
    UNION ALL SELECT DATE '2026-09-30', 'Score'
),
orders AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           o.order_status NOT IN ('Cancelled', 'Returned')                              AS is_valid,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    GROUP BY o.order_id, o.customer_id, o.order_date, o.order_status
),
cats AS (
    SELECT DISTINCT o.customer_id, o.order_date, p.category_id
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
history AS (
    SELECT s.snapshot_date, s.sample, o.customer_id,
           MAX(IF(o.is_valid, o.order_date, NULL))                                    AS last_order_date,
           COUNTIF(o.is_valid)                                                        AS orders_12m,
           SUM(IF(o.is_valid, o.revenue, 0))                                          AS revenue_12m,
           SUM(IF(o.is_valid AND o.order_date > DATE_SUB(s.snapshot_date, INTERVAL 182 DAY), o.revenue, 0))
             / SUM(IF(o.is_valid, o.revenue, 0))                                      AS recent_share,
           AVG(IF(o.is_valid, 0, 1))                                                  AS cancel_share
    FROM snaps AS s
    JOIN orders AS o ON o.order_date <= s.snapshot_date AND o.order_date > DATE_SUB(s.snapshot_date, INTERVAL 365 DAY)
    GROUP BY s.snapshot_date, s.sample, o.customer_id
    HAVING COUNTIF(o.is_valid) > 0
),
breadth AS (
    SELECT s.snapshot_date, c.customer_id, COUNT(DISTINCT c.category_id) AS categories_12m
    FROM snaps AS s
    JOIN cats AS c ON c.order_date <= s.snapshot_date AND c.order_date > DATE_SUB(s.snapshot_date, INTERVAL 365 DAY)
    GROUP BY s.snapshot_date, c.customer_id
),
future AS (
    SELECT s.snapshot_date, o.customer_id, COUNTIF(o.is_valid) AS orders_next_12m
    FROM snaps AS s
    JOIN orders AS o ON o.order_date > s.snapshot_date AND o.order_date <= DATE_ADD(s.snapshot_date, INTERVAL 365 DAY)
    GROUP BY s.snapshot_date, o.customer_id
)
SELECT
    h.snapshot_date, h.sample, h.customer_id,
    DATE_DIFF(h.snapshot_date, h.last_order_date, DAY)                               AS recency_days,
    h.orders_12m, h.revenue_12m, b.categories_12m, h.recent_share, h.cancel_share,
    LN(1 + DATE_DIFF(h.snapshot_date, h.last_order_date, DAY))                       AS f1_ln_recency,
    LN(h.orders_12m)                                                                 AS f2_ln_orders,
    b.categories_12m                                                                 AS f3_categories,
    h.recent_share                                                                   AS f4_recent_share,
    LN(h.revenue_12m)                                                                AS f5_ln_revenue,
    h.cancel_share                                                                   AS f6_cancel_share,
    IF(h.sample = 'Score', NULL, IF(IFNULL(f.orders_next_12m, 0) = 0, 1, 0))        AS churned
FROM history AS h
JOIN breadth AS b ON b.snapshot_date = h.snapshot_date AND b.customer_id = h.customer_id
LEFT JOIN future AS f ON f.snapshot_date = h.snapshot_date AND f.customer_id = h.customer_id;

SELECT sample, snapshot_date, COUNT(*) AS customers, SUM(churned) AS churned,
       ROUND(100 * AVG(churned), 1) AS churn_pct
FROM `sahyadri_b2b.lr_features`
GROUP BY sample, snapshot_date
ORDER BY snapshot_date;

-- Standardised design matrix (training mean and standard deviation)
CREATE OR REPLACE TABLE `sahyadri_b2b.lr_scaling` AS
SELECT
    AVG(f1_ln_recency) AS m1, STDDEV_POP(f1_ln_recency) AS s1,
    AVG(f2_ln_orders) AS m2, STDDEV_POP(f2_ln_orders) AS s2,
    AVG(f3_categories) AS m3, STDDEV_POP(f3_categories) AS s3,
    AVG(f4_recent_share) AS m4, STDDEV_POP(f4_recent_share) AS s4,
    AVG(f5_ln_revenue) AS m5, STDDEV_POP(f5_ln_revenue) AS s5,
    AVG(f6_cancel_share) AS m6, STDDEV_POP(f6_cancel_share) AS s6
FROM `sahyadri_b2b.lr_features`
WHERE sample = 'Train';

CREATE OR REPLACE TABLE `sahyadri_b2b.lr_design` AS
SELECT
    f.snapshot_date, f.sample, f.customer_id, f.churned,
    (f.f1_ln_recency - k.m1) / k.s1 AS x1, (f.f2_ln_orders - k.m2) / k.s2 AS x2,
    (f.f3_categories - k.m3) / k.s3 AS x3, (f.f4_recent_share - k.m4) / k.s4 AS x4,
    (f.f5_ln_revenue - k.m5) / k.s5 AS x5, (f.f6_cancel_share - k.m6) / k.s6 AS x6
FROM `sahyadri_b2b.lr_features` AS f
CROSS JOIN `sahyadri_b2b.lr_scaling` AS k;

-- -----------------------------------------------------------------------------
-- Step 2 · Fit the model by gradient descent (BigQuery scripting loop)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.lr_coefficients` AS
SELECT 0 AS iteration,
       CAST(0 AS FLOAT64) AS b0, CAST(0 AS FLOAT64) AS b1, CAST(0 AS FLOAT64) AS b2, CAST(0 AS FLOAT64) AS b3,
       CAST(0 AS FLOAT64) AS b4, CAST(0 AS FLOAT64) AS b5, CAST(0 AS FLOAT64) AS b6,
       CAST(LN(2) AS FLOAT64) AS log_loss;

WHILE iter < max_iter DO
    INSERT INTO `sahyadri_b2b.lr_coefficients`
    WITH cur AS (
        SELECT * FROM `sahyadri_b2b.lr_coefficients` WHERE iteration = iter
    ),
    pred AS (
        SELECT d.*, c.b0, c.b1, c.b2, c.b3, c.b4, c.b5, c.b6,
               1 / (1 + EXP(-(c.b0 + c.b1 * d.x1 + c.b2 * d.x2 + c.b3 * d.x3 + c.b4 * d.x4 + c.b5 * d.x5 + c.b6 * d.x6))) AS p
        FROM `sahyadri_b2b.lr_design` AS d CROSS JOIN cur AS c
        WHERE d.sample = 'Train'
    ),
    upd AS (
        SELECT
            ANY_VALUE(b0) - learning_rate * AVG(p - churned)          AS b0,
            ANY_VALUE(b1) - learning_rate * AVG((p - churned) * x1)   AS b1,
            ANY_VALUE(b2) - learning_rate * AVG((p - churned) * x2)   AS b2,
            ANY_VALUE(b3) - learning_rate * AVG((p - churned) * x3)   AS b3,
            ANY_VALUE(b4) - learning_rate * AVG((p - churned) * x4)   AS b4,
            ANY_VALUE(b5) - learning_rate * AVG((p - churned) * x5)   AS b5,
            ANY_VALUE(b6) - learning_rate * AVG((p - churned) * x6)   AS b6
        FROM pred
    ),
    loss AS (
        SELECT -AVG(d.churned * LN(q) + (1 - d.churned) * LN(1 - q)) AS log_loss
        FROM (
            SELECT d.churned,
                   1 / (1 + EXP(-(u.b0 + u.b1 * d.x1 + u.b2 * d.x2 + u.b3 * d.x3 + u.b4 * d.x4 + u.b5 * d.x5 + u.b6 * d.x6))) AS q
            FROM `sahyadri_b2b.lr_design` AS d CROSS JOIN upd AS u
            WHERE d.sample = 'Train'
        ) AS d
    )
    SELECT iter + 1, u.b0, u.b1, u.b2, u.b3, u.b4, u.b5, u.b6, l.log_loss
    FROM upd AS u CROSS JOIN loss AS l;
    SET iter = iter + 1;
END WHILE;

-- Convergence: training log-loss at selected iterations
SELECT iteration, ROUND(log_loss, 6) AS log_loss
FROM `sahyadri_b2b.lr_coefficients`
WHERE iteration IN (0, 1, 10, 50, 100, 300, 599, 600)
ORDER BY iteration;

-- Final coefficients (per standard deviation of each feature) and odds ratios
WITH fin AS (SELECT * FROM `sahyadri_b2b.lr_coefficients` WHERE iteration = (SELECT MAX(iteration) FROM `sahyadri_b2b.lr_coefficients`))
          SELECT '0. Intercept' AS term, ROUND(b0, 3) AS coefficient, NULL AS odds_ratio_per_sd FROM fin
UNION ALL SELECT '1. Days since last order (log)', ROUND(b1, 3), ROUND(EXP(b1), 2) FROM fin
UNION ALL SELECT '2. Orders (log)',                ROUND(b2, 3), ROUND(EXP(b2), 2) FROM fin
UNION ALL SELECT '3. Categories bought',           ROUND(b3, 3), ROUND(EXP(b3), 2) FROM fin
UNION ALL SELECT '4. Share of revenue in last 6 months', ROUND(b4, 3), ROUND(EXP(b4), 2) FROM fin
UNION ALL SELECT '5. Revenue (log)',               ROUND(b5, 3), ROUND(EXP(b5), 2) FROM fin
UNION ALL SELECT '6. Share of orders cancelled',   ROUND(b6, 3), ROUND(EXP(b6), 2) FROM fin
ORDER BY term;

-- -----------------------------------------------------------------------------
-- Step 3 · Score every customer and compare with the activity score
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.lr_scores` AS
WITH fin AS (SELECT * FROM `sahyadri_b2b.lr_coefficients` WHERE iteration = (SELECT MAX(iteration) FROM `sahyadri_b2b.lr_coefficients`))
SELECT
    d.snapshot_date, d.sample, d.customer_id, d.churned,
    1 / (1 + EXP(-(c.b0 + c.b1 * d.x1 + c.b2 * d.x2 + c.b3 * d.x3 + c.b4 * d.x4 + c.b5 * d.x5 + c.b6 * d.x6))) AS p_churn,
    (100 * PERCENT_RANK() OVER (PARTITION BY d.snapshot_date ORDER BY f.recency_days DESC)
   + 100 * PERCENT_RANK() OVER (PARTITION BY d.snapshot_date ORDER BY f.orders_12m)
   + 100 * PERCENT_RANK() OVER (PARTITION BY d.snapshot_date ORDER BY f.categories_12m)) / 3 AS activity_score,
    f.recency_days
FROM `sahyadri_b2b.lr_design` AS d
CROSS JOIN fin AS c
JOIN `sahyadri_b2b.lr_features` AS f ON f.snapshot_date = d.snapshot_date AND f.customer_id = d.customer_id;

CREATE OR REPLACE TABLE `sahyadri_b2b.lr_auc` AS
WITH long AS (
              SELECT sample, churned, 'Logistic regression (6 features)' AS model, -p_churn AS value FROM `sahyadri_b2b.lr_scores` WHERE churned IS NOT NULL
    UNION ALL SELECT sample, churned, 'Activity score (3 percentiles)',          activity_score    FROM `sahyadri_b2b.lr_scores` WHERE churned IS NOT NULL
    UNION ALL SELECT sample, churned, 'Recency only',                            -recency_days     FROM `sahyadri_b2b.lr_scores` WHERE churned IS NOT NULL
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY sample, model ORDER BY value)
             + (COUNT(*) OVER (PARTITION BY sample, model, value) - 1) / 2 AS avg_rank
    FROM long
)
SELECT
    sample, model,
    COUNTIF(churned = 0) AS retained, COUNTIF(churned = 1) AS churned,
    -- probability that a retained customer scores as healthier than a churned one
    (SUM(IF(churned = 0, avg_rank, 0)) - COUNTIF(churned = 0) * (COUNTIF(churned = 0) + 1) / 2)
      / (COUNTIF(churned = 0) * COUNTIF(churned = 1))                       AS auc
FROM ranked
GROUP BY sample, model;

SELECT sample, model, retained, churned, ROUND(auc, 3) AS auc
FROM `sahyadri_b2b.lr_auc`
ORDER BY sample DESC, auc DESC;

-- Capture in the riskiest fifth on the test snapshot
WITH t AS (SELECT * FROM `sahyadri_b2b.lr_scores` WHERE sample = 'Test'),
r AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY p_churn DESC, customer_id)       AS q_model,
           NTILE(5) OVER (ORDER BY activity_score, customer_id)     AS q_activity
    FROM t
)
SELECT
    COUNT(*)                                                         AS customers,
    SUM(churned)                                                     AS churners,
    COUNTIF(q_model = 1 AND churned = 1)                             AS caught_by_model_top_fifth,
    COUNTIF(q_activity = 1 AND churned = 1)                          AS caught_by_activity_bottom_fifth,
    ROUND(100 * COUNTIF(q_model = 1 AND churned = 1) / SUM(churned), 1)    AS model_capture_pct,
    ROUND(100 * COUNTIF(q_activity = 1 AND churned = 1) / SUM(churned), 1) AS activity_capture_pct
FROM r;

-- -----------------------------------------------------------------------------
-- Step 4 · Calibration on the test snapshot, and the forecast for 2026-27
-- -----------------------------------------------------------------------------
SELECT
    CASE WHEN p_churn < 0.05 THEN '1. Under 5 %'
         WHEN p_churn < 0.15 THEN '2. 5-15 %'
         WHEN p_churn < 0.30 THEN '3. 15-30 %'
         WHEN p_churn < 0.50 THEN '4. 30-50 %'
         ELSE                     '5. 50 %+' END                         AS predicted_risk,
    COUNT(*)                                                             AS customers,
    ROUND(SUM(p_churn), 1)                                               AS predicted_churners,
    SUM(churned)                                                         AS actual_churners
FROM `sahyadri_b2b.lr_scores`
WHERE sample = 'Test'
GROUP BY predicted_risk
ORDER BY predicted_risk;

SELECT
    sample,
    COUNT(*)                                                             AS customers,
    ROUND(SUM(p_churn), 1)                                               AS predicted_churners,
    SUM(churned)                                                         AS actual_churners
FROM `sahyadri_b2b.lr_scores`
GROUP BY sample
ORDER BY sample DESC;

-- Where the test-year shortfall comes from: churn by orders in the last 12 months
SELECT
    f.sample,
    IF(f.orders_12m >= 5, '5+', CAST(f.orders_12m AS STRING))           AS order_band,
    COUNT(*)                                                             AS customers,
    ROUND(100 * AVG(f.churned), 1)                                       AS actual_churn_pct,
    ROUND(100 * AVG(s.p_churn), 1)                                       AS predicted_churn_pct
FROM `sahyadri_b2b.lr_features` AS f
JOIN `sahyadri_b2b.lr_scores` AS s ON s.snapshot_date = f.snapshot_date AND s.customer_id = f.customer_id
WHERE f.sample IN ('Train', 'Test')
GROUP BY f.sample, order_band
ORDER BY f.sample DESC, order_band;

-- Customers at 30 %+ predicted risk today (30 Sep 2026), largest revenue first
SELECT
    c.customer_name, c.customer_segment, ROUND(s.p_churn, 3) AS p_churn,
    f.recency_days, f.orders_12m, f.categories_12m, ROUND(f.revenue_12m / 1e5, 1) AS revenue_12m_lakh
FROM `sahyadri_b2b.lr_scores` AS s
JOIN `sahyadri_b2b.lr_features` AS f ON f.snapshot_date = s.snapshot_date AND f.customer_id = s.customer_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = s.customer_id
WHERE s.sample = 'Score' AND s.p_churn >= 0.3
ORDER BY f.revenue_12m DESC
LIMIT 10;
