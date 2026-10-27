/* =============================================================================
   Case study · Weekend and holiday postings test — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start DATE DEFAULT DATE '2024-01-01';
DECLARE period_end   DATE DEFAULT DATE '2026-12-31';

WITH d AS (SELECT * FROM `sahyadri_b2b.cal_days`),
     e AS (SELECT * FROM `sahyadri_b2b.cal_events`),
     w AS (SELECT * FROM `sahyadri_b2b.cal_weekday`),
     m AS (SELECT * FROM `sahyadri_b2b.cal_dispatch_model`),

src AS (
              SELECT '1. Order placed' AS event_type, COUNT(*) AS n FROM `sahyadri_b2b.sales_orders`
    UNION ALL SELECT '2. Dispatched', COUNT(*) FROM `sahyadri_b2b.shipments`
    UNION ALL SELECT '3. Delivered', COUNT(delivery_date) FROM `sahyadri_b2b.shipments`
    UNION ALL SELECT '4. Payment', COUNT(*) FROM `sahyadri_b2b.payments`
),
spans AS (
    SELECT event_type, DATE_DIFF(MAX(event_date), MIN(event_date), DAY) + 1 AS span_days FROM e GROUP BY event_type
),
-- cheque and DD receipts on Sundays, recounted with a different weekday anchor (6 Jan 2024 was a Saturday)
cheque_sundays AS (
    SELECT COUNT(*) AS n
    FROM `sahyadri_b2b.payments`
    WHERE payment_method IN ('Cheque', 'Demand Draft')
      AND MOD(DATE_DIFF(payment_date, DATE '2024-01-06', DAY), 7) = 1
),

checks AS (
    SELECT '01. Calendar has one row per day of the range' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT cal_date) FROM d) + ((SELECT COUNT(*) FROM d) - (DATE_DIFF(period_end, period_start, DAY) + 1)) AS actual
    UNION ALL
    SELECT '02. 1 January 2024 is a Monday (weekday 1)', 0,
           (SELECT COUNTIF(weekday_no != 1) FROM d WHERE cal_date = DATE '2024-01-01')
    UNION ALL
    SELECT '03. Three national holidays a year (9 in 2024-2026)', 0,
           (SELECT COUNTIF(is_national_holiday) FROM d) - 9
    UNION ALL
    SELECT '04. Every source event is in the event table', 0,
           (SELECT COUNT(*) FROM src JOIN (SELECT event_type, COUNT(*) AS n FROM e GROUP BY event_type) AS x USING (event_type) WHERE src.n != x.n)
    UNION ALL
    SELECT '05. Weekday table: events add up to each event type', 0,
           (SELECT COUNT(*) FROM src JOIN (SELECT event_type, SUM(events) AS n FROM w GROUP BY event_type) AS x USING (event_type) WHERE src.n != x.n)
    UNION ALL
    SELECT '06. Expected counts add up to observed counts (x1000)', 0,
           (SELECT COUNTIF(ABS(t) > 0.001) FROM (SELECT event_type, SUM(expected_if_calendar_blind) - SUM(events) AS t FROM w GROUP BY event_type))
    UNION ALL
    SELECT '07. Days in period = first-to-last span of each event type', 0,
           (SELECT COUNT(*) FROM spans JOIN (SELECT event_type, SUM(days_in_period) AS n FROM w GROUP BY event_type) AS x USING (event_type)
             WHERE spans.span_days != x.n)
    UNION ALL
    SELECT '08. Dispatch model: predicted shipments = observed shipments (x1000)', 0,
           (SELECT CAST(ROUND(1000 * ABS(SUM(predicted) - SUM(observed))) AS INT64) FROM m)
    UNION ALL
    SELECT '09. Weekday = recount from a different anchor date', 0,
           (SELECT COUNTIF(weekday_no != MOD(MOD(DATE_DIFF(cal_date, DATE '2024-01-07', DAY), 7) + 7, 7)) FROM d)
    UNION ALL
    SELECT '10. Sunday cheque and DD receipts = independent recount', 0,
           (SELECT COUNTIF(weekday_no = 0 AND method IN ('Cheque', 'Demand Draft')) FROM e WHERE event_type = '4. Payment')
         - (SELECT n FROM cheque_sundays)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
