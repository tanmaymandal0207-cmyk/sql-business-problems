/* =============================================================================
   Case study · Customer credit limits — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE train_start  DATE    DEFAULT DATE '2024-10-01';
DECLARE test_start   DATE    DEFAULT DATE '2025-10-01';
DECLARE test_end     DATE    DEFAULT DATE '2026-03-31';
DECLARE outcome_days INT64   DEFAULT 180;
DECLARE limit_buffer FLOAT64 DEFAULT 1.25;
DECLARE sales_days   INT64   DEFAULT 90;
DECLARE hold_days    INT64   DEFAULT 90;
DECLARE bad_payer    FLOAT64 DEFAULT 0.20;

WITH o AS (SELECT * FROM `sahyadri_b2b.cl_orders`),
     l AS (SELECT * FROM `sahyadri_b2b.cl_limits`),
     b AS (SELECT * FROM `sahyadri_b2b.cl_backtest`),

src AS (
    SELECT x.order_id, x.customer_id, x.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY x.order_id, x.customer_id, x.order_date
),
-- check 03: earlier order value by running total, earlier payments by a separate join
running_value AS (
    SELECT order_id,
           SUM(v) OVER (PARTITION BY customer_id ORDER BY order_date, order_id
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) - v AS earlier_value
    FROM src
),
earlier_paid AS (
    SELECT n.order_id, IFNULL(SUM(p.amount), 0) AS paid
    FROM src AS n
    LEFT JOIN src AS e
      ON e.customer_id = n.customer_id
     AND (e.order_date < n.order_date OR (e.order_date = n.order_date AND e.order_id < n.order_id))
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = e.order_id AND p.payment_date <= n.order_date
    GROUP BY n.order_id
),
-- check 04: balances on earlier orders, one row per (order, earlier order)
earlier_balances AS (
    SELECT n.order_id, e.order_id AS earlier_id, e.order_date AS earlier_date, n.order_date,
           e.v - IFNULL(SUM(p.amount), 0) AS balance
    FROM src AS n
    JOIN src AS e
      ON e.customer_id = n.customer_id
     AND (e.order_date < n.order_date OR (e.order_date = n.order_date AND e.order_id < n.order_id))
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = e.order_id AND p.payment_date <= n.order_date
    GROUP BY n.order_id, e.order_id, e.order_date, n.order_date, e.v
),
old_balance AS (
    SELECT order_id,
           SUM(IF(DATE_DIFF(order_date, earlier_date, DAY) > hold_days AND balance > 1, balance, 0)) AS old_bal,
           SUM(GREATEST(balance, 0)) AS positive_bal
    FROM earlier_balances
    GROUP BY order_id
),
window_paid AS (
    SELECT s.order_id, IFNULL(SUM(p.amount), 0) AS paid
    FROM src AS s
    LEFT JOIN `sahyadri_b2b.payments` AS p
      ON p.order_id = s.order_id AND DATE_DIFF(p.payment_date, s.order_date, DAY) <= outcome_days
    GROUP BY s.order_id
),
train AS (
    SELECT customer_id, MAX(exposure_after) AS peak, SUM(order_value) AS sales
    FROM o WHERE order_date >= train_start AND order_date < test_start GROUP BY customer_id
),
past AS (
    SELECT customer_id, SUM(unpaid_after_window) / SUM(order_value) AS r
    FROM o WHERE order_date >= train_start AND DATE_DIFF(test_start, order_date, DAY) > outcome_days
    GROUP BY customer_id
),
seg_median AS (
    SELECT customer_segment,
           APPROX_QUANTILES(history_limit, 2)[OFFSET(1)] AS approx_hist,
           MIN(history_limit) AS lo, MAX(history_limit) AS hi
    FROM l WHERE has_history GROUP BY customer_segment
),

checks AS (
    SELECT '01. One row per valid order' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT COUNT(*) FROM src)) + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM o) AS actual
    UNION ALL
    SELECT '02. Order value = source recount', 0,
           (SELECT COUNTIF(ABS(o.order_value - s.v) > 0.01) FROM o JOIN src AS s USING (order_id))
    UNION ALL
    SELECT '03. Exposure before the order = running value - earlier payments', 0,
           (SELECT COUNTIF(ABS(o.exposure_before - (r.earlier_value - e.paid)) > 0.01
                           OR ABS(o.exposure_after - o.exposure_before - o.order_value) > 0.01)
              FROM o JOIN running_value AS r USING (order_id) JOIN earlier_paid AS e USING (order_id))
    UNION ALL
    SELECT '04. Old unpaid balance = recount, and no more than all positive balances', 0,
           (SELECT COUNTIF(ABS(o.overdue_balance - IFNULL(x.old_bal, 0)) > 0.01 OR o.overdue_balance > IFNULL(x.positive_bal, 0) + 0.01)
              FROM o LEFT JOIN old_balance AS x USING (order_id))
    UNION ALL
    SELECT '05. Unpaid after 180 days = recount, and the not-fully-paid flag agrees', 0,
           (SELECT COUNTIF(ABS(o.unpaid_after_window - GREATEST(o.order_value - w.paid, 0)) > 0.01
                           OR o.not_fully_paid != (o.order_value - w.paid > 1))
              FROM o JOIN window_paid AS w USING (order_id))
    UNION ALL
    SELECT '06. One limit per test customer, history limit = 1.25 x training peak', 0,
           ABS((SELECT COUNT(*) FROM l) - (SELECT COUNT(DISTINCT customer_id) FROM o WHERE order_date BETWEEN test_start AND test_end))
         + (SELECT COUNTIF(l.has_history != (t.customer_id IS NOT NULL)
                           OR (t.customer_id IS NOT NULL AND (ABS(l.history_limit - limit_buffer * t.peak) > 0.01
                                                              OR ABS(l.sales_limit - t.sales * sales_days / 365) > 0.01)))
              FROM l LEFT JOIN train AS t USING (customer_id))
    UNION ALL
    SELECT '07. New customers get a limit inside their segment''s range of trained limits', 0,
           (SELECT COUNTIF(l.history_limit < m.lo - 0.01 OR l.history_limit > m.hi + 0.01)
              FROM l JOIN seg_median AS m USING (customer_segment) WHERE NOT l.has_history)
         + (SELECT COUNTIF(history_limit IS NULL OR sales_limit IS NULL) FROM l)
    UNION ALL
    SELECT '08. Five rules for every test order, block flags recomputed', 0,
           ABS((SELECT COUNT(*) FROM b) - 5 * (SELECT COUNT(*) FROM o WHERE order_date BETWEEN test_start AND test_end))
         + (SELECT COUNTIF(blocked != CASE
                    WHEN rule LIKE 'A%' THEN exposure_after > history_limit
                    WHEN rule LIKE 'B%' THEN exposure_after > sales_limit
                    WHEN rule LIKE 'C%' THEN overdue_balance > 1
                    WHEN rule LIKE 'D%' THEN exposure_after > history_limit OR overdue_balance > 1
                    ELSE customer_id IN (SELECT customer_id FROM past WHERE r > bad_payer) END) FROM b)
    UNION ALL
    SELECT '09. Past-loss rate uses only outcomes known before the test period', 0,
           (SELECT COUNTIF(IFNULL(l.past_loss_rate, -1) != IFNULL(p.r, -1) AND ABS(IFNULL(l.past_loss_rate, -1) - IFNULL(p.r, -1)) > 1e-12)
              FROM l LEFT JOIN past AS p USING (customer_id))
         + (SELECT COUNT(*) FROM o WHERE order_date >= train_start AND DATE_DIFF(test_start, order_date, DAY) > outcome_days
                                     AND DATE_DIFF(DATE_ADD(order_date, INTERVAL outcome_days DAY), test_start, DAY) >= 0)
    UNION ALL
    SELECT '10. Every rule sees the same test losses, and catches no more than all of them', 0,
           (SELECT COUNT(DISTINCT ROUND(total, 2)) - 1 FROM (SELECT rule, SUM(unpaid_after_window) AS total FROM b GROUP BY rule))
         + (SELECT COUNTIF(caught > total + 0.01)
              FROM (SELECT rule, SUM(IF(blocked, unpaid_after_window, 0)) AS caught, SUM(unpaid_after_window) AS total FROM b GROUP BY rule))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
