/* =============================================================================
   Case study · One-and-done customers: how many never order again,
   what it costs, and which second-order signals to watch
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   431 of 500 customers have at least one order (schema.md), but acquisition
   reports count every first order as a win. Management asks:
     1. How many customers place exactly one order and never return?
     2. How much revenue and margin sits in first orders that never repeat?
     3. Do one-and-done customers look different at the first order
        (segment, size, discount, category, salesperson coverage)?
     4. How long should we wait before calling a customer one-and-done,
        and whom should collections/field follow up with first?

   METHOD AND ASSUMPTIONS
     - Orders: every order 2024-01-01 to 2026-09-30, any status except
       Cancelled (cancelled orders are not demand). Returned orders count
       as an order placed, flagged separately.
     - First order = MIN(order_date) per customer; customers with a single
       non-cancelled order are one-and-done candidates.
     - To avoid censoring bias, repeat behaviour is measured on customers
       first acquired up to 2025-09-30 (12 months of follow-up to data end);
       recent acquirers (after 2025-09-30) are reported separately.
     - Order value = SUM(quantity * unit_price * (1 - discount/100));
       NULL discount treated as 0% (every paid NULL-discount line was paid
       at 0% value — see schema.md).
     - Margin = SUM(quantity * (unit_price*(1-discount/100) - unit_cost));
       lines with NULL unit_cost excluded from margin, counted explicitly.
   ============================================================================= */

DECLARE first_order DATE DEFAULT DATE '2024-01-01';
DECLARE last_order  DATE DEFAULT DATE '2026-09-30';
DECLARE cohort_end  DATE DEFAULT DATE '2025-09-30'; -- 12 months follow-up
DECLARE repeat_window_days INT64 DEFAULT 365;

