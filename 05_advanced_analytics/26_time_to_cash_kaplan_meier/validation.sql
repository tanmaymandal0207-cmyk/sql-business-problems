/* =============================================================================
   Case study · Time to cash with Kaplan-Meier — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of           DATE    DEFAULT DATE '2026-09-30';
DECLARE first_delivery  DATE    DEFAULT DATE '2024-01-01';
DECLARE settled_share   FLOAT64 DEFAULT 0.99;
DECLARE horizon         INT64   DEFAULT 365;

WITH o AS (SELECT * FROM `sahyadri_b2b.tc_orders`),
     c AS (SELECT * FROM `sahyadri_b2b.tc_curves`),
     sm AS (SELECT * FROM `sahyadri_b2b.tc_summary`),

src AS (
    SELECT COUNT(*) AS n
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN (SELECT order_id, MAX(delivery_date) AS dd FROM `sahyadri_b2b.shipments` GROUP BY order_id
          HAVING COUNT(delivery_date) = COUNT(*)) AS s ON s.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned') AND s.dd BETWEEN first_delivery AND as_of
),
-- payments up to and before the settlement date
pay AS (
    SELECT o.order_id, o.order_value, o.settled, o.settled_on,
           SUM(IF(p.payment_date <= IFNULL(o.settled_on, as_of), p.amount, 0)) AS paid_by,
           SUM(IF(p.payment_date <  IFNULL(o.settled_on, as_of), p.amount, 0)) AS paid_before
    FROM o LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = o.order_id
    GROUP BY o.order_id, o.order_value, o.settled, o.settled_on
),
groups AS (
    SELECT 'Company' AS dimension, 'All' AS grp, days, settled FROM o
    UNION ALL SELECT 'Segment', customer_segment, days, settled FROM o
    UNION ALL SELECT 'Delivery half-year', cohort, days, settled FROM o
),
sizes AS (
    SELECT dimension, grp, COUNT(*) AS n FROM groups GROUP BY dimension, grp
),
-- bounds: censored treated as paid at once (lower) or as never paid (upper)
bounds AS (
    SELECT c.dimension, c.grp, c.t, c.survival,
           COUNTIF(g.days > c.t) / ANY_VALUE(z.n)                                    AS lower_bound,
           1 - COUNTIF(g.settled AND g.days <= c.t) / ANY_VALUE(z.n)                 AS upper_bound
    FROM c
    JOIN groups AS g ON g.dimension = c.dimension AND g.grp = c.grp
    JOIN sizes AS z ON z.dimension = c.dimension AND z.grp = c.grp
    WHERE c.dimension = 'Company'
    GROUP BY c.dimension, c.grp, c.t, c.survival
),
-- restricted mean recounted day by day: sum of S(t) for t = 0 .. horizon - 1
daily_s AS (
    SELECT d.t, MAX(c.survival) AS s
    FROM UNNEST(GENERATE_ARRAY(0, 364)) AS d
    LEFT JOIN (SELECT t, survival, IFNULL(next_t, 100000) AS next_t FROM c WHERE dimension = 'Company') AS c
      ON d.t >= c.t AND d.t < c.next_t
    GROUP BY d.t
),
ordered AS (
    SELECT dimension, grp, t, at_risk, leaving, survival,
           LAG(at_risk) OVER (PARTITION BY dimension, grp ORDER BY t)  AS prev_at_risk,
           LAG(leaving) OVER (PARTITION BY dimension, grp ORDER BY t)  AS prev_leaving,
           LAG(survival) OVER (PARTITION BY dimension, grp ORDER BY t) AS prev_survival
    FROM c
),

checks AS (
    SELECT '01. One row per valid, fully delivered order of the period' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src)) + ABS((SELECT COUNT(*) FROM o) - (SELECT COUNT(DISTINCT order_id) FROM o)) AS actual
    UNION ALL
    SELECT '02. Settled on the first day payments reach 99 %, and never otherwise', 0,
           (SELECT COUNTIF((settled AND (paid_by < settled_share * order_value OR paid_before >= settled_share * order_value))
                           OR (NOT settled AND paid_by >= settled_share * order_value)) FROM pay)
    UNION ALL
    SELECT '03. Days = settlement - delivery (0 if paid before), else as-of - delivery', 0,
           (SELECT COUNTIF(days != IF(settled, GREATEST(DATE_DIFF(settled_on, delivered_on, DAY), 0), DATE_DIFF(as_of, delivered_on, DAY))
                           OR days < 0) FROM o)
    UNION ALL
    SELECT '04. At risk on the first day = group size, leavers add up to it', 0,
           (SELECT COUNT(*) FROM (SELECT dimension, grp, MAX(at_risk) AS first_risk, SUM(leaving) AS total FROM c GROUP BY dimension, grp) AS x
              JOIN sizes AS z USING (dimension, grp) WHERE x.first_risk != z.n OR x.total != z.n)
    UNION ALL
    SELECT '05. At risk falls by the previous day''s leavers', 0,
           (SELECT COUNTIF(prev_at_risk IS NOT NULL AND at_risk != prev_at_risk - prev_leaving) FROM ordered)
    UNION ALL
    SELECT '06. Survival never rises and stays between 0 and 1', 0,
           (SELECT COUNTIF(survival > 1 + 1e-12 OR survival < 0 OR (prev_survival IS NOT NULL AND survival > prev_survival + 1e-12)) FROM ordered)
    UNION ALL
    SELECT '07. Kaplan-Meier lies between the censored-as-paid and never-paid bounds', 0,
           (SELECT COUNTIF(survival < lower_bound - 1e-12 OR survival > upper_bound + 1e-12) FROM bounds)
    UNION ALL
    SELECT '08. Segment and half-year groups add up to the company', 0,
           (SELECT COUNT(*) FROM (SELECT dimension, SUM(n) AS n FROM sizes GROUP BY dimension) WHERE n != (SELECT COUNT(*) FROM o))
    UNION ALL
    SELECT '09. Median = first day with S <= 0.5', 0,
           (SELECT COUNT(*) FROM sm
              JOIN ordered AS x ON x.dimension = sm.dimension AND x.grp = sm.grp AND x.t = sm.km_median
             WHERE x.survival > 0.5 OR IFNULL(x.prev_survival, 1) <= 0.5)
    UNION ALL
    SELECT '10. Restricted mean = sum of daily S(t) over the first 365 days', 0,
           IF(ABS((SELECT km_restricted_mean FROM sm WHERE dimension = 'Company') - (SELECT SUM(IFNULL(s, 1)) FROM daily_s)) > 1e-6, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
