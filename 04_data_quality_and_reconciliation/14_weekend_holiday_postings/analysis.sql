/* =============================================================================
   Case study · Weekend and holiday postings test
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The internal auditor is planning the year-end review. A standard test in
   any audit of transaction data is to look for activity dated on days the
   business does not work: Sundays and national holidays. The company sells
   Monday to Saturday (Saturday is a half day) and the warehouse is said to
   follow the same calendar. Cheques and demand drafts can only be cleared
   on bank working days. The auditor asks:
     1. On which days of the week are orders, dispatches, deliveries and
        payments dated?
     2. Do any of them follow the business calendar, and which do not?
     3. How many cheque and demand-draft receipts are dated on Sundays or
        national holidays, and how much money is involved?
     4. What do the results say about how each date is captured?

   METHOD
     - Events: order date (sales_orders), dispatch date and delivery date
       (shipments), payment date (payments, by method).
     - Weekday computed portably: MOD(DATE_DIFF(date, DATE '1900-01-07', DAY), 7),
       0 = Sunday ... 6 = Saturday (7 Jan 1900 was a Sunday).
     - National holidays with fixed dates: Republic Day (26 Jan),
       Independence Day (15 Aug), Gandhi Jayanti (2 Oct). Festival holidays
       move each year and are not included.
     - Expected count on a day type if dates ignored the calendar = events x
       (days of that type / all days), over each event type's own first-to-
       last date.
     - Uniformity test across the seven weekdays: chi-square with 6 degrees
       of freedom, against the number of each weekday in the event's period.
       Critical value at 0.1 %: 22.46.
   ============================================================================= */

DECLARE period_start DATE    DEFAULT DATE '2024-01-01';
DECLARE period_end   DATE    DEFAULT DATE '2026-12-31';  -- calendar range; each event type uses its own first-last dates
DECLARE chi_critical FLOAT64 DEFAULT 22.46;

-- -----------------------------------------------------------------------------
-- Step 1 · Calendar and event tables
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cal_days` AS
SELECT
    d                                                                         AS cal_date,
    MOD(DATE_DIFF(d, DATE '1900-01-07', DAY), 7)                              AS weekday_no,
    (EXTRACT(MONTH FROM d) = 1  AND EXTRACT(DAY FROM d) = 26)
 OR (EXTRACT(MONTH FROM d) = 8  AND EXTRACT(DAY FROM d) = 15)
 OR (EXTRACT(MONTH FROM d) = 10 AND EXTRACT(DAY FROM d) = 2)                  AS is_national_holiday
FROM UNNEST(GENERATE_DATE_ARRAY(period_start, period_end)) AS d;

CREATE OR REPLACE TABLE `sahyadri_b2b.cal_events` AS
WITH raw AS (
              SELECT '1. Order placed' AS event_type, CAST(NULL AS STRING) AS method, order_id, order_date AS event_date, CAST(NULL AS NUMERIC) AS amount
              FROM `sahyadri_b2b.sales_orders`
    UNION ALL SELECT '2. Dispatched',    NULL,           order_id, shipment_date, NULL FROM `sahyadri_b2b.shipments`
    UNION ALL SELECT '3. Delivered',     NULL,           order_id, delivery_date, NULL FROM `sahyadri_b2b.shipments` WHERE delivery_date IS NOT NULL
    UNION ALL SELECT '4. Payment',       IFNULL(payment_method, 'Not recorded'), order_id, payment_date, amount FROM `sahyadri_b2b.payments`
)
SELECT r.*, c.weekday_no, c.is_national_holiday
FROM raw AS r
JOIN `sahyadri_b2b.cal_days` AS c ON c.cal_date = r.event_date;

SELECT event_type, COUNT(*) AS events, MIN(event_date) AS first_date, MAX(event_date) AS last_date
FROM `sahyadri_b2b.cal_events`
GROUP BY event_type
ORDER BY event_type;

-- -----------------------------------------------------------------------------
-- Step 2 · Day-of-week profile: observed against a calendar-blind expectation
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cal_weekday` AS
WITH obs AS (
    SELECT event_type, weekday_no, COUNT(*) AS events
    FROM `sahyadri_b2b.cal_events`
    GROUP BY event_type, weekday_no
),
span AS (
    SELECT event_type, MIN(event_date) AS first_date, MAX(event_date) AS last_date
    FROM `sahyadri_b2b.cal_events`
    GROUP BY event_type
),
grid AS (
    SELECT e.event_type, d.weekday_no, COUNT(*) AS days_in_period
    FROM span AS e
    JOIN `sahyadri_b2b.cal_days` AS d ON d.cal_date BETWEEN e.first_date AND e.last_date
    GROUP BY e.event_type, d.weekday_no
)
SELECT
    g.event_type, g.weekday_no,
    CASE g.weekday_no WHEN 0 THEN 'Sun' WHEN 1 THEN 'Mon' WHEN 2 THEN 'Tue' WHEN 3 THEN 'Wed'
                      WHEN 4 THEN 'Thu' WHEN 5 THEN 'Fri' ELSE 'Sat' END                   AS weekday,
    g.days_in_period,
    IFNULL(o.events, 0)                                                                    AS events,
    SUM(IFNULL(o.events, 0)) OVER (PARTITION BY g.event_type) * g.days_in_period
      / SUM(g.days_in_period) OVER (PARTITION BY g.event_type)                             AS expected_if_calendar_blind
