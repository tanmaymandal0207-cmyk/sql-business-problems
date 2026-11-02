/* =============================================================================
   Case study · Do overdue balances slow a customer's ordering?
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Sales and finance disagree. Finance wants salespeople to chase overdue
   invoices before taking new orders. Sales says customers who owe money
   order *more*, not less, so chasing them puts revenue at risk. Both sides
   quote the same report: customers with an overdue balance place about four
   times as many orders a month. The commercial director asks:
     1. Do customers order less in months when they have an overdue balance?
     2. Is the raw comparison a fair answer, or is it comparing different
        customers?
     3. Does a bigger overdue balance make a difference?
     4. Does it differ by segment?

   METHOD
     - Customer-months from April 2024 to September 2026, starting the month
       after the customer's first order.
     - Overdue at the start of a month: a valid (not Cancelled or Returned),
       fully delivered order delivered more than 90 days earlier (beyond the
       usual terms of every segment) that had not received 99 % of its value
       by then. Overdue amount = the unpaid balance on those orders.
     - Outcome: orders placed in the month (all statuses) and valid revenue.
     - Raw comparison: average orders in overdue against other months.
     - Within-customer comparison: each customer's months are compared with
       that customer's own average (customers with both kinds of months),
       so the large accounts that always owe something no longer dominate.
     - Same customer and same recent activity: an overdue balance needs
       earlier orders, so busy spells and overdue months go together. The
       main comparison is within customer x band of orders placed in the
       previous six months (none, 1-2, 3-5, 6+).
     - Permutation test: 500 shuffles of the overdue flag within each
       customer x activity cell.
     - Active months only: a check that leaves out months after a
       customer's last order (lost customers with unpaid debts).
   ============================================================================= */

