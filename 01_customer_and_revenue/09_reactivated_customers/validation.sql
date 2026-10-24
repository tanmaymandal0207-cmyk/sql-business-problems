/* =============================================================================
   Case study · Reactivated customers — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of      DATE  DEFAULT DATE '2026-09-30';
DECLARE lapse_days INT64 DEFAULT 180;

WITH g AS (SELECT * FROM `sahyadri_b2b.customer_order_gaps`),
     e AS (SELECT * FROM `sahyadri_b2b.reactivation_events`),

source_orders AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, o.order_date
),
-- Independent return test: the customer has an earlier order, and no earlier
-- (or same-day, lower id) order inside the 180 days before this one
recount AS (
    SELECT a.order_id,
           COUNTIF(b.order_date < a.order_date OR (b.order_date = a.order_date AND b.order_id < a.order_id)) AS earlier_orders,
           COUNTIF((b.order_date < a.order_date OR (b.order_date = a.order_date AND b.order_id < a.order_id))
                   AND b.order_date >= DATE_SUB(a.order_date, INTERVAL lapse_days DAY))                      AS earlier_within_window
    FROM source_orders AS a
    JOIN source_orders AS b ON b.customer_id = a.customer_id AND b.order_id <> a.order_id
    GROUP BY a.order_id
),
customer_span AS (
    SELECT customer_id,
           SUM(IFNULL(days_since_previous, 0))                 AS summed_gaps,
           DATE_DIFF(MAX(order_date), MIN(order_date), DAY)    AS span_days
    FROM g
    GROUP BY customer_id
),

checks AS (
    SELECT '01. Gap table orders vs source valid orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM g) - (SELECT COUNT(*) FROM source_orders)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM g) AS actual
    UNION ALL
    SELECT '02. Gap table revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM g) - (SELECT SUM(revenue) FROM source_orders), 0) AS INT64)
    UNION ALL
    SELECT '03. First orders = customers, with no previous date', 0,
           ABS((SELECT COUNTIF(order_seq = 1) FROM g) - (SELECT COUNT(DISTINCT customer_id) FROM source_orders))
         + (SELECT COUNTIF(order_seq = 1 AND previous_order_date IS NOT NULL) FROM g)
    UNION ALL
    SELECT '04. Returns vs independent self-join recount', 0,
           (SELECT COUNTIF(is_return) FROM g)
         - (SELECT COUNTIF(earlier_orders > 0 AND earlier_within_window = 0) FROM recount)
    UNION ALL
    SELECT '05. Event rows vs returns in gap table', 0,
           (SELECT COUNT(*) FROM e) - (SELECT COUNTIF(is_return) FROM g)
         + (SELECT COUNT(*) - COUNT(DISTINCT return_order_id) FROM e)
    UNION ALL
    SELECT '06. Events with gap <= 180 days or last order not before return', 0,
           (SELECT COUNTIF(gap_days <= lapse_days OR last_order_before_gap >= return_date) FROM e)
    UNION ALL
    SELECT '07. Stayed flag vs next order date', 0,
           (SELECT COUNTIF(stayed != IFNULL(DATE_DIFF(next_order_date, return_date, DAY) <= lapse_days, FALSE)) FROM e)
    UNION ALL
    SELECT '08. After-window revenue below the return order or no order counted', 0,
           (SELECT COUNTIF(revenue_180_after < return_order_revenue - 0.01 OR orders_180_after < 1) FROM e)
    UNION ALL
    SELECT '09. Observed flag vs as-of cut-off', 0,
           (SELECT COUNTIF(is_observed != (return_date <= DATE_SUB(as_of, INTERVAL lapse_days DAY))) FROM e)
    UNION ALL
    SELECT '10. Summed gaps = first-to-last order span, per customer', 0,
           (SELECT COUNTIF(summed_gaps != span_days) FROM customer_span)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
