/* =============================================================================
   Case study · Why do last month's KPIs change after the pack goes out?
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The monthly operations pack goes to the board on the 5th. Every quarter,
   when the figures are refreshed, last quarter's on-time delivery rate is
   lower and delivery times are longer than the board was told. The
   operations head is accused of flattering the numbers. The financial
   controller wants to know what is happening:
     1. How much do the delivery KPIs change between the pack and the
        final figures, and always in which direction?
     2. Why: which orders are missing from the pack?
     3. Does waiting longer before publishing fix it?
     4. How can each KPI be reported so that it does not need revising?

   METHOD
     - Valid orders (not Cancelled or Returned) with a shipment. An order is
       delivered when every shipment has a delivery date; its delivery date
       is the last one. Months January 2025 - June 2026 (18 months), so the
       final figures (data to 30 September 2026) have matured.
     - "As of" date = last day of the month + a publishing lag: 0, 5
       (the board pack) and 15 days. Only events dated on or before the
       as-of date are known.
     - KPIs:
         On-time delivery, by promise month: orders delivered by the
           promised date / orders.
           Pack method: on-time / orders delivered by the as-of date.
           Fixed method: on-time / all orders promised in the month (an
           order not delivered by the as-of date is already late, because
           its promised date has passed).
         Delivery time, by order month: average days from order to
           delivery. Pack method: orders delivered by the as-of date.
         Dispatch wait, by order month: average days from order to first
           shipment. Pack method: orders shipped by the as-of date.
     - Final = the same KPI on all data. Revision = final - pack.
   ============================================================================= */

DECLARE first_month DATE DEFAULT DATE '2025-01-01';
DECLARE last_month  DATE DEFAULT DATE '2026-06-01';
DECLARE data_end    DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Orders with their dispatch and delivery dates
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.kr_orders` AS
SELECT
    o.order_id, o.order_date, o.promised_delivery_date AS promised_date,
    MIN(s.shipment_date)                                                              AS first_shipment_date,
    -- delivered only when every shipment has a delivery date
    IF(COUNTIF(s.delivery_date IS NULL) = 0, MAX(s.delivery_date), NULL)              AS delivery_date
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
GROUP BY o.order_id, o.order_date, o.promised_delivery_date;

-- -----------------------------------------------------------------------------
-- Step 2 · Each KPI as the pack would have shown it, and as it finally was
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.kr_kpis` AS
WITH months AS (
    SELECT m AS month FROM UNNEST(GENERATE_DATE_ARRAY(first_month, last_month, INTERVAL 1 MONTH)) AS m
),
lags AS (
    SELECT lag_days FROM UNNEST([0, 5, 15]) AS lag_days
),
as_of_dates AS (
    SELECT mo.month, lg.lag_days, DATE_ADD(LAST_DAY(mo.month, MONTH), INTERVAL lg.lag_days DAY) AS as_of
    FROM months AS mo CROSS JOIN lags AS lg
),
on_time AS (
    SELECT a.month, a.lag_days, a.as_of,
           COUNT(*)                                                                   AS promised_orders,
           COUNTIF(o.delivery_date <= a.as_of)                                        AS delivered_by_as_of,
           COUNTIF(o.delivery_date <= o.promised_date AND o.delivery_date <= a.as_of) AS on_time_by_as_of,
           COUNTIF(o.delivery_date <= o.promised_date)                                AS on_time_final
    FROM as_of_dates AS a
    JOIN `sahyadri_b2b.kr_orders` AS o ON DATE_TRUNC(o.promised_date, MONTH) = a.month
    GROUP BY a.month, a.lag_days, a.as_of
),
timing AS (
    SELECT a.month, a.lag_days,
           COUNT(*)                                                                   AS orders_placed,
           AVG(IF(o.delivery_date <= a.as_of, DATE_DIFF(o.delivery_date, o.order_date, DAY), NULL))             AS delivery_days_pack,
           AVG(DATE_DIFF(o.delivery_date, o.order_date, DAY))                         AS delivery_days_final,
           AVG(IF(o.first_shipment_date <= a.as_of, DATE_DIFF(o.first_shipment_date, o.order_date, DAY), NULL)) AS dispatch_days_pack,
           AVG(DATE_DIFF(o.first_shipment_date, o.order_date, DAY))                   AS dispatch_days_final,
           COUNTIF(o.delivery_date IS NULL OR o.delivery_date > a.as_of)              AS not_delivered_by_as_of
    FROM as_of_dates AS a
    JOIN `sahyadri_b2b.kr_orders` AS o ON DATE_TRUNC(o.order_date, MONTH) = a.month
    GROUP BY a.month, a.lag_days
)
SELECT
    t.month, t.lag_days, t.as_of,
    t.promised_orders, t.delivered_by_as_of, t.on_time_by_as_of, t.on_time_final,
    t.on_time_by_as_of / t.delivered_by_as_of                                         AS on_time_pack,
    t.on_time_by_as_of / t.promised_orders                                            AS on_time_fixed,
    t.on_time_final / t.promised_orders                                               AS on_time_final_rate,
    m.orders_placed, m.not_delivered_by_as_of,
    m.delivery_days_pack, m.delivery_days_final,
    m.dispatch_days_pack, m.dispatch_days_final
