/* =============================================================================
   Case study · Which DSO should the board see? Four formulas against the
   age of receivables
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Days sales outstanding (DSO) is the board's main collections KPI. In
   April 2026 it fell, so the credit team was praised. In May it jumped
   by 41 days, and they were blamed. The CFO suspects the formula, not
   the team: the pack divides receivables by one month's sales, so a big
   March or a quiet May moves DSO whatever customers do. She asks:
     1. How much do the common DSO formulas disagree, and how much does
        each swing from month to month?
     2. How much of each formula's movement is just the sales pattern?
     3. Which formula follows how old the receivables really are?
     4. What should the pack report?

   METHOD
     - Invoices: Delivered orders with every shipment delivered; invoice
       date = last delivery date; amount = order value after discount.
       Open amount at a month-end = MAX(0, amount - payments received by
       that date).
     - Month-ends June 2024 - September 2026 (28). Receivables (AR) = open
       amount of invoices dated on or before the month-end.
     - DSO formulas:
         Simple:    AR / sales of the month x days in the month
         3-month:   AR / sales of the last 3 months x their days
         12-month:  AR / sales of the last 12 months x their days (from
                    December 2024)
         Countback: walk back month by month, subtracting each month's
                    sales from AR; DSO = days of the months fully used up +
                    the remainder / that month's sales x its days
     - Benchmark: average age of receivables = open amount-weighted days
       since invoice date. Current DSO = the countback on invoices up to
       90 days old only.
     - Distortion: correlation of each formula's monthly change with the
       month's sales change (log), and the standard deviation of monthly
       changes.
   ============================================================================= */

