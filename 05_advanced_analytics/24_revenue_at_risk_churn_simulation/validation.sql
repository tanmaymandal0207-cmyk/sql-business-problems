/* =============================================================================
   Case study · Revenue at risk from churn — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE scenarios    INT64 DEFAULT 2000;
DECLARE window_days  INT64 DEFAULT 273;

WITH c AS (SELECT * FROM `sahyadri_b2b.rr_customers`),
     p AS (SELECT * FROM `sahyadri_b2b.rr_probabilities`),
     s AS (SELECT * FROM `sahyadri_b2b.rr_scenarios`),

orders AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, o.order_date
),
recount AS (
    SELECT x.snapshot_date, o.customer_id, COUNT(*) AS n, SUM(o.v) AS v
    FROM (SELECT DISTINCT snapshot_date FROM c) AS x
    JOIN orders AS o ON DATE_DIFF(x.snapshot_date, o.order_date, DAY) BETWEEN 0 AND window_days - 1
    GROUP BY x.snapshot_date, o.customer_id
),
next_year AS (
    SELECT DISTINCT x.snapshot_date, o.customer_id
    FROM (SELECT DISTINCT snapshot_date FROM c) AS x
    JOIN orders AS o ON DATE_DIFF(o.order_date, x.snapshot_date, DAY) BETWEEN 1 AND 365
),
formula AS (
    SELECT c.snapshot_date, SUM(p.p * c.exposure) AS mean_loss, SQRT(SUM(p.p * (1 - p.p) * POW(c.exposure, 2))) AS sd_loss
    FROM c JOIN p ON p.applied_at = c.snapshot_date AND p.band = c.band
    GROUP BY c.snapshot_date
),

checks AS (
    SELECT '01. Customers at each snapshot = recount of orders in the previous 9 months' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM c FULL OUTER JOIN recount AS r USING (snapshot_date, customer_id)
             WHERE c.customer_id IS NULL OR r.customer_id IS NULL OR c.orders != r.n OR ABS(c.exposure - r.v) > 0.01) AS actual
    UNION ALL
    SELECT '02. Churned = no valid order in the next 12 months (known outcomes)', 0,
           (SELECT COUNTIF(c.churned != (n.customer_id IS NULL))
              FROM c LEFT JOIN next_year AS n USING (snapshot_date, customer_id) WHERE c.outcome_known)
    UNION ALL
    SELECT '03. Outcomes known for the 2024 and 2025 snapshots only', 0,
           (SELECT COUNTIF(outcome_known != (snapshot_date < DATE '2026-01-01')) FROM c)
    UNION ALL
    SELECT '04. Band follows the number of orders', 0,
           (SELECT COUNTIF(band != CASE WHEN orders = 1 THEN '1. One order' WHEN orders <= 3 THEN '2. 2-3 orders'
                                        WHEN orders <= 8 THEN '3. 4-8 orders' ELSE '4. 9+ orders' END) FROM c)
    UNION ALL
    SELECT '05. Probability = (churners + 0.5) / (customers + 1), applied one year later', 0,
           (SELECT COUNT(*) FROM p
              JOIN (SELECT snapshot_date, band, COUNT(*) AS n, COUNTIF(churned) AS k FROM c WHERE outcome_known GROUP BY snapshot_date, band) AS t
                ON t.band = p.band AND DATE_DIFF(p.applied_at, t.snapshot_date, DAY) BETWEEN 365 AND 366
             WHERE ABS(p.p - (t.k + 0.5) / (t.n + 1)) > 1e-12)
         + ABS(8 - (SELECT COUNT(*) FROM p))
    UNION ALL
    SELECT '06. 2,000 simulated years for the 2025 and 2026 snapshots', 0,
           (SELECT COUNTIF(k != scenarios) FROM (SELECT snapshot_date, COUNT(DISTINCT b) AS k FROM s GROUP BY snapshot_date))
         + ABS(2 - (SELECT COUNT(DISTINCT snapshot_date) FROM s))
    UNION ALL
    SELECT '07. Loss never exceeds exposure, and the stress loss is never below the base loss', 0,
           (SELECT COUNTIF(revenue_lost > exposure + 0.01 OR revenue_lost_stress < revenue_lost - 0.01 OR revenue_lost < 0) FROM s)
    UNION ALL
    SELECT '08. Scenario exposure = total exposure of the customers', 0,
           (SELECT COUNTIF(ABS(s.exposure - t.e) > 0.01) FROM s
              JOIN (SELECT snapshot_date, SUM(exposure) AS e FROM c GROUP BY snapshot_date) AS t USING (snapshot_date))
    UNION ALL
    SELECT '09. Simulated mean loss within 3 standard errors of the closed-form mean', 0,
           (SELECT COUNTIF(ABS(m.m - f.mean_loss) > 3 * f.sd_loss / SQRT(scenarios))
              FROM (SELECT snapshot_date, AVG(revenue_lost) AS m FROM s GROUP BY snapshot_date) AS m JOIN formula AS f USING (snapshot_date))
    UNION ALL
    SELECT '10. Simulated SD of loss within 10 % of the closed-form SD', 0,
           (SELECT COUNTIF(ABS(m.sd / f.sd_loss - 1) > 0.10)
              FROM (SELECT snapshot_date, STDDEV_POP(revenue_lost) AS sd FROM s GROUP BY snapshot_date) AS m JOIN formula AS f USING (snapshot_date))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
