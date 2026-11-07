/* =============================================================================
   Case study · Are silent customers lost? A "buy till you die" test of
   customer dropout
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The churn early-warning report flags any customer who has been silent
   for more than twice their usual ordering gap, and sales spends a day a
   month calling them. The sales head suspects most of them were never
   leaving. The analytics lead proposes the standard model of
   non-contractual customers, BG/NBD ("buy till you die"): each customer
   orders at their own random rate, and after any order may drop out for
   good. Fitting it answers:
     1. Is there any evidence that customers drop out for good, or do they
        just order at random intervals?
     2. How well does the fitted model predict who orders next quarter,
        and how many orders, against a naive run-rate?
     3. Do customers flagged as silent actually come back?
     4. Which customers should sales call: the silent ones, or another
        list?

   METHOD
     - Valid orders (not Cancelled or Returned). A purchase = a distinct
       order day per customer. Calibration: from each customer's first
       order to 30 June 2026; holdout: July - September 2026 (92 days).
       Time in weeks.
     - Per customer: x = repeat purchases, t_x = week of the last purchase
       after the first, T = weeks from the first purchase to 30 June 2026.
     - BG/NBD log-likelihood (Fader, Hardie and Lee, 2005) without gamma
       functions, because Gamma(r + x) / Gamma(r) = PRODUCT(r + k) and
       B(a, b + x) / B(a, b) = PRODUCT((b + k) / (a + b + k)), k = 0 .. x-1:
         LL = SUM_k n_k [ln(r + k) + ln(b + k) - ln(a + b + k)]
              + SUM_i [ r ln(alpha) - (r + x) ln(alpha + T)
                        + ln(1 + [x > 0] a/(b + x - 1) ((alpha + T)/(alpha + t_x))^(r + x)) ]
       with n_k = customers with x > k. The last term is computed in logs
       (log-sum-exp) to avoid overflow.
     - Dropout tested by profile likelihood: the mean dropout chance per
       order, m = a / (a + b), held at 0.05 % - 5 % (a = 0.5 - 5,
       b = a (1 - m) / m), against no dropout at all (the NBD model,
       LL = SUM_k n_k ln(r + k) + SUM_i [r ln(alpha) - (r + x) ln(alpha + T)]).
       r and alpha by grid search (two stages for the NBD).
     - NBD predictions for a window of t weeks:
         expected purchases = (r + x) / (alpha + T) x t
         P(at least one)    = 1 - ((alpha + T) / (alpha + T + t))^(r + x)
       Naive run-rate = x / T x t.
     - Silent: at least 3 repeat purchases and weeks since the last
       purchase (T - t_x) above twice the customer's average gap (t_x / x),
       the early-warning rule.
   ============================================================================= */

DECLARE calibration_end DATE    DEFAULT DATE '2026-06-30';
DECLARE holdout_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE holdout_weeks   FLOAT64 DEFAULT 92 / 7;

