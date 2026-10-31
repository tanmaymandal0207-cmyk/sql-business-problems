/* =============================================================================
   Case study · Missing data: random gaps, structural blanks or a broken process?
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The data quality scorecard counted 1,405 missing values across 11
   completeness rules. Before the dashboards go live the BI lead must decide,
   field by field, whether to exclude, impute or chase the source. The right
   choice depends on why values are missing:
     - structural: a blank that is correct (no delivery date while a
       shipment is still in transit);
     - random: a gap equally likely anywhere, so excluding it biases
       nothing and a simple imputation is safe;
     - systematic: concentrated in a period, a customer, a salesperson or a
       status, which points to a broken process and biases any total.
   She asks:
     1. For each field, is the missing pattern structural, random or
        systematic?
     2. What does each gap do to the reported KPIs?
     3. What should the dashboard do with each field?

   METHOD
     - Fields: order promise date, order salesperson, line discount,
       payment method, shipment delivery date, shipment freight cost.
     - For each field and each dimension (year, month, weekday, segment,
       status, customer, city, category, salesperson ...), a chi-square test
       of the missing rate across groups against one common rate:
       SUM (missing - n p)^2 / (n p (1 - p)); groups with fewer than 30
       records are pooled into 'Other'. With about 30 tests, a statistic is
       called systematic only above the 1 % critical value (Wilson-Hilferty
       approximation). Dispersion ratio = chi-square / degrees of freedom.
     - Structural check for delivery date: missing should coincide exactly
       with shipments not yet delivered.
     - KPI impact: what each gap adds to, or removes from, the totals.
   ============================================================================= */

DECLARE min_group INT64   DEFAULT 30;
DECLARE z_crit    FLOAT64 DEFAULT 2.3263;   -- one-sided 1 % normal quantile

