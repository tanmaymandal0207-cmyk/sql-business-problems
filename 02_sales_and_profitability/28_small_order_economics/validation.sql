/* Validation · Small-order economics — run after analysis.sql. All PASS. */
WITH checks AS (
  SELECT '01. Orders = valid source orders' AS check_name, 0 AS expected,
    ABS((SELECT COUNT(*) FROM `sahyadri_b2b.sm_orders`) - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders` WHERE order_status NOT IN ('Cancelled','Returned'))) AS actual
  UNION ALL SELECT '02. Value = source line value', 0,
    (SELECT COUNT(*) FROM (SELECT order_id, SUM(v) AS s FROM (SELECT o.order_id, i.quantity*i.unit_price*(1-IFNULL(i.discount_percent,0)/100) AS v FROM `sahyadri_b2b.sales_orders` AS o JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id) WHERE o.order_status NOT IN ('Cancelled','Returned')) GROUP BY order_id) AS x JOIN `sahyadri_b2b.sm_orders` AS s USING (order_id) WHERE ABS(x.s - s.order_value) > 1)
  UNION ALL SELECT '03. Contribution = margin - freight - handling', 0,
    (SELECT COUNTIF(ABS(contribution - (product_margin - freight - handling)) > 1e-6) FROM `sahyadri_b2b.sm_orders`)
  UNION ALL SELECT '04. Size bands cover all orders', 0, (SELECT COUNTIF(size_band IS NULL) FROM `sahyadri_b2b.sm_orders`)
  UNION ALL SELECT '05. One row per order', 0, (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM `sahyadri_b2b.sm_orders`)
  UNION ALL SELECT '06. Freight = shipment sum (nulls as 0)', 0,
    (SELECT COUNT(*) FROM `sahyadri_b2b.sm_orders` AS s JOIN (SELECT order_id, SUM(IFNULL(shipping_cost,0)) AS f FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS f USING (order_id) WHERE ABS(s.freight - f.f) > 1e-6)
)
SELECT check_name, expected, actual, IF(actual=expected,'PASS','FAIL') AS status FROM checks ORDER BY check_name;