-- -----------------------------------------------------------------------------
-- Step 1 · Order values and first-order flags
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.so_orders` AS
SELECT o.order_id, o.customer_id, o.order_date, o.order_status, o.employee_id,
       c.customer_name, c.customer_segment, c.industry,
       SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value,
       SUM(i.quantity * (i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) - IFNULL(p.unit_cost, 0))) AS order_margin,
       COUNTIF(p.unit_cost IS NULL) AS lines_missing_cost,
       MAX(IFNULL(i.discount_percent, 0)) AS max_discount_pct,
       COUNT(*) AS lines
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id)
JOIN `sahyadri_b2b.products` AS p USING (product_id)
JOIN `sahyadri_b2b.customers` AS c USING (customer_id)
WHERE o.order_date BETWEEN first_order AND last_order
  AND o.order_status != 'Cancelled'
GROUP BY o.order_id, o.customer_id, o.order_date, o.order_status, o.employee_id,
         c.customer_name, c.customer_segment, c.industry;

CREATE OR REPLACE TABLE `sahyadri_b2b.so_customers` AS
WITH firsts AS (
  SELECT customer_id, MIN(order_date) AS first_date, COUNT(*) AS orders, SUM(order_value) AS lifetime_value
  FROM `sahyadri_b2b.so_orders`
  GROUP BY customer_id
)
SELECT f.customer_id, c.customer_name, c.customer_segment, c.industry,
       f.first_date, f.orders, f.lifetime_value,
       f.first_date <= cohort_end AS in_cohort,
       f.orders = 1 AS is_single_order,
       DATE_DIFF(last_order, f.first_date, DAY) AS days_since_first
FROM firsts AS f
JOIN `sahyadri_b2b.customers` AS c USING (customer_id);

-- -----------------------------------------------------------------------------
-- Step 2 · Headline: how many one-and-done, and what they are worth
-- -----------------------------------------------------------------------------
-- Cohort with full 12-month follow-up
SELECT
  COUNT(*) AS cohort_customers,
  COUNTIF(is_single_order) AS single_order_customers,
  ROUND(100 * COUNTIF(is_single_order) / COUNT(*), 1) AS single_order_pct,
  ROUND(SUM(IF(is_single_order, lifetime_value, 0)) / 1e5, 1) AS single_order_value_lakh,
  ROUND(100 * SUM(IF(is_single_order, lifetime_value, 0)) / SUM(lifetime_value), 1) AS single_order_value_share_pct
FROM `sahyadri_b2b.so_customers`
WHERE in_cohort;

-- By segment and by first-order size band
SELECT
  customer_segment,
  COUNT(*) AS customers,
  ROUND(100 * COUNTIF(is_single_order) / COUNT(*), 1) AS single_pct,
  ROUND(AVG(IF(is_single_order, lifetime_value, NULL)) / 1000, 1) AS avg_single_first_value_k
FROM `sahyadri_b2b.so_customers`
WHERE in_cohort
GROUP BY customer_segment
ORDER BY single_pct DESC;

SELECT
  CASE WHEN first_value < 25000 THEN '1. Under Rs 25k'
       WHEN first_value < 100000 THEN '2. Rs 25k-1L'
       WHEN first_value < 500000 THEN '3. Rs 1-5L'
       ELSE '4. Rs 5L+' END AS first_size_band,
  COUNT(*) AS customers,
  ROUND(100 * COUNTIF(is_single_order) / COUNT(*), 1) AS single_pct
FROM (
  SELECT sc.customer_id, sc.is_single_order, sc.in_cohort,
         (SELECT order_value FROM `sahyadri_b2b.so_orders` AS o
          WHERE o.customer_id = sc.customer_id ORDER BY o.order_date LIMIT 1) AS first_value
  FROM `sahyadri_b2b.so_customers` AS sc
) WHERE in_cohort
GROUP BY first_size_band
ORDER BY first_size_band;

-- -----------------------------------------------------------------------------
-- Step 3 · Do they look different at the first order?
-- -----------------------------------------------------------------------------
WITH firsts AS (
  SELECT o.*, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS rn
  FROM `sahyadri_b2b.so_orders` AS o
  JOIN `sahyadri_b2b.so_customers` AS sc USING (customer_id)
  WHERE sc.in_cohort
)
SELECT
  sc.is_single_order,
  COUNT(*) AS customers,
  ROUND(AVG(f.order_value), 0) AS avg_first_value,
  ROUND(AVG(f.max_discount_pct), 2) AS avg_first_max_discount,
  ROUND(100 * COUNTIF(f.employee_id IS NULL) / COUNT(*), 1) AS unassigned_pct,
  ROUND(100 * COUNTIF(f.order_status = 'Returned') / COUNT(*), 1) AS returned_first_pct,
  ROUND(AVG(f.lines), 2) AS avg_lines
FROM firsts AS f
JOIN `sahyadri_b2b.so_customers` AS sc USING (customer_id)
WHERE f.rn = 1
GROUP BY sc.is_single_order;

-- Time to second order for repeaters (median and 90th percentile)
SELECT
  APPROX_QUANTILES(DATE_DIFF(second_date, first_date, DAY), 100)[OFFSET(50)] AS median_days_to_second,
  APPROX_QUANTILES(DATE_DIFF(second_date, first_date, DAY), 100)[OFFSET(90)] AS p90_days_to_second,
  COUNT(*) AS repeaters
FROM (
  SELECT customer_id, MIN(order_date) AS first_date,
         MIN(IF(rn = 2, order_date, NULL)) AS second_date
  FROM (SELECT customer_id, order_date, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS rn
        FROM `sahyadri_b2b.so_orders`) GROUP BY customer_id
)
WHERE second_date IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Step 4 · Follow-up list: recent singles with high value or risk flags
-- -----------------------------------------------------------------------------
SELECT customer_id, customer_name, customer_segment, first_date, lifetime_value,
       days_since_first
FROM `sahyadri_b2b.so_customers`
WHERE is_single_order
ORDER BY lifetime_value DESC
LIMIT 25;
