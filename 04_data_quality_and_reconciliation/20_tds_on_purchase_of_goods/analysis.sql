/* =============================================================================
   Case study · TDS on purchase of goods: what our customers should deduct,
   and what to reconcile
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   A large buyer must deduct TDS of 0.1 % on its purchases from a supplier
   above Rs 50 lakh in a financial year (section 194Q, section 393(1) of
   the Income-tax Act 2025 from 1 April 2026). The tax is our money: it
   shows as a credit in our tax statement (Form 26AS / AIS) once the
   buyer files its return, and we claim it against our own tax. Until
   March 2025, we also had to collect TCS from such buyers (section
   206C(1H)) unless they deducted TDS. The accountant has never
   reconciled any of it. She asks:
     1. Which customers cross Rs 50 lakh in each financial year, and when?
     2. How much TDS should each deduct, by quarter, so the credits in our
        tax statement can be checked?
     3. Do customers' receipts show the deduction, or do they pay in full?
     4. What TCS exposure did the old rule leave for 2024-25?

   RULES APPLIED (as summarised by tax practitioners; see the README)
     - The buyer deducts 0.1 % of the amount by which its purchases from
       us in the financial year (April - March) exceed Rs 50 lakh, at the
       time the purchase is booked (or paid, if earlier), on the value
       excluding GST (CBDT Circular 13/2021). Only buyers with turnover
       above Rs 10 crore must deduct; their turnover is not in our data.
     - TCS under 206C(1H): 0.1 % of receipts from a buyer above Rs 50 lakh
       in a year, not needed where the buyer deducted TDS; no longer
       collected on sales from 1 April 2025.

   METHOD AND ASSUMPTIONS
     - Invoices: valid orders (not Cancelled or Returned) with a shipment;
       invoice date = first shipment date (the GST invoice travels with
       the goods); taxable value = order value after discount.
     - Every customer whose purchases cross Rs 50 lakh is treated as a
       buyer that must deduct. A sensitivity keeps only Enterprise and
       Distributor customers.
     - Financial years 2024-25, 2025-26 and 2026-27 to date (to September
       2026).
     - A receipt "shows TDS" when an invoice with TDS due was settled
       within Rs 1 of (value - expected TDS); "paid in full" when receipts
       reached the value.
   ============================================================================= */

DECLARE threshold FLOAT64 DEFAULT 5000000;
DECLARE tds_rate  FLOAT64 DEFAULT 0.001;
DECLARE fy_start  DATE    DEFAULT DATE '2024-04-01';
DECLARE data_end  DATE    DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Invoices and the running total per customer and financial year
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.td_invoices` AS
WITH value AS (
    SELECT o.order_id, o.customer_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS taxable_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id
),
dated AS (
    SELECT v.*, MIN(s.shipment_date) AS invoice_date
    FROM value AS v JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = v.order_id
    GROUP BY v.order_id, v.customer_id, v.taxable_value
),
running AS (
    SELECT d.*,
           -- financial year label: the April it starts in
           EXTRACT(YEAR FROM DATE_SUB(d.invoice_date, INTERVAL 3 MONTH))              AS fy,
           SUM(d.taxable_value) OVER (PARTITION BY d.customer_id, EXTRACT(YEAR FROM DATE_SUB(d.invoice_date, INTERVAL 3 MONTH))
                                      ORDER BY d.invoice_date, d.order_id
                                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_value
    FROM dated AS d
    WHERE d.invoice_date BETWEEN fy_start AND data_end
)
SELECT r.*, c.customer_name, c.customer_segment,
       DATE_TRUNC(r.invoice_date, QUARTER)                                            AS quarter,
       -- the part of this invoice that falls above Rs 50 lakh for the year
       GREATEST(0, r.cum_value - threshold) - GREATEST(0, r.cum_value - r.taxable_value - threshold) AS above_threshold,
       tds_rate * (GREATEST(0, r.cum_value - threshold) - GREATEST(0, r.cum_value - r.taxable_value - threshold)) AS tds_expected
FROM running AS r
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = r.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Who crosses Rs 50 lakh, when, and how much TDS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.td_customers` AS
SELECT
    fy, customer_id, ANY_VALUE(customer_name) AS customer_name, ANY_VALUE(customer_segment) AS customer_segment,
    SUM(taxable_value)                                                                AS purchases,
    MIN(IF(cum_value > threshold, invoice_date, NULL))                                AS crossed_on,
    SUM(above_threshold)                                                              AS above_threshold,
    SUM(tds_expected)                                                                 AS tds_expected,
    COUNTIF(tds_expected > 0)                                                         AS invoices_with_tds
FROM `sahyadri_b2b.td_invoices`
GROUP BY fy, customer_id;

