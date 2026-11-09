/* =============================================================================
   Case study · Liquidated damages exposure — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE ld_rate_per_week FLOAT64 DEFAULT 0.005;
DECLARE ld_cap           FLOAT64 DEFAULT 0.10;
DECLARE gst_rate         FLOAT64 DEFAULT 0.18;
DECLARE first_delivery   DATE    DEFAULT DATE '2024-01-01';
DECLARE last_delivery    DATE    DEFAULT DATE '2026-09-30';

WITH s AS (SELECT * FROM `sahyadri_b2b.ld_shipments`),
     o AS (SELECT * FROM `sahyadri_b2b.ld_orders`),

src_orders AS (
    SELECT so.order_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS so
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = so.order_id
    WHERE so.order_status = 'Delivered' AND so.promised_delivery_date IS NOT NULL
      AND so.order_id IN (SELECT order_id FROM `sahyadri_b2b.shipments` GROUP BY order_id
                          HAVING COUNTIF(delivery_date IS NULL) = 0
                             AND MAX(delivery_date) BETWEEN first_delivery AND last_delivery)
    GROUP BY so.order_id
),
recount AS (
    SELECT order_id,
           SUM(ld_rate_per_week * shipment_value_incl_gst * DIV(GREATEST(days_late, 0) + 6, 7)) AS ld_before_cap,
           MAX(days_late) AS max_days_late, COUNT(*) AS n
    FROM s GROUP BY order_id
),
paid AS (
    SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date <= last_delivery GROUP BY order_id
),
buffer_7 AS (
    SELECT s.order_id,
           SUM(ld_rate_per_week * s.shipment_value_incl_gst * DIV(GREATEST(s.days_late - 7, 0) + 6, 7)) AS ld_before_cap
    FROM s GROUP BY s.order_id
),

checks AS (
    SELECT '01. Orders = Delivered, fully delivered, with a promised date, last delivery in the window, value = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT COUNT(*) FROM src_orders))
         + (SELECT COUNTIF(ABS(o.order_value - so.v) > 1e-6) FROM o JOIN src_orders AS so USING (order_id)) AS actual
    UNION ALL
    SELECT '02. Shipments of an order add up to the order value x 1.18, one row per shipment of the order', 0,
           (SELECT COUNTIF(ABS(o.order_value_incl_gst - so.v * (1 + gst_rate)) > 1e-6) FROM o JOIN src_orders AS so USING (order_id))
         + (SELECT COUNT(*) FROM o JOIN (SELECT order_id, COUNT(*) AS n FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS x USING (order_id)
             WHERE o.shipments != x.n)
    UNION ALL
    SELECT '03. Days late = delivery - promised date, weeks of delay = days rounded up to whole weeks (integer recount)', 0,
           (SELECT COUNTIF(days_late != DATE_DIFF(delivery_date, promised_delivery_date, DAY)
                        OR weeks_of_delay != DIV(GREATEST(days_late, 0) + 6, 7)) FROM s)
    UNION ALL
    SELECT '04. LD before cap = 0.5 % x late shipment value x weeks (recount)', 0,
           (SELECT COUNTIF(ABS(o.ld_before_cap - r.ld_before_cap) > 1e-6) FROM o JOIN recount AS r USING (order_id))
    UNION ALL
    SELECT '05. LD = MIN(before cap, 10 % of order value), cap flag consistent', 0,
           (SELECT COUNTIF(ABS(ld - LEAST(ld_before_cap, ld_cap * order_value_incl_gst)) > 1e-9
                        OR cap_binds != (ld_before_cap > ld_cap * order_value_incl_gst)) FROM o)
    UNION ALL
    SELECT '06. LD is positive exactly when some shipment of the order was late', 0,
           (SELECT COUNTIF((o.ld > 0) != (r.max_days_late > 0)) FROM o JOIN recount AS r USING (order_id))
    UNION ALL
    SELECT '07. Paid = payments to 30 September 2026 (recount)', 0,
           (SELECT COUNTIF(ABS(o.paid - IFNULL(p.paid, 0)) > 1e-6) FROM o LEFT JOIN paid AS p USING (order_id))
    UNION ALL
    SELECT '08. Segment LD adds up to the total, every order has a segment', 0,
           IF(ABS((SELECT SUM(x) FROM (SELECT customer_segment, SUM(ld) AS x FROM o GROUP BY customer_segment)) - (SELECT SUM(ld) FROM o)) > 1e-6, 1, 0)
         + (SELECT COUNTIF(customer_segment IS NULL) FROM o)
    UNION ALL
    SELECT '09. A 7-day buffer removes every shipment up to 7 days late from the LD (recount)', 0,
           (SELECT COUNTIF(b.ld_before_cap > 0 AND r.max_days_late <= 7) FROM buffer_7 AS b JOIN recount AS r USING (order_id))
         + IF((SELECT SUM(ld_before_cap) FROM buffer_7) >= (SELECT SUM(ld_before_cap) FROM o), 1, 0)
    UNION ALL
    SELECT '10. Order maximum days late and weeks = recount from shipments', 0,
           (SELECT COUNTIF(o.max_days_late != r.max_days_late OR o.max_weeks_of_delay != DIV(GREATEST(r.max_days_late, 0) + 6, 7))
              FROM o JOIN recount AS r USING (order_id))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
