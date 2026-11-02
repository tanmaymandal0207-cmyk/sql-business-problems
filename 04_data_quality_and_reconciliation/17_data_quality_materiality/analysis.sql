/* =============================================================================
   Case study · Data quality materiality: which issues move the board KPIs?
   Category : Data quality and reconciliation
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Earlier studies found many data quality issues: missing discounts and
   unit costs, duplicate customers, city spellings, missing salespeople,
   duplicate receipts, stale payment flags, missing delivery dates and
   freight. The data team cannot fix everything before the next board
   pack. The CFO asks:
     1. For each headline KPI of the last 12 months, what does a
        straightforward query report, and what is the corrected figure?
     2. Which issues are material, and which can wait?
     3. Which corrections should be built into the reporting layer first?

   METHOD
     - Window: 1 Oct 2025 - 30 Sep 2026 (orders by order date, payments by
       payment date, shipments by dispatch date). Valid orders exclude
       Cancelled and Returned in both versions.
     - "As reported": the KPI as a plain query computes it, letting NULLs
       and duplicates fall where SQL puts them.
     - "Corrected": the same KPI with one data rule applied:
         Revenue            NULL discount treated as 0 %
         Gross margin       lines without a unit cost excluded from both
                            revenue and cost
         Active customers   duplicate customer records merged (same
                            normalised name, city and state: the
                            high-confidence pairs of the deduplication
                            study)
         On-time delivery   orders without a promise date or with an
                            undated delivered shipment excluded
         Cash collected     duplicate receipts (same order, date, amount)
                            counted once
         Paid in full       derived from payments (>= 99 % of value), not
                            from the payment-status flag
         League table       orders without a salesperson shown as
                            "Unassigned" so the table adds up
         Freight %          missing shipping cost filled with the city's
                            average cost per shipment
         Cities / Bengaluru city names standardised (case, spacing, aliases)
     - Material: a change of 1 % or more of an amount or count, or 0.5
       percentage points or more of a rate.
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE pct_limit    FLOAT64 DEFAULT 1.0;
DECLARE pts_limit    FLOAT64 DEFAULT 0.5;

-- -----------------------------------------------------------------------------
-- Step 1 · Lines, orders and helpers for the window
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dq_lines` AS
SELECT
    o.order_id, o.customer_id, o.employee_id, o.order_date, o.order_status, o.payment_status, o.promised_delivery_date,
    i.product_id, i.quantity, i.unit_price, i.discount_percent, p.unit_cost,
    i.quantity * i.unit_price * (1 - i.discount_percent / 100)                        AS revenue_as_reported,
    i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)             AS revenue_corrected
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN window_start AND window_end;

CREATE OR REPLACE TABLE `sahyadri_b2b.dq_city_map` AS
WITH alias AS (
    SELECT 'ahmadabad' AS raw_key, 'ahmedabad' AS city_key UNION ALL SELECT 'bangalore', 'bengaluru' UNION ALL
    SELECT 'baroda', 'vadodara' UNION ALL SELECT 'bombay', 'mumbai' UNION ALL SELECT 'calcutta', 'kolkata' UNION ALL
    SELECT 'delhi', 'new delhi' UNION ALL SELECT 'gurgaon', 'gurugram' UNION ALL SELECT 'madras', 'chennai' UNION ALL
    SELECT 'mysore', 'mysuru' UNION ALL SELECT 'vizag', 'visakhapatnam'
)
SELECT DISTINCT c.city AS raw_city, IFNULL(a.city_key, LOWER(TRIM(c.city))) AS city_key
FROM `sahyadri_b2b.customers` AS c
LEFT JOIN alias AS a ON a.raw_key = LOWER(TRIM(c.city))
WHERE c.city IS NOT NULL;

-- Duplicate customers: same normalised name (lower case, no punctuation, no legal-form words) and the
-- same city and state: the high-confidence pairs of the deduplication study
CREATE OR REPLACE TABLE `sahyadri_b2b.dq_customer_master` AS
WITH normalised AS (
    SELECT customer_id, registration_date, LOWER(TRIM(city)) AS city_key, state,
           TRIM(REGEXP_REPLACE(
               REGEXP_REPLACE(REGEXP_REPLACE(LOWER(customer_name), r'[^a-z0-9 ]', ' '),
                              r'\b(pvt|private|ltd|limited|llp|co|company)\b', ' '),
               r'\s+', ' '))                                                         AS name_key
    FROM `sahyadri_b2b.customers`
),
order_counts AS (
    SELECT customer_id, COUNT(*) AS orders FROM `sahyadri_b2b.sales_orders` GROUP BY customer_id
)
SELECT n.customer_id, n.name_key,
       FIRST_VALUE(n.customer_id) OVER (PARTITION BY n.name_key, n.city_key, n.state
           ORDER BY IFNULL(oc.orders, 0) DESC, n.registration_date, n.customer_id)   AS master_id
FROM normalised AS n
LEFT JOIN order_counts AS oc ON oc.customer_id = n.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Every KPI as reported and corrected
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dq_kpis` AS
WITH revenue AS (
    SELECT SUM(revenue_as_reported) AS reported, SUM(revenue_corrected) AS corrected FROM `sahyadri_b2b.dq_lines`
),
margin AS (
    SELECT 100 * SUM(revenue_corrected - quantity * unit_cost) / SUM(revenue_corrected)                     AS reported,
           100 * SUM(IF(unit_cost IS NOT NULL, revenue_corrected - quantity * unit_cost, 0))
               / SUM(IF(unit_cost IS NOT NULL, revenue_corrected, 0))                                      AS corrected
    FROM `sahyadri_b2b.dq_lines`
),
customers AS (
    SELECT COUNT(DISTINCT l.customer_id) AS reported, COUNT(DISTINCT m.master_id) AS corrected
    FROM `sahyadri_b2b.dq_lines` AS l JOIN `sahyadri_b2b.dq_customer_master` AS m ON m.customer_id = l.customer_id
),
delivery AS (
    SELECT o.order_id, o.promised_delivery_date,
           MAX(s.delivery_date) AS last_dated_delivery,
           COUNTIF(s.delivery_date IS NULL) AS undated
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND o.order_date BETWEEN window_start AND window_end
    GROUP BY o.order_id, o.promised_delivery_date
),
on_time AS (
    SELECT 100 * COUNTIF(last_dated_delivery <= promised_delivery_date) / COUNT(*)                         AS reported,
           100 * COUNTIF(last_dated_delivery <= promised_delivery_date AND promised_delivery_date IS NOT NULL AND undated = 0)
               / COUNTIF(promised_delivery_date IS NOT NULL AND undated = 0)                               AS corrected
    FROM delivery
),
cash AS (
    SELECT SUM(amount) AS reported,
           SUM(IF(rn = 1, amount, 0)) AS corrected
    FROM (
        SELECT amount, ROW_NUMBER() OVER (PARTITION BY order_id, payment_date, amount ORDER BY payment_id) AS rn
        FROM `sahyadri_b2b.payments`
        WHERE payment_date BETWEEN window_start AND window_end
    )
),
paid AS (
    SELECT 100 * COUNTIF(o.payment_status = 'Paid') / COUNT(*)                                             AS reported,
           100 * COUNTIF(IFNULL(p.paid, 0) >= 0.99 * v.value) / COUNT(*)                                    AS corrected
    FROM (SELECT DISTINCT order_id, payment_status FROM `sahyadri_b2b.dq_lines` WHERE order_status = 'Delivered') AS o
    JOIN (SELECT order_id, SUM(revenue_corrected) AS value FROM `sahyadri_b2b.dq_lines` GROUP BY order_id) AS v ON v.order_id = o.order_id
    LEFT JOIN (SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date <= window_end GROUP BY order_id) AS p
      ON p.order_id = o.order_id
),
league AS (
    SELECT SUM(IF(employee_id IS NOT NULL, revenue_corrected, 0)) AS reported, SUM(revenue_corrected) AS corrected
    FROM `sahyadri_b2b.dq_lines`
),
shipments AS (
    SELECT s.shipping_cost, IFNULL(cm.city_key, LOWER(TRIM(s.shipping_city))) AS city_key
    FROM `sahyadri_b2b.shipments` AS s
    LEFT JOIN `sahyadri_b2b.dq_city_map` AS cm ON cm.raw_city = s.shipping_city
    WHERE s.shipment_date BETWEEN window_start AND window_end
),
freight AS (
    SELECT 100 * SUM(shipping_cost) / (SELECT corrected FROM revenue)                                      AS reported,
           100 * SUM(IFNULL(shipping_cost, city_avg)) / (SELECT corrected FROM revenue)                    AS corrected
    FROM (SELECT *, AVG(shipping_cost) OVER (PARTITION BY city_key) AS city_avg FROM shipments)
),
cities AS (
    SELECT COUNT(DISTINCT c.city) AS reported, COUNT(DISTINCT cm.city_key) AS corrected
    FROM `sahyadri_b2b.dq_lines` AS l
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = l.customer_id
    JOIN `sahyadri_b2b.dq_city_map` AS cm ON cm.raw_city = c.city
),
bengaluru AS (
    SELECT SUM(IF(c.city = 'Bengaluru', l.revenue_corrected, 0)) AS reported,
           SUM(IF(cm.city_key = 'bengaluru', l.revenue_corrected, 0)) AS corrected
    FROM `sahyadri_b2b.dq_lines` AS l
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = l.customer_id
    JOIN `sahyadri_b2b.dq_city_map` AS cm ON cm.raw_city = c.city
)
SELECT 1 AS kpi_no, 'Revenue (Rs crore)' AS kpi, 'NULL discount drops the line' AS issue, 'amount' AS kind, reported / 1e7 AS reported, corrected / 1e7 AS corrected FROM revenue
UNION ALL SELECT 2, 'Gross margin %', 'Lines without unit cost count as revenue with no cost', 'rate', reported, corrected FROM margin
UNION ALL SELECT 3, 'Active customers', 'Duplicate customer records', 'amount', reported, corrected FROM customers
UNION ALL SELECT 4, 'On-time delivery %', 'Missing promise date or undated delivery', 'rate', reported, corrected FROM on_time
UNION ALL SELECT 5, 'Cash collected (Rs crore)', 'Duplicate receipts', 'amount', reported / 1e7, corrected / 1e7 FROM cash
UNION ALL SELECT 6, 'Delivered orders paid in full %', 'Stale payment-status flag', 'rate', reported, corrected FROM paid
UNION ALL SELECT 7, 'Salesperson league table total (Rs crore)', 'Orders without a salesperson', 'amount', reported / 1e7, corrected / 1e7 FROM league
UNION ALL SELECT 8, 'Freight % of revenue', 'Missing shipping cost', 'rate', reported, corrected FROM freight
UNION ALL SELECT 9, 'Customer cities', 'City spellings and aliases', 'amount', reported, corrected FROM cities
UNION ALL SELECT 10, 'Bengaluru revenue (Rs crore)', 'City spellings and aliases', 'amount', reported / 1e7, corrected / 1e7 FROM bengaluru;

SELECT
    kpi_no, kpi, issue,
    ROUND(reported, 2)                                                                AS as_reported,
    ROUND(corrected, 2)                                                               AS corrected,
    ROUND(corrected - reported, 2)                                                    AS difference,
    IF(kind = 'amount', ROUND(100 * (corrected - reported) / reported, 2), NULL)      AS difference_pct,
    CASE WHEN kind = 'amount' AND ABS(100 * (corrected - reported) / reported) >= pct_limit THEN 'Material'
         WHEN kind = 'rate'   AND ABS(corrected - reported) >= pts_limit THEN 'Material'
         ELSE 'Not material' END                                                      AS verdict
FROM `sahyadri_b2b.dq_kpis`
ORDER BY kpi_no;

-- -----------------------------------------------------------------------------
-- Step 3 · How many records sit behind each issue
-- -----------------------------------------------------------------------------
SELECT 'NULL discount lines' AS issue, COUNTIF(discount_percent IS NULL) AS records, COUNT(*) AS out_of FROM `sahyadri_b2b.dq_lines`
UNION ALL SELECT 'Lines without unit cost', COUNTIF(unit_cost IS NULL), COUNT(*) FROM `sahyadri_b2b.dq_lines`
UNION ALL SELECT 'Customer IDs that are duplicates', COUNTIF(customer_id != master_id), COUNT(*) FROM `sahyadri_b2b.dq_customer_master`
UNION ALL SELECT 'Delivered orders without a promise date',
                 COUNTIF(promised_delivery_date IS NULL), COUNT(*)
          FROM `sahyadri_b2b.sales_orders` WHERE order_status = 'Delivered' AND order_date BETWEEN window_start AND window_end
UNION ALL SELECT 'Duplicate receipts', COUNTIF(rn > 1), COUNT(*)
          FROM (SELECT ROW_NUMBER() OVER (PARTITION BY order_id, payment_date, amount ORDER BY payment_id) AS rn
                  FROM `sahyadri_b2b.payments` WHERE payment_date BETWEEN window_start AND window_end)
UNION ALL SELECT 'Orders without a salesperson', COUNTIF(employee_id IS NULL), COUNT(*)
          FROM `sahyadri_b2b.sales_orders` WHERE order_date BETWEEN window_start AND window_end
UNION ALL SELECT 'Shipments without shipping cost', COUNTIF(shipping_cost IS NULL), COUNT(*)
          FROM `sahyadri_b2b.shipments` WHERE shipment_date BETWEEN window_start AND window_end
UNION ALL SELECT 'Extra customer city spellings (spellings - standard cities)', COUNT(DISTINCT raw_city) - COUNT(DISTINCT city_key), COUNT(DISTINCT raw_city)
          FROM `sahyadri_b2b.dq_city_map`;

-- -----------------------------------------------------------------------------
-- Step 4 · Where the paid-in-full flag disagrees with the payments
-- -----------------------------------------------------------------------------
WITH orders AS (
    SELECT o.order_id, o.payment_status, v.value, IFNULL(p.paid, 0) AS paid
    FROM (SELECT DISTINCT order_id, payment_status FROM `sahyadri_b2b.dq_lines` WHERE order_status = 'Delivered') AS o
    JOIN (SELECT order_id, SUM(revenue_corrected) AS value FROM `sahyadri_b2b.dq_lines` GROUP BY order_id) AS v ON v.order_id = o.order_id
    LEFT JOIN (SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date <= window_end GROUP BY order_id) AS p
      ON p.order_id = o.order_id
)
SELECT
    payment_status,
    COUNT(*)                                                                          AS delivered_orders,
    COUNTIF(paid >= 0.99 * value)                                                     AS paid_in_full_per_payments,
    COUNTIF(paid > 0 AND paid < 0.99 * value)                                         AS part_paid_per_payments,
    COUNTIF(paid = 0)                                                                 AS nothing_received
FROM orders
GROUP BY payment_status
ORDER BY payment_status;

-- -----------------------------------------------------------------------------
-- Step 5 · On-time delivery: which of the two gaps moves it?
-- -----------------------------------------------------------------------------
WITH delivery AS (
    SELECT o.order_id, o.promised_delivery_date, MAX(s.delivery_date) AS last_dated_delivery, COUNTIF(s.delivery_date IS NULL) AS undated
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND o.order_date BETWEEN window_start AND window_end
    GROUP BY o.order_id, o.promised_delivery_date
)
SELECT
    COUNT(*)                                                                          AS delivered_orders,
    COUNTIF(promised_delivery_date IS NULL)                                           AS no_promise_date,
    COUNTIF(undated > 0)                                                              AS with_undated_shipment,
    ROUND(100 * COUNTIF(last_dated_delivery <= promised_delivery_date) / COUNT(*), 2) AS as_reported_pct,
    ROUND(100 * COUNTIF(last_dated_delivery <= promised_delivery_date) / COUNTIF(promised_delivery_date IS NOT NULL), 2) AS promise_fix_only_pct,
    ROUND(100 * COUNTIF(last_dated_delivery <= promised_delivery_date AND undated = 0) / COUNTIF(undated = 0), 2) AS undated_fix_only_pct
FROM delivery;
