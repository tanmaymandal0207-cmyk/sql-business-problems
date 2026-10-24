/* =============================================================================
   Case study · Cost of a late delivery — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE reorder_cutoff DATE DEFAULT DATE '2026-06-30';
DECLARE payment_cutoff DATE DEFAULT DATE '2026-03-31';

WITH d AS (SELECT * FROM `sahyadri_b2b.delivery_outcomes`),
     pr AS (SELECT * FROM `sahyadri_b2b.late_delivery_paired`),

eligible AS (
    SELECT o.order_id
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments`    AS s ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND o.promised_delivery_date IS NOT NULL
    GROUP BY o.order_id
    HAVING COUNTIF(s.delivery_date IS NULL) = 0
),
valid_orders AS (
    SELECT order_id, customer_id, order_date
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
),
-- orders placed after the delivery but before the recorded "next" order (should be none)
skipped AS (
    SELECT COUNT(*) AS n
    FROM d
    JOIN valid_orders AS v
      ON v.customer_id = d.customer_id
     AND v.order_date > d.final_delivery_date
     AND (d.next_order_date IS NULL OR v.order_date < d.next_order_date)
),
pair_customers AS (
    SELECT 'Reorder within 30 days (points)' AS measure, COUNT(*) AS n FROM (
        SELECT customer_id FROM d WHERE reorder_observed GROUP BY customer_id
        HAVING COUNTIF(is_late) > 0 AND COUNTIF(NOT is_late) > 0)
    UNION ALL
    SELECT 'Order to paid (days)', COUNT(*) FROM (
        SELECT customer_id FROM d WHERE payment_status = 'Paid' GROUP BY customer_id
        HAVING COUNTIF(is_late) > 0 AND COUNTIF(NOT is_late) > 0)
),
paired_wide AS (
    SELECT customer_id,
           MAX(IF(measure = 'Order to paid (days)', difference, NULL))     AS to_paid,
           MAX(IF(measure = 'Order to delivery (days)', difference, NULL)) AS to_delivery,
           MAX(IF(measure = 'Delivery to paid (days)', difference, NULL))  AS delivery_to_paid
    FROM pr
    GROUP BY customer_id
),

checks AS (
    SELECT '01. Outcome rows vs eligible delivered orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM d) - (SELECT COUNT(*) FROM eligible)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM d) AS actual
    UNION ALL
    SELECT '02. Late flag or days late inconsistent with dates', 0,
           (SELECT COUNTIF(is_late != (final_delivery_date > promised_delivery_date)
                        OR (is_late AND days_late <= 0) OR (NOT is_late AND days_late != 0)) FROM d)
    UNION ALL
    SELECT '03. Lateness band inconsistent with days late', 0,
           (SELECT COUNTIF(lateness_band != CASE WHEN days_late = 0 THEN '0. On time'
                                                 WHEN days_late <= 3 THEN '1. 1-3 days late'
                                                 WHEN days_late <= 7 THEN '2. 4-7 days late'
                                                 ELSE '3. 8+ days late' END) FROM d)
    UNION ALL
    SELECT '04. Paid orders without a paid date, or others with one', 0,
           (SELECT COUNTIF((payment_status = 'Paid') != (paid_date IS NOT NULL)) FROM d)
    UNION ALL
    SELECT '05. Valid orders skipped between delivery and next order', 0,
           (SELECT n FROM skipped)
    UNION ALL
    SELECT '06. Reorder flags inconsistent (30-day without 90-day, or with no next order)', 0,
           (SELECT COUNTIF((reordered_30 AND NOT reordered_90) OR (reordered_90 AND next_order_date IS NULL)) FROM d)
    UNION ALL
    SELECT '07. Observation flags vs cut-off dates', 0,
           (SELECT COUNTIF(reorder_observed != (final_delivery_date <= reorder_cutoff)
                        OR collection_observed != (final_delivery_date <= payment_cutoff)) FROM d)
    UNION ALL
    SELECT '08. Paired customers vs independent recount', 0,
           (SELECT SUM(ABS(p.n - x.n)) FROM pair_customers AS p
              JOIN (SELECT measure, COUNT(*) AS n FROM pr GROUP BY measure) AS x ON x.measure = p.measure)
    UNION ALL
    SELECT '09. Paired: order-to-paid = order-to-delivery + delivery-to-paid', 0,
           (SELECT COUNTIF(ABS(to_paid - (to_delivery + delivery_to_paid)) > 1e-9) FROM paired_wide WHERE to_paid IS NOT NULL)
    UNION ALL
    SELECT '10. Outcome revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(order_revenue) FROM d)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i JOIN eligible AS e ON e.order_id = i.order_id), 0) AS INT64)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
