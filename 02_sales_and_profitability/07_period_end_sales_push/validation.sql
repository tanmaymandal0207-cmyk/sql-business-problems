/* =============================================================================
   Case study · Period-end sales push — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start DATE  DEFAULT DATE '2024-01-01';
DECLARE period_end   DATE  DEFAULT DATE '2026-09-30';
DECLARE end_days     INT64 DEFAULT 5;

WITH p AS (SELECT * FROM `sahyadri_b2b.order_period_position`),

src_orders AS (
    SELECT * FROM `sahyadri_b2b.sales_orders`
    WHERE order_date BETWEEN period_start AND period_end
),
src_lines AS (
    SELECT i.*, o.order_status
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN src_orders                       AS o ON o.order_id = i.order_id
),
calendar AS (
    SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(period_start, period_end)) AS d
),

checks AS (
    SELECT '01. Duplicate orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM p) AS actual
    UNION ALL
    SELECT '02. Orders vs source orders in the period', 0,
           (SELECT COUNT(*) FROM p) - (SELECT COUNT(*) FROM src_orders)
    UNION ALL
    SELECT '03. Gross value vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(gross_value) FROM p) - (SELECT SUM(quantity * unit_price) FROM src_lines), 0) AS INT64)
    UNION ALL
    SELECT '04. Discount amount vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(discount_amount) FROM p)
                    - (SELECT SUM(quantity * unit_price * IFNULL(discount_percent, 0) / 100) FROM src_lines), 0) AS INT64)
    UNION ALL
    -- independent rule: day of month above (days in month - 5) means last 5 days
    SELECT '05. Month position inconsistent with day of month', 0,
           (SELECT COUNTIF(
                 (month_position = '3. Last 5 days')
              <> (EXTRACT(DAY FROM order_date) > EXTRACT(DAY FROM LAST_DAY(order_date)) - end_days)
              OR (month_position = '1. First 5 days') <> (EXTRACT(DAY FROM order_date) <= end_days)) FROM p)
    UNION ALL
    SELECT '06. Calendar: last-5-day days = 5 per month in the period', 0,
           (SELECT COUNTIF(EXTRACT(DAY FROM d) > EXTRACT(DAY FROM LAST_DAY(d)) - end_days) FROM calendar)
         - end_days * (SELECT COUNT(DISTINCT DATE_TRUNC(d, MONTH)) FROM calendar)
    UNION ALL
    SELECT '07. Quarter-end or year-end flag inconsistent', 0,
           (SELECT COUNTIF(is_quarter_end_month <> (EXTRACT(MONTH FROM order_date) IN (3, 6, 9, 12))
                        OR is_year_end_month    <> (EXTRACT(MONTH FROM order_date) = 3)
                        OR (is_year_end_month AND NOT is_quarter_end_month)) FROM p)
    UNION ALL
    SELECT '08. Closed flag inconsistent with status', 0,
           (SELECT COUNTIF(is_closed <> (order_status IN ('Delivered', 'Cancelled', 'Returned'))) FROM p)
    UNION ALL
    SELECT '09. Late flag on orders that are not Delivered', 0,
           (SELECT COUNTIF(was_late IS NOT NULL AND order_status <> 'Delivered') FROM p)
    UNION ALL
    SELECT '10. Order line count vs source', 0,
           (SELECT SUM(lines) FROM p) - (SELECT COUNT(*) FROM src_lines)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
