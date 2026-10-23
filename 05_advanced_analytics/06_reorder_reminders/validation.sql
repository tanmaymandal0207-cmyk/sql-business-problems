/* =============================================================================
   Case study · Replenishment reorder reminders — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of_date     DATE  DEFAULT DATE '2026-09-30';
DECLARE backtest_date  DATE  DEFAULT DATE '2026-03-31';
DECLARE horizon_days   INT64 DEFAULT 90;
DECLARE min_events     INT64 DEFAULT 4;

WITH e AS (SELECT * FROM `sahyadri_b2b.customer_product_purchases`),
     r AS (SELECT * FROM `sahyadri_b2b.reorder_status`),
     b AS (SELECT * FROM `sahyadri_b2b.reorder_backtest`),

src_lines AS (
    SELECT o.customer_id, i.product_id, o.order_date,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date <= as_of_date
),
-- previous purchase date found with a self-join instead of LAG
prev AS (
    SELECT e1.customer_id, e1.product_id, e1.purchase_date, MAX(e2.purchase_date) AS prev_date
    FROM e AS e1
    LEFT JOIN e AS e2
      ON e2.customer_id = e1.customer_id AND e2.product_id = e1.product_id AND e2.purchase_date < e1.purchase_date
    GROUP BY e1.customer_id, e1.product_id, e1.purchase_date
),
-- median property for each pair's gap
median_test AS (
    SELECT e.customer_id, e.product_id,
           COUNT(e.gap_days) AS n,
           COUNTIF(e.gap_days <= r.median_gap) AS at_or_below,
           COUNTIF(e.gap_days >= r.median_gap) AS at_or_above
    FROM e JOIN r ON r.customer_id = e.customer_id AND r.product_id = e.product_id
    WHERE e.gap_days IS NOT NULL
    GROUP BY e.customer_id, e.product_id
),
-- actual reorders in the backtest horizon, from source orders
actual AS (
    SELECT DISTINCT customer_id, product_id FROM src_lines
    WHERE order_date > backtest_date AND order_date <= DATE_ADD(backtest_date, INTERVAL horizon_days DAY)
),

checks AS (
    SELECT '01. Duplicate purchase events' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(product_id AS STRING), '|',
                                                    CAST(purchase_date AS STRING))) FROM e) AS actual
    UNION ALL
    SELECT '02. Event value vs source revenue (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(value) FROM e) - (SELECT SUM(revenue) FROM src_lines), 0) AS INT64)
    UNION ALL
    SELECT '03. Status pairs vs distinct customer-product pairs', 0,
           (SELECT COUNT(*) FROM r)
         - (SELECT COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(product_id AS STRING))) FROM src_lines)
    UNION ALL
    SELECT '04. Events per pair vs event rows', 0,
           (SELECT SUM(events) FROM r) - (SELECT COUNT(*) FROM e)
    UNION ALL
    SELECT '05. Gap does not equal days since the previous purchase', 0,
           (SELECT COUNT(*) FROM e JOIN prev AS p
              ON p.customer_id = e.customer_id AND p.product_id = e.product_id AND p.purchase_date = e.purchase_date
             WHERE e.gap_days IS DISTINCT FROM DATE_DIFF(e.purchase_date, p.prev_date, DAY))
    UNION ALL
    SELECT '06. Median gap fails the median property', 0,
           (SELECT COUNTIF(at_or_below < n / 2 OR at_or_above < n / 2) FROM median_test)
    UNION ALL
    SELECT '07. Regularity inconsistent with events and CV', 0,
           (SELECT COUNTIF(
                 (regularity = 'Insufficient history' AND events >= min_events AND median_gap > 0)
              OR (regularity = 'Regular'      AND NOT (events >= min_events AND gap_cv < 0.5))
              OR (regularity = 'Semi-regular' AND NOT (events >= min_events AND gap_cv >= 0.4995 AND gap_cv < 1.0005))
              OR (regularity = 'Irregular'    AND NOT (events >= min_events AND gap_cv >= 0.9995))) FROM r)
    UNION ALL
    SELECT '08. Reorder status inconsistent with days since last / median gap', 0,
           (SELECT COUNTIF(
                 (reorder_status = '1. Not yet due' AND days_since_last >= 0.8 * median_gap)
              OR (reorder_status = '2. Due now'     AND (days_since_last < 0.8 * median_gap OR days_since_last > 1.5 * median_gap))
              OR (reorder_status = '3. Overdue'     AND (days_since_last <= 1.5 * median_gap OR days_since_last > 3 * median_gap))
              OR (reorder_status = '4. Lapsed'      AND days_since_last <= 3 * median_gap)) FROM r)
    UNION ALL
    SELECT '09. Backtest uses purchases after its evaluation date', 0,
           (SELECT COUNTIF(last_purchase > backtest_date) FROM b)
    UNION ALL
    SELECT '10. Backtest reorder flag vs independent source check', 0,
           (SELECT COUNTIF(b.actually_reordered <> (a.customer_id IS NOT NULL))
              FROM b LEFT JOIN actual AS a ON a.customer_id = b.customer_id AND a.product_id = b.product_id)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
