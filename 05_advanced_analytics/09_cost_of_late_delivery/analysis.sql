/* =============================================================================
   Case study · Cost of a late delivery
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   About one delivered order in five arrives after the promised date. The
   operations director is asking for budget (more dispatch staff, a premium
   carrier) to fix it, and the CFO wants to know what lateness actually
   costs the business before approving it:
     1. Do customers pay later for orders delivered late?
     2. Do they reorder less, or less quickly, after a late delivery?
     3. Does it get worse the later the delivery, or when lateness repeats?
     4. Are the differences caused by lateness, or by WHICH customers get
        late deliveries? (within-customer comparison)
     5. What is the cash cost per year?

   KEY RULES
     - Delivered orders with a promised date and a delivery date on every
       shipment. Final delivery = last shipment's delivery date.
     - Late = final delivery after the promised date.
     - Payment timing: orders with payment status Paid; paid date = last
       payment date of the order.
     - Collection outcome: deliveries up to 31 Mar 2026, so at least six
       months have passed for payment.
     - Reorder: the customer's next order (not Cancelled or Returned) placed
       within 30 / 90 days after the final delivery. Deliveries up to
       30 Jun 2026 only, so the 90 days can be observed.
     - Within-customer comparison: customers with at least one late and one
       on-time order; each customer's late average minus on-time average,
       then a paired t-test across customers.
     - Cash cost: extra days of cash outstanding x late-delivered revenue x
       cost of capital (assumed 10 % a year).
   ============================================================================= */

