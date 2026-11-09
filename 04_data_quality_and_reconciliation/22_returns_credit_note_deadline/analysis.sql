/* =============================================================================
   Case study · Returned goods and the GST credit-note deadline: what must
   be credited before 30 November, what is already out of time, and what
   the receivables ledger overstates
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   When a customer returns goods, the original tax invoice still stands.
   The output GST paid on it comes back only through a credit note, and a
   credit note reduces GST only if it is declared by 30 November after the
   end of the financial year of the original supply. Since 1 October 2025
   it also reduces GST only if the customer has reversed the input tax
   credit it took. The accountant has never matched returns to credit
   notes. With the 2025-26 deadline three weeks away (this study is dated
   9 November 2026), she asks:
     1. How many returned orders are there, by financial year of supply,
        and how much GST is at stake against each deadline?
     2. Which returns must be credited, with the customer's ITC reversal
        confirmed, before 30 November 2026?
     3. How much do returned orders still inflate receivables?
     4. What other money is held for customers on orders that were never
        delivered?

   RULES APPLIED (as summarised by GST practitioners; see the README)
     - Section 34(1): a credit note may be issued when goods are returned.
     - Section 34(2): it must be declared no later than 30 November
       following the end of the financial year of the supply (or the
       annual return date, if earlier). After that, the output tax cannot
       be reduced.
     - From 1 October 2025: output tax is reduced only if the registered
       recipient has reversed the input tax credit on the credit note.

   METHOD AND ASSUMPTIONS
     - Returned orders: order status Returned. Invoice date = first
       shipment date; value = order value after discount; GST = 18 %.
     - Financial year of supply: April - March of the invoice date.
       Deadline = 30 November of the year after the financial year ends.
     - Return date: the last delivery date of the returned shipments (the
       data has no separate date for the goods coming back).
     - Report date: 9 November 2026.
     - Every customer is GST-registered (B2B), so the ITC reversal
       condition applies to credit notes issued from 1 October 2025.
     - Money held: receipts on cancelled orders and on orders with no
       shipment.
   ============================================================================= */

DECLARE gst_rate     FLOAT64 DEFAULT 0.18;
DECLARE report_date  DATE    DEFAULT DATE '2026-11-09';
DECLARE itc_rule_from DATE   DEFAULT DATE '2025-10-01';

