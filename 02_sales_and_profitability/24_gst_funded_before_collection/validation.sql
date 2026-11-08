/* =============================================================================
   Case study · GST paid before the customer pays — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE gst_rate      FLOAT64 DEFAULT 0.18;
DECLARE first_invoice DATE    DEFAULT DATE '2024-04-01';
DECLARE last_invoice  DATE    DEFAULT DATE '2026-06-30';
DECLARE data_end      DATE    DEFAULT DATE '2026-09-30';

WITH iv AS (SELECT * FROM `sahyadri_b2b.gs_invoices`),
     r AS (SELECT * FROM `sahyadri_b2b.gs_receipts`),
     f AS (SELECT * FROM `sahyadri_b2b.gs_funding`),
     m AS (SELECT * FROM `sahyadri_b2b.gs_month_ends`),

src AS (
    SELECT COUNT(*) AS n, SUM(v.v) AS v
    FROM (SELECT o.order_id, MIN(s.shipment_date) AS d
          FROM `sahyadri_b2b.sales_orders` AS o
          JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
          WHERE o.order_status NOT IN ('Cancelled', 'Returned')
          GROUP BY o.order_id) AS x
    JOIN (SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS v
          FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id) AS v USING (order_id)
    WHERE x.d BETWEEN first_invoice AND last_invoice
),
paid AS (
    SELECT order_id, SUM(amount) AS received FROM `sahyadri_b2b.payments` WHERE payment_date <= data_end GROUP BY order_id
),
dec_2025 AS (
    SELECT (SELECT SUM(gst) FROM iv WHERE gst_due_date <= DATE '2025-12-31')
         - (SELECT SUM(gst_collected) FROM r WHERE payment_date <= DATE '2025-12-31' AND gst_due_date <= DATE '2025-12-31') AS balance
),

checks AS (
    SELECT '01. Invoices = valid shipped orders invoiced April 2024 - June 2026, value = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM iv) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(taxable_value) FROM iv) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. GST = 18 % of value, due on the 20th of the following month', 0,
           (SELECT COUNTIF(ABS(gst - gst_rate * taxable_value) > 1e-9
                        OR EXTRACT(DAY FROM gst_due_date) != 20
                        OR (EXTRACT(YEAR FROM gst_due_date) * 12 + EXTRACT(MONTH FROM gst_due_date))
                           - (EXTRACT(YEAR FROM invoice_date) * 12 + EXTRACT(MONTH FROM invoice_date)) != 1) FROM iv)
    UNION ALL
    SELECT '03. GST collected = MIN(receipts, value) / value x GST, per invoice', 0,
           (SELECT COUNTIF(ABS(f.gst_collected - LEAST(IFNULL(p.received, 0), f.taxable_value) / f.taxable_value * f.gst) > 1e-6)
              FROM f LEFT JOIN paid AS p USING (order_id))
    UNION ALL
    SELECT '04. Uncollected GST = GST - collected, never negative', 0,
           (SELECT COUNTIF(gst_uncollected < -1e-9 OR ABS(gst_uncollected - (gst - gst_collected)) > 1e-9) FROM f)
    UNION ALL
    SELECT '05. Funded and float rupee-days = recount from receipts and open balances', 0,
           (SELECT COUNT(*) FROM f LEFT JOIN (
               SELECT order_id,
                      SUM(gst_collected * GREATEST(0, DATE_DIFF(payment_date, gst_due_date, DAY))) AS fd,
                      SUM(gst_collected * GREATEST(0, DATE_DIFF(gst_due_date, payment_date, DAY))) AS fl
               FROM r GROUP BY order_id) AS x USING (order_id)
             WHERE ABS(f.funded_rupee_days - (IFNULL(x.fd, 0) + f.gst_uncollected * GREATEST(0, DATE_DIFF(data_end, f.gst_due_date, DAY)))) > 1e-3
                OR ABS(f.float_rupee_days - IFNULL(x.fl, 0)) > 1e-3)
    UNION ALL
    SELECT '06. A receipt is either after the due date (funded) or before it (float), never both', 0,
           (SELECT COUNTIF(DATE_DIFF(payment_date, gst_due_date, DAY) > 0 AND DATE_DIFF(gst_due_date, payment_date, DAY) > 0) FROM r)
    UNION ALL
    SELECT '07. Month-end balance = GST due by then - GST collected by then (December 2025 recount)', 0,
           IF(ABS((SELECT gst_funded FROM m WHERE month_end = DATE '2025-12-31') - (SELECT balance FROM dec_2025)) > 1e-3, 1, 0)
    UNION ALL
    SELECT '08. 27 month-ends, May 2024 - July 2026', 0,
           ABS((SELECT COUNT(*) FROM m) - 27)
         + IF((SELECT MIN(month_end) FROM m) != DATE '2024-05-31' OR (SELECT MAX(month_end) FROM m) != DATE '2026-07-31', 1, 0)
    UNION ALL
    SELECT '09. Receipts only to 30 September 2026, only on study invoices', 0,
           (SELECT COUNTIF(payment_date > data_end) FROM r)
         + (SELECT COUNT(*) FROM r WHERE order_id NOT IN (SELECT order_id FROM iv))
    UNION ALL
    SELECT '10. GST collected per invoice never exceeds its GST, and receipts add up to it', 0,
           (SELECT COUNTIF(gst_collected > gst + 1e-6) FROM f)
         + IF(ABS((SELECT SUM(gst_collected) FROM r) - (SELECT SUM(gst_collected) FROM f)) > 1e-3, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
