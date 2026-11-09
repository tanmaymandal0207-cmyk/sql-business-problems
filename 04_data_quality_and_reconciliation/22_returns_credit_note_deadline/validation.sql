/* =============================================================================
   Case study · Returned goods and the GST credit-note deadline — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE gst_rate     FLOAT64 DEFAULT 0.18;
DECLARE report_date  DATE    DEFAULT DATE '2026-11-09';

WITH r AS (SELECT * FROM `sahyadri_b2b.cn_returns`),

src AS (
    SELECT o.order_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status = 'Returned'
    GROUP BY o.order_id
),
ship AS (
    SELECT order_id, MIN(shipment_date) AS first_ship, MAX(delivery_date) AS last_delivery,
           COUNT(*) AS n, COUNTIF(shipment_status = 'Returned') AS n_returned
    FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
paid AS (SELECT order_id, SUM(amount) AS received FROM `sahyadri_b2b.payments` GROUP BY order_id),

checks AS (
    SELECT '01. Returned orders = orders with status Returned, taxable value = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM r) - (SELECT COUNT(*) FROM src))
         + (SELECT COUNT(*) FROM r LEFT JOIN src AS s USING (order_id) WHERE s.v IS NULL OR ABS(r.taxable_value - s.v) > 1e-6) AS actual
    UNION ALL
    SELECT '02. GST = 18 % of taxable value', 0,
           (SELECT COUNTIF(ABS(gst - gst_rate * taxable_value) > 1e-6) FROM r)
    UNION ALL
    SELECT '03. Deadline = 30 November of the year the financial year of supply ends (recount from the invoice month)', 0,
           (SELECT COUNTIF(EXTRACT(MONTH FROM credit_note_deadline) != 11 OR EXTRACT(DAY FROM credit_note_deadline) != 30
                        OR EXTRACT(YEAR FROM credit_note_deadline) != EXTRACT(YEAR FROM invoice_date) + IF(EXTRACT(MONTH FROM invoice_date) >= 4, 1, 0)
                        OR financial_year != EXTRACT(YEAR FROM invoice_date) - IF(EXTRACT(MONTH FROM invoice_date) >= 4, 0, 1)) FROM r)
    UNION ALL
    SELECT '04. Invoice date = first shipment date, return date = last delivery date', 0,
           (SELECT COUNT(*) FROM r JOIN ship AS s USING (order_id)
             WHERE r.invoice_date != s.first_ship OR r.return_date != s.last_delivery)
    UNION ALL
    SELECT '05. Every returned order was fully returned: all its shipments have status Returned', 0,
           (SELECT COUNT(*) FROM r JOIN ship AS s USING (order_id)
             WHERE r.shipments != s.n OR r.returned_shipments != s.n_returned OR s.n_returned != s.n)
    UNION ALL
    SELECT '06. Received = payments on the order (recount), and none of them is paid', 0,
           (SELECT COUNT(*) FROM r LEFT JOIN paid AS p USING (order_id) WHERE ABS(r.received - IFNULL(p.received, 0)) > 1e-6)
         + (SELECT COUNTIF(received > 0) FROM r)
    UNION ALL
    SELECT '07. Financial-year totals add up to all returned orders and GST', 0,
           ABS((SELECT SUM(n) FROM (SELECT financial_year, COUNT(*) AS n FROM r GROUP BY financial_year)) - (SELECT COUNT(*) FROM r))
         + IF(ABS((SELECT SUM(g) FROM (SELECT financial_year, SUM(gst) AS g FROM r GROUP BY financial_year)) - (SELECT SUM(gst) FROM r)) > 1e-6, 1, 0)
    UNION ALL
    SELECT '08. Due by 30 November 2026 = returns invoiced April 2025 - March 2026 (independent recount)', 0,
           ABS((SELECT COUNTIF(credit_note_deadline = DATE '2026-11-30') FROM r)
             - (SELECT COUNTIF(invoice_date BETWEEN DATE '2025-04-01' AND DATE '2026-03-31') FROM r))
    UNION ALL
    SELECT '09. Out of time = deadline before 9 November 2026 = invoiced before April 2025', 0,
           ABS((SELECT COUNTIF(credit_note_deadline < report_date) FROM r)
             - (SELECT COUNTIF(invoice_date < DATE '2025-04-01') FROM r))
    UNION ALL
    SELECT '10. Return date on or after the invoice date, within 30 days', 0,
           (SELECT COUNTIF(return_date < invoice_date OR DATE_DIFF(return_date, invoice_date, DAY) > 30) FROM r)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
