/* =============================================================================
   Case study · GST paid before the customer pays: how much cash it ties
   up, and how much is lost on bad debts
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   GST is due on the invoice, not on the cash. Every month the company
   pays the government the GST on last month's invoices by the 20th, but
   customers pay on average weeks later, and some never pay. There is no
   GST refund for bad debts. The CFO thinks the company is quietly
   financing its customers' tax. She asks:
     1. On average, how long does the company carry the GST before the
        customer's payment brings it back?
     2. How much GST is outstanding at a typical month-end, and what does
        that cost?
     3. Which customers make it worst?
     4. How much GST has been paid on invoices that will probably never be
        collected?

   RULES APPLIED (as summarised by GST practitioners; see the README)
     - Output GST arises at the invoice and is paid with the monthly
       return, GSTR-3B, by the 20th of the following month.
     - No refund of GST on bad debts; a credit note cannot be issued just
       because the customer did not pay.

   METHOD AND ASSUMPTIONS
     - Invoices: valid orders (not Cancelled or Returned) with a shipment;
       invoice date = first shipment date; taxable value = order value
       after discount; GST = 18 % of it (assumed for every product).
       Invoices dated April 2024 - June 2026; receipts to 30 September 2026.
     - GST due date = the 20th of the month after the invoice.
     - Customers pay GST with each receipt in proportion: GST collected =
       receipt / taxable value x GST (receipts in the data carry the
       taxable value).
     - Funding (rupee-days) per receipt = GST collected x MAX(0, receipt
       date - due date); float = GST collected x MAX(0, due date - receipt
       date). GST not collected by 30 September 2026 is funded from the
       due date to that day.
     - Cost of money: 12 % a year (as in the early-payment discount study).
     - Probably lost: GST on balances still open more than 180 days after
       the due date (the collections studies found almost nothing is
       collected after 180 days).
   ============================================================================= */

