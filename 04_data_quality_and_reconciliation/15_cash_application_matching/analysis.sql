/* =============================================================================
   Case study · Cash application: how many receipts can be matched automatically?
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Two accounts executives spend most of each week applying customer
   receipts to open invoices by hand. A new bank-statement integration will
   bring in each receipt with the customer and the amount, but not the
   invoice it pays. Finance wants to know, before buying the auto-matching
   module, how much of the work rules could take over:
     1. How do customers actually pay: one payment per order, or several?
     2. If a receipt only carries the customer and the amount, how many can
        be matched to the right order by simple rules?
     3. Why do the rest fail, and how much money do they carry?
     4. What would raise the automatic match rate: a fallback rule, or a
        remittance reference on part payments?

   METHOD
     - Every payment is treated as a receipt with only customer, date and
       amount known. Its true order (payments.order_id) is kept aside to
       measure accuracy.
     - Candidate invoices: the customer's orders placed on or before the
       receipt date with an open balance just before the receipt
       (order value - payments recorded earlier; receipts are sequenced by
       date, then payment id).
     - Matching rules, applied in order (amounts within Rs 0.05):
         R1 Exact invoice: amount = the full value of exactly one candidate.
         R2 Exact balance: amount = the open balance of exactly one candidate.
         Otherwise: Ambiguous (amount fits two or more candidates) or
         No match (fits none).
     - Accuracy = share of automatic matches that pick the true order.
     - Round sum = an amount that is a whole multiple of Rs 1,000.
   ============================================================================= */

DECLARE tolerance FLOAT64 DEFAULT 0.05;

-- -----------------------------------------------------------------------------
-- Step 1 · Receipts and how customers pay
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ca_receipts` AS
WITH order_value AS (
    SELECT o.order_id, o.customer_id, o.order_date, o.payment_status,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    GROUP BY o.order_id, o.customer_id, o.order_date, o.payment_status
)
SELECT
    p.payment_id, p.order_id AS true_order_id, v.customer_id, p.payment_date, p.amount, p.payment_method,
    v.order_value,
    COUNT(*) OVER (PARTITION BY p.order_id)                                                    AS payments_on_order,
    ROW_NUMBER() OVER (PARTITION BY p.order_id ORDER BY p.payment_date, p.payment_id)          AS instalment_no,
    MOD(CAST(ROUND(p.amount * 100) AS INT64), 100000) = 0                                      AS is_round_sum
FROM `sahyadri_b2b.payments` AS p
JOIN order_value AS v ON v.order_id = p.order_id;

SELECT
    payments_on_order, instalment_no,
    COUNT(*)                                                         AS receipts,
    ROUND(100 * AVG(amount / order_value), 1)                        AS avg_share_of_order_pct,
    COUNTIF(is_round_sum)                                            AS round_sums,
    ROUND(100 * AVG(IF(is_round_sum, 1, 0)), 1)                      AS round_sum_pct
FROM `sahyadri_b2b.ca_receipts`
GROUP BY payments_on_order, instalment_no
ORDER BY payments_on_order, instalment_no;

-- Which instalments are round sums? (all but the last instalment, by size)
SELECT
    CASE WHEN amount < 5000 THEN '1. Under Rs 5k' WHEN amount < 10000 THEN '2. Rs 5-10k'
         WHEN amount < 20000 THEN '3. Rs 10-20k' ELSE '4. Rs 20k+' END                 AS amount_band,
    COUNT(*)                                                                             AS non_final_instalments,
    ROUND(100 * AVG(IF(is_round_sum, 1, 0)), 1)                                          AS round_sum_pct
FROM `sahyadri_b2b.ca_receipts`
WHERE payments_on_order > 1 AND instalment_no < payments_on_order
GROUP BY amount_band
ORDER BY amount_band;

-- -----------------------------------------------------------------------------
-- Step 2 · Match every receipt using only customer, date and amount
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ca_candidates` AS
WITH orders AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    GROUP BY o.order_id, o.customer_id, o.order_date
),
pairs AS (
    SELECT r.payment_id, r.payment_date, r.amount, o.order_id, o.order_value
    FROM `sahyadri_b2b.ca_receipts` AS r
    JOIN orders AS o ON o.customer_id = r.customer_id AND o.order_date <= r.payment_date
),
paid_before AS (
    -- payments on the candidate order recorded before this receipt
    SELECT c.payment_id, c.order_id, SUM(IFNULL(q.amount, 0)) AS paid
    FROM pairs AS c
    LEFT JOIN `sahyadri_b2b.payments` AS q
      ON q.order_id = c.order_id
     AND (q.payment_date < c.payment_date OR (q.payment_date = c.payment_date AND q.payment_id < c.payment_id))
    GROUP BY c.payment_id, c.order_id
)
SELECT
    c.payment_id, c.order_id, c.amount, c.order_value,
    c.order_value - b.paid                                             AS open_balance,
    ABS(c.amount - c.order_value) <= tolerance                         AS fits_invoice,
    ABS(c.amount - (c.order_value - b.paid)) <= tolerance              AS fits_balance
