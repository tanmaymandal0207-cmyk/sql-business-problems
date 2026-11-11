/* =============================================================================
   Case study · Orders with no salesperson: value, fulfilment and collection
   Category : Operations and supply chain (coverage) / Sales
   352 orders have NULL employee_id (schema.md). Every study reports them
   separately; none analyses them. This study does.
     1. How much value/margin sits on unassigned orders?
     2. Do they fulfil, deliver and collect worse?
     3. Is it a channel (web/phone), a shift, or neglect?
     4. What coverage rule clears the queue?
   METHOD: all orders 2024-01-01 to 2026-09-30; value after discount;
   NULL discount=0%; delivered = order_status Delivered; on-time = delivery
   <= promise (166 null promises excluded, counted); collected = payments sum.
   ============================================================================= */
CREATE OR REPLACE TABLE `sahyadri_b2b.un_orders` AS
WITH value AS (
  SELECT o.order_id, o.order_date, o.customer_id, o.employee_id, o.order_status, o.promised_delivery_date,
         SUM(i.quantity*i.unit_price*(1-IFNULL(i.discount_percent,0)/100)) AS order_value
  FROM `sahyadri_b2b.sales_orders` AS o JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id)
  GROUP BY o.order_id, o.order_date, o.customer_id, o.employee_id, o.order_status, o.promised_delivery_date
),
paid AS (SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` GROUP BY order_id),
ship AS (
  SELECT order_id, MAX(delivery_date) AS delivered_on, SUM(IFNULL(shipping_cost,0)) AS freight
  FROM `sahyadri_b2b.shipments` GROUP BY order_id
)
SELECT v.*, c.customer_name, c.customer_segment,
       v.employee_id IS NULL AS unassigned,
       IFNULL(p.paid,0) AS paid, v.order_value - IFNULL(p.paid,0) AS balance,
       s.delivered_on, s.freight,
       CASE WHEN v.promised_delivery_date IS NULL THEN NULL
            WHEN s.delivered_on IS NULL THEN NULL
            ELSE s.delivered_on <= v.promised_delivery_date END AS on_time
FROM value AS v JOIN `sahyadri_b2b.customers` AS c USING (customer_id)
LEFT JOIN paid AS p USING (order_id) LEFT JOIN ship AS s USING (order_id);

SELECT unassigned, COUNT(*) AS orders, ROUND(SUM(order_value)/1e7,2) AS value_cr,
  ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS share_pct,
  ROUND(100*COUNTIF(order_status='Delivered')/COUNT(*),1) AS delivered_pct,
  ROUND(100*COUNTIF(on_time)/COUNTIF(on_time IS NOT NULL),1) AS ontime_of_promised_pct,
  ROUND(SUM(balance)/1e7,2) AS balance_cr
FROM `sahyadri_b2b.un_orders` GROUP BY unassigned;
SELECT customer_segment, unassigned, COUNT(*) AS orders, ROUND(SUM(order_value)/1e5,1) AS value_lakh
FROM `sahyadri_b2b.un_orders` GROUP BY customer_segment, unassigned ORDER BY customer_segment, unassigned;
SELECT EXTRACT(YEAR FROM order_date) AS y, EXTRACT(QUARTER FROM order_date) AS q,
  COUNTIF(unassigned) AS unassigned_orders, COUNT(*) AS total
FROM `sahyadri_b2b.un_orders` GROUP BY y, q ORDER BY y, q;
SELECT EXTRACT(DAYOFWEEK FROM order_date) AS dow, COUNTIF(unassigned) AS unassigned, COUNT(*) AS total,
  ROUND(100*COUNTIF(unassigned)/COUNT(*),1) AS unassigned_pct
FROM `sahyadri_b2b.un_orders` GROUP BY dow ORDER BY dow;
SELECT order_id, order_date, customer_name, customer_segment, ROUND(order_value,0) AS value_, order_status, ROUND(balance,0) AS bal
FROM `sahyadri_b2b.un_orders` WHERE unassigned AND balance > 10000 ORDER BY balance DESC LIMIT 25;
