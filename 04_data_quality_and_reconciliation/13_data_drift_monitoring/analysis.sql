/* =============================================================================
   Case study · Data drift monitoring with the population stability index
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The BI team refreshes the management dashboards every month. Twice last
   year a dashboard looked wrong and nobody could say whether the business
   had changed or the data feed had. The team wants an automatic monthly
   check that compares each month's data with a reference year and raises
   an alert only when a change is real:
     1. Which fields shift from month to month, and by how much?
     2. Which shifts are larger than normal sampling noise?
     3. Which real shifts are expected business changes and which need
        investigation?
     4. What alert rule should the monthly refresh use?

   METHOD
     - 13 monitored fields at four grains: orders, order lines, payments
       and shipments. Month = order month (orders, lines), payment month or
       shipment month.
     - Reference period: calendar 2024. Monitored months: January 2025 to
       September 2026.
     - Bins: categories (with NULL as its own bin) for text fields; for
       numeric fields, the deciles of the reference period, plus NULL.
     - Population stability index (PSI) per field and month:
         PSI = SUM over bins (a - e) x LN(a / e)
       a, e = monitored-month and reference shares, with 0.5 added to every
       bin count. Usual reading: < 0.10 stable, 0.10-0.25 moderate shift,
       > 0.25 major shift.
     - Noise test: n x N / (n + N) x PSI is approximately chi-square with
       (bins - 1) degrees of freedom when nothing has changed. n and N are
       the number of ORDERS behind the month and the reference period (lines
       of one order are not independent, so orders are the sample size).
       Converted to a z-score with the Wilson-Hilferty approximation; alert
       when z >= 3.30 (1 % across 21 monitored months, Bonferroni).
     - Two adjusted fields show how known business changes are removed:
       price ratio indexed to its calendar-year median, and order status
       for complete order months at least 60 days old.
   ============================================================================= */

DECLARE baseline_start DATE    DEFAULT DATE '2024-01-01';
DECLARE monitor_start  DATE    DEFAULT DATE '2025-01-01';
DECLARE as_of          DATE    DEFAULT DATE '2026-09-30';
DECLARE z_alert        FLOAT64 DEFAULT 3.30;
-- complete order months that are at least 60 days old at the extraction date
DECLARE mature_before  DATE    DEFAULT DATE_TRUNC(DATE_SUB(as_of, INTERVAL 60 DAY), MONTH);