-- -----------------------------------------------------------------------------
-- Step 1 · Customer purchase histories
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.bt_customers` AS
WITH days AS (
    SELECT DISTINCT customer_id, order_date
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned') AND order_date <= holdout_end
),
calibration AS (
    SELECT customer_id,
           COUNT(*) - 1                                                               AS x,
           DATE_DIFF(MAX(order_date), MIN(order_date), DAY) / 7                       AS t_x,
           DATE_DIFF(calibration_end, MIN(order_date), DAY) / 7                       AS t_cal,
           MAX(order_date)                                                            AS last_purchase
    FROM days WHERE order_date <= calibration_end
    GROUP BY customer_id
),
holdout AS (
    SELECT customer_id, COUNT(*) AS y FROM days WHERE order_date > calibration_end GROUP BY customer_id
)
SELECT c.*, IFNULL(h.y, 0) AS y
FROM calibration AS c LEFT JOIN holdout AS h USING (customer_id);

-- Customers with more than k repeat purchases, k = 0 .. max(x) - 1
CREATE OR REPLACE TABLE `sahyadri_b2b.bt_kcounts` AS
SELECT k, COUNTIF(c.x > k) AS n_k
FROM UNNEST(GENERATE_ARRAY(0, 300)) AS k
CROSS JOIN `sahyadri_b2b.bt_customers` AS c
GROUP BY k
HAVING COUNTIF(c.x > k) > 0;

SELECT
    COUNT(*)                                                                          AS customers,
    COUNTIF(x = 0)                                                                    AS one_purchase_only,
    ROUND(AVG(x), 1)                                                                  AS average_repeat_purchases,
    MAX(x)                                                                            AS most_repeat_purchases,
    ROUND(AVG(t_cal), 1)                                                              AS average_weeks_observed,
    SUM(y)                                                                            AS holdout_purchases,
    COUNTIF(y > 0)                                                                    AS holdout_buyers
FROM `sahyadri_b2b.bt_customers`;

-- -----------------------------------------------------------------------------
-- Step 2 · Fit: no dropout (NBD) against dropout (BG/NBD) by profile likelihood
-- -----------------------------------------------------------------------------
-- NBD (no dropout), stage 1: coarse grid
CREATE OR REPLACE TABLE `sahyadri_b2b.bt_nbd_grid` AS
WITH grid AS (
    SELECT r, alpha
    FROM UNNEST(GENERATE_ARRAY(0.2, 1.5, 0.1)) AS r
    CROSS JOIN UNNEST(GENERATE_ARRAY(1.0, 10.0, 0.5)) AS alpha
),
k_term AS (
    SELECT g.r, g.alpha, SUM(kc.n_k * LN(g.r + kc.k)) AS kt
    FROM grid AS g CROSS JOIN `sahyadri_b2b.bt_kcounts` AS kc
    GROUP BY g.r, g.alpha
),
c_term AS (
    SELECT g.r, g.alpha, SUM(g.r * LN(g.alpha) - (g.r + c.x) * LN(g.alpha + c.t_cal)) AS ct
    FROM grid AS g CROSS JOIN `sahyadri_b2b.bt_customers` AS c
    GROUP BY g.r, g.alpha
)
SELECT 1 AS stage, r, alpha, kt + ct AS ll FROM k_term JOIN c_term USING (r, alpha);

-- NBD, stage 2: fine grid around the stage-1 best
INSERT INTO `sahyadri_b2b.bt_nbd_grid`
WITH best AS (
    SELECT r, alpha FROM `sahyadri_b2b.bt_nbd_grid` WHERE stage = 1 ORDER BY ll DESC LIMIT 1
),
grid AS (
    SELECT ROUND(b.r + dr, 4) AS r, ROUND(b.alpha + da, 4) AS alpha
    FROM best AS b
    CROSS JOIN UNNEST(GENERATE_ARRAY(-0.1, 0.1, 0.01)) AS dr
    CROSS JOIN UNNEST(GENERATE_ARRAY(-0.5, 0.5, 0.05)) AS da
),
k_term AS (
    SELECT g.r, g.alpha, SUM(kc.n_k * LN(g.r + kc.k)) AS kt
    FROM grid AS g CROSS JOIN `sahyadri_b2b.bt_kcounts` AS kc
    GROUP BY g.r, g.alpha
),
c_term AS (
    SELECT g.r, g.alpha, SUM(g.r * LN(g.alpha) - (g.r + c.x) * LN(g.alpha + c.t_cal)) AS ct
    FROM grid AS g CROSS JOIN `sahyadri_b2b.bt_customers` AS c
    GROUP BY g.r, g.alpha
)
SELECT 2 AS stage, r, alpha, kt + ct AS ll FROM k_term JOIN c_term USING (r, alpha);

CREATE OR REPLACE TABLE `sahyadri_b2b.bt_nbd` AS
SELECT r, alpha, ll FROM `sahyadri_b2b.bt_nbd_grid` ORDER BY ll DESC LIMIT 1;

-- BG/NBD profile: for each mean dropout chance m, the best fit over a, r and alpha
CREATE OR REPLACE TABLE `sahyadri_b2b.bt_profile` AS
WITH grid AS (
    SELECT m, a, a * (1 - m) / m AS b, r, alpha
    FROM UNNEST([0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05]) AS m
    CROSS JOIN UNNEST([0.5, 1.0, 2.0, 5.0]) AS a
    CROSS JOIN UNNEST(GENERATE_ARRAY(0.2, 1.5, 0.1)) AS r
    CROSS JOIN UNNEST(GENERATE_ARRAY(1.0, 10.0, 0.5)) AS alpha
),
k_term AS (
    SELECT g.m, g.a, g.r, g.alpha,
           SUM(kc.n_k * (LN(g.r + kc.k) + LN(g.b + kc.k) - LN(g.a + g.b + kc.k)))     AS kt
    FROM grid AS g CROSS JOIN `sahyadri_b2b.bt_kcounts` AS kc
    GROUP BY g.m, g.a, g.r, g.alpha
),
c_term AS (
    SELECT m, a, r, alpha,
           SUM(r * LN(alpha) - (r + x) * LN(alpha + t_cal)
               -- ln(1 + exp(c)) computed stably; c = -inf (no term) when x = 0
               + IF(x > 0, GREATEST(c, 0) + LN(1 + EXP(-ABS(c))), 0))                AS ct
    FROM (
        SELECT g.*, cu.x, cu.t_cal,
               IF(cu.x > 0, LN(g.a / (g.b + cu.x - 1)) + (g.r + cu.x) * (LN(g.alpha + cu.t_cal) - LN(g.alpha + cu.t_x)), NULL) AS c
        FROM grid AS g CROSS JOIN `sahyadri_b2b.bt_customers` AS cu
    )
    GROUP BY m, a, r, alpha
)
SELECT m, a, r, alpha, kt + ct AS ll FROM k_term JOIN c_term USING (m, a, r, alpha);

-- Likelihood against the mean dropout chance (higher = better fit)
WITH best_per_m AS (
    SELECT m, ARRAY_AGG(STRUCT(a, r, alpha, ll) ORDER BY ll DESC LIMIT 1)[OFFSET(0)] AS best
    FROM `sahyadri_b2b.bt_profile` GROUP BY m
)
SELECT 'No dropout (NBD)' AS model, 0 AS mean_dropout_per_purchase,
       NULL AS a, ROUND(r, 2) AS r, ROUND(alpha, 2) AS alpha, ROUND(ll, 1) AS log_likelihood, 0.0 AS below_nbd
FROM `sahyadri_b2b.bt_nbd`
UNION ALL
SELECT 'BG/NBD', p.m, p.best.a, ROUND(p.best.r, 2), ROUND(p.best.alpha, 2), ROUND(p.best.ll, 1),
       ROUND(n.ll - p.best.ll, 1)
FROM best_per_m AS p CROSS JOIN `sahyadri_b2b.bt_nbd` AS n
ORDER BY mean_dropout_per_purchase;

-- -----------------------------------------------------------------------------
-- Step 3 · Holdout: who orders in July - September 2026, and how often
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.bt_predictions` AS
SELECT c.*,
       (n.r + c.x) / (n.alpha + c.t_cal) * holdout_weeks                              AS expected_purchases,
       1 - POW((n.alpha + c.t_cal) / (n.alpha + c.t_cal + holdout_weeks), n.r + c.x)   AS p_any_purchase,
       c.x / c.t_cal * holdout_weeks                                                  AS naive_purchases,
       c.x >= 3 AND (c.t_cal - c.t_x) > 2 * c.t_x / c.x                               AS silent
