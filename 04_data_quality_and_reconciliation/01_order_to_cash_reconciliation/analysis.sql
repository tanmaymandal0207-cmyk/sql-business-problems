/* =============================================================================
   Case study · Order-to-cash reconciliation
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Finance reports receivables using the `payment_status` flag on each sales
   order (Paid / Partially Paid / Unpaid). The flag is maintained by hand and
   is never checked against the payments actually received. Before the flag is
   used for collections and month-end reporting, finance needs to know:
     1. Does the flag agree with the payments recorded against each order?
     2. Where it does not, what type of exception is it and how much money is
        involved (duplicate receipts, short payments, payments on cancelled
        orders, flags not updated)?
     3. How much cash is actually outstanding on delivered orders, and how old
        is it?
     4. Which customers hold the largest overdue balances?

   OUTPUTS
     Step 1  order_payment_reconciliation   one row per order (saved table)
     Step 2  Exception summary              one row per reconciliation category
     Step 3  Recorded vs. derived status    agreement matrix
     Step 4  Settlement benchmark           how long fully paid orders took to pay
     Step 5  Receivables ageing             delivered orders with open balances
     Step 6  Overdue balances by customer   top 10 customers, balances > 90 days
     Step 7  Exception register             order-level list for follow-up

   KEY RULES
     - Order value = SUM(quantity * unit_price * (1 - discount_percent / 100)).
       A NULL discount_percent is treated as 0 %. Evidence: all 260 orders
       marked Paid that contain a NULL-discount line were paid exactly at the
       0 % value (see README).
     - Amounts within ₹0.05 are treated as equal (rounding tolerance).
     - Duplicate payment = more than one payment row for the same order with
       the same payment date and amount.
     - Receivables cover Delivered orders only. Ageing is measured from the
       final delivery date (shipment date if delivery date is missing; order
       date if there is no shipment record) to the as-of date.
     - As-of date = 2026-09-30, the last transaction date in the dataset.
   ============================================================================= */

DECLARE as_of_date DATE    DEFAULT DATE '2026-09-30';
DECLARE tolerance  FLOAT64 DEFAULT 0.05;