-- -----------------------------------------------------------------------------
-- Step 1 · One row per record, field and dimension
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.md_observations` AS
WITH orders AS (
    SELECT o.order_id, o.customer_id, o.order_date, o.order_status, c.customer_segment,
           o.promised_delivery_date IS NULL AS promise_missing,
           o.employee_id IS NULL            AS salesperson_missing,
           o.employee_id
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
),
lines AS (
    SELECT i.order_item_id, o.order_date, o.order_status, o.employee_id, c.customer_segment, pc.category_name,
           i.discount_percent IS NULL AS discount_missing
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
),
pays AS (
    SELECT p.payment_id, p.payment_date, p.amount, c.customer_segment, o.customer_id,
           COUNT(*) OVER (PARTITION BY p.order_id) > 1 AS instalment,
           p.payment_method IS NULL AS method_missing
    FROM `sahyadri_b2b.payments` AS p
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
),
ships AS (
    SELECT s.shipment_id, s.shipment_date, s.shipment_status, INITCAP(TRIM(s.shipping_city)) AS city,
           s.shipping_cost IS NULL AS cost_missing, s.delivery_date IS NULL AS delivery_missing
    FROM `sahyadri_b2b.shipments` AS s
),
order_fields AS (
    SELECT 'Order promise date' AS field, order_id AS record_id, order_date, order_status, customer_segment, customer_id, employee_id,
           promise_missing AS is_missing FROM orders
    UNION ALL
    SELECT 'Order salesperson', order_id, order_date, order_status, customer_segment, customer_id, employee_id,
           salesperson_missing FROM orders
)
-- orders: one row per field x dimension
SELECT field, record_id, 'Year' AS dimension, CAST(EXTRACT(YEAR FROM order_date) AS STRING) AS grp, is_missing FROM order_fields
UNION ALL SELECT field, record_id, 'Month', CAST(EXTRACT(MONTH FROM order_date) AS STRING), is_missing FROM order_fields
UNION ALL SELECT field, record_id, 'Weekday', CAST(EXTRACT(DAYOFWEEK FROM order_date) AS STRING), is_missing FROM order_fields
UNION ALL SELECT field, record_id, 'Segment', customer_segment, is_missing FROM order_fields
UNION ALL SELECT field, record_id, 'Order status', order_status, is_missing FROM order_fields
UNION ALL SELECT field, record_id, 'Customer', CAST(customer_id AS STRING), is_missing FROM order_fields
UNION ALL SELECT field, record_id, 'Salesperson', IFNULL(CAST(employee_id AS STRING), 'None'), is_missing
          FROM order_fields WHERE field = 'Order promise date'
-- order lines: discount
UNION ALL SELECT 'Line discount', order_item_id, 'Year', CAST(EXTRACT(YEAR FROM order_date) AS STRING), discount_missing FROM lines
UNION ALL SELECT 'Line discount', order_item_id, 'Month', CAST(EXTRACT(MONTH FROM order_date) AS STRING), discount_missing FROM lines
UNION ALL SELECT 'Line discount', order_item_id, 'Segment', customer_segment, discount_missing FROM lines
UNION ALL SELECT 'Line discount', order_item_id, 'Order status', order_status, discount_missing FROM lines
UNION ALL SELECT 'Line discount', order_item_id, 'Category', category_name, discount_missing FROM lines
UNION ALL SELECT 'Line discount', order_item_id, 'Salesperson', IFNULL(CAST(employee_id AS STRING), 'None'), discount_missing FROM lines
-- payments: method
UNION ALL SELECT 'Payment method', payment_id, 'Year', CAST(EXTRACT(YEAR FROM payment_date) AS STRING), method_missing FROM pays
UNION ALL SELECT 'Payment method', payment_id, 'Weekday', CAST(EXTRACT(DAYOFWEEK FROM payment_date) AS STRING), method_missing FROM pays
UNION ALL SELECT 'Payment method', payment_id, 'Segment', customer_segment, method_missing FROM pays
UNION ALL SELECT 'Payment method', payment_id, 'Payment type', IF(instalment, 'Instalment', 'Single payment'), method_missing FROM pays
UNION ALL SELECT 'Payment method', payment_id, 'Amount band',
                 CASE WHEN amount < 20000 THEN '1. Under 20k' WHEN amount < 100000 THEN '2. 20k-1L' ELSE '3. 1L+' END, method_missing FROM pays
UNION ALL SELECT 'Payment method', payment_id, 'Customer', CAST(customer_id AS STRING), method_missing FROM pays
-- shipments: freight cost and delivery date
UNION ALL SELECT 'Shipment freight cost', shipment_id, 'Year', CAST(EXTRACT(YEAR FROM shipment_date) AS STRING), cost_missing FROM ships
UNION ALL SELECT 'Shipment freight cost', shipment_id, 'Month', CAST(EXTRACT(MONTH FROM shipment_date) AS STRING), cost_missing FROM ships
UNION ALL SELECT 'Shipment freight cost', shipment_id, 'Shipment status', shipment_status, cost_missing FROM ships
UNION ALL SELECT 'Shipment freight cost', shipment_id, 'City', city, cost_missing FROM ships
UNION ALL SELECT 'Shipment delivery date', shipment_id, 'Shipment status', shipment_status, delivery_missing FROM ships;

-- -----------------------------------------------------------------------------
-- Step 2 · How much is missing
-- -----------------------------------------------------------------------------
SELECT
    field,
    COUNT(DISTINCT record_id)                                                  AS records,
    COUNT(DISTINCT IF(is_missing, record_id, NULL))                            AS missing,
    ROUND(100 * COUNT(DISTINCT IF(is_missing, record_id, NULL)) / COUNT(DISTINCT record_id), 2) AS missing_pct
FROM `sahyadri_b2b.md_observations`
GROUP BY field
ORDER BY field;

-- Structural check: delivery date is blank exactly when the shipment is not delivered?
SELECT
    grp                                                                        AS shipment_status,
    COUNT(*)                                                                   AS shipments,
    COUNTIF(is_missing)                                                        AS delivery_date_missing
FROM `sahyadri_b2b.md_observations`
WHERE field = 'Shipment delivery date'
GROUP BY grp
ORDER BY grp;

-- -----------------------------------------------------------------------------
-- Step 3 · Is the missing rate the same across every group? (chi-square)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.md_tests` AS
WITH sized AS (
    SELECT field, dimension, grp, COUNT(*) AS n, COUNTIF(is_missing) AS x
    FROM `sahyadri_b2b.md_observations`
    GROUP BY field, dimension, grp
),
pooled AS (
    -- groups smaller than 30 records are pooled into 'Other'
    SELECT field, dimension, IF(n < min_group, 'Other', grp) AS grp, SUM(n) AS n, SUM(x) AS x
    FROM sized
    GROUP BY field, dimension, IF(n < min_group, 'Other', grp)
),
rates AS (
    SELECT *, SUM(x) OVER (PARTITION BY field, dimension) / SUM(n) OVER (PARTITION BY field, dimension) AS p
    FROM pooled
),
stats AS (
    SELECT field, dimension,
           COUNT(*)                                                    AS groups,
           SUM(n)                                                      AS records,
           SUM(x)                                                      AS missing,
           SUM(POW(x - n * p, 2) / (n * p * (1 - p)))                  AS chi_square,
           MIN(x / n)                                                  AS min_rate,
           MAX(x / n)                                                  AS max_rate
    FROM rates
    WHERE p > 0 AND p < 1
    GROUP BY field, dimension
),
worst AS (
    SELECT field, dimension, grp, x / n AS rate, n,
           ROW_NUMBER() OVER (PARTITION BY field, dimension ORDER BY x / n DESC, n DESC) AS rk
    FROM rates
)
SELECT
    stats.field, stats.dimension, groups, records, missing, chi_square,
    groups - 1                                                                                   AS df,
    (groups - 1) * POW(1 - 2 / (9 * (groups - 1)) + z_crit * SQRT(2 / (9 * (groups - 1))), 3)  AS critical_1pct,
    chi_square / (groups - 1)                                                                    AS dispersion_ratio,
    min_rate, max_rate, w.grp AS highest_group, w.rate AS highest_rate, w.n AS highest_group_records
