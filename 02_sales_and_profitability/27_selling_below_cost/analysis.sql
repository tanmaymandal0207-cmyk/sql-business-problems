/* =============================================================================
   Case study · Selling below cost: which orders lose money and why
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   BUSINESS PROBLEM
   Product cost-to-serve shows operating contribution, but the sales desk
   needs a sharper guardrail: which invoices were priced below product cost,
   and was it the list price or the discount that caused it?
     1. How many lines/orders are sold below cost, and how much margin lost?
     2. Is it list-price-below-cost or discount-driven?
     3. Which products, categories and segments concentrate the loss?
     4. What floor (list check + discount cap) would have prevented it?
   ASSUMPTIONS
     - Valid orders: not Cancelled; line net = unit_price*(1-discount/100);
       NULL discount = 0%; lines with NULL unit_cost excluded, counted.
     - Below-cost line: net unit price < unit_cost.
   ============================================================================= */
DECLARE first_order DATE DEFAULT DATE '2024-01-01';
DECLARE last_order  DATE DEFAULT DATE '2026-09-30';

CREATE OR REPLACE TABLE `sahyadri_b2b.nm_lines` AS
SELECT o.order_id, o.order_date, o.customer_id, c.customer_segment,
       i.product_id, pr.product_name, cat.category_name,
       i.quantity, i.unit_price, IFNULL(i.discount_percent, 0) AS discount_pct,
       pr.selling_price AS list_price, p2.unit_cost,
       i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS line_value,
       i.quantity * (i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) - p2.unit_cost) AS line_margin,
       i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) < p2.unit_cost AS below_cost,
       pr.selling_price < p2.unit_cost AS list_below_cost
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id)
JOIN `sahyadri_b2b.products` AS p2 USING (product_id)
JOIN `sahyadri_b2b.products` AS pr USING (product_id)
JOIN `sahyadri_b2b.product_categories` AS cat ON cat.category_id = pr.category_id
JOIN `sahyadri_b2b.customers` AS c USING (customer_id)
WHERE o.order_date BETWEEN first_order AND last_order
  AND o.order_status != 'Cancelled'
  AND p2.unit_cost IS NOT NULL;

-- Headline loss
SELECT COUNT(*) AS lines, COUNTIF(below_cost) AS below_cost_lines,
  ROUND(100*COUNTIF(below_cost)/COUNT(*),2) AS below_cost_line_pct,
  ROUND(SUM(IF(below_cost, line_margin, 0))/1e5,2) AS below_cost_margin_lakh,
  ROUND(SUM(IF(below_cost AND list_below_cost, 1, 0))/NULLIF(COUNTIF(below_cost),0)*100,1) AS list_caused_pct_of_below
FROM `sahyadri_b2b.nm_lines`;

-- By category and segment
SELECT category_name, COUNTIF(below_cost) AS below_lines,
  ROUND(SUM(IF(below_cost, line_margin, 0))/1e5,2) AS margin_lakh
FROM `sahyadri_b2b.nm_lines` GROUP BY category_name ORDER BY margin_lakh;
SELECT customer_segment, COUNTIF(below_cost) AS below_lines,
  ROUND(SUM(IF(below_cost, line_margin, 0))/1e5,2) AS margin_lakh,
  ROUND(AVG(IF(below_cost, discount_pct, NULL)),2) AS avg_discount_on_below
FROM `sahyadri_b2b.nm_lines` GROUP BY customer_segment ORDER BY margin_lakh;

-- Worst products and orders
SELECT product_id, product_name, category_name, COUNTIF(below_cost) AS below_lines,
  ROUND(SUM(IF(below_cost, line_margin, 0))/1e5,2) AS margin_lakh
FROM `sahyadri_b2b.nm_lines` GROUP BY product_id, product_name, category_name
HAVING COUNTIF(below_cost) > 0 ORDER BY SUM(IF(below_cost, line_margin, 0)) LIMIT 15;
SELECT order_id, order_date, customer_segment,
  ROUND(SUM(line_margin)/1000,1) AS order_margin_k,
  COUNTIF(below_cost) AS below_lines
FROM `sahyadri_b2b.nm_lines` GROUP BY order_id, order_date, customer_segment
HAVING SUM(IF(below_cost, 1, 0)) > 0 ORDER BY SUM(line_margin) LIMIT 20;
