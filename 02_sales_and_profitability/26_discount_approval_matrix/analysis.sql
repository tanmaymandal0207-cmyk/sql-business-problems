/* =============================================================================
   Case study · A discount approval matrix: who should approve which
   discounts, and how many approvals each design creates
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Salespeople set discounts with no approval. The CFO proposes a
   delegation-of-authority matrix by job title: a Sales Executive may give
   up to 5 %, a Senior Sales Executive 7.5 %, a Key Account Manager or
   Regional Sales Manager 10 %, the Head of Sales 12.5 %; anything above
   needs the Managing Director. The Head of Sales says the matrix would
   bury the MD in approvals for routine distributor orders. Before it goes
   live, they ask:
     1. How many orders would the proposed matrix escalate, and to whom?
     2. What actually drives the size of a discount today?
     3. Is there already a rule in the data that limits by customer segment
        would capture, and does it hold on orders it was not built on?
     4. Which salespeople would the proposed matrix flag, and why?

   METHOD AND ASSUMPTIONS
     - Orders: every order entered 1 January 2024 - 30 September 2026, any
       status (an approval would apply when the order is entered).
     - An order needs approval at the level of its highest line discount.
     - 352 orders have no salesperson recorded; the title matrix cannot be
       applied to them and they are reported separately.
       A missing discount is treated as 0 %.
     - Gross value = quantity x unit price; discount given = gross value x
       discount %.
     - Discount above authority (rupees) = gross value of each line x
       MAX(0, its discount - the limit).
     - Alternative design: one cap per customer segment, set at the highest
       order discount the segment received in 2024 - 2025, with approval
       only above it. Tested on January - September 2026.
   ============================================================================= */

DECLARE first_order       DATE    DEFAULT DATE '2024-01-01';
DECLARE last_order        DATE    DEFAULT DATE '2026-09-30';
DECLARE calibration_end   DATE    DEFAULT DATE '2025-12-31';