FROM on_time AS t
JOIN timing AS m USING (month, lag_days);

-- -----------------------------------------------------------------------------
-- Step 3 · How large are the revisions, and in which direction?
-- -----------------------------------------------------------------------------
SELECT
    lag_days                                                                          AS days_after_month_end,
    COUNT(*)                                                                          AS months,
    ROUND(100 * AVG(on_time_final_rate - on_time_pack), 2)                            AS on_time_revision_pts,
    COUNTIF(on_time_final_rate < on_time_pack)                                        AS months_revised_down,
    ROUND(100 * MAX(on_time_pack - on_time_final_rate), 2)                            AS largest_on_time_cut_pts,
    ROUND(AVG(delivery_days_final - delivery_days_pack), 2)                           AS delivery_days_revision,
    COUNTIF(delivery_days_final > delivery_days_pack)                                 AS months_revised_longer,
    ROUND(AVG(dispatch_days_final - dispatch_days_pack), 2)                           AS dispatch_days_revision,
    ROUND(100 * AVG(on_time_final_rate - on_time_fixed), 3)                           AS fixed_method_on_time_revision_pts
FROM `sahyadri_b2b.kr_kpis`
GROUP BY lag_days
ORDER BY lag_days;

-- The board pack (5 days after month-end), month by month
SELECT
    month,
    promised_orders,
    promised_orders - delivered_by_as_of                                              AS promised_but_not_delivered_by_pack,
    ROUND(100 * on_time_pack, 1)                                                      AS on_time_in_pack_pct,
    ROUND(100 * on_time_final_rate, 1)                                                AS on_time_final_pct,
    ROUND(100 * on_time_fixed, 1)                                                     AS on_time_fixed_method_pct,
    ROUND(delivery_days_pack, 2)                                                      AS delivery_days_in_pack,
    ROUND(delivery_days_final, 2)                                                     AS delivery_days_final,
    not_delivered_by_as_of                                                            AS placed_but_not_delivered_by_pack
FROM `sahyadri_b2b.kr_kpis`
WHERE lag_days = 5
ORDER BY month;

-- -----------------------------------------------------------------------------
-- Step 4 · Why: the orders missing from the pack
-- -----------------------------------------------------------------------------
-- Orders promised in the month but not delivered by the pack date, against those that were
WITH as_of_dates AS (
    SELECT month, as_of FROM `sahyadri_b2b.kr_kpis` WHERE lag_days = 5
),
flagged AS (
    SELECT o.*, a.as_of,
           IFNULL(o.delivery_date > a.as_of, TRUE)                                    AS missing_from_pack
    FROM `sahyadri_b2b.kr_orders` AS o
    JOIN as_of_dates AS a ON DATE_TRUNC(o.promised_date, MONTH) = a.month
)
SELECT
    IF(missing_from_pack, 'Not delivered by the pack date', 'Delivered by the pack date') AS orders,
    COUNT(*)                                                                          AS promised_orders,
    ROUND(100 * COUNTIF(delivery_date <= promised_date) / COUNT(*), 1)                AS on_time_pct,
    ROUND(AVG(DATE_DIFF(first_shipment_date, order_date, DAY)), 2)                    AS dispatch_days,
    ROUND(AVG(DATE_DIFF(delivery_date, order_date, DAY)), 2)                          AS delivery_days,
    COUNTIF(delivery_date IS NULL)                                                    AS never_delivered
FROM flagged
GROUP BY orders
ORDER BY orders;

-- Delivery time by order month, pack method against the alternative of reporting by delivery month
-- (orders delivered in the month are all known at month-end, so that figure never changes)
WITH by_delivery_month AS (
    SELECT DATE_TRUNC(delivery_date, MONTH) AS month, AVG(DATE_DIFF(delivery_date, order_date, DAY)) AS days
    FROM `sahyadri_b2b.kr_orders` WHERE delivery_date IS NOT NULL
    GROUP BY month
)
SELECT
    ROUND(AVG(k.delivery_days_pack), 2)                                               AS by_order_month_in_pack,
    ROUND(AVG(k.delivery_days_final), 2)                                              AS by_order_month_final,
    ROUND(AVG(d.days), 2)                                                             AS by_delivery_month,
    ROUND(CORR(k.delivery_days_final, d.days), 3)                                     AS corr_final_with_delivery_month
FROM `sahyadri_b2b.kr_kpis` AS k
JOIN by_delivery_month AS d USING (month)
WHERE k.lag_days = 5;
