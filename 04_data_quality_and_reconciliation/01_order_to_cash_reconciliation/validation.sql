/* =============================================================================
   Case study · Order-to-cash reconciliation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql (which saves sahyadri_b2b.order_payment_reconciliation).
   Every row should return status = 'PASS'.
   ============================================================================= */

WITH reg AS (
    SELECT * FROM `sahyadri_b2b.order_payment_reconciliation`
),

line_total AS (
    SELECT SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS total
    FROM `sahyadri_b2b.sales_order_items`
),

duplicate_rows_independent AS (
    -- recompute duplicate receipts a second way: every repeat row after the first
    SELECT SUM(amount) AS total
    FROM (
        SELECT
            amount,
            ROW_NUMBER() OVER (PARTITION BY order_id, payment_date, amount
                               ORDER BY payment_id) AS rn
        FROM `sahyadri_b2b.payments`
    )
    WHERE rn > 1
),

null_discount_paid_orders AS (
    -- evidence for treating a NULL discount as 0 %
    SELECT r.order_id, r.recorded_status, r.derived_status
    FROM reg AS r
    WHERE r.recorded_status = 'Paid'
      AND r.duplicate_rows = 0
      AND EXISTS (SELECT 1 FROM `sahyadri_b2b.sales_order_items` AS i
                  WHERE i.order_id = r.order_id AND i.discount_percent IS NULL)
),

checks AS (
    SELECT '01. Register rows minus distinct orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM reg) AS actual
    UNION ALL
    SELECT '02. Register rows minus sales_orders rows', 0,
           (SELECT COUNT(*) FROM reg) - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders`)
    UNION ALL
    SELECT '03. Payments without a matching order', 0,
           (SELECT COUNT(*) FROM `sahyadri_b2b.payments` AS p
              WHERE NOT EXISTS (SELECT 1 FROM `sahyadri_b2b.sales_orders` AS o
                                WHERE o.order_id = p.order_id))
    UNION ALL
    SELECT '04. Paid in register vs payments table (paise)', 0,
           CAST(ROUND((SELECT SUM(amount_paid) FROM reg)
                    - (SELECT SUM(amount) FROM `sahyadri_b2b.payments`), 2) * 100 AS INT64)
    UNION ALL
    -- order values are rounded to 2 dp, so allow at most ₹0.005 per order
    SELECT '05. Order value vs line items outside rounding limit (1 = yes)', 0,
           IF(ABS((SELECT SUM(order_value) FROM reg) - (SELECT total FROM line_total))
              > 0.005 * (SELECT COUNT(*) FROM reg), 1, 0)
    UNION ALL
    SELECT '06. Rows where value - paid <> balance', 0,
           (SELECT COUNTIF(ABS(order_value - amount_paid - balance) > 0.01) FROM reg)
    UNION ALL
    SELECT '07. Rows without a reconciliation category', 0,
           (SELECT COUNTIF(reconciliation_category IS NULL) FROM reg)
    UNION ALL
    SELECT '08. Duplicate amount: register vs independent recount (paise)', 0,
           CAST(ROUND((SELECT SUM(duplicate_amount) FROM reg)
                    - (SELECT total FROM duplicate_rows_independent), 2) * 100 AS INT64)
    UNION ALL
    SELECT '09. Open receivable on non-delivered orders', 0,
           (SELECT COUNTIF(open_receivable > 0 AND order_status <> 'Delivered') FROM reg)
    UNION ALL
    SELECT '10. Paid orders with NULL discount not settled at 0 % value', 0,
           (SELECT COUNTIF(derived_status <> 'Paid') FROM null_discount_paid_orders)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;

/* Informational (not pass/fail)

-- Size of the NULL-discount evidence base
SELECT COUNT(*) AS paid_orders_with_null_discount_lines FROM null_discount_paid_orders;

-- Delivered orders with no shipment record (a fulfilment data gap; their
-- receivables are aged from order_date)
SELECT COUNT(*) AS delivered_without_shipment
FROM `sahyadri_b2b.order_payment_reconciliation`
WHERE order_status = 'Delivered' AND final_delivery_date IS NULL;
*/