-- -----------------------------------------------------------------------------
-- Step 1 · Observations: one row per field x record, with month and cluster
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dd_observations` AS
WITH orders AS (
    SELECT o.order_id, o.order_date, o.order_status, o.employee_id, c.customer_segment,
           DATE_DIFF(o.promised_delivery_date, o.order_date, DAY)                            AS promise_window,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))      AS order_value,
           COUNT(*)                                                                          AS lines
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    GROUP BY o.order_id, o.order_date, o.order_status, o.employee_id, c.customer_segment, promise_window
),
lines AS (
    SELECT i.order_id, o.order_date, pc.category_name, i.discount_percent, i.quantity,
           i.unit_price / p.selling_price                                                    AS price_ratio
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
),
year_median AS (
    SELECT DISTINCT EXTRACT(YEAR FROM order_date) AS yr,
           PERCENTILE_CONT(price_ratio, 0.5) OVER (PARTITION BY EXTRACT(YEAR FROM order_date)) AS med
    FROM lines
),
obs AS (
              SELECT 'A. Order'    AS grain, '01. Order value'          AS field, order_id, order_date AS event_date, order_value AS num_value, CAST(NULL AS STRING) AS cat_value FROM orders
    UNION ALL SELECT 'A. Order', '02. Customer segment',                order_id, order_date, NULL, customer_segment FROM orders
    UNION ALL SELECT 'A. Order', '03. Order status',                    order_id, order_date, NULL, order_status FROM orders
    UNION ALL SELECT 'A. Order', '04. Order status (months 60+ days old)', order_id, order_date, NULL, order_status FROM orders
              WHERE order_date < mature_before
    UNION ALL SELECT 'A. Order', '05. Promise window (days)',           order_id, order_date, promise_window, NULL FROM orders
    UNION ALL SELECT 'A. Order', '06. Salesperson assigned',            order_id, order_date, NULL, IF(employee_id IS NULL, 'Unassigned', 'Assigned') FROM orders
    UNION ALL SELECT 'A. Order', '07. Lines per order',                 order_id, order_date, NULL, IF(lines >= 6, '6+', CAST(lines AS STRING)) FROM orders
    UNION ALL SELECT 'B. Line',  '08. Product category',                order_id, order_date, NULL, category_name FROM lines
    UNION ALL SELECT 'B. Line',  '09. Discount %',                      order_id, order_date, NULL, CAST(discount_percent AS STRING) FROM lines
    UNION ALL SELECT 'B. Line',  '10. Quantity',                        order_id, order_date, quantity, NULL FROM lines
    UNION ALL SELECT 'B. Line',  '11. Price ratio (unit price / list)', order_id, order_date, price_ratio, NULL FROM lines
    UNION ALL SELECT 'B. Line',  '12. Price ratio indexed to its year', l.order_id, l.order_date, l.price_ratio / m.med, NULL
              FROM lines AS l JOIN year_median AS m ON m.yr = EXTRACT(YEAR FROM l.order_date)
    UNION ALL SELECT 'C. Payment',  '13. Payment method',               order_id, payment_date, NULL, payment_method FROM `sahyadri_b2b.payments`
    UNION ALL SELECT 'D. Shipment', '14. Shipping cost',                order_id, shipment_date, shipping_cost, NULL FROM `sahyadri_b2b.shipments`
    UNION ALL SELECT 'D. Shipment', '15. Shipment status',              order_id, shipment_date, NULL, shipment_status FROM `sahyadri_b2b.shipments`
)
SELECT
    grain, field, order_id, event_date,
    DATE_TRUNC(event_date, MONTH)                                     AS month_start,
    event_date < monitor_start                                        AS is_reference,
    num_value, cat_value,
    field IN ('01. Order value', '05. Promise window (days)', '10. Quantity',
              '11. Price ratio (unit price / list)', '12. Price ratio indexed to its year',
              '14. Shipping cost')                                    AS is_numeric
FROM obs
WHERE event_date >= baseline_start AND event_date <= as_of;

-- -----------------------------------------------------------------------------
-- Step 2 · Bins: reference deciles for numeric fields, categories otherwise
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dd_cuts` AS
SELECT DISTINCT
    field,
    PERCENTILE_CONT(num_value, 0.1) OVER (PARTITION BY field) AS c1,
    PERCENTILE_CONT(num_value, 0.2) OVER (PARTITION BY field) AS c2,
    PERCENTILE_CONT(num_value, 0.3) OVER (PARTITION BY field) AS c3,
    PERCENTILE_CONT(num_value, 0.4) OVER (PARTITION BY field) AS c4,
    PERCENTILE_CONT(num_value, 0.5) OVER (PARTITION BY field) AS c5,
    PERCENTILE_CONT(num_value, 0.6) OVER (PARTITION BY field) AS c6,
    PERCENTILE_CONT(num_value, 0.7) OVER (PARTITION BY field) AS c7,
    PERCENTILE_CONT(num_value, 0.8) OVER (PARTITION BY field) AS c8,
    PERCENTILE_CONT(num_value, 0.9) OVER (PARTITION BY field) AS c9
FROM `sahyadri_b2b.dd_observations`
WHERE is_numeric AND is_reference AND num_value IS NOT NULL;

CREATE OR REPLACE TABLE `sahyadri_b2b.dd_binned` AS
SELECT
    o.grain, o.field, o.order_id, o.month_start, o.is_reference,
    CASE
        WHEN o.is_numeric AND o.num_value IS NULL THEN 'NULL'
        WHEN o.is_numeric THEN CONCAT('D', CAST(1 + IF(o.num_value >= k.c1, 1, 0) + IF(o.num_value >= k.c2, 1, 0) + IF(o.num_value >= k.c3, 1, 0)
                                                  + IF(o.num_value >= k.c4, 1, 0) + IF(o.num_value >= k.c5, 1, 0) + IF(o.num_value >= k.c6, 1, 0)
                                                  + IF(o.num_value >= k.c7, 1, 0) + IF(o.num_value >= k.c8, 1, 0) + IF(o.num_value >= k.c9, 1, 0) AS STRING))
        ELSE IFNULL(o.cat_value, 'NULL')
    END                                                                AS bin
FROM `sahyadri_b2b.dd_observations` AS o
LEFT JOIN `sahyadri_b2b.dd_cuts` AS k ON k.field = o.field;

