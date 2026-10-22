/* =============================================================================
   Case study · Receivables roll-forward reconciliation
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   At every month-end, finance must show that the trade receivables balance
   moves only for the right reasons:
       opening balance + invoices raised - cash received = closing balance
   Auditors ask for this roll-forward, and for the closing balance to agree
   with the open-item ageing. Customer credit balances (cash received with
   nothing, or not enough, to apply it to) must be shown separately, not
   netted silently against receivables. Finance wants to know:
     1. Does the receivables account roll forward month by month, and what
        are the month-end balances and days sales outstanding?
     2. How large are customer credit balances, and what causes them?
     3. Does the 30 Sep 2026 closing balance agree with the open-item ageing
        in the order-to-cash reconciliation?

   KEY RULES
     - Sub-ledger built from source data: one invoice per Delivered order,
       one receipt per payment row.
     - Invoice amount: order value, rounded to the paisa,
       quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100).
     - Invoice date: final delivery date (the revenue recognition point used
       in the cut-off case study). If missing, the latest shipment date; if
       there is no shipment, the order date. The basis is recorded.
     - Cancelled and Returned orders are not invoiced. Undelivered orders are
       not invoiced yet. Cash received on any of them is a credit balance.
     - Each order's balance at a month-end = invoices - receipts to that date.
       Positive (above 5 paise) = receivable. Negative = credit balance.
     - DSO = gross receivables / invoices in the last 3 months x 91 days.
   ============================================================================= */

DECLARE period_start DATE    DEFAULT DATE '2024-01-01';
DECLARE as_of_date   DATE    DEFAULT DATE '2026-09-30';
DECLARE tolerance    FLOAT64 DEFAULT 0.05;

-- -----------------------------------------------------------------------------
-- Step 1 · Receivables sub-ledger: one row per invoice or receipt
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.receivables_ledger` AS
WITH order_value AS (
    SELECT
        order_id,
        ROUND(SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)), 2) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
shipping AS (
    SELECT order_id, MAX(delivery_date) AS final_delivery_date, MAX(shipment_date) AS last_shipment_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    'Invoice'                                                        AS txn_type,
    COALESCE(s.final_delivery_date, s.last_shipment_date, o.order_date) AS txn_date,
    CASE
        WHEN s.final_delivery_date IS NOT NULL THEN 'Delivery date'
        WHEN s.last_shipment_date  IS NOT NULL THEN 'Shipment date (no delivery date)'
        ELSE 'Order date (no shipment)'
    END                                                              AS date_basis,
    v.order_value                                                    AS amount
FROM `sahyadri_b2b.sales_orders` AS o
JOIN order_value                 AS v ON v.order_id = o.order_id
LEFT JOIN shipping               AS s ON s.order_id = o.order_id
WHERE o.order_status = 'Delivered'
  AND COALESCE(s.final_delivery_date, s.last_shipment_date, o.order_date) <= as_of_date

UNION ALL

SELECT
    p.order_id,
    o.customer_id,
    o.order_status,
    'Receipt'                                                        AS txn_type,
    p.payment_date                                                   AS txn_date,
    'Payment date'                                                   AS date_basis,
    -p.amount                                                        AS amount
FROM `sahyadri_b2b.payments`     AS p
JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
WHERE p.payment_date <= as_of_date;

-- -----------------------------------------------------------------------------
-- Step 2 · Order balance at every month-end
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.receivables_month_end` AS
WITH months AS (
    SELECT LAST_DAY(month_start) AS month_end
    FROM UNNEST(GENERATE_DATE_ARRAY(period_start, as_of_date, INTERVAL 1 MONTH)) AS month_start
),
orders AS (
    SELECT order_id, ANY_VALUE(customer_id) AS customer_id, ANY_VALUE(order_status) AS order_status,
           MIN(txn_date) AS first_txn_date
    FROM `sahyadri_b2b.receivables_ledger`
    GROUP BY order_id
),
balances AS (
    SELECT
        m.month_end,
        o.order_id,
        o.customer_id,
        o.order_status,
        ROUND(SUM(IF(l.txn_type = 'Invoice', l.amount, 0)), 2)  AS invoiced_to_date,
        ROUND(-SUM(IF(l.txn_type = 'Receipt', l.amount, 0)), 2) AS received_to_date,
        ROUND(SUM(l.amount), 2)                                 AS balance
    FROM months AS m
    JOIN orders AS o ON o.first_txn_date <= m.month_end
    JOIN `sahyadri_b2b.receivables_ledger` AS l
      ON l.order_id = o.order_id AND l.txn_date <= m.month_end
    GROUP BY m.month_end, o.order_id, o.customer_id, o.order_status
)
SELECT
    *,
    CASE
        WHEN balance >  tolerance THEN 'Receivable'
        WHEN balance < -tolerance THEN 'Credit balance'
        ELSE 'Settled'
    END AS balance_type
FROM balances;

