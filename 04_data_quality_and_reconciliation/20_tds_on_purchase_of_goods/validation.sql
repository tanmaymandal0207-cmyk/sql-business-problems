/* =============================================================================
   Case study · TDS on purchase of goods — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE threshold FLOAT64 DEFAULT 5000000;
DECLARE tds_rate  FLOAT64 DEFAULT 0.001;
DECLARE fy_start  DATE    DEFAULT DATE '2024-04-01';
DECLARE data_end  DATE    DEFAULT DATE '2026-09-30';

WITH i AS (SELECT * FROM `sahyadri_b2b.td_invoices`),
     c AS (SELECT * FROM `sahyadri_b2b.td_customers`),

src AS (
    SELECT COUNT(*) AS n, SUM(v.v) AS v
    FROM (SELECT o.order_id, MIN(s.shipment_date) AS d
          FROM `sahyadri_b2b.sales_orders` AS o
          JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
          WHERE o.order_status NOT IN ('Cancelled', 'Returned')
          GROUP BY o.order_id) AS f
    JOIN (SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS v
          FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id) AS v USING (order_id)
    WHERE f.d BETWEEN fy_start AND data_end
),
running_recount AS (
    SELECT a.order_id, ANY_VALUE(a.cum_value) AS stored, SUM(b.taxable_value) AS cum
    FROM i AS a JOIN i AS b
      ON b.customer_id = a.customer_id AND b.fy = a.fy
     AND (b.invoice_date < a.invoice_date OR (b.invoice_date = a.invoice_date AND b.order_id <= a.order_id))
    GROUP BY a.order_id
),
receipts_fy25 AS (
    SELECT o.customer_id, SUM(p.amount) AS r
    FROM `sahyadri_b2b.payments` AS p JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
    WHERE p.payment_date BETWEEN DATE '2024-04-01' AND DATE '2025-03-31'
    GROUP BY o.customer_id
),
crossing AS (
    SELECT c.fy, c.customer_id, c.crossed_on,
           MAX(IF(i.invoice_date < c.crossed_on, i.cum_value, NULL)) AS before_cum,
           MIN(IF(i.invoice_date = c.crossed_on, i.cum_value, NULL)) AS at_cum,
           MAX(IF(i.invoice_date = c.crossed_on, i.cum_value, NULL)) AS at_cum_max
    FROM c JOIN i USING (fy, customer_id)
    WHERE c.crossed_on IS NOT NULL
    GROUP BY c.fy, c.customer_id, c.crossed_on
),

checks AS (
    SELECT '01. Invoices = valid shipped orders dated April 2024 - September 2026, value = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM i) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(taxable_value) FROM i) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Financial year runs April - March', 0,
           (SELECT COUNTIF(fy != IF(EXTRACT(MONTH FROM invoice_date) >= 4, EXTRACT(YEAR FROM invoice_date), EXTRACT(YEAR FROM invoice_date) - 1)) FROM i)
    UNION ALL
    SELECT '03. Running total = recount of earlier invoices in the same customer-year', 0,
           (SELECT COUNTIF(ABS(stored - cum) > 1e-6) FROM running_recount)
    UNION ALL
    SELECT '04. Amount above Rs 50 lakh per customer-year = MAX(0, purchases - 50 lakh)', 0,
           (SELECT COUNTIF(ABS(above_threshold - GREATEST(0, purchases - threshold)) > 1e-6) FROM c)
    UNION ALL
    SELECT '05. TDS = 0.1 % of the amount above Rs 50 lakh, invoice by invoice and in total', 0,
           (SELECT COUNTIF(ABS(tds_expected - tds_rate * above_threshold) > 1e-9) FROM i)
         + (SELECT COUNTIF(ABS(tds_expected - tds_rate * above_threshold) > 1e-6) FROM c)
    UNION ALL
    SELECT '06. Customers over Rs 50 lakh have a crossing date, and only they do', 0,
           (SELECT COUNTIF((crossed_on IS NOT NULL) != (purchases > threshold)) FROM c)
    UNION ALL
    SELECT '07. Crossing date: running total at or below Rs 50 lakh before it, above it by the end of that day', 0,
           (SELECT COUNTIF(IFNULL(before_cum, 0) > threshold OR at_cum_max <= threshold) FROM crossing)
    UNION ALL
    SELECT '08. Customer-year purchases add up to all invoices', 0,
           IF(ABS((SELECT SUM(purchases) FROM c) - (SELECT SUM(taxable_value) FROM i)) > 1, 1, 0)
         + ABS((SELECT COUNT(*) FROM c) - (SELECT COUNT(DISTINCT CONCAT(CAST(fy AS STRING), '|', CAST(customer_id AS STRING))) FROM i))
    UNION ALL
    SELECT '09. Quarterly schedule adds up to the total expected TDS', 0,
           IF(ABS((SELECT SUM(t) FROM (SELECT quarter, SUM(tds_expected) AS t FROM i GROUP BY quarter)) - (SELECT SUM(tds_expected) FROM c)) > 1e-6, 1, 0)
         + (SELECT COUNTIF(quarter != DATE_TRUNC(invoice_date, QUARTER)) FROM i)
    UNION ALL
    SELECT '10. TCS base 2024-25 = receipts above Rs 50 lakh per customer (recount)', 0,
           (SELECT COUNTIF(ABS(t.receipts_above - GREATEST(0, r.r - threshold)) > 1e-6 OR ABS(t.received - r.r) > 1e-6)
              FROM `sahyadri_b2b.td_tcs` AS t JOIN receipts_fy25 AS r USING (customer_id))
         + ABS((SELECT COUNT(*) FROM `sahyadri_b2b.td_tcs`) - (SELECT COUNT(*) FROM receipts_fy25))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
