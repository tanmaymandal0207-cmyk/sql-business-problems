/* =============================================================================
   Case study · The MSME 45-day rule: how much of our receivables breach
   it, what interest the law allows, and which customers it pressures
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Indian law protects micro and small manufacturers: a buyer must pay
   within the agreed period, at most 45 days from accepting the goods
   (15 days if nothing is agreed in writing). Late payments carry
   compound interest at three times the RBI bank rate, and since 2024 a
   buyer that has not paid by its year-end cannot deduct the purchase for
   tax (section 43B(h)). The company is considering registering as a
   small enterprise (Udyam) to use these rules with slow payers. The CFO
   asks:
     1. How much of what customers pay arrives after 45 days, and how late?
     2. How much interest would the law have allowed us to claim?
     3. Which customers owed us money past 45 days at their year-end, and
        so would lose their tax deduction?
     4. How should the rules be used?

   RULES APPLIED (as summarised by tax practitioners; see the README)
     - MSMED Act sections 15 - 16: payment within the agreed period, not
       more than 45 days from acceptance; late payments carry compound
       interest with monthly rests at three times the bank rate notified
       by the RBI.
     - Income-tax section 43B(h): a buyer's purchase from a micro or small
       enterprise is deductible only when paid, if paid after the MSMED
       time limit. Applies from 2024-25 and to manufacturers and service
       providers, not traders.

   METHOD AND ASSUMPTIONS
     - Invoices: Delivered orders with every shipment delivered;
       acceptance = last delivery date; due = acceptance + 45 days (a
       written 45-day agreement assumed); amount = order value after
       discount (receipts carry this value; GST would add 18 %).
     - Bank rate 5.50 % (RBI, since December 2025), so interest at 16.5 %
       a year compounded monthly; 6.75 % (the 2024 bank rate, 20.25 %) as a
       sensitivity. Interest on a receipt = amount x ((1 + r/12)^(months
       late) - 1), months late = days late x 12 / 365.
     - Invoices accepted April 2024 - June 2026; receipts and open
       balances to 30 September 2026.
     - 43B(h) test at each customer's assumed 31 March year-end: amounts
       owed to us on 31 March that were then more than 45 days past
       acceptance (2025 and 2026).
   ============================================================================= */

DECLARE first_accepted DATE    DEFAULT DATE '2024-04-01';
DECLARE last_accepted  DATE    DEFAULT DATE '2026-06-30';
DECLARE data_end       DATE    DEFAULT DATE '2026-09-30';
DECLARE credit_days    INT64   DEFAULT 45;
DECLARE bank_rate      FLOAT64 DEFAULT 0.055;
DECLARE bank_rate_2024 FLOAT64 DEFAULT 0.0675;

