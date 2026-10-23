/* =============================================================================
   Case study · Order anomaly screen
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Orders are keyed in by hand. A slipped digit (100 typed as 1000) or a
   wrong price can ship the wrong goods, create a dispute, and distort sales
   and stock figures. Internal audit wants a repeatable screen that flags
   unusual order lines for review before dispatch and before month-end:
     1. How many order lines and orders look unusual, and on which rule?
     2. Do flagged orders end badly (cancelled, returned, unpaid) more often
        than normal orders, which would show the screen catches real problems?
     3. Which flagged orders are still open or unpaid and need review now?

   KEY RULES
     - All orders dated 1 Jan 2024 - 30 Sep 2026, all statuses.
     - Robust benchmarks use medians, which a few extreme values cannot pull.
     - Rules (a line can trigger more than one):
         Q1 Product quantity: quantity >= qty_multiple (10) x the product's
            median quantity (products with at least min_history lines)
         Q2 Customer quantity: quantity >= cust_multiple (5) x the customer's
            median quantity for that product (pairs with min_pair lines)
         P1 Price: unit_price more than price_tolerance (10 %) away from the
            product's median unit_price in the same quarter
         V1 Order value: the order's gross value >= qty_multiple (10) x the
            customer's median order gross value (customers with min_history
            orders); flagged on every line of the order
     - Outcome of a flagged order:
         Paid in full          -> confirmed by the customer (genuine)
         Cancelled / Returned  -> reversed (check the cause)
         Delivered, not fully paid -> review before chasing payment
         Pending / Processing / Shipped -> verify now
   ============================================================================= */

DECLARE period_start    DATE    DEFAULT DATE '2024-01-01';
DECLARE period_end      DATE    DEFAULT DATE '2026-09-30';
DECLARE qty_multiple    FLOAT64 DEFAULT 10;
DECLARE cust_multiple   FLOAT64 DEFAULT 5;
DECLARE price_tolerance FLOAT64 DEFAULT 0.10;
DECLARE min_history     INT64   DEFAULT 20;
DECLARE min_pair        INT64   DEFAULT 4;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per order line with every rule evaluated
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.order_line_anomalies` AS
WITH lines AS (
    SELECT
        i.order_item_id,
        i.order_id,
        i.product_id,
        i.quantity,
        i.unit_price,
        o.customer_id,
        o.order_date,
        o.order_status,
        DATE_TRUNC(o.order_date, QUARTER)                                  AS order_quarter
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_date BETWEEN period_start AND period_end
),
order_gross AS (
    SELECT order_id, customer_id, SUM(quantity * unit_price) AS order_gross
    FROM lines
    GROUP BY order_id, customer_id
),
benchmarks AS (
    SELECT
        l.*,
        PERCENTILE_CONT(l.quantity, 0.5)   OVER (PARTITION BY l.product_id)                AS product_median_qty,
        COUNT(*)                           OVER (PARTITION BY l.product_id)                AS product_lines,
        PERCENTILE_CONT(l.quantity, 0.5)   OVER (PARTITION BY l.customer_id, l.product_id) AS pair_median_qty,
        COUNT(*)                           OVER (PARTITION BY l.customer_id, l.product_id) AS pair_lines,
        PERCENTILE_CONT(l.unit_price, 0.5) OVER (PARTITION BY l.product_id, l.order_quarter) AS quarter_median_price
    FROM lines AS l
),
customer_orders AS (
    SELECT
        order_id,
        order_gross,
        PERCENTILE_CONT(order_gross, 0.5) OVER (PARTITION BY customer_id) AS customer_median_order,
        COUNT(*)                          OVER (PARTITION BY customer_id) AS customer_orders
    FROM order_gross
)
SELECT
    b.order_item_id,
    b.order_id,
    b.customer_id,
    b.product_id,
    b.order_date,
    b.order_status,
    b.quantity,
    b.unit_price,
    ROUND(b.quantity * b.unit_price, 2)                                     AS line_gross,
    b.product_median_qty,
    b.pair_median_qty,
    ROUND(b.quarter_median_price, 2)                                        AS quarter_median_price,
    ROUND(c.order_gross, 2)                                                 AS order_gross,
    ROUND(c.customer_median_order, 2)                                       AS customer_median_order,
    (b.product_lines >= min_history AND b.quantity >= qty_multiple * b.product_median_qty)  AS flag_q1_product_qty,
    (b.pair_lines >= min_pair       AND b.quantity >= cust_multiple * b.pair_median_qty)    AS flag_q2_customer_qty,
    (ABS(b.unit_price / b.quarter_median_price - 1) > price_tolerance)                      AS flag_p1_price,
    (c.customer_orders >= min_history AND c.order_gross >= qty_multiple * c.customer_median_order) AS flag_v1_order_value
FROM benchmarks           AS b
JOIN customer_orders      AS c ON c.order_id = b.order_id;

-- -----------------------------------------------------------------------------
-- Step 2 · How many lines and orders does each rule flag?
-- -----------------------------------------------------------------------------
SELECT
    rule,
    COUNTIF(flagged)                                     AS lines_flagged,
    COUNT(DISTINCT IF(flagged, order_id, NULL))          AS orders_flagged,
    ROUND(SUM(IF(flagged, line_gross, 0)), 2)            AS gross_value_flagged
FROM (
    SELECT 'Q1 Product quantity'  AS rule, order_id, line_gross, flag_q1_product_qty  AS flagged FROM `sahyadri_b2b.order_line_anomalies`
    UNION ALL
    SELECT 'Q2 Customer quantity',          order_id, line_gross, flag_q2_customer_qty           FROM `sahyadri_b2b.order_line_anomalies`
    UNION ALL
    SELECT 'P1 Price',                      order_id, line_gross, flag_p1_price                  FROM `sahyadri_b2b.order_line_anomalies`
    UNION ALL
    SELECT 'V1 Order value',                order_id, line_gross, flag_v1_order_value            FROM `sahyadri_b2b.order_line_anomalies`
)
GROUP BY rule
ORDER BY rule;

-- -----------------------------------------------------------------------------
-- Step 3 · Order-level view: flagged orders and how they ended
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.order_anomaly_review` AS
WITH order_flags AS (
    SELECT
        order_id,
        ANY_VALUE(customer_id)                                      AS customer_id,
        ANY_VALUE(order_date)                                       AS order_date,
        ANY_VALUE(order_status)                                     AS order_status,
        ANY_VALUE(order_gross)                                      AS order_gross,
        COUNTIF(flag_q1_product_qty)                                AS q1_lines,
        COUNTIF(flag_q2_customer_qty)                               AS q2_lines,
        COUNTIF(flag_p1_price)                                      AS p1_lines,
        LOGICAL_OR(flag_v1_order_value)                             AS v1_order,
        LOGICAL_OR(flag_q1_product_qty OR flag_q2_customer_qty
                   OR flag_p1_price OR flag_v1_order_value)         AS is_flagged
    FROM `sahyadri_b2b.order_line_anomalies`
    GROUP BY order_id
),
paid AS (
    SELECT order_id, SUM(amount) AS amount_paid
    FROM `sahyadri_b2b.payments`
    GROUP BY order_id
),
order_net AS (
    SELECT order_id, ROUND(SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)), 2) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
)
SELECT
    f.*,
    n.order_value,
    IFNULL(p.amount_paid, 0)                                         AS amount_paid,
    CASE
        WHEN f.order_status IN ('Cancelled', 'Returned')                 THEN '2. Reversed (cancelled or returned)'
        WHEN f.order_status IN ('Pending', 'Processing', 'Shipped')      THEN '4. Open: verify now'
        WHEN IFNULL(p.amount_paid, 0) >= n.order_value - 0.05            THEN '1. Paid in full: genuine'
        ELSE '3. Delivered, not fully paid: review'
    END                                                              AS outcome