-- -----------------------------------------------------------------------------
-- Step 1 · Returned orders, their financial year and deadline
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cn_returns` AS
WITH value AS (
    SELECT o.order_id, o.customer_id, o.payment_status,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS taxable_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status = 'Returned'
    GROUP BY o.order_id, o.customer_id, o.payment_status
),
dates AS (
    SELECT order_id, MIN(shipment_date) AS invoice_date, MAX(delivery_date) AS return_date,
           COUNT(*) AS shipments, COUNTIF(shipment_status = 'Returned') AS returned_shipments
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
paid AS (
    SELECT order_id, SUM(amount) AS received FROM `sahyadri_b2b.payments` GROUP BY order_id
)
SELECT v.order_id, v.customer_id, c.customer_name, c.customer_segment, v.payment_status,
       d.invoice_date, d.return_date, d.shipments, d.returned_shipments,
       v.taxable_value,
       v.taxable_value * gst_rate                                                     AS gst,
       IFNULL(p.received, 0)                                                          AS received,
       EXTRACT(YEAR FROM DATE_SUB(d.invoice_date, INTERVAL 3 MONTH))                  AS financial_year,
       DATE(EXTRACT(YEAR FROM DATE_SUB(d.invoice_date, INTERVAL 3 MONTH)) + 1, 11, 30) AS credit_note_deadline
FROM value AS v
JOIN dates AS d ON d.order_id = v.order_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = v.customer_id
LEFT JOIN paid AS p ON p.order_id = v.order_id;

-- -----------------------------------------------------------------------------
-- Step 2 · GST at stake by financial year and deadline
-- -----------------------------------------------------------------------------
SELECT
    CONCAT(CAST(financial_year AS STRING), '-', CAST(MOD(financial_year + 1, 100) AS STRING)) AS financial_year_of_supply,
    MIN(credit_note_deadline)                                                         AS credit_note_deadline,
    CASE WHEN MIN(credit_note_deadline) < report_date THEN '1. Passed'
         WHEN DATE_DIFF(MIN(credit_note_deadline), report_date, DAY) <= 31 THEN '2. Due within a month'
         ELSE '3. Open' END                                                            AS status_on_9_november_2026,
    COUNT(*)                                                                          AS returned_orders,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(SUM(taxable_value) / 1e5, 2)                                                AS taxable_value_lakh,
    ROUND(SUM(gst) / 1e5, 2)                                                          AS gst_lakh
FROM `sahyadri_b2b.cn_returns`
GROUP BY financial_year
ORDER BY financial_year;

-- How long goods take to come back, and how close to the deadline the latest returns are
SELECT
    CONCAT(CAST(financial_year AS STRING), '-', CAST(MOD(financial_year + 1, 100) AS STRING)) AS financial_year_of_supply,
    ROUND(AVG(DATE_DIFF(return_date, invoice_date, DAY)), 1)                          AS average_days_invoice_to_return,
    MAX(return_date)                                                                  AS latest_return,
    MIN(DATE_DIFF(credit_note_deadline, return_date, DAY))                            AS fewest_days_left_at_return
FROM `sahyadri_b2b.cn_returns`
GROUP BY financial_year
ORDER BY financial_year;

-- -----------------------------------------------------------------------------
-- Step 3 · The returns to credit before 30 November 2026
-- -----------------------------------------------------------------------------
SELECT
    customer_name, customer_segment,
    COUNT(*)                                                                          AS returned_orders,
    MIN(invoice_date)                                                                 AS first_invoice,
    MAX(invoice_date)                                                                 AS last_invoice,
    ROUND(SUM(taxable_value) / 1e5, 2)                                                AS taxable_value_lakh,
    ROUND(SUM(gst), 0)                                                                AS gst_rupees,
    -- credit notes issued now fall under the ITC reversal rule
    report_date >= itc_rule_from                                                      AS customer_must_confirm_itc_reversal
FROM `sahyadri_b2b.cn_returns`
WHERE credit_note_deadline = DATE '2026-11-30'
GROUP BY customer_name, customer_segment
ORDER BY gst_rupees DESC;

SELECT
    customer_segment,
    COUNTIF(credit_note_deadline = DATE '2026-11-30')                                 AS due_by_30_nov_2026,
    ROUND(SUM(IF(credit_note_deadline = DATE '2026-11-30', gst, 0)) / 1e5, 2)          AS gst_due_lakh,
    COUNTIF(credit_note_deadline < report_date)                                       AS out_of_time,
    ROUND(SUM(IF(credit_note_deadline < report_date, gst, 0)) / 1e5, 2)                AS gst_out_of_time_lakh
FROM `sahyadri_b2b.cn_returns`
GROUP BY customer_segment
ORDER BY gst_due_lakh DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · How much returned orders inflate receivables
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                                          AS returned_orders,
    COUNTIF(payment_status = 'Unpaid')                                                AS flagged_unpaid,
    COUNTIF(received > 0)                                                             AS with_any_receipt,
    ROUND(SUM(taxable_value - received) / 1e5, 2)                                     AS open_taxable_value_lakh,
    ROUND(SUM((taxable_value - received) * (1 + gst_rate)) / 1e5, 2)                  AS open_invoice_value_incl_gst_lakh,
    ROUND(AVG(DATE_DIFF(report_date, invoice_date, DAY)), 0)                          AS average_age_days,
    COUNTIF(DATE_DIFF(report_date, invoice_date, DAY) > 180)                          AS older_than_180_days,
    COUNTIF(returned_shipments < shipments)                                           AS partly_returned_orders
FROM `sahyadri_b2b.cn_returns`;

-- -----------------------------------------------------------------------------
-- Step 5 · Other money held for customers on orders never delivered
-- -----------------------------------------------------------------------------
WITH order_value AS (
    SELECT o.order_id, o.customer_id, o.order_status,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    GROUP BY o.order_id, o.customer_id, o.order_status
),
shipped AS (SELECT DISTINCT order_id FROM `sahyadri_b2b.shipments`),
receipts AS (SELECT order_id, SUM(amount) AS received, MAX(payment_date) AS last_receipt FROM `sahyadri_b2b.payments` GROUP BY order_id)
SELECT
    CASE WHEN v.order_status = 'Cancelled' THEN '1. Cancelled order'
         ELSE CONCAT('2. No shipment, status ', v.order_status) END                    AS situation,
    COUNT(*)                                                                          AS orders,
    ROUND(SUM(r.received) / 1e5, 2)                                                   AS received_lakh,
    MIN(r.last_receipt)                                                               AS oldest_receipt,
    ROUND(AVG(DATE_DIFF(report_date, r.last_receipt, DAY)), 0)                        AS average_days_held
FROM order_value AS v
JOIN receipts AS r ON r.order_id = v.order_id
LEFT JOIN shipped AS s ON s.order_id = v.order_id
WHERE v.order_status = 'Cancelled' OR s.order_id IS NULL
GROUP BY situation
ORDER BY situation;
