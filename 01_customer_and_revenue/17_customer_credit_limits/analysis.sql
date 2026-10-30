/* =============================================================================
   Case study · Customer credit limits: which rule would have stopped the losses?
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Orders are accepted today without any credit check. The ECL study showed
   that a balance still unpaid six months after delivery is never collected,
   and the CFO wants credit control at order entry before the new ERP goes
   live. Two kinds of rule are on the table: a credit limit per customer, and
   a hold on customers with old unpaid balances. She asks:
     1. How much credit does each customer actually use, and how does it
        compare with what they buy?
     2. How many orders were accepted from customers who already owed money
        on old orders?
     3. Which rule would have blocked the orders that were never paid,
        without blocking good business?

   METHOD
     - Valid orders: not Cancelled or Returned. Order value = net line value.
     - Exposure when an order is placed = value of the customer's earlier
       valid orders (date, then order id) - payments on them up to the order
       date, plus the new order. Exposure only rises at orders, so its peak
       over a period is the largest exposure at any order.
     - Training year: Oct 2024 - Sep 2025. Test period: orders placed
       Oct 2025 - Mar 2026, so 180 days after each order can be observed.
     - Outcome: the order's value still unpaid 180 days after the order date
       ("lost"; the ECL study found nothing is collected after that point).
     - Rules, each applied to every test order:
         A. History limit   - 1.25 x the customer's peak exposure in the
                              training year
         B. Sales limit     - 90 days of the customer's training-year sales
         C. Overdue hold    - block if anything is unpaid on an order placed
                              more than 90 days earlier
         D. A or C
         E. Past-loss hold  - block customers that left more than 20 % of
                              the value of their training-year orders placed
                              by 3 Apr 2025 unpaid after 180 days (outcome
                              known before the test starts)
       A rule is useful only if it catches more loss per rupee of good
       business blocked than blocking orders at random would
       (lift = that ratio / the same ratio for all test orders).
       Customers with no training orders get the median limit of their
       segment. Blocking is evaluated order by order on actual history (a
       blocked order is not removed from later exposure).
   ============================================================================= */

DECLARE train_start  DATE    DEFAULT DATE '2024-10-01';
DECLARE test_start   DATE    DEFAULT DATE '2025-10-01';
DECLARE test_end     DATE    DEFAULT DATE '2026-03-31';
DECLARE outcome_days INT64   DEFAULT 180;
DECLARE limit_buffer FLOAT64 DEFAULT 1.25;
DECLARE sales_days   INT64   DEFAULT 90;
DECLARE hold_days    INT64   DEFAULT 90;
DECLARE bad_payer    FLOAT64 DEFAULT 0.20;

