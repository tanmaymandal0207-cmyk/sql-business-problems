/* =============================================================================
   Case study · Payment rails audit: do the receipts in the ledger fit the
   rules of the payment system they claim to have used?
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Every month the bank reconciliation leaves a list of receipts that do
   not match the bank statement by date or by type, and the accountant
   clears them by hand. The statutory auditor has asked whether the
   payment method and date recorded on each receipt can be relied on.
   Each Indian payment rail has hard rules, so the ledger can be tested
   against them without the bank statement:
     1. Do receipts recorded as RTGS or UPI respect those rails' amount
        limits?
     2. Are cheques and demand drafts dated on days the clearing system
        does not run, and how many of those fall at a month-end?
     3. How many receipts have no method at all?
     4. How is the mix of payment methods changing, and by segment?

   RULES APPLIED (as published by banks and the RBI; see the README)
     - RTGS: minimum Rs 2 lakh, no maximum; available 24 x 7.
     - UPI: Rs 1 lakh per transaction for ordinary payments.
     - NEFT: no minimum or maximum; available 24 x 7.
     - Cheques (and demand drafts) clear through the Cheque Truncation
       System, presented 10 am - 4 pm on working days only. From
       4 October 2025, cheques are cleared and credited within hours.
     - Bank holidays: every Sunday and the second and fourth Saturday of
       each month (national and state holidays are not in the data and are
       not tested, so the counts are a lower bound).

   METHOD AND ASSUMPTIONS
     - Receipts: every payment dated 1 January 2024 - 30 September 2026.
     - The payment date is taken as the date the receipt was booked.
     - Non-clearing day: a Sunday, or a Saturday that is the second or
       fourth Saturday of its month.
     - Month-end cut-off risk: a cheque or draft dated on a non-clearing day
       that is one of the last three days of its month, with no clearing
       day between it and the month-end; the money reaches the bank next
       month.
   ============================================================================= */

