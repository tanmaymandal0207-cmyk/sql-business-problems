/* =============================================================================
   Case study · Order-to-cash process mining — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE paise FLOAT64 DEFAULT 0.05;

WITH e AS (SELECT * FROM `sahyadri_b2b.pm_events`),
     c AS (SELECT * FROM `sahyadri_b2b.pm_cases`),
     v AS (SELECT * FROM `sahyadri_b2b.pm_variants`),

src_counts AS (
    SELECT o.order_id,
           IFNULL(s.n, 0) AS dispatches, IFNULL(s.d, 0) AS deliveries, IFNULL(p.n, 0) AS payments
    FROM `sahyadri_b2b.sales_orders` AS o
    LEFT JOIN (SELECT order_id, COUNT(*) AS n, COUNT(delivery_date) AS d FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS s
      ON s.order_id = o.order_id
    LEFT JOIN (SELECT order_id, COUNT(*) AS n FROM `sahyadri_b2b.payments` GROUP BY order_id) AS p
      ON p.order_id = o.order_id
),
order_value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id
),
-- fully paid date recomputed with a self-join (no window function)
cum AS (
    SELECT a.order_id, a.payment_date, SUM(b.amount) AS paid
    FROM `sahyadri_b2b.payments` AS a
    JOIN `sahyadri_b2b.payments` AS b
      ON b.order_id = a.order_id
     AND (b.payment_date < a.payment_date OR (b.payment_date = a.payment_date AND b.payment_id <= a.payment_id))
    GROUP BY a.order_id, a.payment_id, a.payment_date
),
paid_recount AS (
    SELECT cum.order_id, MIN(cum.payment_date) AS d
    FROM cum JOIN order_value AS ov ON ov.order_id = cum.order_id
    WHERE cum.paid >= ov.v - paise
    GROUP BY cum.order_id
),
pairs AS (
    SELECT COUNT(*) AS n
    FROM e AS a JOIN e AS b ON b.order_id = a.order_id AND b.event_no = a.event_no + 1
),

checks AS (
    SELECT '01. Events = orders + shipments + dated deliveries + payments' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM e)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders`)
         - (SELECT COUNT(*) + COUNT(delivery_date) FROM `sahyadri_b2b.shipments`)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.payments`) AS actual
    UNION ALL
    SELECT '02. Event numbers run 1..n without gaps in every order', 0,
           (SELECT COUNTIF(mx != n OR mn != 1) FROM (SELECT order_id, MAX(event_no) AS mx, MIN(event_no) AS mn, COUNT(*) AS n FROM e GROUP BY order_id))
    UNION ALL
    SELECT '03. One case per order, each with exactly one Order event', 0,
           (SELECT COUNT(*) FROM c) - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders`)
         + (SELECT COUNTIF(n != 1) FROM (SELECT order_id, COUNTIF(activity = 'Order') AS n FROM e GROUP BY order_id))
    UNION ALL
    SELECT '04. Dispatch, delivery and payment counts = source', 0,
           (SELECT COUNT(*) FROM c JOIN src_counts AS s USING (order_id)
             WHERE c.dispatches != s.dispatches OR c.deliveries != s.deliveries OR c.payments != s.payments)
    UNION ALL
    SELECT '05. Fully paid date = self-join recount', 0,
           (SELECT COUNT(*) FROM c LEFT JOIN paid_recount AS r USING (order_id)
             WHERE IFNULL(c.fully_paid_date, DATE '1900-01-01') != IFNULL(r.d, DATE '1900-01-01'))
    UNION ALL
    SELECT '06. Paid path groups have a fully paid date, unpaid group has none', 0,
           (SELECT COUNTIF((path_group IN ('1. Paid once after delivery', '2. Paid in instalments after delivery',
                                           '3. Advance payment', '4. Paid during delivery') AND fully_paid_date IS NULL)
                        OR (path_group = '5. Delivered, not fully paid' AND fully_paid_date IS NOT NULL)) FROM c)
    UNION ALL
    SELECT '07. Variant orders add up to all orders, cumulative share ends at 1', 0,
           (SELECT SUM(orders) FROM v) - (SELECT COUNT(*) FROM c)
         + (SELECT COUNTIF(ABS(cumulative_share - 1) > 1e-12) FROM v WHERE variant_rank = (SELECT MAX(variant_rank) FROM v))
    UNION ALL
    SELECT '08. Activities in each variant = events of the order', 0,
           (SELECT COUNTIF(ARRAY_LENGTH(SPLIT(REPLACE(REPLACE(variant, ' > [Cancelled]', ''), ' > [Returned]', ''), ' > ')) != events) FROM c)
    UNION ALL
    SELECT '09. Directly-follows transitions = events - orders', 0,
           (SELECT n FROM pairs) - ((SELECT COUNT(*) FROM e) - (SELECT COUNT(*) FROM c))
    UNION ALL
    SELECT '10. Order-to-cash = dispatch + delivery + cash steps', 0,
           (SELECT COUNTIF(days_order_to_cash != days_order_to_dispatch + days_dispatch_to_delivery + days_delivery_to_cash)
              FROM c WHERE days_order_to_cash IS NOT NULL AND days_dispatch_to_delivery IS NOT NULL)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