-- -----------------------------------------------------------------------------
-- Step 3 · Monthly roll-forward: opening + invoices - receipts = closing
-- -----------------------------------------------------------------------------
WITH flows AS (
    SELECT
        LAST_DAY(txn_date)                                  AS month_end,
        SUM(IF(txn_type = 'Invoice', amount, 0))            AS invoices,
        -SUM(IF(txn_type = 'Receipt', amount, 0))           AS receipts
    FROM `sahyadri_b2b.receivables_ledger`
    GROUP BY month_end
),
closing AS (
    SELECT
        month_end,
        SUM(balance)                                        AS net_balance,
        SUM(IF(balance_type = 'Receivable', balance, 0))    AS gross_receivables,
        -SUM(IF(balance_type = 'Credit balance', balance, 0)) AS credit_balances
    FROM `sahyadri_b2b.receivables_month_end`
    GROUP BY month_end
),
joined AS (
    SELECT
        c.month_end,
        IFNULL(LAG(c.net_balance) OVER (ORDER BY c.month_end), 0) AS opening_net,
        IFNULL(f.invoices, 0)                                     AS invoices,
        IFNULL(f.receipts, 0)                                     AS receipts,
        c.net_balance                                             AS closing_net,
        c.gross_receivables,
        c.credit_balances,
        SUM(IFNULL(f.invoices, 0)) OVER (ORDER BY c.month_end ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS invoices_3m
    FROM closing     AS c
    LEFT JOIN flows  AS f ON f.month_end = c.month_end
)
SELECT
    month_end,
    ROUND(opening_net, 2)                                          AS opening_net,
    ROUND(invoices, 2)                                             AS invoices,
    ROUND(receipts, 2)                                             AS receipts,
    ROUND(closing_net, 2)                                          AS closing_net,
    ROUND(opening_net + invoices - receipts - closing_net, 2)      AS roll_forward_difference,
    ROUND(gross_receivables, 2)                                    AS gross_receivables,
    ROUND(credit_balances, 2)                                      AS credit_balances,
    ROUND(SAFE_DIVIDE(gross_receivables, invoices_3m) * 91, 0)     AS dso_days
FROM joined
ORDER BY month_end;

-- -----------------------------------------------------------------------------
-- Step 4 · Credit balances at the as-of date: what are they?
-- -----------------------------------------------------------------------------
WITH dup AS (
    SELECT order_id, COUNT(*) - COUNT(DISTINCT CONCAT(CAST(payment_date AS STRING), '|', CAST(amount AS STRING))) AS duplicate_rows
    FROM `sahyadri_b2b.payments`
    GROUP BY order_id
)
SELECT
    CASE
        WHEN b.order_status IN ('Cancelled', 'Returned')            THEN '1. Cash on cancelled or returned order (refund due)'
        WHEN b.order_status <> 'Delivered'                          THEN '2. Advance on order not yet delivered'
        WHEN d.duplicate_rows > 0                                   THEN '3. Duplicate receipt on delivered order'
        ELSE                                                             '4. Other overpayment on delivered order'
    END                                       AS credit_balance_cause,
    COUNT(*)                                  AS orders,
    COUNT(DISTINCT b.customer_id)             AS customers,
    ROUND(-SUM(b.balance), 2)                 AS credit_amount
FROM `sahyadri_b2b.receivables_month_end` AS b
LEFT JOIN dup                             AS d ON d.order_id = b.order_id
WHERE b.month_end = LAST_DAY(as_of_date) AND b.balance_type = 'Credit balance'
GROUP BY credit_balance_cause
ORDER BY credit_balance_cause;

-- -----------------------------------------------------------------------------
-- Step 5 · Tie-out at 30 Sep 2026: roll-forward vs open-item ageing
--          (requires sahyadri_b2b.order_payment_reconciliation from the
--          order-to-cash reconciliation case study)
-- -----------------------------------------------------------------------------
SELECT
    'Gross receivables on delivered orders'                                      AS line_item,
    (SELECT COUNTIF(balance_type = 'Receivable') FROM `sahyadri_b2b.receivables_month_end`
      WHERE month_end = LAST_DAY(as_of_date))                                    AS roll_forward_orders,
    (SELECT ROUND(SUM(IF(balance_type = 'Receivable', balance, 0)), 2) FROM `sahyadri_b2b.receivables_month_end`
      WHERE month_end = LAST_DAY(as_of_date))                                    AS roll_forward_amount,
    (SELECT COUNTIF(open_receivable > 0) FROM `sahyadri_b2b.order_payment_reconciliation`) AS ageing_orders,
    (SELECT ROUND(SUM(open_receivable), 2) FROM `sahyadri_b2b.order_payment_reconciliation`) AS ageing_amount;

-- Invoices dated on a fallback basis (no delivery date in the data)
SELECT date_basis, COUNT(*) AS invoices, ROUND(SUM(amount), 2) AS amount
FROM `sahyadri_b2b.receivables_ledger`
WHERE txn_type = 'Invoice'
GROUP BY date_basis
ORDER BY invoices DESC;
