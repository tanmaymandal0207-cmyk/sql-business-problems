/* =============================================================================
   Case study · Dispatch workload and capacity planning — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start DATE DEFAULT DATE '2024-01-02';
DECLARE period_end   DATE DEFAULT DATE '2026-09-30';

WITH w AS (
    SELECT * FROM `sahyadri_b2b.daily_dispatch_workload`
),

checks AS (
    SELECT '01. Duplicate days' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT day) FROM w) AS actual
    UNION ALL
    SELECT '02. Calendar days vs days in period', 0,
           (SELECT COUNT(*) FROM w) - (DATE_DIFF(period_end, period_start, DAY) + 1)
    UNION ALL
    SELECT '03. Shipments vs shipments table in period', 0,
           (SELECT SUM(shipments) FROM w)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.shipments`
             WHERE shipment_date BETWEEN period_start AND period_end)
    UNION ALL
    SELECT '04. Shipments dated outside the period', 0,
           (SELECT COUNT(*) FROM `sahyadri_b2b.shipments`
             WHERE shipment_date NOT BETWEEN period_start AND period_end)
    UNION ALL
    SELECT '05. Orders received vs orders in period', 0,
           (SELECT SUM(orders_received) FROM w)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders`
             WHERE order_date BETWEEN period_start AND period_end)
    UNION ALL
    -- 1 Jan 2024 is before the first shipment; any orders on it are reported here
    SELECT '06. Orders dated outside the period (expected 9, all on 1 Jan 2024)', 9,
           (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders`
             WHERE order_date NOT BETWEEN period_start AND period_end)
    UNION ALL
    SELECT '07. Weekday names not matching weekday numbers', 0,
           (SELECT COUNT(DISTINCT CONCAT(CAST(weekday_number AS STRING), weekday_name)) - 7 FROM w)
    UNION ALL
    SELECT '08. Months missing from the calendar', 0,
           12 - (SELECT COUNT(DISTINCT month_number) FROM w)
    UNION ALL
    SELECT '09. Negative counts', 0,
           (SELECT COUNTIF(shipments < 0 OR orders_received < 0) FROM w)
    UNION ALL
    SELECT '10. Weekday shipment totals vs overall total', 0,
           (SELECT SUM(s) FROM (SELECT SUM(shipments) AS s FROM w GROUP BY weekday_number))
         - (SELECT SUM(shipments) FROM w)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