-- -----------------------------------------------------------------------------
-- Step 1 · Exposure at every order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cl_orders` AS
WITH orders AS (
    SELECT o.order_id, o.customer_id, c.customer_segment, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, c.customer_segment, o.order_date
),
paid AS (
    -- payments on each earlier order up to the date of the new order
    SELECT n.order_id, e.order_id AS earlier_order_id, e.order_date AS earlier_order_date, e.order_value AS earlier_value,
           IFNULL(SUM(IF(p.payment_date <= n.order_date, p.amount, 0)), 0) AS earlier_paid
    FROM orders AS n
    JOIN orders AS e
      ON e.customer_id = n.customer_id
     AND (e.order_date < n.order_date OR (e.order_date = n.order_date AND e.order_id < n.order_id))
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = e.order_id
    GROUP BY n.order_id, e.order_id, e.order_date, e.order_value
),
prior AS (
    SELECT n.order_id,
           IFNULL(SUM(x.earlier_value - x.earlier_paid), 0)                                       AS exposure_before,
           IFNULL(SUM(IF(x.earlier_order_date < DATE_SUB(n.order_date, INTERVAL hold_days DAY)
                         AND x.earlier_value - x.earlier_paid > 1, x.earlier_value - x.earlier_paid, 0)), 0) AS overdue_balance
    FROM orders AS n
    LEFT JOIN paid AS x ON x.order_id = n.order_id
    GROUP BY n.order_id
),
outcome AS (
    SELECT o.order_id,
           IFNULL(SUM(IF(p.payment_date <= DATE_ADD(o.order_date, INTERVAL outcome_days DAY), p.amount, 0)), 0) AS paid_in_window
    FROM orders AS o
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = o.order_id
    GROUP BY o.order_id
)
SELECT
    o.*,
    pr.exposure_before,
    pr.exposure_before + o.order_value                                     AS exposure_after,
    pr.overdue_balance,
    GREATEST(o.order_value - oc.paid_in_window, 0)                         AS unpaid_after_window,
    o.order_value - oc.paid_in_window > 1                                  AS not_fully_paid
FROM orders AS o
JOIN prior AS pr ON pr.order_id = o.order_id
JOIN outcome AS oc ON oc.order_id = o.order_id;

-- Peak exposure against sales, by segment (training year)
WITH c AS (
    SELECT customer_id, customer_segment, MAX(exposure_after) AS peak_exposure, SUM(order_value) AS sales
    FROM `sahyadri_b2b.cl_orders`
    WHERE order_date >= train_start AND order_date < test_start
    GROUP BY customer_id, customer_segment
)
SELECT
    customer_segment,
    COUNT(*)                                                                AS customers,
    ROUND(APPROX_QUANTILES(peak_exposure, 100)[OFFSET(50)] / 1e5, 2)        AS median_peak_exposure_lakh,
    ROUND(MAX(peak_exposure) / 1e5, 1)                                      AS largest_peak_lakh,
    ROUND(APPROX_QUANTILES(365 * peak_exposure / sales, 100)[OFFSET(50)], 0) AS median_peak_in_days_of_sales,
    ROUND(SUM(peak_exposure) / 1e7, 2)                                      AS sum_of_peaks_crore
FROM c
GROUP BY customer_segment
ORDER BY customer_segment;

-- -----------------------------------------------------------------------------
-- Step 2 · Orders accepted from customers with old unpaid balances
-- -----------------------------------------------------------------------------
SELECT
    EXTRACT(YEAR FROM order_date)                                                       AS order_year,
    COUNT(*)                                                                            AS orders,
    COUNTIF(overdue_balance > 1)                                                        AS orders_with_old_balance,
    ROUND(100 * COUNTIF(overdue_balance > 1) / COUNT(*), 1)                             AS share_pct,
    ROUND(SUM(IF(overdue_balance > 1, order_value, 0)) / 1e5, 1)                        AS value_lakh,
    ROUND(100 * AVG(IF(overdue_balance > 1 AND order_date <= test_end, IF(not_fully_paid, 1, 0), NULL)), 1) AS not_paid_in_180d_pct_with_old_balance,
    ROUND(100 * AVG(IF(overdue_balance <= 1 AND order_date <= test_end, IF(not_fully_paid, 1, 0), NULL)), 1) AS not_paid_in_180d_pct_others
FROM `sahyadri_b2b.cl_orders`
GROUP BY order_year
ORDER BY order_year;

-- What the losses are: test-period orders not fully paid 180 days after the order
SELECT
    COUNT(*)                                                                             AS test_orders,
    COUNTIF(not_fully_paid)                                                              AS not_fully_paid_orders,
    COUNTIF(not_fully_paid AND unpaid_after_window >= order_value - 1)                   AS nothing_paid,
    COUNTIF(not_fully_paid AND unpaid_after_window <  order_value - 1)                   AS part_paid,
    ROUND(SUM(unpaid_after_window) / 1e5, 1)                                             AS unpaid_lakh,
    ROUND(100 * SUM(unpaid_after_window) / SUM(order_value), 1)                          AS unpaid_share_of_value_pct,
    COUNT(DISTINCT IF(not_fully_paid, customer_id, NULL))                                AS customers_with_a_loss,
    COUNT(DISTINCT customer_id)                                                          AS customers
FROM `sahyadri_b2b.cl_orders`
WHERE order_date BETWEEN test_start AND test_end;

-- -----------------------------------------------------------------------------
-- Step 3 · Limits from the training year, and a back-test of four rules
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cl_limits` AS
WITH trained AS (
    SELECT customer_id, customer_segment,
           limit_buffer * MAX(exposure_after)        AS history_limit,
           SUM(order_value) * sales_days / 365       AS sales_limit
    FROM `sahyadri_b2b.cl_orders`
    WHERE order_date >= train_start AND order_date < test_start
    GROUP BY customer_id, customer_segment
),
segment_default AS (
    SELECT DISTINCT customer_segment,
           PERCENTILE_CONT(history_limit, 0.5) OVER (PARTITION BY customer_segment) AS history_default,
           PERCENTILE_CONT(sales_limit, 0.5)   OVER (PARTITION BY customer_segment) AS sales_default
    FROM trained
),
past_loss AS (
    -- orders whose 180-day outcome is known before the test period starts
    SELECT customer_id, SUM(unpaid_after_window) / SUM(order_value) AS past_loss_rate
    FROM `sahyadri_b2b.cl_orders`
    WHERE order_date >= train_start AND order_date < DATE_SUB(test_start, INTERVAL outcome_days DAY)
    GROUP BY customer_id
),
test_customers AS (
    SELECT DISTINCT customer_id, customer_segment
    FROM `sahyadri_b2b.cl_orders`
    WHERE order_date BETWEEN test_start AND test_end
)
SELECT
    c.customer_id, c.customer_segment,
    t.customer_id IS NOT NULL                                AS has_history,
    IFNULL(t.history_limit, d.history_default)              AS history_limit,
    IFNULL(t.sales_limit, d.sales_default)                  AS sales_limit,
    pl.past_loss_rate,
    IFNULL(pl.past_loss_rate > bad_payer, FALSE)            AS past_bad_payer
FROM test_customers AS c
LEFT JOIN trained AS t ON t.customer_id = c.customer_id
LEFT JOIN past_loss AS pl ON pl.customer_id = c.customer_id
JOIN segment_default AS d ON d.customer_segment = c.customer_segment;

