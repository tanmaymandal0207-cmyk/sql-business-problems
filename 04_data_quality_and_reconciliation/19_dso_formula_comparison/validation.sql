/* =============================================================================
   Case study · Which DSO should the board see? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_month_end DATE DEFAULT DATE '2024-06-30';
DECLARE last_month_end  DATE DEFAULT DATE '2026-09-30';

WITH iv AS (SELECT * FROM `sahyadri_b2b.ds_invoices`),
     s AS (SELECT * FROM `sahyadri_b2b.ds_sales`),
     op AS (SELECT * FROM `sahyadri_b2b.ds_open`),
     d AS (SELECT * FROM `sahyadri_b2b.ds_dso`),

src AS (
    SELECT COUNT(*) AS n
    FROM (SELECT o.order_id FROM `sahyadri_b2b.sales_orders` AS o
          JOIN `sahyadri_b2b.shipments` AS x ON x.order_id = o.order_id
          WHERE o.order_status = 'Delivered'
          GROUP BY o.order_id HAVING COUNTIF(x.delivery_date IS NULL) = 0)
),
ar_sep AS (
    -- receivables on 30 September 2026 recounted from invoices and payments
    SELECT SUM(GREATEST(0, iv.amount - IFNULL(p.paid, 0))) AS ar
    FROM iv
    LEFT JOIN (SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date <= last_month_end GROUP BY order_id) AS p
      USING (order_id)
),
history AS (
    SELECT d.month_end, d.ar, d.dso_countback, s.month, s.sales, s.days,
           SUM(s.days) OVER (PARTITION BY d.month_end ORDER BY s.month DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_days,
           SUM(s.sales) OVER (PARTITION BY d.month_end ORDER BY s.month DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_sales,
           ROW_NUMBER() OVER (PARTITION BY d.month_end ORDER BY s.month DESC) AS j
    FROM d JOIN s ON s.month <= DATE_TRUNC(d.month_end, MONTH)
),
inverted AS (
    -- sales in the last "countback" days, months prorated: must equal receivables
    SELECT month_end, ANY_VALUE(ar) AS ar,
           SUM(CASE WHEN cum_days <= dso_countback THEN sales
                    WHEN cum_days - days < dso_countback THEN (dso_countback - (cum_days - days)) / days * sales
                    ELSE 0 END) AS sales_in_window
    FROM history GROUP BY month_end
),
ratios AS (
    SELECT month_end, ANY_VALUE(ar) AS ar,
           SUM(IF(j = 1, sales, 0)) AS s1, SUM(IF(j = 1, days, 0)) AS d1,
           SUM(IF(j <= 3, sales, 0)) AS s3, SUM(IF(j <= 3, days, 0)) AS d3
    FROM history GROUP BY month_end
),

checks AS (
    SELECT '01. Invoices = Delivered orders with every shipment delivered' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM iv) - (SELECT n FROM src)) AS actual
    UNION ALL
    SELECT '02. Monthly sales add up to all invoices, days = calendar days of the month', 0,
           IF(ABS((SELECT SUM(sales) FROM s) - (SELECT SUM(amount) FROM iv)) > 1, 1, 0)
         + (SELECT COUNTIF(days != EXTRACT(DAY FROM LAST_DAY(month, MONTH))) FROM s)
    UNION ALL
    SELECT '03. One open row per month-end and invoice dated on or before it, never negative or above the amount', 0,
           ABS((SELECT COUNT(*) FROM op) - (SELECT COUNT(*) FROM d CROSS JOIN iv WHERE iv.invoice_date <= d.month_end))
         + (SELECT COUNT(*) FROM op JOIN iv USING (order_id) WHERE op.open_amount < 0 OR op.open_amount > iv.amount + 1e-6)
    UNION ALL
    SELECT '04. Receivables on 30 September 2026 = recount from invoices and payments', 0,
           IF(ABS((SELECT ar FROM d WHERE month_end = last_month_end) - (SELECT ar FROM ar_sep)) > 1, 1, 0)
    UNION ALL
    SELECT '05. Simple and 3-month DSO = receivables / sales x days (recount)', 0,
           (SELECT COUNT(*) FROM d JOIN ratios AS r USING (month_end)
             WHERE ABS(d.dso_simple - r.ar / r.s1 * r.d1) > 1e-6 OR ABS(d.dso_3_month - r.ar / r.s3 * r.d3) > 1e-6)
    UNION ALL
    SELECT '06. Countback inverted: sales in the last DSO days (prorated) = receivables', 0,
           (SELECT COUNTIF(ABS(sales_in_window - ar) > 1) FROM inverted)
    UNION ALL
    SELECT '07. Current-invoice countback never exceeds the full countback', 0,
           (SELECT COUNTIF(dso_current > dso_countback + 1e-9 OR dso_current IS NULL OR dso_countback IS NULL) FROM d)
    UNION ALL
    SELECT '08. Average age = open-amount-weighted days since invoice (recount)', 0,
           (SELECT COUNT(*) FROM d JOIN (SELECT month_end, SUM(open_amount * age_days) / SUM(open_amount) AS a FROM op GROUP BY month_end) AS x
             USING (month_end) WHERE ABS(d.average_age - x.a) > 1e-6)
    UNION ALL
    SELECT '09. 28 month-ends, 12-month DSO only once 12 months of sales exist (22 values)', 0,
           ABS((SELECT COUNT(*) FROM d) - 28) + ABS((SELECT COUNT(dso_12_month) FROM d) - 22)
         + (SELECT COUNTIF(month_end NOT BETWEEN first_month_end AND last_month_end) FROM d)
    UNION ALL
    SELECT '10. Receivables up to 90 days old never exceed total receivables', 0,
           (SELECT COUNTIF(ar_current > ar + 1e-6 OR ar_current < 0) FROM d)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