-- -----------------------------------------------------------------------------
-- Step 1 · Invoices, due dates and every receipt's days late
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ms_invoices` AS
WITH value AS (
    SELECT o.order_id, o.customer_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS amount
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_id, o.customer_id
),
accepted AS (
    SELECT order_id, MAX(delivery_date) AS accepted_on
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
    HAVING COUNTIF(delivery_date IS NULL) = 0
)
SELECT v.order_id, v.customer_id, c.customer_name, c.customer_segment, v.amount, a.accepted_on,
       DATE_ADD(a.accepted_on, INTERVAL credit_days DAY)                              AS due_on
FROM value AS v
JOIN accepted AS a USING (order_id)
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = v.customer_id
WHERE a.accepted_on BETWEEN first_accepted AND last_accepted;

-- Receipts capped at the invoice amount, and the open balance on 30 September 2026
CREATE OR REPLACE TABLE `sahyadri_b2b.ms_items` AS
WITH receipts AS (
    SELECT iv.order_id, p.payment_date,
           LEAST(p.amount, GREATEST(0, iv.amount - IFNULL(SUM(p.amount) OVER w_before, 0))) AS settled
    FROM `sahyadri_b2b.ms_invoices` AS iv
    JOIN `sahyadri_b2b.payments` AS p ON p.order_id = iv.order_id
    WHERE p.payment_date <= data_end
    WINDOW w_before AS (PARTITION BY iv.order_id ORDER BY p.payment_date, p.payment_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
),
open_balance AS (
    SELECT iv.order_id, iv.amount - IFNULL(SUM(r.settled), 0) AS open_amount
    FROM `sahyadri_b2b.ms_invoices` AS iv LEFT JOIN receipts AS r USING (order_id)
    GROUP BY iv.order_id, iv.amount
)
SELECT iv.order_id, iv.customer_id, iv.customer_name, iv.customer_segment, iv.accepted_on, iv.due_on,
       'Paid' AS kind, r.payment_date AS settled_on, r.settled AS amount
FROM `sahyadri_b2b.ms_invoices` AS iv JOIN receipts AS r USING (order_id)
WHERE r.settled > 0
UNION ALL
SELECT iv.order_id, iv.customer_id, iv.customer_name, iv.customer_segment, iv.accepted_on, iv.due_on,
       'Open on 30 Sep 2026', data_end, ob.open_amount
FROM `sahyadri_b2b.ms_invoices` AS iv JOIN open_balance AS ob USING (order_id)
WHERE ob.open_amount > 1;

CREATE OR REPLACE TABLE `sahyadri_b2b.ms_interest` AS
SELECT *,
       DATE_DIFF(settled_on, accepted_on, DAY)                                        AS days_from_acceptance,
       GREATEST(0, DATE_DIFF(settled_on, due_on, DAY))                                AS days_late,
       amount * (POW(1 + 3 * bank_rate / 12, GREATEST(0, DATE_DIFF(settled_on, due_on, DAY)) * 12 / 365) - 1)      AS interest,
       amount * (POW(1 + 3 * bank_rate_2024 / 12, GREATEST(0, DATE_DIFF(settled_on, due_on, DAY)) * 12 / 365) - 1) AS interest_at_2024_rate
FROM `sahyadri_b2b.ms_items`;

-- -----------------------------------------------------------------------------
-- Step 2 · How much is paid after 45 days, and how late
-- -----------------------------------------------------------------------------
SELECT
    kind,
    COUNT(*)                                                                          AS items,
    ROUND(SUM(amount) / 1e7, 2)                                                       AS amount_crore,
    ROUND(100 * SUM(IF(days_late > 0, amount, 0)) / SUM(amount), 1)                   AS beyond_45_days_pct,
    ROUND(100 * SUM(IF(days_from_acceptance > 15, amount, 0)) / SUM(amount), 1)       AS beyond_15_days_pct,
    ROUND(SUM(amount * days_from_acceptance) / SUM(amount), 1)                        AS average_days_from_acceptance,
    ROUND(SUM(IF(days_late > 0, amount * days_late, 0)) / NULLIF(SUM(IF(days_late > 0, amount, 0)), 0), 1) AS average_days_late_when_late
FROM `sahyadri_b2b.ms_interest`
GROUP BY ROLLUP(kind)
ORDER BY kind;

-- Distribution of paid amounts by days from acceptance
SELECT
    CASE WHEN days_from_acceptance <= 15 THEN '1. Within 15 days'
         WHEN days_from_acceptance <= 45 THEN '2. 16-45 days'
         WHEN days_from_acceptance <= 90 THEN '3. 46-90 days'
         WHEN days_from_acceptance <= 180 THEN '4. 91-180 days'
         ELSE '5. Over 180 days' END                                                  AS paid_after,
    COUNT(*)                                                                          AS receipts,
    ROUND(SUM(amount) / 1e7, 2)                                                       AS amount_crore,
    ROUND(100 * SUM(amount) / SUM(SUM(amount)) OVER (), 1)                            AS share_pct
FROM `sahyadri_b2b.ms_interest`
WHERE kind = 'Paid'
GROUP BY paid_after
ORDER BY paid_after;

-- -----------------------------------------------------------------------------
-- Step 3 · Interest the law would have allowed
-- -----------------------------------------------------------------------------
SELECT
    kind,
    ROUND(SUM(interest) / 1e5, 2)                                                     AS interest_at_16_5_pct_lakh,
    ROUND(SUM(interest_at_2024_rate) / 1e5, 2)                                        AS interest_at_20_25_pct_lakh,
    ROUND(100 * SUM(interest) / SUM(amount), 2)                                       AS interest_as_pct_of_amount
FROM `sahyadri_b2b.ms_interest`
GROUP BY ROLLUP(kind)
ORDER BY kind;

SELECT
    customer_segment,
    ROUND(SUM(amount) / 1e7, 2)                                                       AS amount_crore,
    ROUND(100 * SUM(IF(days_late > 0, amount, 0)) / SUM(amount), 1)                   AS beyond_45_days_pct,
    ROUND(SUM(IF(kind = 'Paid', interest, 0)) / 1e5, 2)                               AS interest_on_late_receipts_lakh,
    ROUND(SUM(IF(kind != 'Paid', interest, 0)) / 1e5, 2)                              AS interest_accrued_on_open_lakh
FROM `sahyadri_b2b.ms_interest`
GROUP BY customer_segment
ORDER BY SUM(interest) DESC;

-- Customers with the most interest on receipts they actually paid late
SELECT
    customer_name, customer_segment,
    COUNTIF(kind = 'Paid' AND days_late > 0)                                          AS late_receipts,
    ROUND(SUM(IF(kind = 'Paid' AND days_late > 0, amount * days_late, 0))
          / NULLIF(SUM(IF(kind = 'Paid' AND days_late > 0, amount, 0)), 0), 0)        AS average_days_late,
    ROUND(SUM(IF(kind = 'Paid', interest, 0)) / 1e5, 2)                               AS interest_on_paid_lakh
FROM `sahyadri_b2b.ms_interest`
GROUP BY customer_name, customer_segment
ORDER BY SUM(IF(kind = 'Paid', interest, 0)) DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 4 · Section 43B(h): balances past 45 days at the customer's 31 March year-end
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ms_year_end` AS
WITH year_ends AS (
    SELECT DATE '2025-03-31' AS year_end UNION ALL SELECT DATE '2026-03-31'
),
paid_by AS (
    SELECT ye.year_end, iv.order_id,
           LEAST(iv.amount, IFNULL(SUM(IF(p.payment_date <= ye.year_end, p.amount, 0)), 0)) AS paid
    FROM year_ends AS ye
    JOIN `sahyadri_b2b.ms_invoices` AS iv ON iv.accepted_on <= ye.year_end
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = iv.order_id
    GROUP BY ye.year_end, iv.order_id, iv.amount
)
SELECT pb.year_end, iv.customer_id, iv.customer_name, iv.customer_segment, iv.order_id, iv.accepted_on,
       iv.amount - pb.paid                                                            AS owed,
       DATE_DIFF(pb.year_end, iv.accepted_on, DAY) > credit_days                      AS past_45_days