DECLARE first_month_end DATE DEFAULT DATE '2024-06-30';
DECLARE last_month_end  DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Invoices, monthly sales and receivables at each month-end
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ds_invoices` AS
WITH value AS (
    SELECT o.order_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS amount
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_id
),
delivered AS (
    SELECT order_id, MAX(delivery_date) AS invoice_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
    HAVING COUNTIF(delivery_date IS NULL) = 0
)
SELECT v.order_id, d.invoice_date, DATE_TRUNC(d.invoice_date, MONTH) AS invoice_month, v.amount
FROM value AS v JOIN delivered AS d USING (order_id);

CREATE OR REPLACE TABLE `sahyadri_b2b.ds_sales` AS
SELECT invoice_month AS month, SUM(amount) AS sales,
       DATE_DIFF(LAST_DAY(invoice_month, MONTH), invoice_month, DAY) + 1              AS days
FROM `sahyadri_b2b.ds_invoices`
GROUP BY invoice_month;

CREATE OR REPLACE TABLE `sahyadri_b2b.ds_open` AS
WITH month_ends AS (
    SELECT LAST_DAY(m, MONTH) AS month_end
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(first_month_end, MONTH), DATE_TRUNC(last_month_end, MONTH), INTERVAL 1 MONTH)) AS m
),
paid AS (
    SELECT me.month_end, p.order_id, SUM(p.amount) AS paid
    FROM month_ends AS me
    JOIN `sahyadri_b2b.payments` AS p ON p.payment_date <= me.month_end
    GROUP BY me.month_end, p.order_id
)
SELECT me.month_end, iv.order_id, iv.invoice_date, iv.invoice_month,
       GREATEST(0, iv.amount - IFNULL(pd.paid, 0))                                    AS open_amount,
       DATE_DIFF(me.month_end, iv.invoice_date, DAY)                                  AS age_days
FROM month_ends AS me
JOIN `sahyadri_b2b.ds_invoices` AS iv ON iv.invoice_date <= me.month_end
LEFT JOIN paid AS pd ON pd.month_end = me.month_end AND pd.order_id = iv.order_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Four DSO formulas, the countback for current invoices, and the age benchmark
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ds_dso` AS
WITH ar AS (
    SELECT month_end,
           SUM(open_amount)                                                           AS ar,
           SUM(IF(age_days <= 90, open_amount, 0))                                    AS ar_current,
           SUM(open_amount * age_days) / NULLIF(SUM(open_amount), 0)                  AS average_age
    FROM `sahyadri_b2b.ds_open`
    GROUP BY month_end
),
back AS (
    -- each month-end with its own and earlier months' sales, newest first
    SELECT a.month_end, a.ar, a.ar_current, s.month, s.sales, s.days,
           ROW_NUMBER() OVER (PARTITION BY a.month_end ORDER BY s.month DESC)         AS j,
           SUM(s.sales) OVER (PARTITION BY a.month_end ORDER BY s.month DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_sales,
           SUM(s.days)  OVER (PARTITION BY a.month_end ORDER BY s.month DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_days
    FROM ar AS a
    JOIN `sahyadri_b2b.ds_sales` AS s ON s.month <= DATE_TRUNC(a.month_end, MONTH)
),
countback AS (
    SELECT month_end,
           -- the month where cumulative sales first reach AR: full months before it + a fraction of it
           MAX(IF(cum_sales >= ar AND cum_sales - sales < ar, (cum_days - days) + (ar - (cum_sales - sales)) / sales * days, NULL))                 AS dso_countback,
           MAX(IF(cum_sales >= ar_current AND cum_sales - sales < ar_current, (cum_days - days) + (ar_current - (cum_sales - sales)) / sales * days, NULL)) AS dso_current,
           SUM(IF(j = 1, sales, 0))                                                   AS sales_1,
           SUM(IF(j = 1, days, 0))                                                    AS days_1,
           SUM(IF(j <= 3, sales, 0))                                                  AS sales_3,
           SUM(IF(j <= 3, days, 0))                                                   AS days_3,
           SUM(IF(j <= 12, sales, 0))                                                 AS sales_12,
           SUM(IF(j <= 12, days, 0))                                                  AS days_12,
           MAX(j)                                                                     AS months_of_history
    FROM back
    GROUP BY month_end
)
SELECT a.month_end, a.ar, a.ar_current, a.average_age,
       c.sales_1 AS month_sales,
       a.ar / c.sales_1 * c.days_1                                                    AS dso_simple,
       a.ar / c.sales_3 * c.days_3                                                    AS dso_3_month,
       IF(c.months_of_history >= 12, a.ar / c.sales_12 * c.days_12, NULL)              AS dso_12_month,
       c.dso_countback, c.dso_current
FROM ar AS a JOIN countback AS c USING (month_end);

SELECT
    month_end,
    ROUND(ar / 1e7, 2)                                                                AS ar_crore,
    ROUND(month_sales / 1e7, 2)                                                       AS month_sales_crore,
    ROUND(dso_simple, 0)                                                              AS simple,
    ROUND(dso_3_month, 0)                                                             AS three_month,
    ROUND(dso_12_month, 0)                                                            AS twelve_month,
    ROUND(dso_countback, 0)                                                           AS countback,
    ROUND(dso_current, 0)                                                             AS current_invoices_countback,
    ROUND(average_age, 0)                                                             AS average_age_days
FROM `sahyadri_b2b.ds_dso`
ORDER BY month_end;

-- -----------------------------------------------------------------------------
-- Step 3 · Which formula moves with sales, and which follows the age of receivables?
-- -----------------------------------------------------------------------------
WITH changes AS (
    SELECT month_end,
           LN(month_sales) - LAG(LN(month_sales)) OVER (ORDER BY month_end)            AS d_ln_sales,
           average_age - LAG(average_age) OVER (ORDER BY month_end)                    AS d_age,
           dso_simple - LAG(dso_simple) OVER (ORDER BY month_end)                      AS d_simple,
           dso_3_month - LAG(dso_3_month) OVER (ORDER BY month_end)                    AS d_three,
           dso_12_month - LAG(dso_12_month) OVER (ORDER BY month_end)                  AS d_twelve,
           dso_countback - LAG(dso_countback) OVER (ORDER BY month_end)                AS d_countback,
           dso_current - LAG(dso_current) OVER (ORDER BY month_end)                    AS d_current
    FROM `sahyadri_b2b.ds_dso`
),
long_form AS (
    SELECT '1. Simple (one month)' AS formula, d_simple AS d, d_ln_sales, d_age FROM changes UNION ALL
    SELECT '2. 3-month', d_three, d_ln_sales, d_age FROM changes UNION ALL
    SELECT '3. 12-month', d_twelve, d_ln_sales, d_age FROM changes UNION ALL
    SELECT '4. Countback', d_countback, d_ln_sales, d_age FROM changes UNION ALL
    SELECT '5. Countback, invoices up to 90 days', d_current, d_ln_sales, d_age FROM changes
)
SELECT
    formula,
    COUNT(d)                                                                          AS monthly_changes,
    ROUND(STDDEV_POP(d), 1)                                                           AS sd_of_monthly_change_days,
    ROUND(MAX(ABS(d)), 0)                                                             AS largest_monthly_move_days,
    ROUND(CORR(d, d_ln_sales), 2)                                                     AS corr_with_sales_change,
    ROUND(CORR(d, d_age), 2)                                                          AS corr_with_age_change
FROM long_form
WHERE d IS NOT NULL
GROUP BY formula
ORDER BY formula;

-- The trend over the period: every formula against the age of receivables
SELECT
    ROUND(MAX(IF(month_end = DATE '2024-12-31', dso_simple, NULL)), 0)           AS simple_dec_2024,
    ROUND(MAX(IF(month_end = last_month_end, dso_simple, NULL)), 0)              AS simple_sep_2026,
    ROUND(MAX(IF(month_end = DATE '2024-12-31', dso_countback, NULL)), 0)        AS countback_dec_2024,
    ROUND(MAX(IF(month_end = last_month_end, dso_countback, NULL)), 0)           AS countback_sep_2026,
    ROUND(MAX(IF(month_end = DATE '2024-12-31', dso_12_month, NULL)), 0)         AS twelve_month_dec_2024,
    ROUND(MAX(IF(month_end = last_month_end, dso_12_month, NULL)), 0)            AS twelve_month_sep_2026,
    ROUND(MAX(IF(month_end = DATE '2024-12-31', average_age, NULL)), 0)          AS age_dec_2024,
    ROUND(MAX(IF(month_end = last_month_end, average_age, NULL)), 0)             AS age_sep_2026,
    ROUND(MAX(IF(month_end = DATE '2024-12-31', 100 * (1 - ar_current / ar), NULL)), 1) AS over_90_days_share_dec_2024,
    ROUND(MAX(IF(month_end = last_month_end, 100 * (1 - ar_current / ar), NULL)), 1)    AS over_90_days_share_sep_2026
FROM `sahyadri_b2b.ds_dso`;

-- -----------------------------------------------------------------------------
-- Step 4 · The months that caused trouble: March to May 2026
-- -----------------------------------------------------------------------------
SELECT
    month_end,
    ROUND(month_sales / 1e7, 2)                                                       AS month_sales_crore,
    ROUND(dso_simple, 0)                                                              AS simple,
    ROUND(dso_countback, 0)                                                           AS countback,
    ROUND(dso_current, 0)                                                             AS current_invoices_countback,
    ROUND(average_age, 0)                                                             AS average_age_days
FROM `sahyadri_b2b.ds_dso`
WHERE month_end BETWEEN DATE '2026-02-28' AND DATE '2026-06-30'
ORDER BY month_end;
