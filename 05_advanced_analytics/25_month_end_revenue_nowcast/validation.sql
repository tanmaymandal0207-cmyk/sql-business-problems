/* =============================================================================
   Case study · Nowcasting month-end revenue — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE history_start   DATE    DEFAULT DATE '2024-01-01';
DECLARE history_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE backtest_start  DATE    DEFAULT DATE '2024-04-01';
DECLARE large_order     FLOAT64 DEFAULT 500000;

WITH d AS (SELECT * FROM `sahyadri_b2b.nc_days`),
     m AS (SELECT * FROM `sahyadri_b2b.nc_months`),
     w AS (SELECT * FROM `sahyadri_b2b.nc_weights`),
     n AS (SELECT * FROM `sahyadri_b2b.nc_nowcasts`),

orders AS (
    SELECT o.order_id, o.order_date, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN history_start AND history_end
    GROUP BY o.order_id, o.order_date
),
-- revenue in the first 15 days of each month, straight from orders
first_15 AS (
    SELECT DATE_TRUNC(order_date, MONTH) AS month, SUM(value) AS v
    FROM orders WHERE EXTRACT(DAY FROM order_date) <= 15
    GROUP BY month
),
prior_recount AS (
    SELECT series, month, prior,
           (LAG(revenue, 1) OVER x + LAG(revenue, 2) OVER x + LAG(revenue, 3) OVER x) / 3 AS p
    FROM m WINDOW x AS (PARTITION BY series ORDER BY month)
),
-- each month's weights, weighted by how often each weekday occurred before the month
weight_mean AS (
    SELECT w.series, w.month, SUM(w.weight * c.days) / SUM(c.days) AS mean_weight
    FROM w
    JOIN (SELECT series, month, weekday, COUNT(*) AS days
            FROM (SELECT m.series, m.month, x.weekday FROM m JOIN d AS x ON x.series = m.series AND x.day < m.month)
           GROUP BY series, month, weekday) AS c
      ON c.series = w.series AND c.month = w.month AND c.weekday = w.weekday
    GROUP BY w.series, w.month
),
steps AS (
    SELECT series, month, day_n, to_date, LAG(to_date) OVER (PARTITION BY series, month ORDER BY day_n) AS previous FROM n
),

checks AS (
    SELECT '01. Daily revenue = source for both series' AS check_name, 0 AS expected,
           IF(ABS((SELECT SUM(revenue) FROM d WHERE series = 'All orders') - (SELECT SUM(value) FROM orders)) > 1, 1, 0)
         + IF(ABS((SELECT SUM(revenue) FROM d WHERE series = 'Excluding large orders')
                  - (SELECT SUM(IF(value < large_order, value, 0)) FROM orders)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. One row per calendar day per series', 0,
           (SELECT COUNT(*) FROM (SELECT series, COUNT(*) AS n, COUNT(DISTINCT day) AS u FROM d GROUP BY series)
             WHERE n != u OR n != DATE_DIFF(history_end, history_start, DAY) + 1)
         + ABS((SELECT COUNT(DISTINCT series) FROM d) - 2)
    UNION ALL
    SELECT '03. Prior = average of the previous 3 months', 0,
           (SELECT COUNTIF(p IS NOT NULL AND ABS(prior - p) > 0.01) FROM prior_recount)
    UNION ALL
    SELECT '04. Weekday weights average 1 over the days before each month', 0,
           (SELECT COUNTIF(ABS(mean_weight - 1) > 1e-9) FROM weight_mean)
    UNION ALL
    SELECT '05. 30 back-test months x 28 days for each series', 0,
           ABS((SELECT COUNT(*) FROM n) - 2 * 30 * 28)
         + ABS((SELECT COUNT(DISTINCT month) FROM n) - 30)
         + IF((SELECT MIN(month) FROM n) != backtest_start, 1, 0)
    UNION ALL
    SELECT '06. Revenue to date never falls and never exceeds the month', 0,
           (SELECT COUNTIF(to_date < previous - 0.01) FROM steps)
         + (SELECT COUNTIF(to_date > actual + 0.01) FROM n)
    UNION ALL
    SELECT '07. Revenue to day 15 = direct recount from orders', 0,
           (SELECT COUNTIF(ABS(n.to_date - f.v) > 0.01) FROM n JOIN first_15 AS f ON f.month = n.month
             WHERE n.series = 'All orders' AND n.day_n = 15)
    UNION ALL
    SELECT '08. Calendar run-rate = revenue to date x days in month / day', 0,
           (SELECT COUNTIF(ABS(n.calendar_run_rate - n.to_date * EXTRACT(DAY FROM LAST_DAY(n.month)) / n.day_n) > 0.01) FROM n)
    UNION ALL
    SELECT '09. Blend = revenue to date + prior x weight still to come', 0,
           (SELECT COUNTIF(ABS(blend - (to_date + prior * (1 - elapsed_weight))) > 0.01
                           OR elapsed_weight <= 0 OR elapsed_weight > 1 + 1e-9) FROM n)
    UNION ALL
    SELECT '10. Weekday run-rate = revenue to date / elapsed weight', 0,
           (SELECT COUNTIF(ABS(weekday_run_rate - to_date / elapsed_weight) > 0.01) FROM n)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
