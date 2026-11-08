/* =============================================================================
   Case study · The MSME 45-day rule — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_accepted DATE    DEFAULT DATE '2024-04-01';
DECLARE last_accepted  DATE    DEFAULT DATE '2026-06-30';
DECLARE data_end       DATE    DEFAULT DATE '2026-09-30';
DECLARE credit_days    INT64   DEFAULT 45;
DECLARE bank_rate      FLOAT64 DEFAULT 0.055;

WITH iv AS (SELECT * FROM `sahyadri_b2b.ms_invoices`),
     it AS (SELECT * FROM `sahyadri_b2b.ms_interest`),
     ye AS (SELECT * FROM `sahyadri_b2b.ms_year_end`),

src AS (
    SELECT COUNT(*) AS n, SUM(v.v) AS v
    FROM (SELECT o.order_id, MAX(s.delivery_date) AS d
          FROM `sahyadri_b2b.sales_orders` AS o
          JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
          WHERE o.order_status = 'Delivered'
          GROUP BY o.order_id HAVING COUNTIF(s.delivery_date IS NULL) = 0) AS x
    JOIN (SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS v
          FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id) AS v USING (order_id)
    WHERE x.d BETWEEN first_accepted AND last_accepted
),
per_order AS (
    SELECT order_id, SUM(amount) AS total, SUM(IF(kind = 'Paid', amount, 0)) AS paid FROM it GROUP BY order_id
),
paid_2026 AS (
    SELECT iv.order_id, iv.amount - LEAST(iv.amount, IFNULL(SUM(p.amount), 0)) AS owed
    FROM iv LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = iv.order_id AND p.payment_date <= DATE '2026-03-31'
    WHERE iv.accepted_on <= DATE '2026-03-31'
    GROUP BY iv.order_id, iv.amount
),

checks AS (
    SELECT '01. Invoices = fully delivered orders accepted April 2024 - June 2026, amount = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM iv) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(amount) FROM iv) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Due date = acceptance + 45 days', 0,
           (SELECT COUNTIF(DATE_DIFF(due_on, accepted_on, DAY) != credit_days) FROM iv)
    UNION ALL
    SELECT '03. Receipts settled + balance open = invoice amount, for every invoice', 0,
           (SELECT COUNT(*) FROM iv LEFT JOIN per_order AS p USING (order_id) WHERE ABS(IFNULL(p.total, 0) - iv.amount) > 1)
    UNION ALL
    SELECT '04. Receipts never settle more than the invoice', 0,
           (SELECT COUNTIF(p.paid > iv.amount + 1e-6) FROM iv JOIN per_order AS p USING (order_id))
    UNION ALL
    SELECT '05. Days late = MAX(0, settled date - due date), days from acceptance recount', 0,
           (SELECT COUNTIF(days_late != GREATEST(0, DATE_DIFF(settled_on, due_on, DAY))
                        OR days_from_acceptance != DATE_DIFF(settled_on, accepted_on, DAY)) FROM it)
    UNION ALL
    SELECT '06. Interest = amount x ((1 + 3 x bank rate / 12)^(months late) - 1), zero when on time', 0,
           (SELECT COUNTIF(ABS(interest - amount * (POW(1 + 3 * bank_rate / 12, days_late * 12 / 365) - 1)) > 1e-6
                        OR (days_late = 0 AND ABS(interest) > 1e-9)) FROM it)
    UNION ALL
    SELECT '07. Open balances are dated 30 September 2026, receipts never after it', 0,
           (SELECT COUNTIF(kind != 'Paid' AND settled_on != data_end) FROM it)
         + (SELECT COUNTIF(kind = 'Paid' AND settled_on > data_end) FROM it)
    UNION ALL
    SELECT '08. Owed at 31 March 2026 = amount - payments by then (recount)', 0,
           (SELECT COUNT(*) FROM (SELECT * FROM ye WHERE year_end = DATE '2026-03-31') AS y
              FULL OUTER JOIN (SELECT * FROM paid_2026 WHERE owed > 1) AS r USING (order_id)
             WHERE y.order_id IS NULL OR r.order_id IS NULL OR ABS(y.owed - r.owed) > 1e-6)
    UNION ALL
    SELECT '09. Past 45 days = more than 45 days between acceptance and the year-end', 0,
           (SELECT COUNTIF(past_45_days != (DATE_DIFF(year_end, accepted_on, DAY) > credit_days)) FROM ye)
    UNION ALL
    SELECT '10. Interest is never negative, and higher at the 2024 bank rate', 0,
           (SELECT COUNTIF(interest < 0 OR interest_at_2024_rate < interest - 1e-9) FROM it)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
