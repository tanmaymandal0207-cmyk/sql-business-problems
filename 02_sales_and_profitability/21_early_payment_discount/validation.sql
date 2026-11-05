/* =============================================================================
   Case study · Early-payment discount — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE delivered_from DATE    DEFAULT DATE '2024-10-01';
DECLARE delivered_to   DATE    DEFAULT DATE '2025-09-30';
DECLARE as_of          DATE    DEFAULT DATE '2026-09-30';
DECLARE cost_of_money  FLOAT64 DEFAULT 0.12;
DECLARE window_days    INT64   DEFAULT 10;
DECLARE settled_share  FLOAT64 DEFAULT 0.99;

WITH o AS (SELECT * FROM `sahyadri_b2b.ep_orders`),
     t AS (SELECT * FROM `sahyadri_b2b.ep_terms`),
     sm AS (SELECT * FROM `sahyadri_b2b.ep_summary`),

src AS (
    SELECT COUNT(*) AS n
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN (SELECT order_id, MAX(delivery_date) AS d FROM `sahyadri_b2b.shipments` GROUP BY order_id
          HAVING COUNT(delivery_date) = COUNT(*)) AS s ON s.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned') AND s.d BETWEEN delivered_from AND delivered_to
),
pay AS (
    SELECT o.order_id, o.order_value, o.settled, o.settled_on,
           SUM(IF(p.payment_date <= IFNULL(o.settled_on, as_of), p.amount, 0)) AS paid_by,
           SUM(IF(p.payment_date <  IFNULL(o.settled_on, as_of), p.amount, 0)) AS paid_before
    FROM o LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = o.order_id
    GROUP BY o.order_id, o.order_value, o.settled, o.settled_on
),
seg_vs_all AS (
    SELECT discount,
           SUM(IF(segment = 'All segments', windfall, -windfall))                     AS windfall_gap,
           SUM(IF(segment = 'All segments', net_if_all_switch, -net_if_all_switch))   AS net_gap
    FROM sm GROUP BY discount
),

checks AS (
    SELECT '01. One row per valid, fully delivered order delivered in the window' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src)) + ABS((SELECT COUNT(*) FROM o) - (SELECT COUNT(DISTINCT order_id) FROM o)) AS actual
    UNION ALL
    SELECT '02. Settled on the first day payments reach 99 %, never otherwise', 0,
           (SELECT COUNTIF((settled AND (paid_by < settled_share * order_value OR paid_before >= settled_share * order_value))
                           OR (NOT settled AND paid_by >= settled_share * order_value)) FROM pay)
    UNION ALL
    SELECT '03. Days to pay = settlement - delivery (0 if before), none when not settled', 0,
           (SELECT COUNTIF((settled AND days_to_pay != GREATEST(DATE_DIFF(settled_on, delivered_on, DAY), 0))
                           OR (NOT settled AND days_to_pay IS NOT NULL)) FROM o)
    UNION ALL
    SELECT '04. Three discount terms for every order', 0,
           ABS((SELECT COUNT(*) FROM t) - 3 * (SELECT COUNT(*) FROM o))
    UNION ALL
    SELECT '05. Windfall only on early payers, switch values only on later payers', 0,
           (SELECT COUNTIF((windfall > 0 AND NOT (settled AND days_to_pay <= window_days))
                           OR (discount_if_switch > 0 AND NOT (settled AND days_to_pay > window_days))
                           OR (NOT settled AND (windfall + financing_saved_if_switch + discount_if_switch) != 0)) FROM t)
    UNION ALL
    SELECT '06. Financing saved = value x (days - 10) x 12 % / 365', 0,
           (SELECT COUNTIF(settled AND days_to_pay > window_days
                           AND ABS(financing_saved_if_switch - order_value * (days_to_pay - window_days) * cost_of_money / 365) > 1e-6) FROM t)
    UNION ALL
    SELECT '07. A switch gains exactly when days to pay exceed the break-even day', 0,
           (SELECT COUNTIF(settled AND days_to_pay > window_days
                           AND (financing_saved_if_switch > discount_if_switch) != (days_to_pay > break_even_day)) FROM t)
    UNION ALL
    SELECT '08. Segments add up to the all-segment totals', 0,
           (SELECT COUNTIF(ABS(windfall_gap) > 1e-6 OR ABS(net_gap) > 1e-6) FROM seg_vs_all)
    UNION ALL
    SELECT '09. Receivable released = value x days saved / 365 (recount)', 0,
           (SELECT COUNTIF(ABS(receivable_released_if_all_switch
                               - (SELECT SUM(IF(settled AND days_to_pay > window_days, order_value * (days_to_pay - window_days), 0)) / 365 FROM o)) > 1e-3)
              FROM sm WHERE segment = 'All segments')
    UNION ALL
    SELECT '10. Payment-speed bands add up to all orders', 0,
           ABS((SELECT COUNTIF(settled AND days_to_pay <= window_days) + COUNTIF(settled AND days_to_pay > window_days) + COUNTIF(NOT settled) FROM o)
               - (SELECT COUNT(*) FROM o))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
