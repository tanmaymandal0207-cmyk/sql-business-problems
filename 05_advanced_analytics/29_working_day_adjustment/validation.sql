/* =============================================================================
   Case study · Working-day adjustment — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_day DATE DEFAULT DATE '2024-01-01';
DECLARE last_day  DATE DEFAULT DATE '2026-09-30';
DECLARE train_end DATE DEFAULT DATE '2024-12-31';

WITH dy AS (SELECT * FROM `sahyadri_b2b.wd_days`),
     w AS (SELECT * FROM `sahyadri_b2b.wd_weights`),
     m AS (SELECT * FROM `sahyadri_b2b.wd_months`),

src AS (
    SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN first_day AND last_day
),
weighted AS (
    SELECT dy.month, SUM(w.weight) AS s FROM dy JOIN w USING (weekday) GROUP BY dy.month
),

checks AS (
    SELECT '01. One row per calendar day, revenue = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM dy) - (DATE_DIFF(last_day, first_day, DAY) + 1))
         + ABS((SELECT COUNT(*) FROM dy) - (SELECT COUNT(DISTINCT d) FROM dy))
         + IF(ABS((SELECT SUM(revenue) FROM dy) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Weekday weights average 1 over the 2024 days', 0,
           IF(ABS((SELECT SUM(w.weight * w.days_in_training) / SUM(w.days_in_training) FROM w) - 1) > 1e-9, 1, 0)
    UNION ALL
    SELECT '03. Seven weekdays, trained on the 366 days of 2024 only', 0,
           ABS((SELECT COUNT(*) FROM w) - 7) + ABS((SELECT SUM(days_in_training) FROM w) - 366)
    UNION ALL
    SELECT '04. Trading-day index averages 1 across the 33 months', 0,
           IF(ABS((SELECT AVG(tdi) FROM m) - 1) > 1e-9, 1, 0) + ABS((SELECT COUNT(*) FROM m) - 33)
    UNION ALL
    SELECT '05. Adjusted revenue x trading-day index = revenue', 0,
           (SELECT COUNTIF(ABS(adjusted_revenue * tdi - revenue) > 1e-3) FROM m)
    UNION ALL
    SELECT '06. Revenue change = calendar change + adjusted change (logs)', 0,
           (SELECT COUNTIF(d_ln_revenue IS NOT NULL
                           AND ABS(d_ln_revenue - d_ln_tdi - (LN(adjusted_revenue) - LN(prev_adj))) > 1e-9)
              FROM (SELECT *, LAG(adjusted_revenue) OVER (ORDER BY month) AS prev_adj FROM m))
    UNION ALL
    SELECT '07. Days, Sundays and Saturdays per month = calendar recount', 0,
           (SELECT COUNT(*) FROM m JOIN (SELECT month, COUNT(*) AS n, COUNTIF(weekday = 'Sun') AS sun, COUNTIF(weekday = 'Sat') AS sat FROM dy GROUP BY month) AS x
              USING (month) WHERE m.days != x.n OR m.sundays != x.sun OR m.saturdays != x.sat)
    UNION ALL
    SELECT '08. Weighted days = sum of the weights of the month''s days', 0,
           (SELECT COUNTIF(ABS(m.weighted_days - x.s) > 1e-9) FROM m JOIN weighted AS x USING (month))
    UNION ALL
    SELECT '09. Weights = average weekday revenue / average daily revenue in 2024 (recount)', 0,
           (SELECT COUNTIF(ABS(w.weight - x.r) > 1e-9) FROM w
              JOIN (SELECT weekday, AVG(revenue) / (SELECT AVG(revenue) FROM dy WHERE d <= train_end) AS r
                      FROM dy WHERE d <= train_end GROUP BY weekday) AS x USING (weekday))
    UNION ALL
    SELECT '10. 32 month-on-month changes', 0,
           ABS((SELECT COUNT(d_ln_revenue) FROM m) - 32)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
