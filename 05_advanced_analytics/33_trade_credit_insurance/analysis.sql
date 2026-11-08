/* =============================================================================
   Case study · Would trade credit insurance have paid our bad debts?
   Testing the policy conditions against two years of losses
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Bad debts have reached about 7 % of sales (see the expected credit loss
   study). A broker proposes a trade credit insurance policy: the insurer
   pays 90 % of a buyer's unpaid debt. The CFO is tempted, but asks what
   the policy would actually have paid on the losses of the last two
   years, and what premium would be worth paying:
     1. How much has been lost, and on which customers?
     2. Which of those losses would the policy's conditions have covered?
     3. What premium rate would break even on history, with and without
        the conditions?
     4. If insurance is not the answer, what is?

   POLICY TERMS APPLIED (as summarised in insurers' policy documents; see the README)
     - Indemnity: the insured percentage of the unpaid debt, typically
       85 - 90 %; 90 % used here.
     - Premium: a percentage of insured turnover.
     - No cover for deliveries made to a buyer that already has an overdue
       invoice beyond the maximum extension period ("no further deliveries
       ... if the oldest invoice remains outstanding"). 60 days past due is
       assumed here (the period is set in each policy's schedule).
     - Claims are for the buyer's insolvency or protracted default.
       Disputed debts are not paid until the dispute is settled in the
       insured's favour.

   METHOD AND ASSUMPTIONS
     - Invoices: Delivered orders with every shipment delivered; invoice
       date = last delivery; amount = order value after discount (GST not
       added); due date = invoice + 45 days.
     - Default date = due date + 180 days. Only invoices whose default date
       is on or before 30 September 2026 are judged (invoiced to mid-
       February 2026). Loss = amount unpaid on 30 September 2026.
     - Delivered while overdue: at the invoice date, the same customer had
       an earlier invoice more than 60 days past due with more than Rs 1
       still unpaid.
     - Customer kept paying: the customer made any payment after the
       defaulted invoice's default date. Such a customer was trading and
       solvent; the unpaid invoice is a dispute, short payment or
       collection failure, not buyer default.
     - Insurable loss: a defaulted invoice not delivered while overdue,
       from a customer who made no payment after its default date.
   ============================================================================= */