CREATE OR REPLACE TABLE `sahyadri_b2b.cl_backtest` AS
WITH rules AS (
    SELECT 'A. History limit (1.25 x peak)' AS rule UNION ALL
    SELECT 'B. Sales limit (90 days of sales)' UNION ALL
    SELECT 'C. Overdue hold (unpaid > 90 days)' UNION ALL
    SELECT 'D. History limit or overdue hold' UNION ALL
    SELECT 'E. Past-loss hold (> 20 % unpaid)'
)
SELECT
    r.rule, o.order_id, o.customer_id, o.customer_segment, o.order_date, o.order_value,
    o.exposure_after, o.overdue_balance, o.unpaid_after_window, o.not_fully_paid,
    l.has_history, l.history_limit, l.sales_limit,
    CASE
        WHEN r.rule LIKE 'A%' THEN o.exposure_after > l.history_limit
        WHEN r.rule LIKE 'B%' THEN o.exposure_after > l.sales_limit
        WHEN r.rule LIKE 'C%' THEN o.overdue_balance > 1
        WHEN r.rule LIKE 'D%' THEN o.exposure_after > l.history_limit OR o.overdue_balance > 1
        ELSE l.past_bad_payer
    END                                                      AS blocked
FROM `sahyadri_b2b.cl_orders` AS o
JOIN `sahyadri_b2b.cl_limits` AS l ON l.customer_id = o.customer_id
CROSS JOIN rules AS r
WHERE o.order_date BETWEEN test_start AND test_end;

SELECT
    rule,
    COUNT(*)                                                                         AS test_orders,
    COUNTIF(blocked)                                                                 AS blocked_orders,
    ROUND(100 * COUNTIF(blocked) / COUNT(*), 1)                                      AS blocked_pct,
    ROUND(SUM(IF(blocked, order_value, 0)) / 1e5, 1)                                 AS blocked_value_lakh,
    ROUND(SUM(IF(blocked AND NOT not_fully_paid, order_value, 0)) / 1e5, 1)          AS good_business_blocked_lakh,
    ROUND(SUM(IF(blocked, unpaid_after_window, 0)) / 1e5, 1)                         AS losses_caught_lakh,
    ROUND(SUM(unpaid_after_window) / 1e5, 1)                                         AS all_losses_lakh,
    ROUND(100 * SUM(IF(blocked, unpaid_after_window, 0)) / SUM(unpaid_after_window), 1) AS losses_caught_pct,
    ROUND(SUM(IF(blocked, unpaid_after_window, 0)) / NULLIF(SUM(IF(blocked AND NOT not_fully_paid, order_value, 0)), 0), 3)
                                                                                     AS loss_caught_per_rupee_of_good_blocked,
    ROUND(SUM(unpaid_after_window) / SUM(IF(NOT not_fully_paid, order_value, 0)), 3)  AS same_ratio_if_random,
    ROUND((SUM(IF(blocked, unpaid_after_window, 0)) / NULLIF(SUM(IF(blocked AND NOT not_fully_paid, order_value, 0)), 0))
          / (SUM(unpaid_after_window) / SUM(IF(NOT not_fully_paid, order_value, 0))), 2) AS lift_vs_random
FROM `sahyadri_b2b.cl_backtest`
GROUP BY rule
ORDER BY rule;

-- Where the losses are, and which rule catches them, by segment
SELECT
    customer_segment,
    COUNT(DISTINCT order_id)                                                                           AS test_orders,
    ROUND(SUM(IF(rule LIKE 'A%', unpaid_after_window, 0)) / 1e5, 1)                                    AS losses_lakh,
    ROUND(100 * SUM(IF(rule LIKE 'A%', unpaid_after_window, 0)) / SUM(IF(rule LIKE 'A%', order_value, 0)), 1) AS loss_rate_pct,
    ROUND(100 * SUM(IF(rule LIKE 'A%' AND blocked, unpaid_after_window, 0)) / NULLIF(SUM(IF(rule LIKE 'A%', unpaid_after_window, 0)), 0), 1) AS caught_by_a_pct,
    ROUND(100 * SUM(IF(rule LIKE 'C%' AND blocked, unpaid_after_window, 0)) / NULLIF(SUM(IF(rule LIKE 'C%', unpaid_after_window, 0)), 0), 1) AS caught_by_c_pct,
    ROUND(100 * AVG(IF(rule LIKE 'C%', IF(blocked, 1, 0), NULL)), 1)                                   AS blocked_by_c_pct
FROM `sahyadri_b2b.cl_backtest`
GROUP BY customer_segment
ORDER BY customer_segment;

-- New customers (no training history): how do the segment defaults do?
SELECT
    has_history,
    COUNT(DISTINCT customer_id)                                                           AS customers,
    COUNTIF(rule LIKE 'A%')                                                               AS test_orders,
    ROUND(100 * AVG(IF(rule LIKE 'A%', IF(blocked, 1, 0), NULL)), 1)                      AS blocked_by_a_pct,
    ROUND(100 * SUM(IF(rule LIKE 'A%', unpaid_after_window, 0)) / SUM(IF(rule LIKE 'A%', order_value, 0)), 1) AS loss_rate_pct
FROM `sahyadri_b2b.cl_backtest`
GROUP BY has_history
ORDER BY has_history;