-- -----------------------------------------------------------------------------
-- Step 1 · Orders, the proposed limits and the segment caps
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.da_title_limits` AS
SELECT 'Sales Executive' AS designation,          5.0 AS limit_pct, 1 AS approval_level UNION ALL
SELECT 'Senior Sales Executive',                  7.5,              2              UNION ALL
SELECT 'Key Account Manager',                    10.0,              3              UNION ALL
SELECT 'Regional Sales Manager',                 10.0,              3              UNION ALL
SELECT 'Head of Sales',                          12.5,              4;

CREATE OR REPLACE TABLE `sahyadri_b2b.da_lines` AS
SELECT o.order_id, o.order_date, o.order_status, o.customer_id, o.employee_id,
       i.order_item_id, i.quantity * i.unit_price                                     AS gross_value,
       IFNULL(i.discount_percent, 0)                                                  AS discount_pct
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
WHERE o.order_date BETWEEN first_order AND last_order;

CREATE OR REPLACE TABLE `sahyadri_b2b.da_orders` AS
WITH by_order AS (
    SELECT order_id, order_date, order_status, customer_id, employee_id,
           COUNT(*)                                                                   AS lines,
           SUM(gross_value)                                                           AS gross_value,
           SUM(gross_value * discount_pct / 100)                                      AS discount_given,
           MAX(discount_pct)                                                          AS max_discount_pct
    FROM `sahyadri_b2b.da_lines`
    GROUP BY order_id, order_date, order_status, customer_id, employee_id
)
SELECT b.*, IFNULL(e.employee_name, 'Not recorded') AS employee_name, IFNULL(e.designation, 'Not recorded') AS designation,
       c.customer_name, c.customer_segment,
       CASE WHEN b.gross_value < 25000 THEN '1. Under Rs 25,000'
            WHEN b.gross_value < 100000 THEN '2. Rs 25,000 - 1 lakh'
            WHEN b.gross_value < 500000 THEN '3. Rs 1 - 5 lakh'
            ELSE '4. Rs 5 lakh and above' END                                          AS size_band,
       b.order_date <= calibration_end                                                AS calibration_period,
       t.limit_pct                                                                    AS title_limit_pct,
       -- level that must approve under the proposed matrix: the lowest title whose limit covers the discount
       CASE WHEN t.limit_pct IS NULL THEN 'No salesperson recorded'
            WHEN b.max_discount_pct <= t.limit_pct THEN 'Own authority'
            WHEN b.max_discount_pct <= 7.5 THEN 'Senior Sales Executive'
            WHEN b.max_discount_pct <= 10 THEN 'Manager (KAM or RSM)'
            WHEN b.max_discount_pct <= 12.5 THEN 'Head of Sales'
            ELSE 'Managing Director' END                                               AS title_approver
FROM by_order AS b
LEFT JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = b.employee_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = b.customer_id
LEFT JOIN `sahyadri_b2b.da_title_limits` AS t ON t.designation = e.designation;

CREATE OR REPLACE TABLE `sahyadri_b2b.da_segment_caps` AS
SELECT customer_segment,
       MAX(max_discount_pct)                                                          AS segment_cap_pct,
       COUNT(*)                                                                       AS calibration_orders
FROM `sahyadri_b2b.da_orders`
WHERE calibration_period
GROUP BY customer_segment;

-- -----------------------------------------------------------------------------
-- Step 2 · What the proposed matrix would escalate
-- -----------------------------------------------------------------------------
SELECT
    title_approver,
    COUNT(*)                                                                          AS orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                                  AS share_pct,
    ROUND(COUNT(*) / (DATE_DIFF(last_order, first_order, DAY) / 7), 1)                AS per_week
FROM `sahyadri_b2b.da_orders`
GROUP BY title_approver
ORDER BY CASE title_approver WHEN 'Own authority' THEN 0 WHEN 'Senior Sales Executive' THEN 1
              WHEN 'Manager (KAM or RSM)' THEN 2 WHEN 'Head of Sales' THEN 3 WHEN 'Managing Director' THEN 4 ELSE 5 END;

SELECT
    designation,
    COUNT(DISTINCT employee_id)                                                       AS people,
    MAX(title_limit_pct)                                                              AS limit_pct,
    COUNT(*)                                                                          AS orders,
    ROUND(AVG(max_discount_pct), 2)                                                   AS average_max_discount_pct,
    COUNTIF(max_discount_pct > title_limit_pct)                                       AS orders_above_own_limit,
    ROUND(100 * COUNTIF(max_discount_pct > title_limit_pct) / COUNT(*), 1)            AS above_own_limit_pct
FROM `sahyadri_b2b.da_orders`
GROUP BY designation
ORDER BY limit_pct IS NULL, limit_pct, designation;

-- Rupees of discount above each person's limit
SELECT
    o.designation,
    ROUND(SUM(l.gross_value * l.discount_pct / 100) / 1e5, 1)                         AS discount_given_lakh,
    ROUND(SUM(l.gross_value * GREATEST(0, l.discount_pct - o.title_limit_pct) / 100) / 1e5, 1) AS discount_above_limit_lakh
FROM `sahyadri_b2b.da_lines` AS l
JOIN `sahyadri_b2b.da_orders` AS o ON o.order_id = l.order_id
GROUP BY o.designation
ORDER BY discount_above_limit_lakh DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · What drives the discount
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    size_band,
    COUNT(*)                                                                          AS orders,
    ROUND(AVG(max_discount_pct), 2)                                                   AS average_max_discount_pct,
    ROUND(100 * COUNTIF(max_discount_pct > 12.5) / COUNT(*), 1)                       AS above_12_5_pct
FROM `sahyadri_b2b.da_orders`
GROUP BY customer_segment, size_band
ORDER BY customer_segment, size_band;

-- How much of the variation in order discounts each factor explains (share of variance between group means)
WITH overall AS (SELECT AVG(max_discount_pct) AS m, VARIANCE(max_discount_pct) * (COUNT(*) - 1) AS total_ss FROM `sahyadri_b2b.da_orders`),
by_factor AS (
    SELECT 'Customer segment' AS factor, customer_segment AS grp, COUNT(*) AS n, AVG(max_discount_pct) AS m FROM `sahyadri_b2b.da_orders` GROUP BY customer_segment
    UNION ALL
    SELECT 'Order size band', size_band, COUNT(*), AVG(max_discount_pct) FROM `sahyadri_b2b.da_orders` GROUP BY size_band
    UNION ALL
    SELECT 'Segment x size band', CONCAT(customer_segment, ' ', size_band), COUNT(*), AVG(max_discount_pct) FROM `sahyadri_b2b.da_orders` GROUP BY customer_segment, size_band
    UNION ALL
    SELECT 'Job title', designation, COUNT(*), AVG(max_discount_pct) FROM `sahyadri_b2b.da_orders` GROUP BY designation
)
SELECT
    f.factor,
    COUNT(*)                                                                          AS groups,
    ROUND(100 * SUM(f.n * POW(f.m - o.m, 2)) / MAX(o.total_ss), 1)                    AS variance_explained_pct
FROM by_factor AS f CROSS JOIN overall AS o
GROUP BY f.factor
ORDER BY variance_explained_pct DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · The unwritten rule: a discount cap per segment
-- -----------------------------------------------------------------------------
SELECT
    c.customer_segment,
    c.segment_cap_pct,
    COUNT(*)                                                                          AS orders,
    ROUND(100 * COUNTIF(o.max_discount_pct = c.segment_cap_pct) / COUNT(*), 1)        AS orders_at_the_cap_pct,
    COUNTIF(o.max_discount_pct > c.segment_cap_pct)                                   AS orders_above_the_cap,
    COUNTIF(NOT o.calibration_period AND o.max_discount_pct > c.segment_cap_pct)      AS above_the_cap_in_2026,
    COUNTIF(o.max_discount_pct > o.title_limit_pct)                                   AS escalated_by_title_matrix,
    COUNTIF(o.max_discount_pct > 12.5 AND o.title_limit_pct IS NOT NULL)              AS to_md_by_title_matrix
FROM `sahyadri_b2b.da_orders` AS o
JOIN `sahyadri_b2b.da_segment_caps` AS c USING (customer_segment)
GROUP BY c.customer_segment, c.segment_cap_pct
ORDER BY c.segment_cap_pct;

-- The cap holds in every salesperson's orders and in every size band
SELECT
    o.size_band,
    COUNT(*)                                                                          AS orders,
    COUNTIF(o.max_discount_pct > c.segment_cap_pct)                                   AS above_segment_cap,
    COUNT(DISTINCT IF(o.max_discount_pct = c.segment_cap_pct, o.employee_name, NULL))  AS salespeople_giving_the_cap
FROM `sahyadri_b2b.da_orders` AS o
JOIN `sahyadri_b2b.da_segment_caps` AS c USING (customer_segment)
GROUP BY o.size_band
ORDER BY o.size_band;

SELECT
    IF(o.calibration_period, '1. January 2024 - December 2025 (calibration)', '2. January - September 2026 (test)') AS period,
    COUNT(*)                                                                          AS orders,
    COUNTIF(o.max_discount_pct > o.title_limit_pct)                                   AS escalated_title_matrix,
    COUNTIF(o.max_discount_pct > 12.5 AND o.title_limit_pct IS NOT NULL)              AS to_md_title_matrix,
    ROUND(COUNTIF(o.max_discount_pct > o.title_limit_pct)
          / (DATE_DIFF(MAX(o.order_date), MIN(o.order_date), DAY) / 7), 1)            AS title_escalations_per_week,
    COUNTIF(o.max_discount_pct > c.segment_cap_pct)                                   AS escalated_segment_caps
FROM `sahyadri_b2b.da_orders` AS o
JOIN `sahyadri_b2b.da_segment_caps` AS c USING (customer_segment)
GROUP BY period
ORDER BY period;

-- -----------------------------------------------------------------------------
-- Step 5 · Which salespeople the title matrix would flag, and why
-- -----------------------------------------------------------------------------
SELECT
    o.employee_name, o.designation,
    COUNT(*)                                                                          AS orders,
    ROUND(100 * COUNTIF(o.customer_segment IN ('Distributor', 'Enterprise')) / COUNT(*), 1) AS distributor_or_enterprise_pct,
    ROUND(AVG(o.max_discount_pct), 2)                                                 AS average_max_discount_pct,
    ROUND(100 * COUNTIF(o.max_discount_pct > o.title_limit_pct) / COUNT(*), 1)        AS above_title_limit_pct,
    COUNTIF(o.max_discount_pct > c.segment_cap_pct)                                   AS above_segment_cap
FROM `sahyadri_b2b.da_orders` AS o
JOIN `sahyadri_b2b.da_segment_caps` AS c USING (customer_segment)
WHERE o.employee_id IS NOT NULL
GROUP BY o.employee_name, o.designation
ORDER BY above_title_limit_pct DESC;

-- Within one segment, does the salesperson's title change the discount?
SELECT
    customer_segment,
    designation,
    COUNT(*)                                                                          AS orders,
    ROUND(AVG(max_discount_pct), 2)                                                   AS average_max_discount_pct
FROM `sahyadri_b2b.da_orders`
WHERE employee_id IS NOT NULL
GROUP BY customer_segment, designation
ORDER BY customer_segment, average_max_discount_pct DESC;