FROM pairs AS c
JOIN paid_before AS b ON b.payment_id = c.payment_id AND b.order_id = c.order_id
WHERE c.order_value - b.paid > tolerance;

CREATE OR REPLACE TABLE `sahyadri_b2b.ca_matches` AS
WITH agg AS (
    SELECT payment_id,
           COUNT(*)                                                   AS open_candidates,
           COUNTIF(fits_invoice)                                      AS invoice_fits,
           COUNTIF(fits_balance)                                      AS balance_fits,
           ANY_VALUE(IF(fits_invoice, order_id, NULL))                AS invoice_order,
           ANY_VALUE(IF(fits_balance, order_id, NULL))                AS balance_order
    FROM `sahyadri_b2b.ca_candidates`
    GROUP BY payment_id
)
SELECT
    r.*,
    IFNULL(a.open_candidates, 0)                                       AS open_candidates,
    CASE
        WHEN a.invoice_fits = 1                                  THEN 'R1. Exact invoice amount'
        WHEN IFNULL(a.invoice_fits, 0) = 0 AND a.balance_fits = 1 THEN 'R2. Exact open balance'
        WHEN a.invoice_fits > 1 OR a.balance_fits > 1             THEN 'X1. Ambiguous'
        ELSE                                                           'X2. No match'
    END                                                                AS match_result,
    CASE
        WHEN a.invoice_fits = 1                                  THEN a.invoice_order
        WHEN IFNULL(a.invoice_fits, 0) = 0 AND a.balance_fits = 1 THEN a.balance_order
    END                                                                AS matched_order_id
FROM `sahyadri_b2b.ca_receipts` AS r
LEFT JOIN agg AS a ON a.payment_id = r.payment_id;

SELECT
    match_result,
    COUNT(*)                                                           AS receipts,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                   AS share_pct,
    ROUND(SUM(amount) / 1e7, 2)                                        AS value_crore,
    ROUND(100 * SUM(amount) / SUM(SUM(amount)) OVER (), 1)             AS value_share_pct,
    COUNTIF(matched_order_id = true_order_id)                          AS correct,
    COUNTIF(matched_order_id != true_order_id)                         AS wrong
FROM `sahyadri_b2b.ca_matches`
GROUP BY match_result
ORDER BY match_result;

-- -----------------------------------------------------------------------------
-- Step 3 · Why receipts fail to match
-- -----------------------------------------------------------------------------
SELECT
    CASE WHEN payments_on_order = 1 AND ABS(amount - order_value) <= tolerance THEN '1. Single full payment'
         WHEN payments_on_order = 1                                          THEN '2. Single part payment (order not fully paid)'
         WHEN instalment_no < payments_on_order                              THEN '3. Instalment, not the last'
         ELSE                                                                     '4. Last instalment' END AS receipt_type,
    COUNT(*)                                                                                   AS receipts,
    ROUND(100 * AVG(IF(match_result LIKE 'R%', 1, 0)), 1)                                     AS auto_matched_pct,
    ROUND(100 * AVG(IF(match_result = 'X1. Ambiguous', 1, 0)), 1)                             AS ambiguous_pct,
    ROUND(100 * AVG(IF(match_result = 'X2. No match', 1, 0)), 1)                              AS no_match_pct,
    ROUND(100 * AVG(IF(is_round_sum, 1, 0)), 1)                                               AS round_sum_pct
FROM `sahyadri_b2b.ca_matches`
GROUP BY receipt_type
ORDER BY receipt_type;