FROM `sahyadri_b2b.bt_customers` AS c CROSS JOIN `sahyadri_b2b.bt_nbd` AS n
WHERE c.t_cal > 0;

SELECT
    COUNT(*)                                                                          AS customers,
    SUM(y)                                                                            AS actual_purchases,
    ROUND(SUM(expected_purchases), 1)                                                 AS nbd_expected_purchases,
    ROUND(SUM(naive_purchases), 1)                                                    AS naive_expected_purchases,
    COUNTIF(y > 0)                                                                    AS actual_buyers,
    ROUND(SUM(p_any_purchase), 1)                                                     AS nbd_expected_buyers,
    ROUND(AVG(ABS(expected_purchases - y)), 3)                                        AS nbd_mean_abs_error,
    ROUND(AVG(ABS(naive_purchases - y)), 3)                                           AS naive_mean_abs_error
FROM `sahyadri_b2b.bt_predictions`;

-- Calibration by predicted chance of buying
SELECT
    CASE WHEN p_any_purchase < 0.25 THEN '1. Below 25 %'
         WHEN p_any_purchase < 0.50 THEN '2. 25 - 50 %'
         WHEN p_any_purchase < 0.75 THEN '3. 50 - 75 %'
         WHEN p_any_purchase < 0.95 THEN '4. 75 - 95 %'
         ELSE '5. 95 % and above' END                                                 AS predicted_chance,
    COUNT(*)                                                                          AS customers,
    ROUND(100 * AVG(p_any_purchase), 1)                                               AS predicted_buyers_pct,
    ROUND(100 * COUNTIF(y > 0) / COUNT(*), 1)                                         AS actual_buyers_pct,
    ROUND(SUM(expected_purchases), 1)                                                 AS predicted_purchases,
    SUM(y)                                                                            AS actual_purchases