DECLARE credit_days        INT64   DEFAULT 45;
DECLARE default_after_days INT64   DEFAULT 180;
DECLARE max_extension_days INT64   DEFAULT 60;
DECLARE insured_pct        FLOAT64 DEFAULT 0.90;
DECLARE data_end           DATE    DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Invoices, losses, and the policy tests for each invoice
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ti_invoices` AS
WITH value AS (
    SELECT o.order_id, o.customer_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS amount
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_id, o.customer_id
),
delivered AS (
    SELECT order_id, MAX(delivery_date) AS invoice_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
    HAVING COUNTIF(delivery_date IS NULL) = 0
),
base AS (
    SELECT v.order_id, v.customer_id, v.amount, d.invoice_date,
           DATE_ADD(d.invoice_date, INTERVAL credit_days DAY)                         AS due_date,
           DATE_ADD(d.invoice_date, INTERVAL credit_days + default_after_days DAY)    AS default_date
    FROM value AS v JOIN delivered AS d ON d.order_id = v.order_id
),
paid AS (
    SELECT b.order_id,
           IFNULL(SUM(IF(p.payment_date <= data_end, p.amount, 0)), 0)                AS paid_by_data_end,
           IFNULL(SUM(IF(p.payment_date <= b.default_date, p.amount, 0)), 0)          AS paid_by_default_date
    FROM base AS b
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = b.order_id
    GROUP BY b.order_id
)
SELECT b.*, c.customer_name, c.customer_segment,
       p.paid_by_data_end, p.paid_by_default_date,
       GREATEST(0, b.amount - p.paid_by_data_end)                                     AS loss
FROM base AS b
JOIN paid AS p ON p.order_id = b.order_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = b.customer_id
WHERE b.default_date <= data_end;

CREATE OR REPLACE TABLE `sahyadri_b2b.ti_tests` AS
WITH earlier_overdue AS (
    -- for each invoice, earlier invoices of the same customer more than 60 days past due on its invoice date
    SELECT a.order_id, b.order_id AS earlier_order_id, b.amount AS earlier_amount, a.invoice_date
    FROM `sahyadri_b2b.ti_invoices` AS a
    JOIN `sahyadri_b2b.ti_invoices` AS b
      ON b.customer_id = a.customer_id
     AND DATE_ADD(b.due_date, INTERVAL max_extension_days DAY) < a.invoice_date
),
earlier_open AS (
    SELECT e.order_id, e.earlier_order_id, e.earlier_amount - IFNULL(SUM(p.amount), 0) AS open_on_invoice_date
    FROM earlier_overdue AS e
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = e.earlier_order_id AND p.payment_date < e.invoice_date
    GROUP BY e.order_id, e.earlier_order_id, e.earlier_amount
),
overdue_at_delivery AS (
    SELECT order_id, COUNTIF(open_on_invoice_date > 1) AS overdue_invoices_at_delivery
    FROM earlier_open
    GROUP BY order_id
),
customer_payments AS (
    SELECT o.customer_id, p.payment_date, p.amount
    FROM `sahyadri_b2b.payments` AS p
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
    WHERE p.payment_date <= data_end
),
paid_after_default AS (
    SELECT iv.order_id, SUM(cp.amount) AS customer_paid_after_default
    FROM `sahyadri_b2b.ti_invoices` AS iv
    JOIN customer_payments AS cp ON cp.customer_id = iv.customer_id AND cp.payment_date > iv.default_date
    WHERE iv.loss > 1
    GROUP BY iv.order_id
)
SELECT iv.*,
       IFNULL(o.overdue_invoices_at_delivery, 0) > 0                                  AS delivered_while_overdue,
       IFNULL(pa.customer_paid_after_default, 0)                                      AS customer_paid_after_default,
       CASE WHEN iv.loss <= 1 THEN '0. Paid'
            WHEN IFNULL(o.overdue_invoices_at_delivery, 0) > 0 THEN '1. Not covered: delivered while the customer was overdue'
            WHEN IFNULL(pa.customer_paid_after_default, 0) > 0 THEN '2. Not buyer default: the customer kept paying'
            ELSE '3. Insurable: the customer stopped paying' END                       AS loss_class
FROM `sahyadri_b2b.ti_invoices` AS iv
LEFT JOIN overdue_at_delivery AS o ON o.order_id = iv.order_id
LEFT JOIN paid_after_default AS pa ON pa.order_id = iv.order_id;

-- -----------------------------------------------------------------------------
-- Step 2 · How much has been lost, and how
-- -----------------------------------------------------------------------------
SELECT
    IFNULL(customer_segment, 'All')                                                   AS segment,
    COUNT(*)                                                                          AS invoices,
    ROUND(SUM(amount) / 1e7, 2)                                                       AS invoiced_crore,
    COUNTIF(loss > 1)                                                                 AS defaulted_invoices,
    ROUND(SUM(loss) / 1e5, 1)                                                         AS loss_lakh,
    ROUND(100 * SUM(loss) / SUM(amount), 2)                                           AS loss_rate_pct,
    -- collected after the default date: zero means 180 days past due is a clean default point
    ROUND(SUM(LEAST(amount, paid_by_data_end) - LEAST(amount, paid_by_default_date)) / 1e5, 2) AS collected_after_default_lakh
FROM `sahyadri_b2b.ti_tests`
GROUP BY ROLLUP (customer_segment)
ORDER BY customer_segment IS NULL, loss_lakh DESC;

SELECT
    CASE WHEN paid_by_data_end <= 0 THEN '1. Nothing paid' ELSE '2. Part paid' END    AS defaulted_invoice,
    COUNT(*)                                                                          AS invoices,
    ROUND(SUM(loss) / 1e5, 1)                                                         AS loss_lakh,
    ROUND(100 * SUM(loss) / SUM(amount), 1)                                           AS unpaid_share_of_invoice_pct
FROM `sahyadri_b2b.ti_tests`
WHERE loss > 1
GROUP BY defaulted_invoice
ORDER BY defaulted_invoice;

SELECT
    COUNT(DISTINCT customer_id)                                                       AS customers,
    COUNT(DISTINCT IF(loss > 1, customer_id, NULL))                                   AS customers_with_a_loss
FROM `sahyadri_b2b.ti_tests`;

-- -----------------------------------------------------------------------------
-- Step 3 · Which losses would the policy have covered?
-- -----------------------------------------------------------------------------
SELECT
    loss_class,
    COUNT(*)                                                                          AS invoices,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(SUM(amount) / 1e7, 2)                                                       AS invoiced_crore,
    ROUND(SUM(loss) / 1e5, 1)                                                         AS loss_lakh,
    ROUND(100 * SUM(loss) / SUM(SUM(loss)) OVER (), 1)                                AS share_of_loss_pct,
    ROUND(insured_pct * SUM(IF(loss_class LIKE '3.%', loss, 0)) / 1e5, 2)             AS claim_paid_lakh
FROM `sahyadri_b2b.ti_tests`
GROUP BY loss_class
ORDER BY loss_class;

-- The two tests are not exclusive: how much of the loss fails each, on its own
SELECT
    delivered_while_overdue,
    customer_paid_after_default > 0                                                   AS customer_kept_paying,
    COUNT(*)                                                                          AS defaulted_invoices,
    ROUND(SUM(loss) / 1e5, 1)                                                         AS loss_lakh,
    ROUND(100 * SUM(loss) / SUM(SUM(loss)) OVER (), 1)                                AS share_of_loss_pct
FROM `sahyadri_b2b.ti_tests`
WHERE loss > 1
GROUP BY delivered_while_overdue, customer_kept_paying
ORDER BY delivered_while_overdue, customer_kept_paying;

-- Of the invoices delivered while overdue: how many deliveries the policy condition would have stopped
SELECT
    delivered_while_overdue,
    COUNT(*)                                                                          AS invoices,
    ROUND(SUM(amount) / 1e7, 2)                                                       AS invoiced_crore,
    ROUND(100 * SUM(amount) / SUM(SUM(amount)) OVER (), 1)                            AS share_of_sales_pct,
    ROUND(100 * SUM(loss) / SUM(amount), 2)                                           AS loss_rate_pct
FROM `sahyadri_b2b.ti_tests`
GROUP BY delivered_while_overdue
ORDER BY delivered_while_overdue;

-- -----------------------------------------------------------------------------
-- Step 4 · The premium rate that would have broken even
-- -----------------------------------------------------------------------------
SELECT
    IFNULL(customer_segment, 'All')                                                   AS segment,
    ROUND(SUM(amount) / 1e7, 2)                                                       AS turnover_crore,
    -- as the broker presents it: 90 % of every loss on all turnover
    ROUND(100 * insured_pct * SUM(loss) / SUM(amount), 2)                             AS break_even_rate_all_losses_pct,
    -- with the conditions: no cover on deliveries while overdue (that turnover is not insured), buyer default only
    ROUND(SUM(IF(NOT delivered_while_overdue, amount, 0)) / 1e7, 2)                   AS insurable_turnover_crore,
    ROUND(insured_pct * SUM(IF(loss_class LIKE '3.%', loss, 0)) / 1e5, 2)             AS claims_lakh,
    ROUND(100 * insured_pct * SUM(IF(loss_class LIKE '3.%', loss, 0))
          / NULLIF(SUM(IF(NOT delivered_while_overdue, amount, 0)), 0), 3)            AS break_even_rate_with_conditions_pct
FROM `sahyadri_b2b.ti_tests`
GROUP BY ROLLUP (customer_segment)
ORDER BY customer_segment IS NULL, segment;

-- -----------------------------------------------------------------------------
-- Step 5 · Where the losses really come from
-- -----------------------------------------------------------------------------
-- Customers who kept paying newer invoices while older ones stayed unpaid: a collection list
SELECT
    customer_name, customer_segment,
    COUNTIF(loss > 1)                                                                 AS unpaid_invoices,
    ROUND(SUM(loss) / 1e5, 2)                                                         AS unpaid_lakh,
    COUNTIF(loss > 1 AND paid_by_data_end > 0)                                        AS of_which_part_paid,
    ROUND(MAX(IF(loss > 1, customer_paid_after_default, 0)) / 1e5, 1)                 AS paid_since_on_other_invoices_lakh
FROM `sahyadri_b2b.ti_tests`
WHERE loss_class NOT LIKE '3.%'
GROUP BY customer_name, customer_segment
HAVING SUM(loss) > 0
ORDER BY unpaid_lakh DESC
LIMIT 10;

-- The few customers who really stopped paying
SELECT
    customer_name, customer_segment,
    COUNTIF(loss_class LIKE '3.%')                                                    AS insurable_invoices,
    ROUND(SUM(IF(loss_class LIKE '3.%', loss, 0)) / 1e5, 2)                           AS insurable_loss_lakh,
    MAX(IF(loss_class LIKE '3.%', invoice_date, NULL))                                AS last_insurable_invoice
FROM `sahyadri_b2b.ti_tests`
GROUP BY customer_name, customer_segment
HAVING COUNTIF(loss_class LIKE '3.%') > 0
ORDER BY insurable_loss_lakh DESC;
