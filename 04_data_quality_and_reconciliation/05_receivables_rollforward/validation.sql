/* =============================================================================
   Case study · Receivables roll-forward reconciliation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   Checks 07 and 08 need sahyadri_b2b.order_payment_reconciliation from the
   order-to-cash reconciliation case study.
   ============================================================================= */

DECLARE period_start DATE DEFAULT DATE '2024-01-01';
DECLARE as_of_date   DATE DEFAULT DATE '2026-09-30';

WITH l AS (SELECT * FROM `sahyadri_b2b.receivables_ledger`),
     b AS (SELECT * FROM `sahyadri_b2b.receivables_month_end`),

delivered AS (
    SELECT o.order_id, o.order_date,
           ROUND(SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)), 2) AS order_value
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_id, o.order_date
),
months AS (
    SELECT LAST_DAY(month_start) AS month_end
    FROM UNNEST(GENERATE_DATE_ARRAY(period_start, as_of_date, INTERVAL 1 MONTH)) AS month_start
),
-- independent cumulative ledger total at each month-end
cumulative AS (
    SELECT m.month_end, ROUND(SUM(l.amount), 2) AS net
    FROM months AS m
    JOIN l ON l.txn_date <= m.month_end
    GROUP BY m.month_end
),
month_totals AS (
    SELECT month_end, ROUND(SUM(balance), 2) AS net
    FROM b
    GROUP BY month_end
),
month_flows AS (
    SELECT LAST_DAY(txn_date) AS month_end, SUM(amount) AS flows
    FROM l
    GROUP BY month_end
),
-- roll-forward: change in net balance vs the month's invoices less receipts
roll_forward AS (
    SELECT
        m.month_end,
        IFNULL(t.net, 0) - IFNULL(LAG(t.net) OVER (ORDER BY m.month_end), 0) AS change_in_net,
        IFNULL(f.flows, 0)                                                   AS month_flows
    FROM months AS m
    LEFT JOIN month_totals AS t ON t.month_end = m.month_end
    LEFT JOIN month_flows  AS f ON f.month_end = m.month_end
),
as_of AS (SELECT * FROM b WHERE month_end = LAST_DAY(as_of_date)),

checks AS (
    SELECT '01. Invoices vs delivered orders (one each)' AS check_name, 0 AS expected,
           (SELECT COUNTIF(txn_type = 'Invoice') FROM l) - (SELECT COUNT(*) FROM delivered)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM l WHERE txn_type = 'Invoice') AS actual
    UNION ALL
    SELECT '02. Invoice total vs delivered order value (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(amount) FROM l WHERE txn_type = 'Invoice')
                    - (SELECT SUM(order_value) FROM delivered), 0) AS INT64)
    UNION ALL
    SELECT '03. Receipt total vs source payments (rupees, rounded)', 0,
           CAST(ROUND((SELECT -SUM(amount) FROM l WHERE txn_type = 'Receipt')
                    - (SELECT SUM(amount) FROM `sahyadri_b2b.payments` WHERE payment_date <= as_of_date), 0) AS INT64)
    UNION ALL
    SELECT '04. Receipt rows vs source payment rows', 0,
           (SELECT COUNTIF(txn_type = 'Receipt') FROM l)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.payments` WHERE payment_date <= as_of_date)
    UNION ALL
    SELECT '05. Month-ends where order balances do not equal the cumulative ledger', 0,
           (SELECT COUNT(*) FROM months AS m
              LEFT JOIN cumulative   AS c ON c.month_end = m.month_end
              LEFT JOIN month_totals AS t ON t.month_end = m.month_end
             WHERE ABS(IFNULL(c.net, 0) - IFNULL(t.net, 0)) > 0.05)
    UNION ALL
    SELECT '06. Months where opening + invoices - receipts <> closing', 0,
           (SELECT COUNTIF(ABS(change_in_net - month_flows) > 0.05) FROM roll_forward)
    UNION ALL
    SELECT '07. As-of gross receivables vs order-to-cash ageing (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(IF(balance_type = 'Receivable', balance, 0)) FROM as_of)
                    - (SELECT SUM(open_receivable) FROM `sahyadri_b2b.order_payment_reconciliation`), 0) AS INT64)
    UNION ALL
    SELECT '08. As-of receivable orders vs order-to-cash ageing', 0,
           (SELECT COUNTIF(balance_type = 'Receivable') FROM as_of)
         - (SELECT COUNTIF(open_receivable > 0) FROM `sahyadri_b2b.order_payment_reconciliation`)
    UNION ALL
    SELECT '09. Invoices or receivable balances on orders not delivered', 0,
           (SELECT COUNTIF(txn_type = 'Invoice' AND order_status <> 'Delivered') FROM l)
         + (SELECT COUNTIF(balance_type = 'Receivable' AND order_status <> 'Delivered') FROM b)
    UNION ALL
    SELECT '10. Invoices dated before the order or after the as-of date', 0,
           (SELECT COUNT(*) FROM l JOIN delivered AS d ON d.order_id = l.order_id
             WHERE l.txn_type = 'Invoice' AND (l.txn_date < d.order_date OR l.txn_date > as_of_date))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