FROM paid_by AS pb JOIN `sahyadri_b2b.ms_invoices` AS iv USING (order_id)
WHERE iv.amount - pb.paid > 1;

SELECT
    year_end,
    COUNT(DISTINCT customer_id)                                                       AS customers_owing,
    COUNT(DISTINCT IF(past_45_days, customer_id, NULL))                               AS customers_owing_past_45_days,
    ROUND(SUM(owed) / 1e7, 2)                                                         AS owed_crore,
    ROUND(SUM(IF(past_45_days, owed, 0)) / 1e7, 2)                                    AS owed_past_45_days_crore,
    ROUND(100 * SUM(IF(past_45_days, owed, 0)) / SUM(owed), 1)                        AS past_45_days_pct
FROM `sahyadri_b2b.ms_year_end`
GROUP BY year_end
ORDER BY year_end;

-- Largest balances that would be disallowed for the customer at 31 March 2026
SELECT customer_name, customer_segment,
       COUNT(*)                                                                       AS invoices,
       ROUND(SUM(owed) / 1e5, 1)                                                      AS owed_past_45_days_lakh
FROM `sahyadri_b2b.ms_year_end`
WHERE year_end = DATE '2026-03-31' AND past_45_days
GROUP BY customer_name, customer_segment
ORDER BY SUM(owed) DESC
LIMIT 10;
