/* =============================================================================
   Case study · Data quality materiality — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start DATE DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE DEFAULT DATE '2026-09-30';

WITH l AS (SELECT * FROM `sahyadri_b2b.dq_lines`),
     k AS (SELECT * FROM `sahyadri_b2b.dq_kpis`),
     cm AS (SELECT * FROM `sahyadri_b2b.dq_customer_master`),

src AS (
    SELECT COUNT(*) AS n, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v,
           SUM(IF(i.discount_percent IS NULL, i.quantity * i.unit_price, 0)) AS null_discount_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN window_start AND window_end
),
costed AS (
    SELECT l.* FROM l JOIN `sahyadri_b2b.products` AS p ON p.product_id = l.product_id WHERE p.unit_cost IS NOT NULL
),
order_counts AS (
    SELECT customer_id, COUNT(*) AS orders FROM `sahyadri_b2b.sales_orders` GROUP BY customer_id
),
duplicate_rows AS (
    SELECT order_id, payment_date, amount, COUNT(*) - 1 AS extra
    FROM `sahyadri_b2b.payments`
    WHERE payment_date BETWEEN window_start AND window_end
    GROUP BY order_id, payment_date, amount
    HAVING COUNT(*) > 1
),
delivered AS (
    SELECT o.order_id, o.promised_delivery_date, COUNTIF(s.delivery_date IS NULL) AS undated, MAX(s.delivery_date) AS last_dated
    FROM `sahyadri_b2b.sales_orders` AS o JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND o.order_date BETWEEN window_start AND window_end
    GROUP BY o.order_id, o.promised_delivery_date
),
paid_recount AS (
    SELECT COUNT(*) AS n, COUNTIF(p.paid >= 0.99 * v.value) AS full_paid
    FROM (SELECT order_id, SUM(revenue_corrected) AS value FROM l WHERE order_status = 'Delivered' GROUP BY order_id) AS v
    LEFT JOIN (SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date <= window_end GROUP BY order_id) AS p
      ON p.order_id = v.order_id
),
ship AS (
    SELECT s.shipping_cost, IFNULL(m.city_key, LOWER(TRIM(s.shipping_city))) AS city_key
    FROM `sahyadri_b2b.shipments` AS s LEFT JOIN `sahyadri_b2b.dq_city_map` AS m ON m.raw_city = s.shipping_city
    WHERE s.shipment_date BETWEEN window_start AND window_end
),
city_avg AS (
    SELECT city_key, AVG(shipping_cost) AS avg_cost FROM ship GROUP BY city_key
),

checks AS (
    SELECT '01. Lines = valid lines of the window, corrected revenue = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM l) - (SELECT n FROM src))
         + IF(ABS((SELECT corrected FROM k WHERE kpi_no = 1) * 1e7 - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Reported revenue = corrected - value of NULL-discount lines', 0,
           IF(ABS(((SELECT corrected FROM k WHERE kpi_no = 1) - (SELECT reported FROM k WHERE kpi_no = 1)) * 1e7
                  - (SELECT null_discount_value FROM src)) > 1, 1, 0)
    UNION ALL
    SELECT '03. Corrected margin = margin recomputed on costed lines only', 0,
           IF(ABS((SELECT corrected FROM k WHERE kpi_no = 2)
                  - (SELECT 100 * SUM(revenue_corrected - quantity * unit_cost) / SUM(revenue_corrected) FROM costed)) > 1e-9, 1, 0)
    UNION ALL
    SELECT '04. Six duplicate customers, each master has at least as many orders', 0,
           ABS((SELECT COUNTIF(customer_id != master_id) FROM cm) - 6)
         + (SELECT COUNT(*) FROM cm AS d JOIN order_counts AS od ON od.customer_id = d.customer_id
              LEFT JOIN order_counts AS om ON om.customer_id = d.master_id
             WHERE d.customer_id != d.master_id AND IFNULL(om.orders, 0) < od.orders)
         + (SELECT COUNT(*) FROM cm AS a JOIN cm AS b ON b.customer_id = a.master_id WHERE b.master_id != b.customer_id)
    UNION ALL
    SELECT '05. On-time corrected base = delivered orders with a promise and every shipment dated', 0,
           (SELECT IF(ABS((SELECT corrected FROM k WHERE kpi_no = 4)
                     - 100 * COUNTIF(promised_delivery_date IS NOT NULL AND undated = 0 AND last_dated <= promised_delivery_date)
                           / COUNTIF(promised_delivery_date IS NOT NULL AND undated = 0)) > 1e-9, 1, 0)
              FROM delivered)
    UNION ALL
    SELECT '06. Cash difference = amounts of the extra duplicate receipts', 0,
           IF(ABS(((SELECT reported FROM k WHERE kpi_no = 5) - (SELECT corrected FROM k WHERE kpi_no = 5)) * 1e7
                  - (SELECT IFNULL(SUM(amount * extra), 0) FROM duplicate_rows)) > 0.01, 1, 0)
    UNION ALL
    SELECT '07. Paid-in-full share = recount from payments', 0,
           IF(ABS((SELECT corrected FROM k WHERE kpi_no = 6) - (SELECT 100 * full_paid / n FROM paid_recount)) > 1e-9, 1, 0)
    UNION ALL
    SELECT '08. League table + unassigned revenue = company revenue', 0,
           IF(ABS(((SELECT corrected FROM k WHERE kpi_no = 7) - (SELECT reported FROM k WHERE kpi_no = 7)) * 1e7
                  - (SELECT SUM(revenue_corrected) FROM l WHERE employee_id IS NULL)) > 1, 1, 0)
    UNION ALL
    SELECT '09. Freight filled in = city averages for the shipments without a cost', 0,
           IF(ABS(((SELECT corrected FROM k WHERE kpi_no = 8) - (SELECT reported FROM k WHERE kpi_no = 8)) / 100 * (SELECT corrected FROM k WHERE kpi_no = 1) * 1e7
                  - (SELECT SUM(c.avg_cost) FROM ship AS s JOIN city_avg AS c USING (city_key) WHERE s.shipping_cost IS NULL)) > 1, 1, 0)
         + (SELECT COUNTIF(avg_cost IS NULL) FROM city_avg)
    UNION ALL
    SELECT '10. Every customer city maps, Bengaluru = all its spellings', 0,
           (SELECT COUNT(*) FROM `sahyadri_b2b.customers` AS c LEFT JOIN `sahyadri_b2b.dq_city_map` AS m ON m.raw_city = c.city
             WHERE c.city IS NOT NULL AND m.raw_city IS NULL)
         + IF(ABS((SELECT corrected FROM k WHERE kpi_no = 10) * 1e7
                  - (SELECT SUM(l.revenue_corrected) FROM l JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = l.customer_id
                      WHERE LOWER(TRIM(c.city)) IN ('bengaluru', 'bangalore'))) > 1, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