FROM stats
JOIN worst AS w ON w.field = stats.field AND w.dimension = stats.dimension AND w.rk = 1
WHERE groups >= 2;

SELECT
    field, dimension, groups,
    ROUND(chi_square, 1)                                                  AS chi_square,
    ROUND(critical_1pct, 1)                                               AS critical_1pct,
    ROUND(dispersion_ratio, 2)                                            AS dispersion_ratio,
    IF(chi_square > critical_1pct, 'Systematic', 'Random-like')           AS verdict,
    highest_group,
    ROUND(100 * highest_rate, 1)                                          AS highest_rate_pct,
    ROUND(100 * missing / records, 2)                                     AS overall_rate_pct
FROM `sahyadri_b2b.md_tests`
WHERE field != 'Shipment delivery date'
ORDER BY field, dispersion_ratio DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · What each gap does to the KPIs
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.md_impact` AS
WITH line_value AS (
    SELECT i.order_item_id, i.order_id, o.order_status, i.quantity * i.unit_price AS gross, i.discount_percent
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
avg_discount AS (
    SELECT SUM(gross * discount_percent) / SUM(gross) AS d FROM line_value WHERE discount_percent IS NOT NULL
)
SELECT 'Line discount' AS field,
       'Revenue overstated if a missing discount is read as 0 %' AS effect,
       ROUND(SUM(IF(l.discount_percent IS NULL, l.gross, 0)) * ANY_VALUE(a.d) / 100 / 1e5, 2) AS amount_lakh,
       ROUND(100 * SUM(IF(l.discount_percent IS NULL, l.gross, 0)) * ANY_VALUE(a.d) / 100
             / SUM(l.gross * (1 - IFNULL(l.discount_percent, 0) / 100)), 3)            AS share_of_kpi_pct
FROM line_value AS l CROSS JOIN avg_discount AS a
UNION ALL
SELECT 'Order salesperson', 'Valid-order revenue with no salesperson to credit',
       ROUND(SUM(IF(o.employee_id IS NULL, l.gross * (1 - IFNULL(l.discount_percent, 0) / 100), 0)) / 1e5, 2),
       ROUND(100 * SUM(IF(o.employee_id IS NULL, l.gross * (1 - IFNULL(l.discount_percent, 0) / 100), 0))
             / SUM(l.gross * (1 - IFNULL(l.discount_percent, 0) / 100)), 3)
FROM line_value AS l JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = l.order_id
UNION ALL
SELECT 'Shipment freight cost', 'Freight understated if a missing cost is read as 0 (at the average cost)',
       ROUND(COUNTIF(shipping_cost IS NULL) * AVG(shipping_cost) / 1e5, 2),
       ROUND(100 * COUNTIF(shipping_cost IS NULL) * AVG(shipping_cost) / SUM(shipping_cost), 3)
FROM `sahyadri_b2b.shipments`
UNION ALL
SELECT 'Order promise date', 'Delivered orders left out of the on-time rate',
       COUNTIF(promised_delivery_date IS NULL AND order_status = 'Delivered'),
       ROUND(100 * COUNTIF(promised_delivery_date IS NULL AND order_status = 'Delivered') / COUNTIF(order_status = 'Delivered'), 3)
FROM `sahyadri_b2b.sales_orders`
UNION ALL
SELECT 'Payment method', 'Receipts that cannot be routed to a bank-feed rule (₹ lakh)',
       ROUND(SUM(IF(payment_method IS NULL, amount, 0)) / 1e5, 2),
       ROUND(100 * SUM(IF(payment_method IS NULL, amount, 0)) / SUM(amount), 3)
FROM `sahyadri_b2b.payments`
UNION ALL
SELECT 'Shipment delivery date', 'Delivered shipments with no delivery date (no lead time)',
       COUNTIF(delivery_date IS NULL AND shipment_status = 'Delivered'),
       ROUND(100 * COUNTIF(delivery_date IS NULL AND shipment_status = 'Delivered') / COUNTIF(shipment_status = 'Delivered'), 3)
FROM `sahyadri_b2b.shipments`;

SELECT * FROM `sahyadri_b2b.md_impact`;
