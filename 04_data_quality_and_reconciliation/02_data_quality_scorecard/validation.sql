/* =============================================================================
   Case study · Data quality scorecard — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   Checks 05-10 recount selected rules with different SQL, to confirm the
   scorecard logic rather than repeat it.
   ============================================================================= */

WITH r AS (
    SELECT * FROM `sahyadri_b2b.data_quality_results`
),

failed AS (
    SELECT rule_id, records_failed FROM r
),

checks AS (
    SELECT '01. Duplicate rule IDs' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT rule_id) FROM r) AS actual
    UNION ALL
    SELECT '02. Rules missing from the scorecard (expected 29)', 0,
           29 - (SELECT COUNT(*) FROM r)
    UNION ALL
    SELECT '03. Rules with failed > checked, or NULL counts', 0,
           (SELECT COUNTIF(records_failed > records_checked
                           OR records_failed IS NULL OR records_checked IS NULL) FROM r)
    UNION ALL
    SELECT '04. Row-count rules whose checked count differs from table size', 0,
           (SELECT COUNTIF(records_checked <> CASE table_name
                    WHEN 'products'          THEN (SELECT COUNT(*) FROM `sahyadri_b2b.products`)
                    WHEN 'sales_order_items' THEN (SELECT COUNT(*) FROM `sahyadri_b2b.sales_order_items`)
                    WHEN 'shipments'         THEN (SELECT COUNT(*) FROM `sahyadri_b2b.shipments`)
                    WHEN 'payments'          THEN (SELECT COUNT(*) FROM `sahyadri_b2b.payments`)
                    WHEN 'customers'         THEN (SELECT COUNT(*) FROM `sahyadri_b2b.customers`)
                    WHEN 'employees'         THEN (SELECT COUNT(*) FROM `sahyadri_b2b.employees`)
                    WHEN 'sales_orders'      THEN (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders`)
                 END)
            FROM r WHERE rule_id IN ('C01','C02','C03','C04','C05','C07','C08','C09','C10','C11'))
    UNION ALL
    -- recount C02 using COUNT(column), which ignores NULLs
    SELECT '05. C02 recount (missing discounts)', 0,
           (SELECT records_failed FROM failed WHERE rule_id = 'C02')
         - (SELECT COUNT(*) - COUNT(discount_percent) FROM `sahyadri_b2b.sales_order_items`)
    UNION ALL
    SELECT '06. C03 recount (missing freight)', 0,
           (SELECT records_failed FROM failed WHERE rule_id = 'C03')
         - (SELECT COUNT(*) - COUNT(shipping_cost) FROM `sahyadri_b2b.shipments`)
    UNION ALL
    -- recount U03 with ROW_NUMBER instead of COUNT(DISTINCT ...)
    SELECT '07. U03 recount (duplicate payments)', 0,
           (SELECT records_failed FROM failed WHERE rule_id = 'U03')
         - (SELECT COUNTIF(rn > 1) FROM (
                SELECT ROW_NUMBER() OVER (PARTITION BY order_id, payment_date, amount
                                          ORDER BY payment_id) AS rn
                FROM `sahyadri_b2b.payments`))
    UNION ALL
    -- recount K04 with EXISTS instead of a LEFT JOIN
    SELECT '08. K04 recount (Unpaid orders with payments)', 0,
           (SELECT records_failed FROM failed WHERE rule_id = 'K04')
         - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders` AS o
             WHERE o.payment_status = 'Unpaid'
               AND EXISTS (SELECT 1 FROM `sahyadri_b2b.payments` AS p WHERE p.order_id = o.order_id))
    UNION ALL
    -- recount U01 with GROUP BY / HAVING
    SELECT '09. U01 recount (duplicate customer IDs)', 0,
           (SELECT records_failed FROM failed WHERE rule_id = 'U01')
         - (SELECT IFNULL(SUM(n - 1), 0) FROM (
                SELECT COUNT(*) AS n FROM `sahyadri_b2b.customers`
                GROUP BY customer_id HAVING COUNT(*) > 1))
    UNION ALL
    -- recount K03 with NOT EXISTS
    SELECT '10. K03 recount (Delivered orders without shipment)', 0,
           (SELECT records_failed FROM failed WHERE rule_id = 'K03')
         - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders` AS o
             WHERE o.order_status = 'Delivered'
               AND NOT EXISTS (SELECT 1 FROM `sahyadri_b2b.shipments` AS s WHERE s.order_id = o.order_id))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