DECLARE first_month   DATE    DEFAULT DATE '2024-04-01';
DECLARE last_month    DATE    DEFAULT DATE '2026-09-01';
DECLARE overdue_days  INT64   DEFAULT 90;
DECLARE settled_share FLOAT64 DEFAULT 0.99;
DECLARE shuffles      INT64   DEFAULT 500;
DECLARE prime         INT64   DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Customer-months with overdue status and orders placed
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ob_months` AS
WITH value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id
),
delivered AS (
    SELECT order_id, MAX(delivery_date) AS delivered_on
    FROM `sahyadri_b2b.shipments` GROUP BY order_id
    HAVING COUNT(delivery_date) = COUNT(*)
),
receivables AS (
    SELECT o.order_id, o.customer_id, v.order_value, d.delivered_on
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN value AS v ON v.order_id = o.order_id
    JOIN delivered AS d ON d.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
months AS (
    SELECT m FROM UNNEST(GENERATE_DATE_ARRAY(first_month, last_month, INTERVAL 1 MONTH)) AS m
),
customer_span AS (
    SELECT customer_id, MIN(order_date) AS first_order, MAX(order_date) AS last_order
    FROM `sahyadri_b2b.sales_orders` GROUP BY customer_id
),
grid AS (
    SELECT c.customer_id, mo.m, c.last_order
    FROM customer_span AS c
    JOIN months AS mo ON mo.m > c.first_order
),
-- balance of each receivable at the start of each month, for receivables already past due
past_due AS (
    SELECT g.customer_id, g.m, r.order_id, r.order_value,
           r.order_value - IFNULL(SUM(IF(p.payment_date < g.m, p.amount, 0)), 0) AS balance
    FROM grid AS g
    JOIN receivables AS r
      ON r.customer_id = g.customer_id AND DATE_ADD(r.delivered_on, INTERVAL overdue_days DAY) < g.m
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = r.order_id
    GROUP BY g.customer_id, g.m, r.order_id, r.order_value
),
overdue AS (
    SELECT customer_id, m, COUNT(*) AS overdue_orders, SUM(balance) AS overdue_amount
    FROM past_due
    WHERE balance > (1 - settled_share) * order_value
    GROUP BY customer_id, m
),
placed AS (
    SELECT o.customer_id, DATE_TRUNC(o.order_date, MONTH) AS m, COUNT(*) AS orders,
           SUM(IF(o.order_status NOT IN ('Cancelled', 'Returned'), v.order_value, 0)) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    LEFT JOIN value AS v ON v.order_id = o.order_id
    GROUP BY o.customer_id, m
)
SELECT
    g.customer_id, c.customer_segment, g.m AS month,
    g.m <= g.last_order                                                               AS active_month,
    od.customer_id IS NOT NULL                                                        AS overdue,
    IFNULL(od.overdue_orders, 0)                                                      AS overdue_orders,
    IFNULL(od.overdue_amount, 0)                                                      AS overdue_amount,
    IFNULL(pl.orders, 0)                                                              AS orders,
    IFNULL(pl.revenue, 0)                                                             AS revenue,
    ROW_NUMBER() OVER (PARTITION BY g.customer_id ORDER BY g.m)                       AS month_no,
    -- orders placed in the previous six months: how active the customer was going into the month
    IFNULL(SUM(IFNULL(pl.orders, 0)) OVER (PARTITION BY g.customer_id ORDER BY g.m ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING), 0) AS prior_6m_orders
FROM grid AS g
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = g.customer_id
LEFT JOIN overdue AS od ON od.customer_id = g.customer_id AND od.m = g.m
LEFT JOIN placed AS pl ON pl.customer_id = g.customer_id AND pl.m = g.m;

-- -----------------------------------------------------------------------------
-- Step 2 · The raw comparison
-- -----------------------------------------------------------------------------
SELECT
    IF(overdue, 'Overdue balance', 'No overdue balance')                              AS month_type,
    COUNT(*)                                                                          AS customer_months,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(AVG(orders), 3)                                                             AS orders_per_month,
    ROUND(AVG(revenue) / 1e3, 1)                                                      AS revenue_per_month_k,
    ROUND(100 * AVG(IF(orders > 0, 1, 0)), 1)                                         AS months_with_an_order_pct
FROM `sahyadri_b2b.ob_months`
GROUP BY month_type
ORDER BY month_type DESC;

-- Who has overdue balances? Customers by share of their months overdue
WITH c AS (
    SELECT customer_id, AVG(IF(overdue, 1, 0)) AS share_overdue, AVG(orders) AS orders_per_month
    FROM `sahyadri_b2b.ob_months` GROUP BY customer_id
)
SELECT
    CASE WHEN share_overdue = 0 THEN '1. Never overdue' WHEN share_overdue < 0.5 THEN '2. Overdue < half the months'
         WHEN share_overdue < 1 THEN '3. Overdue half the months or more' ELSE '4. Always overdue' END AS customer_type,
    COUNT(*)                                                                          AS customers,
    ROUND(AVG(orders_per_month), 2)                                                   AS orders_per_month
FROM c
GROUP BY customer_type
ORDER BY customer_type;

-- -----------------------------------------------------------------------------
-- Step 3 · Within-customer comparison, with a permutation test
-- -----------------------------------------------------------------------------
-- (a) Same customer: each customer's months against its own average
WITH mixed AS (
    SELECT customer_id FROM `sahyadri_b2b.ob_months`
    GROUP BY customer_id
    HAVING COUNTIF(overdue) > 0 AND COUNTIF(NOT overdue) > 0
),
centred AS (
    SELECT m.*, m.orders - AVG(m.orders) OVER (PARTITION BY m.customer_id) AS orders_dev
    FROM `sahyadri_b2b.ob_months` AS m JOIN mixed USING (customer_id)
)
SELECT
    COUNT(DISTINCT customer_id)                                                       AS customers,
    COUNT(*)                                                                          AS customer_months,
    ROUND(AVG(IF(overdue, orders_dev, NULL)) - AVG(IF(NOT overdue, orders_dev, NULL)), 3) AS within_customer_difference
FROM centred;

-- (b) Same customer and same recent activity: an overdue balance needs earlier orders,
--     so months are compared only with the customer's months of similar activity
CREATE OR REPLACE TABLE `sahyadri_b2b.ob_within` AS
WITH banded AS (
    SELECT *,
           CASE WHEN prior_6m_orders = 0 THEN '1. None' WHEN prior_6m_orders <= 2 THEN '2. 1-2'
                WHEN prior_6m_orders <= 5 THEN '3. 3-5' ELSE '4. 6+' END              AS activity_band
    FROM `sahyadri_b2b.ob_months`
),
mixed AS (
    -- cells (customer x activity band) with both overdue and clear months
    SELECT customer_id, activity_band FROM banded
    GROUP BY customer_id, activity_band
    HAVING COUNTIF(overdue) > 0 AND COUNTIF(NOT overdue) > 0
)
SELECT b.*,
       b.orders  - AVG(b.orders)  OVER (PARTITION BY b.customer_id, b.activity_band)  AS orders_dev,
       b.revenue - AVG(b.revenue) OVER (PARTITION BY b.customer_id, b.activity_band)  AS revenue_dev,
       ROW_NUMBER() OVER (PARTITION BY b.customer_id, b.activity_band ORDER BY b.month) AS cell_no
FROM banded AS b
JOIN mixed USING (customer_id, activity_band);

CREATE OR REPLACE TABLE `sahyadri_b2b.ob_permutations` AS
WITH draws AS (
    SELECT w.customer_id, w.activity_band, w.cell_no, w.orders_dev, b,
           ROW_NUMBER() OVER (PARTITION BY b, w.customer_id, w.activity_band
                              ORDER BY MOD(MOD(b * 7919 + w.customer_id * 104729 + w.month_no * 1299709, prime)
                                         * MOD(b * 7919 + w.customer_id * 104729 + w.month_no * 1299709, prime) + 12345, prime)) AS shuffled_no
    FROM `sahyadri_b2b.ob_within` AS w
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, shuffles)) AS b
),
relabelled AS (
    -- each month takes the overdue flag of another month in the same cell
    SELECT d.b, d.orders_dev, f.overdue
    FROM draws AS d
    JOIN `sahyadri_b2b.ob_within` AS f
      ON f.customer_id = d.customer_id AND f.activity_band = d.activity_band AND f.cell_no = d.shuffled_no
)
SELECT b, AVG(IF(overdue, orders_dev, NULL)) - AVG(IF(NOT overdue, orders_dev, NULL)) AS difference
FROM relabelled
GROUP BY b;

WITH observed AS (
    SELECT AVG(IF(overdue, orders_dev, NULL)) - AVG(IF(NOT overdue, orders_dev, NULL))   AS difference,
           AVG(IF(overdue, revenue_dev, NULL)) - AVG(IF(NOT overdue, revenue_dev, NULL)) AS revenue_difference,
           COUNT(DISTINCT customer_id)                                                    AS customers,
           COUNT(*)                                                                       AS customer_months,
           AVG(orders)                                                                    AS orders_per_month
    FROM `sahyadri_b2b.ob_within`
)
SELECT
    o.customers, o.customer_months,
    ROUND(o.difference, 3)                                                            AS within_difference_orders,
    ROUND(100 * o.difference / o.orders_per_month, 1)                                 AS within_difference_pct,
    ROUND(o.revenue_difference / 1e3, 1)                                              AS within_difference_revenue_k,
    ROUND(APPROX_QUANTILES(p.difference, 40)[OFFSET(1)], 3)                           AS shuffle_p2_5,
    ROUND(APPROX_QUANTILES(p.difference, 40)[OFFSET(39)], 3)                          AS shuffle_p97_5,
    ROUND(AVG(IF(ABS(p.difference) >= ABS(o.difference), 1, 0)), 3)                   AS p_value_two_sided
FROM observed AS o
CROSS JOIN `sahyadri_b2b.ob_permutations` AS p
GROUP BY o.customers, o.customer_months, o.difference, o.revenue_difference, o.orders_per_month;

-- By recent activity
SELECT
    activity_band,
    COUNTIF(overdue)                                                                  AS overdue_months,
    COUNTIF(NOT overdue)                                                              AS clear_months,
    ROUND(AVG(IF(overdue, orders, NULL)), 2)                                          AS orders_when_overdue,
    ROUND(AVG(IF(NOT overdue, orders, NULL)), 2)                                      AS orders_when_clear,
    ROUND(AVG(IF(overdue, orders_dev, NULL)) - AVG(IF(NOT overdue, orders_dev, NULL)), 3) AS within_difference_orders
FROM `sahyadri_b2b.ob_within`
GROUP BY activity_band
ORDER BY activity_band;

-- Customer by customer: did each order less in its overdue months (same activity band)?
WITH per_customer AS (
    SELECT customer_id,
           AVG(IF(overdue, orders_dev, NULL)) - AVG(IF(NOT overdue, orders_dev, NULL))    AS difference
    FROM `sahyadri_b2b.ob_within` GROUP BY customer_id
)
SELECT
    COUNT(*)                                                                          AS customers,
    COUNTIF(difference < 0)                                                           AS ordered_less_when_overdue,
    COUNTIF(difference > 0)                                                           AS ordered_more_when_overdue,
    COUNTIF(difference = 0)                                                           AS no_difference
FROM per_customer;

-- -----------------------------------------------------------------------------
-- Step 4 · Size of the overdue balance, segments and active months only
-- -----------------------------------------------------------------------------
WITH typical AS (
    SELECT customer_id, AVG(revenue) AS avg_monthly_revenue FROM `sahyadri_b2b.ob_months` GROUP BY customer_id
)
SELECT
    CASE WHEN NOT w.overdue THEN '0. Not overdue'
         WHEN w.overdue_amount < t.avg_monthly_revenue THEN '1. Under one month of revenue'
         WHEN w.overdue_amount < 3 * t.avg_monthly_revenue THEN '2. One to three months'
         ELSE '3. Over three months' END                                              AS overdue_size,
    COUNT(*)                                                                          AS customer_months,
    ROUND(AVG(w.orders_dev), 3)                                                       AS orders_vs_own_average,
    ROUND(AVG(w.orders), 2)                                                           AS orders_per_month
FROM `sahyadri_b2b.ob_within` AS w
JOIN typical AS t USING (customer_id)
GROUP BY overdue_size
ORDER BY overdue_size;

SELECT
    customer_segment,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(100 * AVG(IF(overdue, 1, 0)), 1)                                            AS months_overdue_pct,
    ROUND(AVG(IF(overdue, orders_dev, NULL)) - AVG(IF(NOT overdue, orders_dev, NULL)), 3) AS within_difference_orders,
    ROUND(AVG(orders), 2)                                                             AS orders_per_month
FROM `sahyadri_b2b.ob_within`
GROUP BY customer_segment
ORDER BY customer_segment;

-- Active months only: the same comparison without months after the customer's last order
WITH banded AS (
    SELECT *,
           CASE WHEN prior_6m_orders = 0 THEN '1. None' WHEN prior_6m_orders <= 2 THEN '2. 1-2'
                WHEN prior_6m_orders <= 5 THEN '3. 3-5' ELSE '4. 6+' END              AS activity_band
    FROM `sahyadri_b2b.ob_months`
    WHERE active_month
),
mixed AS (
    SELECT customer_id, activity_band FROM banded
    GROUP BY customer_id, activity_band
    HAVING COUNTIF(overdue) > 0 AND COUNTIF(NOT overdue) > 0
),
centred AS (
    SELECT b.*, b.orders - AVG(b.orders) OVER (PARTITION BY b.customer_id, b.activity_band) AS dev
    FROM banded AS b JOIN mixed USING (customer_id, activity_band)
)
SELECT
    COUNT(DISTINCT customer_id)                                                       AS customers,
    COUNT(*)                                                                          AS customer_months,
    ROUND(AVG(IF(overdue, dev, NULL)) - AVG(IF(NOT overdue, dev, NULL)), 3)           AS within_difference_orders,
    (SELECT COUNTIF(NOT active_month) FROM `sahyadri_b2b.ob_months`)                  AS months_after_last_order,
    (SELECT ROUND(100 * AVG(IF(overdue, 1, 0)), 1) FROM `sahyadri_b2b.ob_months` WHERE NOT active_month) AS overdue_pct_after_last_order
FROM centred;
