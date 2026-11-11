/* =============================================================================
   Case study · Small-order economics: do small orders pay after freight?
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Freight is mostly fixed per shipment while handling is per order; small
   orders can lose money even with healthy product margin.
     1. What share of orders/value sits below Rs 25k, 10k, 5k?
     2. What is product margin vs freight vs handling by size band?
     3. Below what size does the average order go below zero contribution?
     4. What minimum-order-value or fee recovers the loss?
   ASSUMPTIONS: valid orders (not Cancelled/Returned); value after discount;
   freight = shipments.shipping_cost summed per order (316 nulls treated as
   0 and counted); handling = Rs 350/order + Rs 45/line (stated, sensitivity
   +-50% in README); 79 raw shipping_city values standardised by TRIM.
   ============================================================================= */
DECLARE handling_per_order NUMERIC DEFAULT 350;
DECLARE handling_per_line NUMERIC DEFAULT 45;

CREATE OR REPLACE TABLE `sahyadri_b2b.sm_orders` AS
WITH value AS (
  SELECT o.order_id, o.order_date, o.customer_id, c.customer_segment,
         COUNT(*) AS lines,
         SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent,0)/100)) AS order_value,
         SUM(i.quantity * (i.unit_price*(1-IFNULL(i.discount_percent,0)/100) - IFNULL(p.unit_cost,0))) AS product_margin
  FROM `sahyadri_b2b.sales_orders` AS o
  JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id)
  JOIN `sahyadri_b2b.products` AS p USING (product_id)
  JOIN `sahyadri_b2b.customers` AS c USING (customer_id)
  WHERE o.order_status NOT IN ('Cancelled','Returned') GROUP BY o.order_id, o.order_date, o.customer_id, c.customer_segment
),
freight AS (
  SELECT order_id, SUM(IFNULL(shipping_cost,0)) AS freight, COUNTIF(shipping_cost IS NULL) AS null_freight
  FROM `sahyadri_b2b.shipments` GROUP BY order_id
)
SELECT v.*, IFNULL(f.freight,0) AS freight, IFNULL(f.null_freight,0) AS null_freight,
  handling_per_order + handling_per_line * v.lines AS handling,
  v.product_margin - IFNULL(f.freight,0) - (handling_per_order + handling_per_line * v.lines) AS contribution,
  CASE WHEN v.order_value < 5000 THEN '1. Under Rs 5k' WHEN v.order_value < 10000 THEN '2. Rs 5-10k'
       WHEN v.order_value < 25000 THEN '3. Rs 10-25k' WHEN v.order_value < 100000 THEN '4. Rs 25k-1L'
       ELSE '5. Rs 1L+' END AS size_band
FROM value AS v LEFT JOIN freight AS f USING (order_id);

SELECT size_band, COUNT(*) AS orders, ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS share_pct,
  ROUND(SUM(order_value)/1e5,1) AS value_lakh, ROUND(AVG(product_margin),0) AS avg_margin,
  ROUND(AVG(freight),0) AS avg_freight, ROUND(AVG(handling),0) AS avg_handling,
  ROUND(AVG(contribution),0) AS avg_contribution, ROUND(100*COUNTIF(contribution<0)/COUNT(*),1) AS loss_making_pct
FROM `sahyadri_b2b.sm_orders` GROUP BY size_band ORDER BY size_band;
SELECT customer_segment, size_band, COUNT(*) AS orders, ROUND(AVG(contribution),0) AS avg_contribution,
  ROUND(100*COUNTIF(contribution<0)/COUNT(*),1) AS loss_pct
FROM `sahyadri_b2b.sm_orders` GROUP BY customer_segment, size_band ORDER BY customer_segment, size_band;
-- MOV simulation: fee Rs 500 under Rs 10k
SELECT COUNTIF(order_value < 10000) AS orders_under_10k,
  ROUND(SUM(IF(contribution<0 AND order_value<10000, contribution,0))/1e5,2) AS loss_lakh_under_10k,
  ROUND(COUNTIF(order_value<10000)*500/1e5,2) AS fee_recovery_lakh
FROM `sahyadri_b2b.sm_orders`;
SELECT order_id, order_date, customer_segment, lines, ROUND(order_value,0) AS value_, ROUND(contribution,0) AS contrib
FROM `sahyadri_b2b.sm_orders` WHERE contribution < 0 ORDER BY contribution LIMIT 25;
