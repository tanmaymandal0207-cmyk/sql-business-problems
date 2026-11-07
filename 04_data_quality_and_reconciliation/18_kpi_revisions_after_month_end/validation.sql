/* =============================================================================
   Case study · KPI revisions after month-end — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_month DATE DEFAULT DATE '2025-01-01';
DECLARE last_month  DATE DEFAULT DATE '2026-06-01';

WITH o AS (SELECT * FROM `sahyadri_b2b.kr_orders`),
     k AS (SELECT * FROM `sahyadri_b2b.kr_kpis`),

src AS (
    SELECT COUNT(DISTINCT x.order_id) AS n
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned')
),
open_shipments AS (
    SELECT order_id, COUNTIF(delivery_date IS NULL) AS open_n, MAX(delivery_date) AS last_d, MIN(shipment_date) AS first_s
    FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
recount AS (
    -- the board-pack (5-day) figures recounted straight from orders, month by month
    SELECT k.month,
           ANY_VALUE(k.delivery_days_pack) AS stored_pack, ANY_VALUE(k.delivery_days_final) AS stored_final,
           ANY_VALUE(k.dispatch_days_pack) AS stored_dispatch, ANY_VALUE(k.not_delivered_by_as_of) AS stored_open,
           AVG(IF(o.delivery_date <= k.as_of, DATE_DIFF(o.delivery_date, o.order_date, DAY), NULL)) AS pack,
           AVG(DATE_DIFF(o.delivery_date, o.order_date, DAY)) AS final,
           AVG(IF(o.first_shipment_date <= k.as_of, DATE_DIFF(o.first_shipment_date, o.order_date, DAY), NULL)) AS dispatch,
           COUNTIF(o.delivery_date IS NULL OR o.delivery_date > k.as_of) AS open_n
    FROM k JOIN o ON o.order_date BETWEEN k.month AND LAST_DAY(k.month, MONTH)
    WHERE k.lag_days = 5
    GROUP BY k.month
),
promised_recount AS (
    SELECT k.month, k.lag_days, ANY_VALUE(k.promised_orders) AS stored, COUNT(*) AS n
    FROM k JOIN o ON o.promised_date BETWEEN k.month AND LAST_DAY(k.month, MONTH)
    GROUP BY k.month, k.lag_days
),

checks AS (
    SELECT '01. Orders = valid orders with at least one shipment' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src)) AS actual
    UNION ALL
    SELECT '02. Delivery date only when every shipment is delivered, and = the last one', 0,
           (SELECT COUNTIF((o.delivery_date IS NULL) != (x.open_n > 0)
                        OR (x.open_n = 0 AND o.delivery_date != x.last_d)
                        OR o.first_shipment_date != x.first_s)
              FROM o JOIN open_shipments AS x USING (order_id))
    UNION ALL
    SELECT '03. 18 months x 3 lags, as-of = last day of the month + lag', 0,
           ABS((SELECT COUNT(*) FROM k) - 54)
         + (SELECT COUNTIF(as_of != DATE_ADD(LAST_DAY(month, MONTH), INTERVAL lag_days DAY)) FROM k)
         + (SELECT COUNTIF(month NOT BETWEEN first_month AND last_month) FROM k)
    UNION ALL
    SELECT '04. Orders promised in each month = recount, the same at every lag', 0,
           (SELECT COUNTIF(stored != n) FROM promised_recount)
    UNION ALL
    SELECT '05. Fixed method = final on-time rate exactly, at every lag', 0,
           (SELECT COUNTIF(on_time_by_as_of != on_time_final OR ABS(on_time_fixed - on_time_final_rate) > 1e-12) FROM k)
    UNION ALL
    SELECT '06. Pack on-time rate is never below the final rate (smaller denominator)', 0,
           (SELECT COUNTIF(on_time_pack < on_time_final_rate - 1e-12) FROM k)
    UNION ALL
    SELECT '07. Orders known delivered grow with the lag and never exceed orders promised', 0,
           (SELECT COUNT(*) FROM (
               SELECT month, delivered_by_as_of - LAG(delivered_by_as_of) OVER (PARTITION BY month ORDER BY lag_days) AS step FROM k)
             WHERE step < 0)
         + (SELECT COUNTIF(delivered_by_as_of > promised_orders) FROM k)
    UNION ALL
    SELECT '08. Board-pack and final delivery days = recount from orders', 0,
           (SELECT COUNTIF(ABS(stored_pack - pack) > 1e-9 OR ABS(stored_final - final) > 1e-9) FROM recount)
    UNION ALL
    SELECT '09. Board-pack dispatch days = recount from orders', 0,
           (SELECT COUNTIF(ABS(stored_dispatch - dispatch) > 1e-9) FROM recount)
    UNION ALL
    SELECT '10. Orders not delivered by the pack date = recount', 0,
           (SELECT COUNTIF(stored_open != open_n) FROM recount)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
