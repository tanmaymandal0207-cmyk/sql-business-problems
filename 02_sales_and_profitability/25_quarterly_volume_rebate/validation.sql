/* =============================================================================
   Case study · A quarterly volume rebate — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_invoice DATE DEFAULT DATE '2024-01-01';
DECLARE last_invoice  DATE DEFAULT DATE '2026-09-30';

WITH iv AS (SELECT * FROM `sahyadri_b2b.qr_invoices`),
     q  AS (SELECT * FROM `sahyadri_b2b.qr_quarters`),

src AS (
    SELECT COUNT(*) AS n, SUM(v.v) AS v, SUM(v.c) AS c
    FROM (SELECT o.order_id, MIN(s.shipment_date) AS d
          FROM `sahyadri_b2b.sales_orders` AS o
          JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
          WHERE o.order_status NOT IN ('Cancelled', 'Returned')
          GROUP BY o.order_id) AS x
    JOIN (SELECT i.order_id,
                 SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v,
                 SUM(i.quantity * p.unit_cost) AS c
          FROM `sahyadri_b2b.sales_order_items` AS i
          JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
          GROUP BY i.order_id) AS v USING (order_id)
    WHERE x.d BETWEEN first_invoice AND last_invoice
),
recount AS (
    SELECT customer_id, quarter_start, SUM(purchases) AS purchases, COUNT(*) AS invoices
    FROM iv GROUP BY customer_id, quarter_start
),
months AS (
    SELECT customer_id, invoice_month, SUM(purchases) AS purchases FROM iv GROUP BY customer_id, invoice_month
),

checks AS (
    SELECT '01. Invoices = valid shipped orders invoiced January 2024 - September 2026, value and cost = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM iv) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(purchases) FROM iv) - (SELECT v FROM src)) > 1, 1, 0)
         + IF(ABS((SELECT SUM(cost) FROM iv) - (SELECT c FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Quarter = calendar quarter of the invoice date, 11 quarters, customer-quarters add up to invoices', 0,
           (SELECT COUNTIF(EXTRACT(DAY FROM quarter_start) != 1
                        OR EXTRACT(MONTH FROM quarter_start) NOT IN (1, 4, 7, 10)
                        OR invoice_date < quarter_start
                        OR (EXTRACT(YEAR FROM invoice_date) * 12 + EXTRACT(MONTH FROM invoice_date))
                           - (EXTRACT(YEAR FROM quarter_start) * 12 + EXTRACT(MONTH FROM quarter_start)) > 2) FROM iv)
         + ABS((SELECT COUNT(DISTINCT quarter_start) FROM q) - 11)
         + (SELECT COUNT(*) FROM q FULL OUTER JOIN recount AS r USING (customer_id, quarter_start)
             WHERE q.purchases IS NULL OR r.purchases IS NULL OR ABS(q.purchases - r.purchases) > 1e-6 OR q.invoices != r.invoices)
    UNION ALL
    SELECT '03. Rate = highest tier reached: 1 % from Rs 10 lakh, 2 % from Rs 20 lakh, 3 % from Rs 40 lakh', 0,
           (SELECT COUNTIF(rate != CASE WHEN purchases >= 4000000 THEN 0.03 WHEN purchases >= 2000000 THEN 0.02
                                        WHEN purchases >= 1000000 THEN 0.01 ELSE 0 END) FROM q)
    UNION ALL
    SELECT '04. Retroactive = purchases x rate, incremental = 1 % above each threshold (recount)', 0,
           (SELECT COUNTIF(ABS(retroactive_rebate - purchases * rate) > 1e-6
                        OR ABS(incremental_rebate - (0.01 * GREATEST(0, purchases - 1000000) + 0.01 * GREATEST(0, purchases - 2000000)
                                                     + 0.01 * GREATEST(0, purchases - 4000000))) > 1e-6) FROM q)
    UNION ALL
    SELECT '05. Incremental rebate is never above the retroactive one, and zero below Rs 10 lakh', 0,
           (SELECT COUNTIF(incremental_rebate > retroactive_rebate + 1e-6 OR (rate = 0 AND incremental_rebate != 0)) FROM q)
    UNION ALL
    SELECT '06. Next threshold = the lowest tier above purchases, gap = threshold - purchases', 0,
           (SELECT COUNTIF((purchases < 4000000 AND (next_threshold IS NULL OR next_threshold <= purchases
                                                     OR ABS(gap_to_next_threshold - (next_threshold - purchases)) > 1e-6))
                        OR (purchases >= 4000000 AND next_threshold IS NOT NULL)
                        OR (next_threshold = 2000000 AND purchases < 1000000)
                        OR (next_threshold = 4000000 AND purchases < 2000000)) FROM q)
    UNION ALL
    SELECT '07. Next-month purchases = invoices of the month after the quarter (recount), none for July - September 2026', 0,
           (SELECT COUNT(*) FROM q LEFT JOIN months AS m
               ON m.customer_id = q.customer_id AND m.invoice_month = DATE_ADD(q.quarter_start, INTERVAL 3 MONTH)
             WHERE (q.quarter_start < DATE '2026-07-01' AND ABS(q.next_month_purchases - IFNULL(m.purchases, 0)) > 1e-6)
                OR (q.quarter_start = DATE '2026-07-01' AND q.next_month_purchases IS NOT NULL))
    UNION ALL
    SELECT '08. Rate if pulled forward = tier of purchases + next month, never below the actual rate', 0,
           (SELECT COUNTIF(rate_if_pulled_forward < rate
                        OR rate_if_pulled_forward != CASE WHEN purchases + IFNULL(next_month_purchases, 0) >= 4000000 THEN 0.03
                                                          WHEN purchases + IFNULL(next_month_purchases, 0) >= 2000000 THEN 0.02
                                                          WHEN purchases + IFNULL(next_month_purchases, 0) >= 1000000 THEN 0.01 ELSE 0 END) FROM q)
    UNION ALL
    SELECT '09. Financial year runs April - March', 0,
           (SELECT COUNTIF(financial_year != IF(EXTRACT(MONTH FROM quarter_start) >= 4,
                                                EXTRACT(YEAR FROM quarter_start), EXTRACT(YEAR FROM quarter_start) - 1)) FROM q)
    UNION ALL
    SELECT '10. Break-even: gross profit on the extra purchases, less the rebate on them, repays the rebate', 0,
           (SELECT COUNTIF(ABS(x * gross_profit / purchases - x * rate - retroactive_rebate) > 1e-3)
              FROM (SELECT *, retroactive_rebate / (gross_profit / purchases - rate) AS x
                    FROM q WHERE rate > 0 AND gross_profit / purchases > rate))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