FROM grid AS g
LEFT JOIN obs AS o ON o.event_type = g.event_type AND o.weekday_no = g.weekday_no;

SELECT
    event_type,
    SUM(IF(weekday_no = 0, events, 0))                                                    AS sunday_events,
    ROUND(100 * SUM(IF(weekday_no = 0, events, 0)) / SUM(events), 1)                      AS sunday_share_pct,
    ROUND(SUM(IF(weekday_no = 0, events, 0)) / SUM(IF(weekday_no = 0, days_in_period, 0)), 2)               AS per_sunday,
    ROUND(SUM(IF(weekday_no BETWEEN 1 AND 5, events, 0)) / SUM(IF(weekday_no BETWEEN 1 AND 5, days_in_period, 0)), 2) AS per_weekday,
    ROUND(SUM(IF(weekday_no = 6, events, 0)) / SUM(IF(weekday_no = 6, days_in_period, 0)), 2)               AS per_saturday,
    ROUND(SUM(POW(events - expected_if_calendar_blind, 2) / expected_if_calendar_blind), 1) AS chi_square_vs_uniform,
    IF(SUM(POW(events - expected_if_calendar_blind, 2) / expected_if_calendar_blind) > chi_critical,
       'Follows a weekly pattern', 'No weekly pattern')                                    AS verdict
FROM `sahyadri_b2b.cal_weekday`
GROUP BY event_type
ORDER BY event_type;

-- Full weekday table (events per day of that weekday)
SELECT
    weekday_no, weekday,
    ROUND(SUM(IF(event_type = '1. Order placed', events, 0)) / ANY_VALUE(days_in_period), 2) AS orders_per_day,
    ROUND(SUM(IF(event_type = '2. Dispatched',   events, 0)) / ANY_VALUE(days_in_period), 2) AS dispatches_per_day,
    ROUND(SUM(IF(event_type = '3. Delivered',    events, 0)) / ANY_VALUE(days_in_period), 2) AS deliveries_per_day,
    ROUND(SUM(IF(event_type = '4. Payment',      events, 0)) / ANY_VALUE(days_in_period), 2) AS payments_per_day
FROM `sahyadri_b2b.cal_weekday`
GROUP BY weekday_no, weekday
ORDER BY weekday_no;

-- Is the dispatch date simply "order date + N calendar days"?
-- If the warehouse ignored weekends, the lag would not depend on the order's
-- weekday, and the dispatch weekdays would follow from combining the order-
-- weekday mix with the lag mix. Compare that prediction with what is recorded.
CREATE OR REPLACE TABLE `sahyadri_b2b.cal_dispatch_model` AS
WITH s AS (
    SELECT o.order_date, sh.shipment_date,
           MOD(DATE_DIFF(o.order_date, DATE '1900-01-07', DAY), 7)                   AS order_wd,
           MOD(DATE_DIFF(sh.shipment_date, DATE '1900-01-07', DAY), 7)               AS dispatch_wd,
           DATE_DIFF(sh.shipment_date, o.order_date, DAY)                            AS lag_days
    FROM `sahyadri_b2b.shipments` AS sh
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = sh.order_id
),
wd AS (SELECT order_wd, COUNT(*) / (SELECT COUNT(*) FROM s) AS p FROM s GROUP BY order_wd),
lg AS (SELECT lag_days, COUNT(*) / (SELECT COUNT(*) FROM s) AS p FROM s GROUP BY lag_days),
predicted AS (
    SELECT MOD(MOD(wd.order_wd + lg.lag_days, 7) + 7, 7) AS weekday_no,
           SUM(wd.p * lg.p) * (SELECT COUNT(*) FROM s)   AS predicted
    FROM wd CROSS JOIN lg
    GROUP BY weekday_no
),
observed AS (SELECT dispatch_wd AS weekday_no, COUNT(*) AS observed FROM s GROUP BY dispatch_wd)
SELECT o.weekday_no, o.observed, p.predicted
FROM observed AS o JOIN predicted AS p USING (weekday_no);

