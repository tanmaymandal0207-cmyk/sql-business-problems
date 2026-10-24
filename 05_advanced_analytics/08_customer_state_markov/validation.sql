/* =============================================================================
   Case study · Customer state transitions (Markov chain) — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE high_value       FLOAT64 DEFAULT 200000;
DECLARE last_quarter     DATE    DEFAULT DATE '2026-07-01';
DECLARE backtest_quarter DATE    DEFAULT DATE '2025-07-01';

WITH s AS (SELECT * FROM `sahyadri_b2b.customer_quarter_state`),
     m AS (SELECT * FROM `sahyadri_b2b.state_transitions`),
     p AS (SELECT * FROM `sahyadri_b2b.markov_projection`),

src AS (
    SELECT o.customer_id, o.order_date,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date < DATE_ADD(last_quarter, INTERVAL 3 MONTH)
),
expected_rows AS (
    -- quarters from each customer's first order quarter to the last quarter, inclusive
    SELECT SUM(DATE_DIFF(last_quarter, DATE_TRUNC(first_order, QUARTER), QUARTER) + 1) AS n
    FROM (SELECT customer_id, MIN(order_date) AS first_order FROM src GROUP BY customer_id)
),
-- Silent / Lost recomputed with a self-join over the previous three quarters
recent_activity AS (
    SELECT a.customer_id, a.quarter_start, COUNTIF(b.revenue > 0) AS active_quarters
    FROM s AS a
    JOIN s AS b
      ON b.customer_id = a.customer_id
     AND b.quarter_start BETWEEN DATE_SUB(a.quarter_start, INTERVAL 9 MONTH) AND a.quarter_start
    GROUP BY a.customer_id, a.quarter_start
),
start_mix AS (
    SELECT state, COUNT(*) AS n FROM s WHERE quarter_start = last_quarter GROUP BY state
),
step1_manual AS (
    SELECT t.to_state, SUM(x.n * t.probability) AS customers
    FROM start_mix AS x
    JOIN m AS t ON t.from_state = x.state AND t.fit = 'Full history'
    GROUP BY t.to_state
),
row_sums AS (
    SELECT fit, from_state, SUM(probability) AS total, MIN(probability) AS min_p, MAX(probability) AS max_p
    FROM m GROUP BY fit, from_state
),
run_totals AS (
    SELECT run, step, SUM(customers) AS customers FROM p GROUP BY run, step
),

checks AS (
    SELECT '01. Duplicate customer-quarter rows' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(quarter_start AS STRING))) FROM s) AS actual
    UNION ALL
    SELECT '02. Rows vs quarters from first order to the last quarter', 0,
           (SELECT COUNT(*) FROM s) - (SELECT n FROM expected_rows)
    UNION ALL
    SELECT '03. Revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM s) - (SELECT SUM(revenue) FROM src), 0) AS INT64)
    UNION ALL
    SELECT '04. State inconsistent with revenue and recent activity', 0,
           (SELECT COUNTIF(
                 (x.state = '1. High'    AND NOT x.revenue >= high_value)
              OR (x.state = '2. Low'     AND NOT (x.revenue > 0 AND x.revenue < high_value))
              OR (x.state LIKE '%Silent%' AND NOT (x.revenue = 0 AND r.active_quarters > 0))
              OR (x.state = '6. Lost'     AND NOT (x.revenue = 0 AND r.active_quarters = 0)))
              FROM s AS x JOIN recent_activity AS r
                ON r.customer_id = x.customer_id AND r.quarter_start = x.quarter_start)
    UNION ALL
    SELECT '05. Matrix rows whose probabilities do not sum to 1, or fall outside 0-1', 0,
           (SELECT COUNTIF(ABS(total - 1) > 1e-9 OR min_p < 0 OR max_p > 1) FROM row_sums)
    UNION ALL
    SELECT '06. Full-history transitions vs rows minus customers', 0,
           (SELECT SUM(transitions) FROM m WHERE fit = 'Full history')
         - ((SELECT COUNT(*) FROM s) - (SELECT COUNT(DISTINCT customer_id) FROM s))
    UNION ALL
    SELECT '07. Projection steps that gain or lose customers', 0,
           (SELECT COUNTIF(ABS(t.customers - z.customers) > 1e-6)
              FROM run_totals AS t JOIN run_totals AS z ON z.run = t.run AND z.step = 0)
    UNION ALL
    SELECT '08. Backtest matrix uses transitions after the backtest quarter', 0,
           (SELECT SUM(transitions) FROM m WHERE fit = 'To backtest date')
         - (SELECT COUNT(*) FROM s AS a JOIN s AS b
              ON b.customer_id = a.customer_id
             AND b.quarter_start = DATE_ADD(a.quarter_start, INTERVAL 3 MONTH)
             WHERE b.quarter_start <= backtest_quarter)
    UNION ALL
    SELECT '09. Scenario matrix differs from full history outside the Silent rows', 0,
           (SELECT COUNT(*) FROM m AS a JOIN m AS b
              ON b.from_state = a.from_state AND b.to_state = a.to_state
             WHERE a.fit = 'Full history' AND b.fit = 'Win-back scenario'
               AND a.from_state NOT LIKE '%Silent%' AND ABS(a.probability - b.probability) > 1e-12)
    UNION ALL
    SELECT '10. Forecast step 1 vs manual matrix multiplication', 0,
           (SELECT COUNTIF(ABS(x.customers - y.customers) > 1e-6)
              FROM p AS x JOIN step1_manual AS y ON y.to_state = x.state
             WHERE x.run = 'Forecast' AND x.step = 1)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