-- -----------------------------------------------------------------------------
-- Step 3 · PSI and noise test per field x monitored month
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dd_psi` AS
WITH field_bins AS (
    SELECT DISTINCT grain, field, bin FROM `sahyadri_b2b.dd_binned`
),
months AS (
    SELECT DISTINCT field, month_start FROM `sahyadri_b2b.dd_binned` WHERE NOT is_reference
),
ref_counts AS (
    SELECT field, bin, COUNT(*) AS n FROM `sahyadri_b2b.dd_binned` WHERE is_reference GROUP BY field, bin
),
ref_totals AS (
    SELECT field, COUNT(*) AS records, COUNT(DISTINCT order_id) AS orders FROM `sahyadri_b2b.dd_binned` WHERE is_reference GROUP BY field
),
mon_counts AS (
    SELECT field, month_start, bin, COUNT(*) AS n FROM `sahyadri_b2b.dd_binned` WHERE NOT is_reference GROUP BY field, month_start, bin
),
mon_totals AS (
    SELECT field, month_start, COUNT(*) AS records, COUNT(DISTINCT order_id) AS orders
    FROM `sahyadri_b2b.dd_binned` WHERE NOT is_reference GROUP BY field, month_start
),
grid AS (
    SELECT b.grain, b.field, m.month_start, b.bin,
           IFNULL(mc.n, 0)                                                  AS month_n,
           IFNULL(rc.n, 0)                                                  AS ref_n,
           COUNT(*) OVER (PARTITION BY b.field, m.month_start)              AS bins
    FROM field_bins AS b
    JOIN months AS m ON m.field = b.field
    LEFT JOIN mon_counts AS mc ON mc.field = b.field AND mc.month_start = m.month_start AND mc.bin = b.bin
    LEFT JOIN ref_counts AS rc ON rc.field = b.field AND rc.bin = b.bin
),
shares AS (
    SELECT g.*, mt.records AS month_records, mt.orders AS month_orders, rt.records AS ref_records, rt.orders AS ref_orders,
           (g.month_n + 0.5) / (mt.records + 0.5 * g.bins)                  AS a,
           (g.ref_n   + 0.5) / (rt.records + 0.5 * g.bins)                  AS e
    FROM grid AS g
    JOIN mon_totals AS mt ON mt.field = g.field AND mt.month_start = g.month_start
    JOIN ref_totals AS rt ON rt.field = g.field
),
psi AS (
    SELECT grain, field, month_start,
           ANY_VALUE(bins) AS bins, ANY_VALUE(month_records) AS month_records, ANY_VALUE(month_orders) AS month_orders,
           ANY_VALUE(ref_records) AS ref_records, ANY_VALUE(ref_orders) AS ref_orders,
           SUM((a - e) * LN(a / e)) AS psi
    FROM shares
    GROUP BY grain, field, month_start
),
tested AS (
    SELECT *,
           psi * month_orders * ref_orders / (month_orders + ref_orders)    AS chi_orders,
           psi * month_records * ref_records / (month_records + ref_records) AS chi_records_naive,
           bins - 1                                                         AS df
    FROM psi
)
SELECT *,
    (POW(chi_orders / df, 1 / 3) - (1 - 2 / (9 * df))) / SQRT(2 / (9 * df))        AS z,
    (POW(chi_records_naive / df, 1 / 3) - (1 - 2 / (9 * df))) / SQRT(2 / (9 * df)) AS z_naive,
    CASE WHEN psi < 0.10 THEN '1. Stable (< 0.10)' WHEN psi < 0.25 THEN '2. Moderate (0.10-0.25)' ELSE '3. Major (> 0.25)' END AS psi_band
FROM tested;

-- Field summary over the 21 monitored months
SELECT
    field,
    ANY_VALUE(bins)                                                    AS bins,
    ROUND(AVG(month_records))                                          AS avg_records_per_month,
    ROUND(AVG(month_orders))                                           AS avg_orders_per_month,
    ROUND(AVG(psi), 3)                                                 AS avg_psi,
    ROUND(MAX(psi), 3)                                                 AS max_psi,
    COUNTIF(psi >= 0.10)                                               AS months_psi_over_0_10,
    COUNTIF(z >= z_alert)                                              AS months_beyond_noise,
    COUNTIF(z_naive >= z_alert)                                        AS months_beyond_noise_if_records_independent
FROM `sahyadri_b2b.dd_psi`
GROUP BY field
ORDER BY field;

-- -----------------------------------------------------------------------------
-- Step 4 · The alerts, and what is behind them
-- -----------------------------------------------------------------------------
SELECT field, month_start, ROUND(psi, 3) AS psi, psi_band, ROUND(z, 1) AS z, month_orders
FROM `sahyadri_b2b.dd_psi`
WHERE z >= z_alert
ORDER BY field, month_start;

-- Price ratio: the alert is the January list price increase
SELECT
    month_start,
    ROUND(MAX(IF(field = '11. Price ratio (unit price / list)', psi, NULL)), 3)  AS psi_raw_price_ratio,
    ROUND(MAX(IF(field = '12. Price ratio indexed to its year', psi, NULL)), 3)  AS psi_indexed_price_ratio
FROM `sahyadri_b2b.dd_psi`
WHERE field IN ('11. Price ratio (unit price / list)', '12. Price ratio indexed to its year')
  AND EXTRACT(MONTH FROM month_start) IN (1, 6, 12)
GROUP BY month_start
ORDER BY month_start;

-- Order status: the alert is order maturity (recent orders are still open)
SELECT
    b.month_start,
    COUNT(*)                                                                    AS orders,
    ROUND(100 * COUNTIF(b.bin IN ('Pending', 'Processing', 'Shipped')) / COUNT(*), 1) AS still_open_pct,
    ROUND(ANY_VALUE(p.psi), 3)                                                  AS psi_order_status
FROM `sahyadri_b2b.dd_binned` AS b
JOIN `sahyadri_b2b.dd_psi` AS p ON p.field = b.field AND p.month_start = b.month_start
WHERE b.field = '03. Order status' AND b.month_start >= DATE '2026-05-01'
GROUP BY b.month_start
ORDER BY b.month_start;

-- Bin detail for every alert outside the two explained fields
SELECT p.field, p.month_start, b.bin,
       COUNTIF(NOT b.is_reference AND b.month_start = p.month_start)                        AS month_n,
       ROUND(100 * COUNTIF(NOT b.is_reference AND b.month_start = p.month_start)
             / ANY_VALUE(p.month_records), 1)                                               AS month_pct,
       ROUND(100 * COUNTIF(b.is_reference) / ANY_VALUE(p.ref_records), 1)                    AS reference_pct
FROM `sahyadri_b2b.dd_psi` AS p
JOIN `sahyadri_b2b.dd_binned` AS b ON b.field = p.field
WHERE p.z >= z_alert
  AND p.field NOT IN ('03. Order status', '11. Price ratio (unit price / list)', '15. Shipment status')
GROUP BY p.field, p.month_start, b.bin
ORDER BY p.field, p.month_start, b.bin;

-- What PSI does sampling noise alone produce? (10 bins, against the 2024 reference)
WITH ref AS (
    SELECT COUNT(DISTINCT order_id) AS n_ref FROM `sahyadri_b2b.dd_observations`
    WHERE field = '01. Order value' AND is_reference
),
periods AS (
              SELECT 'Week' AS period, 7 AS days
    UNION ALL SELECT 'Month', 30
    UNION ALL SELECT 'Quarter', 91
)
SELECT
    p.period,
    ROUND(r.n_ref * p.days / 366)                                                      AS orders_per_period,
    ROUND(9 * (1 / (r.n_ref * p.days / 366) + 1 / r.n_ref), 3)                         AS expected_psi_no_change,
    -- PSI that reaches z = 3.30 (Wilson-Hilferty, 9 degrees of freedom)
    ROUND(9 * POW(1 - 2 / 81 + z_alert * SQRT(2 / 81), 3) * (1 / (r.n_ref * p.days / 366) + 1 / r.n_ref), 3) AS psi_alert_threshold
FROM periods AS p CROSS JOIN ref AS r
ORDER BY p.days;

-- Expected PSI from sampling noise alone at typical monthly volumes
SELECT
    field, ANY_VALUE(bins) AS bins, ROUND(AVG(month_orders)) AS avg_orders_per_month,
    ROUND(AVG((bins - 1) * (month_orders + ref_orders) / (month_orders * ref_orders)), 3) AS expected_psi_no_change
FROM `sahyadri_b2b.dd_psi`
GROUP BY field
ORDER BY field;