SELECT
    weekday_no,
    CASE weekday_no WHEN 0 THEN 'Sun' WHEN 1 THEN 'Mon' WHEN 2 THEN 'Tue' WHEN 3 THEN 'Wed'
                    WHEN 4 THEN 'Thu' WHEN 5 THEN 'Fri' ELSE 'Sat' END                 AS weekday,
    observed, ROUND(predicted, 1) AS predicted_if_lag_ignores_weekends,
    ROUND(SUM(POW(observed - predicted, 2) / predicted) OVER (), 1)               AS chi_square_6_df
FROM `sahyadri_b2b.cal_dispatch_model`
ORDER BY weekday_no;

-- Dispatch lag by the weekday the order was placed
SELECT
    MOD(DATE_DIFF(o.order_date, DATE '1900-01-07', DAY), 7)                        AS order_weekday_no,
    COUNT(*)                                                                       AS shipments,
    ROUND(AVG(DATE_DIFF(sh.shipment_date, o.order_date, DAY)), 2)                  AS avg_days_to_dispatch,
    ROUND(100 * COUNTIF(MOD(DATE_DIFF(sh.shipment_date, DATE '1900-01-07', DAY), 7) = 0) / COUNT(*), 1) AS dispatched_on_sunday_pct
FROM `sahyadri_b2b.shipments` AS sh
JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = sh.order_id
GROUP BY order_weekday_no
ORDER BY order_weekday_no;

-- -----------------------------------------------------------------------------
-- Step 3 · Payments that cannot have cleared on the recorded date
-- -----------------------------------------------------------------------------
SELECT
    method,
    COUNT(*)                                                                    AS payments,
    COUNTIF(weekday_no = 0)                                                     AS on_sunday,
    COUNTIF(is_national_holiday AND weekday_no != 0)                            AS on_national_holiday,
    ROUND(100 * COUNTIF(weekday_no = 0 OR is_national_holiday) / COUNT(*), 1)   AS non_working_day_pct,
    ROUND(SUM(IF(weekday_no = 0 OR is_national_holiday, amount, 0)) / 1e5, 1)   AS non_working_day_value_lakh,
    IF(method IN ('Cheque', 'Demand Draft'), 'Needs a bank working day', 'Can settle any day') AS settlement
FROM `sahyadri_b2b.cal_events`
WHERE event_type = '4. Payment'
GROUP BY method
ORDER BY payments DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · National holidays
-- -----------------------------------------------------------------------------
WITH span AS (
    SELECT event_type, MIN(event_date) AS first_date, MAX(event_date) AS last_date,
           COUNT(*) AS events, COUNTIF(is_national_holiday) AS events_on_holidays
    FROM `sahyadri_b2b.cal_events`
    GROUP BY event_type
),
h AS (
    SELECT s.event_type, COUNTIF(d.is_national_holiday) AS holiday_days, COUNT(*) AS all_days
    FROM span AS s JOIN `sahyadri_b2b.cal_days` AS d ON d.cal_date BETWEEN s.first_date AND s.last_date
    GROUP BY s.event_type
)
SELECT
    s.event_type, h.holiday_days,
    s.events_on_holidays,
    ROUND(s.events * h.holiday_days / h.all_days, 1)                            AS expected_if_calendar_blind,
    ROUND(s.events_on_holidays / (s.events * h.holiday_days / h.all_days), 2)   AS ratio
FROM span AS s
JOIN h USING (event_type)
ORDER BY s.event_type;

-- Holiday-by-holiday detail
SELECT
    c.cal_date,
    CASE c.weekday_no WHEN 0 THEN 'Sun' WHEN 1 THEN 'Mon' WHEN 2 THEN 'Tue' WHEN 3 THEN 'Wed'
                      WHEN 4 THEN 'Thu' WHEN 5 THEN 'Fri' ELSE 'Sat' END                AS weekday,
    COUNTIF(e.event_type = '1. Order placed')                                   AS orders,
    COUNTIF(e.event_type = '2. Dispatched')                                     AS dispatches,
    COUNTIF(e.event_type = '3. Delivered')                                      AS deliveries,
    COUNTIF(e.event_type = '4. Payment')                                        AS payments,
    COUNTIF(e.event_type = '4. Payment' AND e.method IN ('Cheque', 'Demand Draft')) AS cheque_dd_payments
FROM `sahyadri_b2b.cal_days` AS c
LEFT JOIN `sahyadri_b2b.cal_events` AS e ON e.event_date = c.cal_date
WHERE c.is_national_holiday
GROUP BY c.cal_date, c.weekday_no
ORDER BY c.cal_date;
