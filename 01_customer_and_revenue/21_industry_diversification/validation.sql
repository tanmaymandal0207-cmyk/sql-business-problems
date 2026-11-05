/* =============================================================================
   Case study · Industry diversification — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

WITH d AS (SELECT * FROM `sahyadri_b2b.id_months`),
     c AS (SELECT * FROM `sahyadri_b2b.id_company`),
     s AS (SELECT * FROM `sahyadri_b2b.id_shuffles`),
     k AS (SELECT * FROM `sahyadri_b2b.id_contribution`),

src AS (
    SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN DATE '2024-01-01' AND DATE '2026-09-30'
),
industries AS (
    SELECT COUNT(DISTINCT IFNULL(industry, 'Unknown')) AS n FROM `sahyadri_b2b.customers`
),
fit AS (
    SELECT industry, SUM(swing) AS swing_sum, CORR(swing, t) AS r FROM d GROUP BY industry
),
summed AS (
    SELECT t, SUM(swing) AS swing, SUM(revenue) AS revenue FROM d GROUP BY t
),
pairs AS (
    SELECT COUNT(*) AS n FROM (SELECT DISTINCT industry FROM d) AS a JOIN (SELECT DISTINCT industry FROM d) AS b ON a.industry < b.industry
),

checks AS (
    SELECT '01. One row per industry per month, revenue = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM d) - (SELECT n FROM industries) * 33)
         + IF(ABS((SELECT SUM(revenue) FROM d) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Swings around each trend sum to zero and are uncorrelated with time', 0,
           (SELECT COUNTIF(ABS(swing_sum) > 1e-3 OR ABS(IFNULL(r, 0)) > 1e-9) FROM fit)
    UNION ALL
    SELECT '03. Company revenue and swing = sum over industries', 0,
           (SELECT COUNTIF(ABS(c.swing - x.swing) > 1e-3 OR ABS(c.revenue - x.revenue) > 1e-3) FROM c JOIN summed AS x USING (t))
         + ABS((SELECT COUNT(*) FROM c) - 33)
    UNION ALL
    SELECT '04. Risk shares add up to 100 %, with and without March', 0,
           IF(ABS((SELECT SUM(risk_share) FROM k) - 1) > 1e-9, 1, 0)
         + IF(ABS((SELECT SUM(risk_share_without_march) FROM k) - 1) > 1e-9, 1, 0)
    UNION ALL
    SELECT '05. Revenue shares add up to 100 %', 0,
           IF(ABS((SELECT SUM(revenue_share) FROM k) - 1) > 1e-12, 1, 0)
    UNION ALL
    SELECT '06. 500 rearrangements, each with a positive company standard deviation', 0,
           ABS((SELECT COUNT(*) FROM s) - 500) + (SELECT COUNTIF(sd_all_months <= 0 OR sd_without_march <= 0) FROM s)
    UNION ALL
    SELECT '07. Sum of industry standard deviations exceeds the company standard deviation', 0,
           IF((SELECT SUM(sd) FROM (SELECT STDDEV_POP(swing) AS sd FROM d GROUP BY industry)) < (SELECT STDDEV_POP(swing) FROM c), 1, 0)
    UNION ALL
    SELECT '08. Industry pairs = n (n - 1) / 2', 0,
           ABS((SELECT n FROM pairs) - (SELECT n * (n - 1) / 2 FROM industries))
    UNION ALL
    SELECT '09. Exactly three March months', 0,
           ABS((SELECT COUNTIF(is_march) FROM c) - 3)
    UNION ALL
    SELECT '10. Risk share = covariance with the company swing / its variance (recount)', 0,
           (SELECT COUNTIF(ABS(k.risk_share - x.cv / (SELECT VAR_POP(swing) FROM c)) > 1e-9) FROM k
              JOIN (SELECT d.industry, COVAR_POP(d.swing, c.swing) AS cv FROM d JOIN c USING (t) GROUP BY d.industry) AS x USING (industry))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