-- -----------------------------------------------------------------------------
-- Step 1 · Order-level reconciliation register
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.order_payment_reconciliation` AS
WITH order_value AS (
    SELECT
        order_id,
        SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),

payment_summary AS (
    SELECT
        order_id,
        COUNT(*)          AS payment_count,
        SUM(amount)       AS amount_paid,
        MAX(payment_date) AS last_payment_date
    FROM `sahyadri_b2b.payments`
    GROUP BY order_id
),

duplicate_payments AS (
    -- same order, same date, same amount recorded more than once
    SELECT
        order_id,
        SUM(row_count - 1)          AS duplicate_rows,
        SUM((row_count - 1) * amount) AS duplicate_amount
    FROM (
        SELECT order_id, payment_date, amount, COUNT(*) AS row_count
        FROM `sahyadri_b2b.payments`
        GROUP BY order_id, payment_date, amount
    )
    WHERE row_count > 1
    GROUP BY order_id
),

final_delivery AS (
    SELECT
        order_id,
        COALESCE(MAX(delivery_date), MAX(shipment_date)) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),

base AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.order_status,
        o.payment_status                          AS recorded_status,
        ROUND(v.order_value, 2)                   AS order_value,
        ROUND(IFNULL(p.amount_paid, 0), 2)        AS amount_paid,
        IFNULL(p.payment_count, 0)                AS payment_count,
        IFNULL(d.duplicate_rows, 0)               AS duplicate_rows,
        ROUND(IFNULL(d.duplicate_amount, 0), 2)   AS duplicate_amount,
        p.last_payment_date,
        f.final_delivery_date
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN order_value                 AS v ON v.order_id = o.order_id
    LEFT JOIN payment_summary        AS p ON p.order_id = o.order_id
    LEFT JOIN duplicate_payments     AS d ON d.order_id = o.order_id
    LEFT JOIN final_delivery         AS f ON f.order_id = o.order_id
),

with_balance AS (
    -- balance from the rounded figures so that value - paid = balance exactly
    SELECT *, ROUND(order_value - amount_paid, 2) AS balance
    FROM base
),

derived AS (
    SELECT
        *,
        CASE
            WHEN amount_paid <= tolerance     THEN 'Unpaid'
            WHEN ABS(balance) <= tolerance    THEN 'Paid'
            WHEN balance < -tolerance         THEN 'Overpaid'
            ELSE 'Partially Paid'
        END AS derived_status
    FROM with_balance
)

SELECT
    *,
    -- one primary category per order, in order of financial priority
    CASE
        WHEN order_status IN ('Cancelled', 'Returned') AND amount_paid > tolerance
            THEN '1. Payment on cancelled/returned order'
        WHEN duplicate_rows > 0
            THEN '2. Duplicate payment'
        WHEN derived_status = 'Overpaid'
            THEN '3. Overpayment'
        WHEN recorded_status = 'Paid' AND derived_status = 'Partially Paid'
            THEN '4. Short payment marked Paid'
        WHEN recorded_status <> 'Paid' AND derived_status = 'Paid'
            THEN '5. Paid but status not updated'
        WHEN recorded_status <> derived_status
            THEN '6. Other status mismatch'
        ELSE '0. Matched'
    END AS reconciliation_category,

    CASE
        WHEN order_status = 'Delivered' AND balance > tolerance THEN balance
        ELSE 0
    END AS open_receivable,

    CASE
        WHEN order_status = 'Delivered' AND balance > tolerance
            THEN DATE_DIFF(as_of_date, COALESCE(final_delivery_date, order_date), DAY)
    END AS days_outstanding
FROM derived;

-- -----------------------------------------------------------------------------
-- Step 2 · Exception summary
-- -----------------------------------------------------------------------------
SELECT
    reconciliation_category,
    COUNT(*)                                    AS orders,
    ROUND(SUM(order_value), 2)                  AS order_value,
    ROUND(SUM(amount_paid), 2)                  AS amount_paid,
    ROUND(SUM(CASE
        WHEN reconciliation_category LIKE '1.%' THEN amount_paid        -- refundable
        WHEN reconciliation_category LIKE '2.%' THEN duplicate_amount   -- received twice
        WHEN reconciliation_category LIKE '3.%' THEN -balance           -- excess received
        WHEN reconciliation_category LIKE '4.%' THEN balance            -- shortfall
        ELSE 0
    END), 2)                                    AS amount_at_issue
FROM `sahyadri_b2b.order_payment_reconciliation`
GROUP BY reconciliation_category
ORDER BY reconciliation_category;

-- -----------------------------------------------------------------------------
-- Step 3 · Recorded status vs. status derived from payments
-- -----------------------------------------------------------------------------
SELECT
    recorded_status,
    COUNTIF(derived_status = 'Paid')           AS derived_paid,
    COUNTIF(derived_status = 'Partially Paid') AS derived_partially_paid,
    COUNTIF(derived_status = 'Unpaid')         AS derived_unpaid,
    COUNTIF(derived_status = 'Overpaid')       AS derived_overpaid,
    COUNT(*)                                   AS total_orders
FROM `sahyadri_b2b.order_payment_reconciliation`
GROUP BY recorded_status
ORDER BY recorded_status;

-- -----------------------------------------------------------------------------
-- Step 4 · Settlement benchmark: days from final delivery to final payment
--          for delivered orders that are fully paid (matched)
-- -----------------------------------------------------------------------------
SELECT DISTINCT
    COUNT(*) OVER ()                                         AS paid_orders,
    PERCENTILE_CONT(days_to_settle, 0.5) OVER ()             AS median_days,
    PERCENTILE_CONT(days_to_settle, 0.9) OVER ()             AS p90_days,
    PERCENTILE_CONT(days_to_settle, 0.99) OVER ()            AS p99_days
FROM (
    SELECT DATE_DIFF(last_payment_date, final_delivery_date, DAY) AS days_to_settle
    FROM `sahyadri_b2b.order_payment_reconciliation`
    WHERE order_status = 'Delivered'
      AND reconciliation_category = '0. Matched'
      AND derived_status = 'Paid'
      AND final_delivery_date IS NOT NULL
);

-- -----------------------------------------------------------------------------
-- Step 5 · Receivables ageing (delivered orders with an open balance)
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN days_outstanding <= 30  THEN '1. 0-30 days'
        WHEN days_outstanding <= 60  THEN '2. 31-60 days'
        WHEN days_outstanding <= 90  THEN '3. 61-90 days'
        WHEN days_outstanding <= 180 THEN '4. 91-180 days'
        WHEN days_outstanding <= 365 THEN '5. 181-365 days'
        ELSE                              '6. Over 365 days'
    END                                                   AS ageing_bucket,
    COUNT(*)                                              AS orders,
    COUNTIF(amount_paid = 0)                              AS orders_with_no_payment,
    ROUND(SUM(open_receivable), 2)                        AS open_receivable,
    ROUND(100 * SUM(open_receivable)
          / SUM(SUM(open_receivable)) OVER (), 2)         AS pct_of_receivables
FROM `sahyadri_b2b.order_payment_reconciliation`
WHERE open_receivable > 0
GROUP BY ageing_bucket
ORDER BY ageing_bucket;

-- -----------------------------------------------------------------------------
-- Step 6 · Customers with the largest balances overdue by more than 90 days
-- -----------------------------------------------------------------------------
SELECT
    r.customer_id,
    c.customer_name,
    c.customer_segment,
    COUNT(*)                                AS overdue_orders,
    ROUND(SUM(r.open_receivable), 2)        AS overdue_balance,
    MAX(r.days_outstanding)                 AS oldest_days_outstanding,
    MAX(r.last_payment_date)                AS last_payment_on_overdue_orders
FROM `sahyadri_b2b.order_payment_reconciliation` AS r
JOIN `sahyadri_b2b.customers`                    AS c
    ON c.customer_id = r.customer_id
WHERE r.open_receivable > 0
  AND r.days_outstanding > 90
GROUP BY r.customer_id, c.customer_name, c.customer_segment
ORDER BY overdue_balance DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 7 · Exception register for follow-up
-- -----------------------------------------------------------------------------
SELECT
    reconciliation_category,
    order_id,
    customer_id,
    order_date,
    order_status,
    recorded_status,
    derived_status,
    order_value,
    amount_paid,
    payment_count,
    duplicate_amount,
    balance
FROM `sahyadri_b2b.order_payment_reconciliation`
WHERE reconciliation_category <> '0. Matched'
ORDER BY reconciliation_category, ABS(balance) DESC, order_id;