DECLARE rtgs_minimum  FLOAT64 DEFAULT 200000;
DECLARE upi_limit     FLOAT64 DEFAULT 100000;
DECLARE first_receipt DATE    DEFAULT DATE '2024-01-01';
DECLARE last_receipt  DATE    DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Receipts and the rail tests
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pr_receipts` AS
WITH base AS (
    SELECT p.payment_id, p.order_id, o.customer_id, c.customer_name, c.customer_segment,
           p.payment_date, p.amount,
           IFNULL(p.payment_method, 'Not recorded')                                   AS payment_method,
           EXTRACT(DAYOFWEEK FROM p.payment_date)                                     AS weekday_number,   -- 1 = Sunday, 7 = Saturday
           DIV(EXTRACT(DAY FROM p.payment_date) - 1, 7) + 1                           AS week_of_month,
           LAST_DAY(p.payment_date, MONTH)                                            AS month_end
    FROM `sahyadri_b2b.payments` AS p
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE p.payment_date BETWEEN first_receipt AND last_receipt
)
SELECT b.*,
       b.weekday_number = 1 OR (b.weekday_number = 7 AND b.week_of_month IN (2, 4))  AS non_clearing_day,
       b.payment_method = 'RTGS' AND b.amount < rtgs_minimum                           AS rtgs_below_minimum,
       b.payment_method = 'UPI' AND b.amount > upi_limit                               AS upi_above_limit,
       b.payment_method = 'Not recorded'                                              AS method_missing,
       b.payment_method IN ('Cheque', 'Demand Draft')
         AND (b.weekday_number = 1 OR (b.weekday_number = 7 AND b.week_of_month IN (2, 4))) AS instrument_on_non_clearing_day
FROM base AS b;

-- Month-end cut-off: instruments dated on a non-clearing day with no clearing day left in the month
CREATE OR REPLACE TABLE `sahyadri_b2b.pr_cutoff` AS
WITH days AS (
    SELECT d,
           EXTRACT(DAYOFWEEK FROM d) = 1
             OR (EXTRACT(DAYOFWEEK FROM d) = 7 AND DIV(EXTRACT(DAY FROM d) - 1, 7) + 1 IN (2, 4)) AS non_clearing
    FROM UNNEST(GENERATE_DATE_ARRAY(first_receipt, last_receipt)) AS d
),
last_clearing AS (
    SELECT LAST_DAY(d, MONTH) AS month_end, MAX(d) AS last_clearing_day
    FROM days
    WHERE NOT non_clearing
    GROUP BY month_end
)
SELECT r.payment_id, r.payment_date, r.month_end, l.last_clearing_day, r.amount, r.payment_method, r.customer_name
FROM `sahyadri_b2b.pr_receipts` AS r
JOIN last_clearing AS l ON l.month_end = r.month_end
WHERE r.payment_method IN ('Cheque', 'Demand Draft')
  AND r.payment_date > l.last_clearing_day;

-- -----------------------------------------------------------------------------
-- Step 2 · The tests at a glance
-- -----------------------------------------------------------------------------
SELECT '1. Recorded as RTGS, below the Rs 2 lakh minimum' AS test,
       COUNTIF(rtgs_below_minimum) AS receipts, COUNTIF(payment_method = 'RTGS') AS tested,
       ROUND(SUM(IF(rtgs_below_minimum, amount, 0)) / 1e5, 1) AS value_lakh,
       COUNT(DISTINCT IF(rtgs_below_minimum, customer_id, NULL)) AS customers
FROM `sahyadri_b2b.pr_receipts`
UNION ALL
SELECT '2. Recorded as UPI, above the Rs 1 lakh limit',
       COUNTIF(upi_above_limit), COUNTIF(payment_method = 'UPI'),
       ROUND(SUM(IF(upi_above_limit, amount, 0)) / 1e5, 1),
       COUNT(DISTINCT IF(upi_above_limit, customer_id, NULL))
FROM `sahyadri_b2b.pr_receipts`
UNION ALL
SELECT '3. Cheque or draft dated on a non-clearing day',
       COUNTIF(instrument_on_non_clearing_day), COUNTIF(payment_method IN ('Cheque', 'Demand Draft')),
       ROUND(SUM(IF(instrument_on_non_clearing_day, amount, 0)) / 1e5, 1),
       COUNT(DISTINCT IF(instrument_on_non_clearing_day, customer_id, NULL))
FROM `sahyadri_b2b.pr_receipts`
UNION ALL
SELECT '4. No payment method recorded',
       COUNTIF(method_missing), COUNT(*),
       ROUND(SUM(IF(method_missing, amount, 0)) / 1e5, 1),
       COUNT(DISTINCT IF(method_missing, customer_id, NULL))
FROM `sahyadri_b2b.pr_receipts`
ORDER BY test;

-- Baseline: share of all receipts dated on a non-clearing day, by method (electronic rails run every day)
SELECT
    payment_method,
    COUNT(*)                                                                          AS receipts,
    ROUND(100 * COUNTIF(non_clearing_day) / COUNT(*), 1)                              AS on_non_clearing_day_pct,
    ROUND(100 * COUNTIF(weekday_number = 1) / COUNT(*), 1)                            AS on_sunday_pct
FROM `sahyadri_b2b.pr_receipts`
GROUP BY payment_method
ORDER BY receipts DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · The RTGS receipts below the minimum
-- -----------------------------------------------------------------------------
SELECT
    CASE WHEN amount < 50000 THEN '1. Under Rs 50,000'
         WHEN amount < 100000 THEN '2. Rs 50,000 - 1 lakh'
         WHEN amount < 200000 THEN '3. Rs 1 - 2 lakh'
         ELSE '4. Rs 2 lakh and above (valid)' END                                     AS amount_band,
    COUNT(*)                                                                          AS rtgs_receipts,
    ROUND(SUM(amount) / 1e5, 1)                                                       AS value_lakh
FROM `sahyadri_b2b.pr_receipts`
WHERE payment_method = 'RTGS'
GROUP BY amount_band
ORDER BY amount_band;

SELECT
    EXTRACT(YEAR FROM payment_date)                                                   AS year,
    COUNTIF(payment_method = 'RTGS')                                                  AS rtgs_receipts,
    COUNTIF(rtgs_below_minimum)                                                       AS below_minimum,
    ROUND(100 * COUNTIF(rtgs_below_minimum) / COUNTIF(payment_method = 'RTGS'), 1)    AS below_minimum_pct
FROM `sahyadri_b2b.pr_receipts`
GROUP BY year
ORDER BY year;

SELECT
    customer_segment,
    COUNTIF(payment_method = 'RTGS')                                                  AS rtgs_receipts,
    COUNTIF(rtgs_below_minimum)                                                       AS below_minimum,
    ROUND(100 * COUNTIF(rtgs_below_minimum) / COUNTIF(payment_method = 'RTGS'), 1)    AS below_minimum_pct
FROM `sahyadri_b2b.pr_receipts`
GROUP BY customer_segment
ORDER BY below_minimum_pct DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Cheques and drafts on non-clearing days, and month-end cut-off
-- -----------------------------------------------------------------------------
SELECT
    EXTRACT(YEAR FROM payment_date)                                                   AS year,
    COUNTIF(payment_method IN ('Cheque', 'Demand Draft'))                             AS instruments,
    COUNTIF(instrument_on_non_clearing_day AND weekday_number = 1)                    AS on_sunday,
    COUNTIF(instrument_on_non_clearing_day AND weekday_number = 7)                    AS on_2nd_or_4th_saturday,
    ROUND(100 * COUNTIF(instrument_on_non_clearing_day) / COUNTIF(payment_method IN ('Cheque', 'Demand Draft')), 1) AS on_non_clearing_day_pct,
    ROUND(SUM(IF(instrument_on_non_clearing_day, amount, 0)) / 1e5, 1)                AS value_lakh
FROM `sahyadri_b2b.pr_receipts`
GROUP BY year
ORDER BY year;

SELECT
    COUNT(*)                                                                          AS instruments_after_last_clearing_day,
    COUNT(DISTINCT month_end)                                                         AS month_ends_affected,
    (SELECT COUNT(DISTINCT month_end) FROM `sahyadri_b2b.pr_receipts`)                AS month_ends,
    ROUND(SUM(amount) / 1e5, 1)                                                       AS value_lakh,
    ROUND(MAX(amount) / 1e5, 2)                                                       AS largest_lakh
FROM `sahyadri_b2b.pr_cutoff`;

SELECT month_end, last_clearing_day, COUNT(*) AS instruments, ROUND(SUM(amount) / 1e5, 2) AS value_lakh
FROM `sahyadri_b2b.pr_cutoff`
GROUP BY month_end, last_clearing_day
ORDER BY value_lakh DESC
LIMIT 8;

-- -----------------------------------------------------------------------------
-- Step 5 · The mix of payment methods
-- -----------------------------------------------------------------------------
SELECT
    EXTRACT(YEAR FROM payment_date)                                                   AS year,
    COUNT(*)                                                                          AS receipts,
    ROUND(100 * COUNTIF(payment_method IN ('NEFT', 'RTGS', 'UPI')) / COUNT(*), 1)     AS electronic_pct,
    ROUND(100 * COUNTIF(payment_method IN ('Cheque', 'Demand Draft')) / COUNT(*), 1)  AS cheque_or_draft_pct,
    ROUND(100 * COUNTIF(method_missing) / COUNT(*), 1)                                AS not_recorded_pct,
    ROUND(100 * SUM(IF(payment_method IN ('Cheque', 'Demand Draft'), amount, 0)) / SUM(amount), 1) AS cheque_or_draft_value_pct
FROM `sahyadri_b2b.pr_receipts`
GROUP BY year
ORDER BY year;

SELECT
    customer_segment,
    COUNT(*)                                                                          AS receipts,
    ROUND(100 * COUNTIF(payment_method = 'NEFT') / COUNT(*), 1)                       AS neft_pct,
    ROUND(100 * COUNTIF(payment_method = 'RTGS') / COUNT(*), 1)                       AS rtgs_pct,
    ROUND(100 * COUNTIF(payment_method = 'UPI') / COUNT(*), 1)                        AS upi_pct,
    ROUND(100 * COUNTIF(payment_method = 'Cheque') / COUNT(*), 1)                     AS cheque_pct,
    ROUND(100 * COUNTIF(payment_method = 'Demand Draft') / COUNT(*), 1)               AS draft_pct,
    ROUND(100 * COUNTIF(method_missing) / COUNT(*), 1)                                AS not_recorded_pct
FROM `sahyadri_b2b.pr_receipts`
GROUP BY customer_segment
ORDER BY receipts DESC;