DECLARE as_of           DATE    DEFAULT DATE '2026-09-30';
DECLARE reorder_cutoff  DATE    DEFAULT DATE '2026-06-30';
DECLARE payment_cutoff  DATE    DEFAULT DATE '2026-03-31';
DECLARE cost_of_capital FLOAT64 DEFAULT 0.10;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per delivered order with lateness, payment and reorder
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.delivery_outcomes` AS
WITH deliveries AS (
    SELECT order_id,
           IF(COUNT(delivery_date) = COUNT(*), MAX(delivery_date), NULL) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
paid AS (
    SELECT order_id, MAX(payment_date) AS paid_date
    FROM `sahyadri_b2b.payments`
    GROUP BY order_id
),
revenue AS (
    SELECT order_id,
           SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_revenue
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
valid_orders AS (
    SELECT order_id, customer_id, order_date
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
),
base AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.promised_delivery_date,
        d.final_delivery_date,
        o.payment_status,
        r.order_revenue,
        IF(o.payment_status = 'Paid', p.paid_date, NULL)                        AS paid_date
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN deliveries AS d ON d.order_id = o.order_id
    JOIN revenue    AS r ON r.order_id = o.order_id
    LEFT JOIN paid  AS p ON p.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
      AND o.promised_delivery_date IS NOT NULL
      AND d.final_delivery_date IS NOT NULL
),
next_order AS (
    SELECT b.order_id, MIN(v.order_date) AS next_order_date
    FROM base AS b
    JOIN valid_orders AS v
      ON v.customer_id = b.customer_id AND v.order_date > b.final_delivery_date
    GROUP BY b.order_id
)
SELECT
    b.*,
    b.final_delivery_date > b.promised_delivery_date                            AS is_late,
    GREATEST(DATE_DIFF(b.final_delivery_date, b.promised_delivery_date, DAY), 0) AS days_late,
    CASE WHEN b.final_delivery_date <= b.promised_delivery_date THEN '0. On time'
         WHEN DATE_DIFF(b.final_delivery_date, b.promised_delivery_date, DAY) <= 3 THEN '1. 1-3 days late'
         WHEN DATE_DIFF(b.final_delivery_date, b.promised_delivery_date, DAY) <= 7 THEN '2. 4-7 days late'
         ELSE '3. 8+ days late' END                                              AS lateness_band,
    DATE_DIFF(b.final_delivery_date, b.order_date, DAY)                         AS order_to_delivery_days,
    DATE_DIFF(b.paid_date, b.order_date, DAY)                                   AS order_to_paid_days,
    DATE_DIFF(b.paid_date, b.final_delivery_date, DAY)                          AS delivery_to_paid_days,
    n.next_order_date,
    IFNULL(DATE_DIFF(n.next_order_date, b.final_delivery_date, DAY) <= 30, FALSE) AS reordered_30,
    IFNULL(DATE_DIFF(n.next_order_date, b.final_delivery_date, DAY) <= 90, FALSE) AS reordered_90,
    b.final_delivery_date <= reorder_cutoff                                     AS reorder_observed,
    b.final_delivery_date <= payment_cutoff                                     AS collection_observed,
    LAG(b.final_delivery_date > b.promised_delivery_date)
        OVER (PARTITION BY b.customer_id ORDER BY b.final_delivery_date, b.order_id) AS previous_delivery_late
FROM base AS b
LEFT JOIN next_order AS n ON n.order_id = b.order_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Pooled comparison: late against on-time, with test statistics
-- -----------------------------------------------------------------------------
WITH reorder AS (
    SELECT
        is_late,
        COUNT(*)                                          AS n,
        AVG(IF(reordered_30, 1, 0))                       AS r30,
        AVG(IF(reordered_90, 1, 0))                       AS r90
    FROM `sahyadri_b2b.delivery_outcomes`
    WHERE reorder_observed
    GROUP BY is_late
),
payment AS (
    SELECT
        is_late,
        COUNT(*)                                          AS n,
        AVG(order_to_paid_days)                           AS mean_days,
        STDDEV_SAMP(order_to_paid_days)                   AS sd_days,
        APPROX_QUANTILES(order_to_paid_days, 2)[OFFSET(1)] AS median_days,
        AVG(delivery_to_paid_days)                        AS mean_delivery_to_paid,
        APPROX_QUANTILES(delivery_to_paid_days, 2)[OFFSET(1)] AS median_delivery_to_paid,
        AVG(order_to_delivery_days)                       AS mean_order_to_delivery
    FROM `sahyadri_b2b.delivery_outcomes`
    WHERE payment_status = 'Paid'
    GROUP BY is_late
),
collection AS (
    SELECT
        is_late,
        COUNT(*)                                          AS n,
        AVG(IF(payment_status = 'Paid', 1, 0))            AS paid_share,
        AVG(IF(payment_status = 'Unpaid', 1, 0))          AS unpaid_share
    FROM `sahyadri_b2b.delivery_outcomes`
    WHERE collection_observed
    GROUP BY is_late
)
SELECT
    IF(r.is_late, 'Late', 'On time')                      AS delivery,
    r.n                                                   AS deliveries_reorder_observed,
    ROUND(100 * r.r30, 1)                                 AS reordered_30_pct,
    ROUND(100 * r.r90, 1)                                 AS reordered_90_pct,
    p.n                                                   AS paid_orders,
    ROUND(p.mean_order_to_delivery, 1)                    AS mean_order_to_delivery_days,
    ROUND(p.mean_days, 1)                                 AS mean_order_to_paid_days,
    p.median_days                                         AS median_order_to_paid_days,
    ROUND(p.mean_delivery_to_paid, 1)                     AS mean_delivery_to_paid_days,
    p.median_delivery_to_paid                             AS median_delivery_to_paid_days,
    c.n                                                   AS deliveries_collection_observed,
    ROUND(100 * c.paid_share, 1)                          AS fully_paid_pct,
    ROUND(100 * c.unpaid_share, 1)                        AS unpaid_pct
FROM reorder    AS r
JOIN payment    AS p ON p.is_late = r.is_late
JOIN collection AS c ON c.is_late = r.is_late
ORDER BY delivery DESC;

-- Test statistics for the pooled differences
WITH reorder AS (
    SELECT
        COUNTIF(is_late) AS n1, COUNTIF(NOT is_late) AS n0,
        AVG(IF(is_late, IF(reordered_30, 1, 0), NULL))     AS p1,
        AVG(IF(NOT is_late, IF(reordered_30, 1, 0), NULL)) AS p0,
        AVG(IF(reordered_30, 1, 0))                        AS p
    FROM `sahyadri_b2b.delivery_outcomes`
    WHERE reorder_observed
),
payment AS (
    SELECT
        COUNTIF(is_late) AS n1, COUNTIF(NOT is_late) AS n0,
        AVG(IF(is_late, order_to_paid_days, NULL))         AS m1,
        AVG(IF(NOT is_late, order_to_paid_days, NULL))     AS m0,
        VAR_SAMP(IF(is_late, order_to_paid_days, NULL))    AS v1,
        VAR_SAMP(IF(NOT is_late, order_to_paid_days, NULL)) AS v0
    FROM `sahyadri_b2b.delivery_outcomes`
    WHERE payment_status = 'Paid'
)
SELECT 'Reorder within 30 days (two-proportion z)' AS test,
       ROUND(100 * (p1 - p0), 1)                    AS difference_late_minus_on_time,
       ROUND((p1 - p0) / SQRT(p * (1 - p) * (1 / n1 + 1 / n0)), 2) AS statistic
FROM reorder
UNION ALL
SELECT 'Order-to-paid days (Welch t)',
       ROUND(m1 - m0, 1),
       ROUND((m1 - m0) / SQRT(v1 / n1 + v0 / n0), 2)
FROM payment;

-- -----------------------------------------------------------------------------
-- Step 3 · Does it get worse the later the delivery?
-- -----------------------------------------------------------------------------
SELECT
    lateness_band,
    COUNTIF(reorder_observed)                                                AS deliveries_reorder_observed,
    ROUND(100 * AVG(IF(reorder_observed, IF(reordered_30, 1, 0), NULL)), 1)  AS reordered_30_pct,
    ROUND(100 * AVG(IF(reorder_observed, IF(reordered_90, 1, 0), NULL)), 1)  AS reordered_90_pct,
    COUNTIF(payment_status = 'Paid')                                         AS paid_orders,
    ROUND(AVG(order_to_delivery_days), 1)                                    AS mean_order_to_delivery_days,
    ROUND(AVG(order_to_paid_days), 1)                                        AS mean_order_to_paid_days,
    ROUND(AVG(delivery_to_paid_days), 1)                                     AS mean_delivery_to_paid_days
FROM `sahyadri_b2b.delivery_outcomes`
GROUP BY lateness_band
ORDER BY lateness_band;

-- Repeated lateness: this delivery and the previous one
SELECT
    CASE WHEN previous_delivery_late IS NULL THEN '0. First delivery'
         WHEN previous_delivery_late THEN '2. Previous late'
         ELSE '1. Previous on time' END                        AS previous_delivery,
    IF(is_late, 'Late', 'On time')                             AS this_delivery,
    COUNT(*)                                                   AS deliveries_reorder_observed,
    ROUND(100 * AVG(IF(reordered_30, 1, 0)), 1)                AS reordered_30_pct,
    ROUND(100 * AVG(IF(reordered_90, 1, 0)), 1)                AS reordered_90_pct
FROM `sahyadri_b2b.delivery_outcomes`
WHERE reorder_observed
GROUP BY previous_delivery, this_delivery
ORDER BY previous_delivery, this_delivery DESC;

-- Did customers who went quiet leave after a late delivery?
-- Last measured delivery of each customer: lapsed (no order in the last 180 days) vs still active
WITH last_valid_order AS (
    SELECT customer_id, MAX(order_date) AS last_order_date
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY customer_id
),
last_delivery AS (
    SELECT * FROM `sahyadri_b2b.delivery_outcomes`
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY final_delivery_date DESC, order_id DESC) = 1
)
SELECT
    IF(v.last_order_date <= DATE_SUB(as_of, INTERVAL 180 DAY), 'Lapsed (no order in 180 days)', 'Active') AS customer_status,
    COUNT(*)                                                   AS customers,
    ROUND(100 * AVG(IF(d.is_late, 1, 0)), 1)                   AS last_delivery_late_pct
FROM last_delivery AS d
JOIN last_valid_order AS v ON v.customer_id = d.customer_id
GROUP BY customer_status
ORDER BY customer_status;

-- -----------------------------------------------------------------------------
-- Step 4 · Within-customer comparison: the same customer, late vs on time
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.late_delivery_paired` AS
WITH reorder AS (
    SELECT
        customer_id,
        AVG(IF(is_late, IF(reordered_30, 1, 0), NULL)) - AVG(IF(NOT is_late, IF(reordered_30, 1, 0), NULL)) AS diff_reorder_30,
        AVG(IF(is_late, IF(reordered_90, 1, 0), NULL)) - AVG(IF(NOT is_late, IF(reordered_90, 1, 0), NULL)) AS diff_reorder_90
    FROM `sahyadri_b2b.delivery_outcomes`
    WHERE reorder_observed
    GROUP BY customer_id
    HAVING COUNTIF(is_late) > 0 AND COUNTIF(NOT is_late) > 0
),
payment AS (
    SELECT
        customer_id,
        AVG(IF(is_late, order_to_paid_days, NULL))    - AVG(IF(NOT is_late, order_to_paid_days, NULL))    AS diff_order_to_paid,
        AVG(IF(is_late, delivery_to_paid_days, NULL)) - AVG(IF(NOT is_late, delivery_to_paid_days, NULL)) AS diff_delivery_to_paid,
        AVG(IF(is_late, order_to_delivery_days, NULL)) - AVG(IF(NOT is_late, order_to_delivery_days, NULL)) AS diff_order_to_delivery
    FROM `sahyadri_b2b.delivery_outcomes`
    WHERE payment_status = 'Paid'
    GROUP BY customer_id
    HAVING COUNTIF(is_late) > 0 AND COUNTIF(NOT is_late) > 0
)
SELECT 'Reorder within 30 days (points)' AS measure, customer_id, 100 * diff_reorder_30 AS difference FROM reorder
UNION ALL
SELECT 'Reorder within 90 days (points)', customer_id, 100 * diff_reorder_90 FROM reorder
UNION ALL
SELECT 'Order to delivery (days)', customer_id, diff_order_to_delivery FROM payment
UNION ALL
SELECT 'Order to paid (days)', customer_id, diff_order_to_paid FROM payment
UNION ALL
SELECT 'Delivery to paid (days)', customer_id, diff_delivery_to_paid FROM payment;