DECLARE gst_rate      FLOAT64 DEFAULT 0.18;
DECLARE cost_of_money FLOAT64 DEFAULT 0.12;
DECLARE first_invoice DATE    DEFAULT DATE '2024-04-01';
DECLARE last_invoice  DATE    DEFAULT DATE '2026-06-30';
DECLARE data_end      DATE    DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Invoices, GST due dates and GST collected with each receipt
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.gs_invoices` AS
WITH value AS (
    SELECT o.order_id, o.customer_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS taxable_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id
),
dated AS (
    SELECT v.order_id, v.customer_id, v.taxable_value, MIN(s.shipment_date) AS invoice_date
    FROM value AS v JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = v.order_id
    GROUP BY v.order_id, v.customer_id, v.taxable_value
)
SELECT d.*, c.customer_name, c.customer_segment,
       d.taxable_value * gst_rate                                                     AS gst,
       DATE_ADD(DATE(EXTRACT(YEAR FROM d.invoice_date), EXTRACT(MONTH FROM d.invoice_date), 20), INTERVAL 1 MONTH) AS gst_due_date
FROM dated AS d
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = d.customer_id
WHERE d.invoice_date BETWEEN first_invoice AND last_invoice;

CREATE OR REPLACE TABLE `sahyadri_b2b.gs_receipts` AS
SELECT iv.order_id, iv.customer_id, iv.customer_segment, iv.gst_due_date, p.payment_id, p.payment_date,
       -- GST carried by this receipt, capped so an invoice never returns more than its GST
       LEAST(p.amount, GREATEST(0, iv.taxable_value - IFNULL(SUM(p.amount) OVER w_before, 0))) / iv.taxable_value * iv.gst AS gst_collected
FROM `sahyadri_b2b.gs_invoices` AS iv
JOIN `sahyadri_b2b.payments` AS p ON p.order_id = iv.order_id
WHERE p.payment_date <= data_end
WINDOW w_before AS (PARTITION BY iv.order_id ORDER BY p.payment_date, p.payment_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING);

-- Per invoice: funding in rupee-days, float, and the GST still uncollected
CREATE OR REPLACE TABLE `sahyadri_b2b.gs_funding` AS
WITH by_invoice AS (
    SELECT order_id,
           SUM(gst_collected)                                                         AS gst_collected,
           SUM(gst_collected * GREATEST(0, DATE_DIFF(payment_date, gst_due_date, DAY))) AS funded_rupee_days_collected,
           SUM(gst_collected * GREATEST(0, DATE_DIFF(gst_due_date, payment_date, DAY))) AS float_rupee_days
    FROM `sahyadri_b2b.gs_receipts`
    GROUP BY order_id
)
SELECT iv.*,
       IFNULL(b.gst_collected, 0)                                                     AS gst_collected,
       iv.gst - IFNULL(b.gst_collected, 0)                                            AS gst_uncollected,
       IFNULL(b.funded_rupee_days_collected, 0)
         + (iv.gst - IFNULL(b.gst_collected, 0)) * GREATEST(0, DATE_DIFF(data_end, iv.gst_due_date, DAY)) AS funded_rupee_days,
       IFNULL(b.float_rupee_days, 0)                                                  AS float_rupee_days,
       DATE_DIFF(data_end, iv.gst_due_date, DAY)                                      AS days_since_due
FROM `sahyadri_b2b.gs_invoices` AS iv
LEFT JOIN by_invoice AS b USING (order_id);

-- -----------------------------------------------------------------------------
-- Step 2 · How long the GST is carried, and what it costs
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                                          AS invoices,
    ROUND(SUM(taxable_value) / 1e7, 2)                                                AS taxable_value_crore,
    ROUND(SUM(gst) / 1e7, 2)                                                          AS gst_paid_to_government_crore,
    ROUND(100 * SUM(gst_collected) / SUM(gst), 1)                                     AS gst_recovered_by_sep_2026_pct,
    -- GST-weighted average days between paying the GST and getting it back (collected part)
    ROUND(SUM(funded_rupee_days - gst_uncollected * GREATEST(0, days_since_due)) / NULLIF(SUM(gst_collected), 0), 1) AS average_days_funded_on_collected_gst,
    ROUND(SUM(float_rupee_days) / NULLIF(SUM(gst_collected), 0), 1)                   AS average_days_of_float_on_collected_gst,
    ROUND(100 * SUM(IF(funded_rupee_days > 0, gst, 0)) / SUM(gst), 1)                 AS gst_on_invoices_paid_after_due_date_pct
FROM `sahyadri_b2b.gs_funding`;

-- GST paid to the government but not yet collected, at each month-end (to July 2026: the June 2026
-- invoices, the last in the study, fall due on 20 July)
CREATE OR REPLACE TABLE `sahyadri_b2b.gs_month_ends` AS
WITH month_ends AS (
    SELECT LAST_DAY(m, MONTH) AS month_end
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2024-05-01', DATE '2026-07-01', INTERVAL 1 MONTH)) AS m
),
paid AS (
    SELECT me.month_end, SUM(iv.gst) AS gst_paid
    FROM month_ends AS me JOIN `sahyadri_b2b.gs_invoices` AS iv ON iv.gst_due_date <= me.month_end
    GROUP BY me.month_end
),
collected AS (
    SELECT me.month_end, SUM(r.gst_collected) AS gst_collected
    FROM month_ends AS me JOIN `sahyadri_b2b.gs_receipts` AS r ON r.payment_date <= me.month_end AND r.gst_due_date <= me.month_end
    GROUP BY me.month_end
)
SELECT p.month_end, p.gst_paid, IFNULL(c.gst_collected, 0) AS gst_collected,
       p.gst_paid - IFNULL(c.gst_collected, 0)                                        AS gst_funded
FROM paid AS p LEFT JOIN collected AS c USING (month_end);

SELECT
    ROUND(AVG(gst_funded) / 1e5, 1)                                                   AS average_gst_funded_lakh,
    ROUND(MAX(gst_funded) / 1e5, 1)                                                   AS peak_gst_funded_lakh,
    ARRAY_AGG(month_end ORDER BY gst_funded DESC LIMIT 1)[OFFSET(0)]                  AS peak_month_end,
    ROUND(MIN(gst_funded) / 1e5, 1)                                                   AS lowest_gst_funded_lakh,
    ROUND(MAX(IF(month_end = DATE '2024-06-30', gst_funded, NULL)) / 1e5, 1)           AS jun_2024_lakh,
    ROUND(MAX(IF(month_end = DATE '2026-07-31', gst_funded, NULL)) / 1e5, 1)           AS jul_2026_lakh,
    ROUND(cost_of_money * AVG(IF(month_end > DATE '2025-07-31', gst_funded, NULL)) / 1e5, 2) AS yearly_cost_latest_12_months_lakh
FROM `sahyadri_b2b.gs_month_ends`;

-- Quarter-ends, with the part of the balance that is over 180 days past its due date
SELECT
    m.month_end,
    ROUND(m.gst_funded / 1e5, 1)                                                      AS gst_funded_lakh,
    ROUND(SUM(IF(DATE_DIFF(m.month_end, iv.gst_due_date, DAY) > 180, iv.gst, 0)) / 1e5
          - SUM(IF(DATE_DIFF(m.month_end, iv.gst_due_date, DAY) > 180, IFNULL(r.collected_by_month_end, 0), 0)) / 1e5, 1) AS of_which_over_180_days_lakh
FROM `sahyadri_b2b.gs_month_ends` AS m
JOIN `sahyadri_b2b.gs_invoices` AS iv ON iv.gst_due_date <= m.month_end
LEFT JOIN (
    SELECT me.month_end, rc.order_id, SUM(rc.gst_collected) AS collected_by_month_end
    FROM `sahyadri_b2b.gs_month_ends` AS me
    JOIN `sahyadri_b2b.gs_receipts` AS rc ON rc.payment_date <= me.month_end
    GROUP BY me.month_end, rc.order_id
) AS r ON r.month_end = m.month_end AND r.order_id = iv.order_id
WHERE EXTRACT(MONTH FROM m.month_end) IN (3, 6, 9, 12)
GROUP BY m.month_end, m.gst_funded
ORDER BY m.month_end;

-- -----------------------------------------------------------------------------
-- Step 3 · Which customers make it worst?
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                                                          AS invoices,
    ROUND(SUM(gst) / 1e5, 1)                                                          AS gst_lakh,
    ROUND(SUM(funded_rupee_days) / SUM(gst), 1)                                       AS funded_days_per_rupee_of_gst,
    ROUND(SUM(funded_rupee_days) * cost_of_money / 365 / 1e5, 2)                      AS funding_cost_lakh,
    ROUND(100 * SUM(funded_rupee_days) / SUM(SUM(funded_rupee_days)) OVER (), 1)       AS share_of_funding_pct
FROM `sahyadri_b2b.gs_funding`
GROUP BY customer_segment
ORDER BY funded_days_per_rupee_of_gst DESC;

SELECT
    customer_name, customer_segment,
    ROUND(SUM(gst) / 1e5, 2)                                                          AS gst_lakh,
    ROUND(SUM(funded_rupee_days) / SUM(gst), 0)                                       AS funded_days_per_rupee_of_gst,
    ROUND(SUM(funded_rupee_days) * cost_of_money / 365 / 1e5, 2)                      AS funding_cost_lakh,
    ROUND(SUM(gst_uncollected) / 1e5, 2)                                              AS gst_uncollected_lakh
FROM `sahyadri_b2b.gs_funding`
GROUP BY customer_name, customer_segment
ORDER BY SUM(funded_rupee_days) DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 4 · GST paid on invoices that will probably never be collected
-- -----------------------------------------------------------------------------
SELECT
    CASE WHEN gst_uncollected <= 1 THEN '1. Fully collected'
         WHEN days_since_due <= 90 THEN '2. Open, up to 90 days past the GST due date'
         WHEN days_since_due <= 180 THEN '3. Open, 91-180 days'
         ELSE '4. Open, over 180 days (probably lost)' END                             AS status_on_30_sep_2026,
    COUNT(*)                                                                          AS invoices,
    ROUND(SUM(gst_uncollected) / 1e5, 2)                                              AS gst_uncollected_lakh,
    ROUND(SUM(taxable_value - gst_collected / gst_rate) / 1e5, 2)                     AS taxable_value_uncollected_lakh
FROM `sahyadri_b2b.gs_funding`
GROUP BY status_on_30_sep_2026
ORDER BY status_on_30_sep_2026;