FROM `sahyadri_b2b.bt_predictions`
GROUP BY predicted_chance
ORDER BY predicted_chance;

-- -----------------------------------------------------------------------------
-- Step 4 · Do silent customers come back?
-- -----------------------------------------------------------------------------
SELECT
    IF(silent, 'Silent (over twice their usual gap)', 'Not silent')                   AS status_on_30_june,
    COUNT(*)                                                                          AS customers,
    COUNTIF(y > 0)                                                                    AS ordered_july_september,
    ROUND(100 * COUNTIF(y > 0) / COUNT(*), 1)                                         AS ordered_pct,
    ROUND(SUM(p_any_purchase), 1)                                                     AS nbd_expected_buyers,
    SUM(y)                                                                            AS purchases,
    ROUND(SUM(expected_purchases), 1)                                                 AS nbd_expected_purchases
FROM `sahyadri_b2b.bt_predictions`
WHERE x >= 3
GROUP BY status_on_30_june
ORDER BY status_on_30_june DESC;

-- Who to call: as of 30 September 2026, the largest customers least likely to order in the next quarter
WITH now AS (
    SELECT o.customer_id,
           COUNT(DISTINCT o.order_date) - 1                                           AS x,
           DATE_DIFF(MAX(o.order_date), MIN(o.order_date), DAY) / 7                   AS t_x,
           DATE_DIFF(holdout_end, MIN(o.order_date), DAY) / 7                         AS t_cal
    FROM `sahyadri_b2b.sales_orders` AS o
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date <= holdout_end
    GROUP BY o.customer_id
),
value AS (
    SELECT o.customer_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue_12m
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date > DATE_SUB(holdout_end, INTERVAL 12 MONTH)
    GROUP BY o.customer_id
)
SELECT
    cu.customer_name, cu.customer_segment,
    ROUND(v.revenue_12m / 1e5, 1)                                                     AS revenue_last_12_months_lakh,
    ROUND(w.t_cal - w.t_x, 1)                                                         AS weeks_since_last_order,
    ROUND(w.t_x / NULLIF(w.x, 0), 1)                                                  AS usual_gap_weeks,
    ROUND(100 * (1 - POW((n.alpha + w.t_cal) / (n.alpha + w.t_cal + 13), n.r + w.x)), 0) AS chance_of_order_next_13_weeks_pct
FROM now AS w
JOIN value AS v USING (customer_id)
JOIN `sahyadri_b2b.customers` AS cu USING (customer_id)
CROSS JOIN `sahyadri_b2b.bt_nbd` AS n
WHERE v.revenue_12m >= 1000000
ORDER BY chance_of_order_next_13_weeks_pct, v.revenue_12m DESC
LIMIT 10;