SELECT
    measure,
    COUNT(*)                                                   AS customers,
    ROUND(AVG(difference), 2)                                  AS mean_difference_late_minus_on_time,
    ROUND(STDDEV_SAMP(difference) / SQRT(COUNT(*)), 2)         AS standard_error,
    ROUND(AVG(difference) / (STDDEV_SAMP(difference) / SQRT(COUNT(*))), 2) AS paired_t
FROM `sahyadri_b2b.late_delivery_paired`
GROUP BY measure
ORDER BY measure;

-- -----------------------------------------------------------------------------
-- Step 5 · Cash cost per year of slower payment on late deliveries
-- -----------------------------------------------------------------------------
WITH extra_days AS (
    SELECT AVG(difference) AS days
    FROM `sahyadri_b2b.late_delivery_paired`
    WHERE measure = 'Order to paid (days)'
),
late_revenue AS (
    SELECT SUM(order_revenue) AS revenue, COUNT(*) AS orders
    FROM `sahyadri_b2b.delivery_outcomes`
    WHERE is_late
      AND final_delivery_date > DATE_SUB(as_of, INTERVAL 12 MONTH)
)
SELECT
    l.orders                                                   AS late_deliveries_12m,
    ROUND(l.revenue, 0)                                        AS late_delivered_revenue_12m,
    ROUND(e.days, 1)                                           AS extra_days_to_payment,
    ROUND(l.revenue * e.days / 365, 0)                         AS extra_average_receivables,
    ROUND(l.revenue * e.days / 365 * cost_of_capital, 0)       AS annual_financing_cost
FROM late_revenue AS l
CROSS JOIN extra_days AS e;