-- Why the unmatched receipts fail, by what happened on the true order
WITH seq AS (
    SELECT m.*,
           m.order_value - SUM(m.amount) OVER (PARTITION BY m.true_order_id ORDER BY m.payment_date, m.payment_id
                                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS open_after,
           m.order_value - SUM(m.amount) OVER (PARTITION BY m.true_order_id ORDER BY m.payment_date, m.payment_id
                                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) + m.amount AS open_before
    FROM `sahyadri_b2b.ca_matches` AS m
)
SELECT
    CASE WHEN open_before <= tolerance                 THEN '4. Duplicate: order already fully paid'
         WHEN instalment_no < payments_on_order        THEN '1. Instalment, more payments followed'
         WHEN open_after > 500                         THEN '2. Part payment, order still open'
         ELSE                                               '3. Short payment of Rs 500 or less' END AS reason,
    COUNT(*)                                                                    AS receipts,
    ROUND(SUM(amount) / 1e5, 2)                                                 AS value_lakh,
    ROUND(100 * AVG(IF(is_round_sum, 1, 0)), 1)                                 AS round_sum_pct,
    ROUND(SUM(GREATEST(open_after, 0)) / 1e5, 2)                                AS balance_left_open_lakh
FROM seq
WHERE match_result LIKE 'X%'
GROUP BY reason
ORDER BY reason;

-- Ambiguous receipts: how many open invoices of the same customer share the amount?
SELECT
    m.payment_id, m.customer_id, m.payment_date, m.amount, m.open_candidates,
    COUNTIF(c.fits_invoice OR c.fits_balance)                          AS orders_with_same_amount
FROM `sahyadri_b2b.ca_matches` AS m
JOIN `sahyadri_b2b.ca_candidates` AS c ON c.payment_id = m.payment_id
WHERE m.match_result = 'X1. Ambiguous'
GROUP BY m.payment_id, m.customer_id, m.payment_date, m.amount, m.open_candidates
ORDER BY m.amount DESC;

-- How many open invoices does a customer have when a receipt arrives?
SELECT
    CASE WHEN open_candidates <= 1 THEN '1. 0-1' WHEN open_candidates <= 3 THEN '2. 2-3'
         WHEN open_candidates <= 10 THEN '3. 4-10' ELSE '4. 11+' END   AS open_invoices,
    COUNT(*)                                                           AS receipts,
    ROUND(100 * AVG(IF(match_result LIKE 'R%', 1, 0)), 1)              AS auto_matched_pct
FROM `sahyadri_b2b.ca_matches`
GROUP BY open_invoices
ORDER BY open_invoices;

-- -----------------------------------------------------------------------------
-- Step 4 · Fallback rules for the unmatched receipts, and what a remittance
--          reference on part payments would add
-- -----------------------------------------------------------------------------
WITH x AS (
    SELECT c.payment_id, c.order_id, m.true_order_id,
           c.open_balance >= m.amount - tolerance                                                       AS large_enough,
           SUM(IF(c.open_balance >= m.amount - tolerance, 1, 0)) OVER (PARTITION BY c.payment_id)      AS large_enough_count,
           ROW_NUMBER() OVER (PARTITION BY c.payment_id ORDER BY o.order_date, c.order_id)             AS oldest_rank,
           ROW_NUMBER() OVER (PARTITION BY c.payment_id ORDER BY o.order_date DESC, c.order_id DESC)   AS newest_rank
    FROM `sahyadri_b2b.ca_candidates` AS c
    JOIN `sahyadri_b2b.ca_matches` AS m ON m.payment_id = c.payment_id AND m.match_result LIKE 'X%'
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = c.order_id
)
SELECT 'F1. Oldest open invoice' AS fallback_rule, COUNT(*) AS receipts_matched,
       COUNTIF(order_id = true_order_id) AS correct, COUNTIF(order_id != true_order_id) AS wrong
FROM x WHERE oldest_rank = 1
UNION ALL
SELECT 'F2. Newest open invoice', COUNT(*), COUNTIF(order_id = true_order_id), COUNTIF(order_id != true_order_id)
FROM x WHERE newest_rank = 1
UNION ALL
SELECT 'F3. Only one open invoice large enough', COUNT(*), COUNTIF(order_id = true_order_id), COUNTIF(order_id != true_order_id)
FROM x WHERE large_enough AND large_enough_count = 1
ORDER BY fallback_rule;

SELECT
    COUNTIF(match_result LIKE 'R%')                                                         AS auto_matched_now,
    COUNTIF(match_result LIKE 'X%' AND instalment_no < payments_on_order)                   AS unmatched_non_final_instalments,
    COUNTIF(match_result LIKE 'X%' AND payments_on_order = 1)                               AS unmatched_single_part_payments,
    ROUND(100 * (COUNTIF(match_result LIKE 'R%')
                 + COUNTIF(match_result LIKE 'X%' AND (instalment_no < payments_on_order OR payments_on_order = 1))) / COUNT(*), 1)
                                                                                            AS auto_rate_if_part_payments_carry_a_reference_pct
FROM `sahyadri_b2b.ca_matches`;
