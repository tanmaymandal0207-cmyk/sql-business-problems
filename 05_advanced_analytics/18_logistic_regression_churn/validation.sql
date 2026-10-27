/* =============================================================================
   Case study · Logistic regression churn model — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE max_iter INT64 DEFAULT 600;

WITH f AS (SELECT * FROM `sahyadri_b2b.lr_features`),
     d AS (SELECT * FROM `sahyadri_b2b.lr_design`),
     c AS (SELECT * FROM `sahyadri_b2b.lr_coefficients`),
     s AS (SELECT * FROM `sahyadri_b2b.lr_scores`),
     a AS (SELECT * FROM `sahyadri_b2b.lr_auc`),

snaps AS (
    SELECT DISTINCT snapshot_date FROM f
),
valid_orders AS (
    SELECT DISTINCT customer_id, order_date FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
),
active AS (
    SELECT n.snapshot_date, COUNT(DISTINCT v.customer_id) AS customers
    FROM snaps AS n
    JOIN valid_orders AS v ON v.order_date <= n.snapshot_date AND v.order_date > DATE_SUB(n.snapshot_date, INTERVAL 365 DAY)
    GROUP BY n.snapshot_date
),
came_back AS (
    SELECT DISTINCT n.snapshot_date, v.customer_id
    FROM snaps AS n
    JOIN valid_orders AS v ON v.order_date > n.snapshot_date AND v.order_date <= DATE_ADD(n.snapshot_date, INTERVAL 365 DAY)
),
fin AS (SELECT * FROM c WHERE iteration = max_iter),
train_pred AS (
    SELECT d.churned, d.x1, d.x2, d.x3, d.x4, d.x5, d.x6,
           1 / (1 + EXP(-(fin.b0 + fin.b1 * d.x1 + fin.b2 * d.x2 + fin.b3 * d.x3 + fin.b4 * d.x4 + fin.b5 * d.x5 + fin.b6 * d.x6))) AS p
    FROM d CROSS JOIN fin
    WHERE d.sample = 'Train'
),
loss_steps AS (
    SELECT iteration, log_loss - LAG(log_loss) OVER (ORDER BY iteration) AS change FROM c
),
pairs AS (
    SELECT AVG(IF(g.p_churn < b.p_churn, 1, IF(g.p_churn = b.p_churn, 0.5, 0)))                    AS auc_model,
           AVG(IF(g.activity_score > b.activity_score, 1, IF(g.activity_score = b.activity_score, 0.5, 0))) AS auc_activity
    FROM s AS g CROSS JOIN s AS b
    WHERE g.sample = 'Test' AND b.sample = 'Test' AND g.churned = 0 AND b.churned = 1
),

checks AS (
    SELECT '01. One row per active customer per snapshot' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM active JOIN (SELECT snapshot_date, COUNT(*) AS n FROM f GROUP BY snapshot_date) AS x USING (snapshot_date)
             WHERE active.customers != x.n)
         + (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(snapshot_date AS STRING), CAST(customer_id AS STRING))) FROM f) AS actual
    UNION ALL
    SELECT '02. Churn label = no valid order in the next 12 months (recount)', 0,
           (SELECT COUNTIF(f.churned != IF(cb.customer_id IS NULL, 1, 0))
              FROM f LEFT JOIN came_back AS cb ON cb.snapshot_date = f.snapshot_date AND cb.customer_id = f.customer_id
             WHERE f.sample != 'Score')
    UNION ALL
    SELECT '03. Training features standardised (mean 0, s.d. 1)', 0,
           (SELECT IF(GREATEST(ABS(AVG(x1)), ABS(AVG(x2)), ABS(AVG(x3)), ABS(AVG(x4)), ABS(AVG(x5)), ABS(AVG(x6)),
                               ABS(STDDEV_POP(x1) - 1), ABS(STDDEV_POP(x2) - 1), ABS(STDDEV_POP(x3) - 1),
                               ABS(STDDEV_POP(x4) - 1), ABS(STDDEV_POP(x5) - 1), ABS(STDDEV_POP(x6) - 1)) < 1e-9, 0, 1)
              FROM d WHERE sample = 'Train')
    UNION ALL
    SELECT '04. One coefficient row per iteration, 0 to 600', 0,
           (SELECT COUNT(*) - (max_iter + 1) + COUNT(*) - COUNT(DISTINCT iteration) + MAX(iteration) - max_iter FROM c)
    UNION ALL
    SELECT '05. Log-loss never rises over the last 500 iterations', 0,
           (SELECT COUNTIF(change > 1e-12) FROM loss_steps WHERE iteration > max_iter - 500)
    UNION ALL
    SELECT '06. Converged: every gradient component below 0.0001', 0,
           (SELECT IF(GREATEST(ABS(AVG(p - churned)), ABS(AVG((p - churned) * x1)), ABS(AVG((p - churned) * x2)),
                               ABS(AVG((p - churned) * x3)), ABS(AVG((p - churned) * x4)), ABS(AVG((p - churned) * x5)),
                               ABS(AVG((p - churned) * x6))) < 0.0001, 0, 1) FROM train_pred)
    UNION ALL
    SELECT '07. Predicted churners = actual churners on training data (within 0.1)', 0,
           (SELECT IF(ABS(SUM(p) - SUM(churned)) < 0.1, 0, 1) FROM train_pred)
    UNION ALL
    SELECT '08. Final log-loss = recount from the fitted probabilities', 0,
           (SELECT IF(ABS((SELECT log_loss FROM fin) - (-AVG(churned * LN(p) + (1 - churned) * LN(1 - p)))) < 1e-9, 0, 1) FROM train_pred)
    UNION ALL
    SELECT '09. Test AUC (model) = brute-force pair count', 0,
           (SELECT COUNTIF(ABS(a.auc - p.auc_model) > 1e-9) FROM a CROSS JOIN pairs AS p
             WHERE a.sample = 'Test' AND a.model LIKE 'Logistic%')
    UNION ALL
    SELECT '10. Test AUC (activity score) = brute-force pair count', 0,
           (SELECT COUNTIF(ABS(a.auc - p.auc_activity) > 1e-9) FROM a CROSS JOIN pairs AS p
             WHERE a.sample = 'Test' AND a.model LIKE 'Activity%')
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