SELECT
    CONCAT(CAST(fy AS STRING), '-', SUBSTR(CAST(fy + 1 AS STRING), 3, 2))             AS financial_year,
    COUNT(*)                                                                          AS customers_buying,
    COUNTIF(crossed_on IS NOT NULL)                                                   AS customers_over_50_lakh,
    ROUND(100 * SUM(IF(crossed_on IS NOT NULL, purchases, 0)) / SUM(purchases), 1)    AS their_share_of_sales_pct,
    ROUND(SUM(above_threshold) / 1e7, 2)                                              AS purchases_above_50_lakh_crore,
    ROUND(SUM(tds_expected), 0)                                                       AS tds_expected_rupees,
    SUM(invoices_with_tds)                                                            AS invoices_with_tds,
    -- sensitivity: only Enterprise and Distributor customers deduct
    ROUND(SUM(IF(customer_segment IN ('Enterprise', 'Distributor'), tds_expected, 0)), 0) AS tds_if_only_enterprise_distributor
FROM `sahyadri_b2b.td_customers`
GROUP BY fy
ORDER BY fy;

-- When in the year customers cross Rs 50 lakh
SELECT
    CONCAT(CAST(fy AS STRING), '-', SUBSTR(CAST(fy + 1 AS STRING), 3, 2))             AS financial_year,
    FORMAT_DATE('%b', crossed_on)                                                     AS month_crossed,
    COUNT(*)                                                                          AS customers
FROM `sahyadri_b2b.td_customers`
WHERE crossed_on IS NOT NULL
GROUP BY fy, FORMAT_DATE('%b', crossed_on), EXTRACT(MONTH FROM DATE_SUB(crossed_on, INTERVAL 3 MONTH))
ORDER BY fy, EXTRACT(MONTH FROM DATE_SUB(crossed_on, INTERVAL 3 MONTH));

-- The reconciliation schedule: expected TDS credits by quarter (what Form 26AS / AIS should show)
SELECT
    quarter,
    COUNT(DISTINCT IF(tds_expected > 0, customer_id, NULL))                           AS deducting_customers,
    COUNTIF(tds_expected > 0)                                                         AS invoices,
    ROUND(SUM(tds_expected), 0)                                                       AS tds_expected_rupees
FROM `sahyadri_b2b.td_invoices`
GROUP BY quarter
HAVING SUM(tds_expected) > 0
ORDER BY quarter;

-- Largest expected deductors, latest full year (2025-26)
SELECT customer_name, customer_segment,
       ROUND(purchases / 1e5, 1)                                                      AS purchases_lakh,
       crossed_on,
       ROUND(tds_expected, 0)                                                         AS tds_expected_rupees,
       invoices_with_tds
FROM `sahyadri_b2b.td_customers`
WHERE fy = 2025 AND crossed_on IS NOT NULL
ORDER BY tds_expected DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 3 · Do receipts show the deduction?
-- -----------------------------------------------------------------------------
WITH receipts AS (
    SELECT order_id, SUM(amount) AS received FROM `sahyadri_b2b.payments` GROUP BY order_id
)
SELECT
    CASE WHEN r.received IS NULL THEN '4. Nothing received'
         WHEN ABS(r.received - (i.taxable_value - i.tds_expected)) <= 1 THEN '1. Settled net of TDS'
         WHEN r.received >= i.taxable_value - 1 THEN '2. Paid in full (no deduction visible)'
         ELSE '3. Part paid' END                                                      AS receipt_pattern,
    COUNT(*)                                                                          AS invoices_with_tds_due,
    ROUND(SUM(i.tds_expected), 0)                                                     AS tds_expected_rupees
FROM `sahyadri_b2b.td_invoices` AS i
LEFT JOIN receipts AS r USING (order_id)
WHERE i.tds_expected > 0
GROUP BY receipt_pattern
ORDER BY receipt_pattern;

-- -----------------------------------------------------------------------------
-- Step 4 · TCS exposure for 2024-25 under section 206C(1H)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.td_tcs` AS
WITH receipts AS (
    SELECT o.customer_id, p.payment_date, p.amount,
           SUM(p.amount) OVER (PARTITION BY o.customer_id ORDER BY p.payment_date, p.payment_id
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)       AS cum_received
    FROM `sahyadri_b2b.payments` AS p
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
    WHERE p.payment_date BETWEEN DATE '2024-04-01' AND DATE '2025-03-31'
)
SELECT customer_id,
       SUM(amount)                                                                    AS received,
       SUM(GREATEST(0, cum_received - threshold) - GREATEST(0, cum_received - amount - threshold)) AS receipts_above
FROM receipts GROUP BY customer_id;

SELECT
    COUNTIF(receipts_above > 0)                                                       AS customers_with_receipts_over_50_lakh,
    ROUND(SUM(receipts_above) / 1e7, 2)                                               AS receipts_above_50_lakh_crore,
    ROUND(tds_rate * SUM(receipts_above), 0)                                          AS tcs_due_if_no_tds_rupees
FROM `sahyadri_b2b.td_tcs`;
