/* =============================================================================
   Case study · Payment rails audit — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE rtgs_minimum  FLOAT64 DEFAULT 200000;
DECLARE upi_limit     FLOAT64 DEFAULT 100000;
DECLARE first_receipt DATE    DEFAULT DATE '2024-01-01';
DECLARE last_receipt  DATE    DEFAULT DATE '2026-09-30';

WITH r AS (SELECT * FROM `sahyadri_b2b.pr_receipts`),
     k AS (SELECT * FROM `sahyadri_b2b.pr_cutoff`),

src AS (
    SELECT COUNT(*) AS n, SUM(amount) AS v, COUNTIF(payment_method IS NULL) AS missing
    FROM `sahyadri_b2b.payments`
    WHERE payment_date BETWEEN first_receipt AND last_receipt
),
-- independent calendar: 31 December 2023 was a Sunday
cal AS (
    SELECT payment_id, payment_date, month_end, payment_method, amount,
           MOD(DATE_DIFF(payment_date, DATE '2023-12-31', DAY), 7)                     AS dow0,   -- 0 = Sunday, 6 = Saturday
           EXTRACT(DAY FROM payment_date)                                             AS dom,
           MOD(DATE_DIFF(month_end, DATE '2023-12-31', DAY), 7)                        AS me_dow0,
           EXTRACT(DAY FROM month_end)                                                AS me_dom
    FROM r
),
cal2 AS (
    SELECT *,
           dow0 = 0 OR (dow0 = 6 AND (dom BETWEEN 8 AND 14 OR dom BETWEEN 22 AND 28))  AS nc,
           me_dow0 = 0 OR (me_dow0 = 6 AND (me_dom BETWEEN 8 AND 14 OR me_dom BETWEEN 22 AND 28)) AS me_nc
    FROM cal
),

checks AS (
    SELECT '01. Receipts = payments dated January 2024 - September 2026, amounts = source, every receipt has a customer' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM r) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(amount) FROM r) - (SELECT v FROM src)) > 1e-3, 1, 0)
         + (SELECT COUNTIF(customer_id IS NULL OR customer_segment IS NULL) FROM r) AS actual
    UNION ALL
    SELECT '02. Method "Not recorded" exactly where the source method is missing', 0,
           ABS((SELECT COUNTIF(method_missing) FROM r) - (SELECT missing FROM src))
         + (SELECT COUNTIF(method_missing != (payment_method = 'Not recorded')) FROM r)
    UNION ALL
    SELECT '03. Non-clearing day = Sunday or 2nd / 4th Saturday (recount from a fixed Sunday and day of month)', 0,
           (SELECT COUNTIF(r.non_clearing_day != c.nc) FROM r JOIN cal2 AS c USING (payment_id))
    UNION ALL
    SELECT '04. RTGS below minimum = RTGS and under Rs 2 lakh (recount)', 0,
           (SELECT COUNTIF(rtgs_below_minimum != (payment_method = 'RTGS' AND amount < rtgs_minimum)) FROM r)
    UNION ALL
    SELECT '05. UPI above limit = UPI and over Rs 1 lakh (recount)', 0,
           (SELECT COUNTIF(upi_above_limit != (payment_method = 'UPI' AND amount > upi_limit)) FROM r)
    UNION ALL
    SELECT '06. Instrument on a non-clearing day = cheque or draft dated on a non-clearing day', 0,
           (SELECT COUNTIF(r.instrument_on_non_clearing_day != (r.payment_method IN ('Cheque', 'Demand Draft') AND c.nc))
              FROM r JOIN cal2 AS c USING (payment_id))
    UNION ALL
    SELECT '07. Cut-off list = cheques and drafts with no clearing day left in their month (independent recount)', 0,
           ABS((SELECT COUNT(*) FROM k)
             - (SELECT COUNT(*) FROM cal2
                 WHERE payment_method IN ('Cheque', 'Demand Draft') AND nc
                   AND (payment_date = month_end OR (DATE_ADD(payment_date, INTERVAL 1 DAY) = month_end AND me_nc))))
    UNION ALL
    SELECT '08. Each cut-off row: dated after the last clearing day, which is a clearing day within 2 days of month-end', 0,
           (SELECT COUNTIF(payment_date <= last_clearing_day OR DATE_DIFF(month_end, last_clearing_day, DAY) > 2
                        OR MOD(DATE_DIFF(last_clearing_day, DATE '2023-12-31', DAY), 7) = 0) FROM k)
    UNION ALL
    SELECT '09. RTGS receipts below + at or above the minimum = all RTGS receipts', 0,
           ABS((SELECT COUNTIF(rtgs_below_minimum) + COUNTIF(payment_method = 'RTGS' AND amount >= rtgs_minimum) FROM r)
             - (SELECT COUNTIF(payment_method = 'RTGS') FROM r))
    UNION ALL
    SELECT '10. Six methods only, electronic + cheque or draft + not recorded = all receipts', 0,
           ABS((SELECT COUNT(DISTINCT payment_method) FROM r) - 6)
         + ABS((SELECT COUNTIF(payment_method IN ('NEFT', 'RTGS', 'UPI')) + COUNTIF(payment_method IN ('Cheque', 'Demand Draft'))
                       + COUNTIF(method_missing) FROM r) - (SELECT COUNT(*) FROM r))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