FROM order_flags     AS f
JOIN order_net       AS n ON n.order_id = f.order_id
LEFT JOIN paid       AS p ON p.order_id = f.order_id;

-- Does the screen pick out problem orders? Outcome mix, flagged vs not flagged
SELECT
    IF(is_flagged, 'Flagged', 'Not flagged')                                  AS screen_result,
    COUNT(*)                                                                  AS orders,
    ROUND(100 * COUNTIF(outcome LIKE '1.%') / COUNT(*), 1)                    AS pct_paid_in_full,
    ROUND(100 * COUNTIF(outcome LIKE '2.%') / COUNT(*), 1)                    AS pct_reversed,
    ROUND(100 * COUNTIF(outcome LIKE '3.%') / COUNT(*), 1)                    AS pct_delivered_not_fully_paid,
    ROUND(100 * COUNTIF(outcome LIKE '4.%') / COUNT(*), 1)                    AS pct_open,
    ROUND(SUM(order_value), 2)                                                AS order_value
FROM `sahyadri_b2b.order_anomaly_review`
GROUP BY screen_result
ORDER BY screen_result;

-- Two-proportion z-test: reversal rate, flagged vs not flagged
WITH c AS (
    SELECT
        COUNTIF(is_flagged)                                  AS n1,
        COUNTIF(NOT is_flagged)                              AS n2,
        COUNTIF(is_flagged AND outcome LIKE '2.%')           AS r1,
        COUNTIF(NOT is_flagged AND outcome LIKE '2.%')       AS r2
    FROM `sahyadri_b2b.order_anomaly_review`
)
SELECT
    ROUND(100 * r1 / n1, 2)  AS reversal_rate_flagged_pct,
    ROUND(100 * r2 / n2, 2)  AS reversal_rate_not_flagged_pct,
    ROUND((r1 / n1 - r2 / n2)
          / SQRT((r1 + r2) / (n1 + n2) * (1 - (r1 + r2) / (n1 + n2)) * (1 / n1 + 1 / n2)), 2) AS z_score
FROM c;

-- -----------------------------------------------------------------------------
-- Step 4 · Review queue: flagged orders that are open, unpaid or reversed
-- -----------------------------------------------------------------------------
SELECT
    r.outcome,
    r.order_id,
    r.customer_id,
    cu.customer_name,
    r.order_date,
    r.order_status,
    r.order_value,
    r.amount_paid,
    CONCAT(IF(r.q1_lines > 0, 'Q1 ', ''), IF(r.q2_lines > 0, 'Q2 ', ''),
           IF(r.p1_lines > 0, 'P1 ', ''), IF(r.v1_order,     'V1',  ''))   AS rules_triggered
FROM `sahyadri_b2b.order_anomaly_review` AS r
JOIN `sahyadri_b2b.customers`            AS cu ON cu.customer_id = r.customer_id
WHERE r.is_flagged AND r.outcome NOT LIKE '1.%'
ORDER BY r.outcome DESC, r.order_value DESC;

-- The most extreme quantity lines (largest multiple of the product median)
SELECT
    a.order_id,
    a.customer_id,
    a.product_id,
    p.product_name,
    a.order_date,
    a.order_status,
    a.quantity,
    a.product_median_qty,
    ROUND(a.quantity / a.product_median_qty, 1)  AS multiple_of_median,
    a.line_gross
FROM `sahyadri_b2b.order_line_anomalies` AS a
JOIN `sahyadri_b2b.products`             AS p ON p.product_id = a.product_id
WHERE a.flag_q1_product_qty
ORDER BY multiple_of_median DESC
LIMIT 10;
