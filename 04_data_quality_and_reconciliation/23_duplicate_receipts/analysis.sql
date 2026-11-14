/* =============================================================================
   Case study · Duplicate receipts: how much was collected twice
   7 payments repeat an earlier receipt for same order/date/amount (schema.md)
   and one has missing method — treated as duplicates in order-to-cash. But
   finance still needs: which receipts, what refund exposure, and what
   control stops it?
     1. Which receipts are exact duplicates (order, date, amount)?
     2. How much double-collected value is at stake (refund exposure)?
     3. Do duplicates cluster by method, day, customer or salesperson?
     4. What matching rule flags them at entry?
   METHOD: grain one row per payment; duplicate group = (order_id, payment_date,
   amount) with >1 receipt; keep earliest payment_id as original, rest as
   duplicate; exposure = duplicate amount (refund owed if order not underpaid).
   ============================================================================= */
CREATE OR REPLACE TABLE `sahyadri_b2b.dr_receipts` AS
WITH ranked AS (
  SELECT p.*, c.customer_name, c.customer_segment,
         ROW_NUMBER() OVER (PARTITION BY p.order_id, p.payment_date, p.amount ORDER BY p.payment_id) AS rn,
         COUNT(*) OVER (PARTITION BY p.order_id, p.payment_date, p.amount) AS grp_n
  FROM `sahyadri_b2b.payments` AS p LEFT JOIN `sahyadri_b2b.sales_orders` AS o USING (order_id)
  LEFT JOIN `sahyadri_b2b.customers` AS c USING (customer_id)
)
SELECT *, grp_n > 1 AS in_dup_group, rn > 1 AS is_duplicate FROM ranked;

SELECT COUNT(*) AS receipts, COUNTIF(in_dup_group) AS in_groups, COUNTIF(is_duplicate) AS duplicates,
  ROUND(SUM(IF(is_duplicate, amount, 0))/1e5,2) AS duplicate_value_lakh
FROM `sahyadri_b2b.dr_receipts`;
SELECT order_id, payment_date, amount, COUNT(*) AS n, STRING_AGG(CAST(payment_id AS STRING), ',' ORDER BY payment_id) AS payment_ids
FROM `sahyadri_b2b.dr_receipts` WHERE in_dup_group GROUP BY order_id, payment_date, amount ORDER BY amount DESC;
SELECT IFNULL(payment_method,'(missing)') AS method, COUNTIF(is_duplicate) AS dups, COUNT(*) AS receipts
FROM `sahyadri_b2b.dr_receipts` GROUP BY method ORDER BY dups DESC;
-- Exposure: duplicate amount on orders that are not underpaid
WITH val AS (
  SELECT o.order_id, SUM(i.quantity*i.unit_price*(1-IFNULL(i.discount_percent,0)/100)) AS v
  FROM `sahyadri_b2b.sales_orders` AS o JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id) GROUP BY order_id
),
paid AS (SELECT order_id, SUM(amount) AS p FROM `sahyadri_b2b.payments` GROUP BY order_id)
SELECT r.order_id, r.payment_id, r.payment_date, r.amount, r.payment_method, r.customer_name,
  ROUND(v.v,2) AS order_value, ROUND(p.p,2) AS total_paid, ROUND(p.p - v.v,2) AS overpaid
FROM `sahyadri_b2b.dr_receipts` AS r JOIN val AS v USING (order_id) JOIN paid AS p USING (order_id)
WHERE r.is_duplicate ORDER BY overpaid DESC;
