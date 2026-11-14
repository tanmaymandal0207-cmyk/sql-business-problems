/* Validation · Unassigned orders — run after analysis.sql. All PASS. */
WITH checks AS (
  SELECT '01. Rows = all source orders' AS check_name, 0 AS expected,
    ABS((SELECT COUNT(*) FROM `sahyadri_b2b.un_orders`) - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders`)) AS actual
  UNION ALL SELECT '02. Unassigned = 352 source nulls', 0,
    ABS((SELECT COUNTIF(unassigned) FROM `sahyadri_b2b.un_orders`) - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders` WHERE employee_id IS NULL))
  UNION ALL SELECT '03. Value tie-out per order', 0,
    (SELECT COUNT(*) FROM (SELECT order_id, SUM(i.quantity*i.unit_price*(1-IFNULL(i.discount_percent,0)/100)) AS s FROM `sahyadri_b2b.sales_orders` AS o JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id) GROUP BY order_id) AS x JOIN `sahyadri_b2b.un_orders` AS u USING (order_id) WHERE ABS(x.s-u.order_value) > 1)
  UNION ALL SELECT '04. Paid = payments sum', 0,
    (SELECT COUNT(*) FROM `sahyadri_b2b.un_orders` AS u JOIN (SELECT order_id, SUM(amount) AS s FROM `sahyadri_b2b.payments` GROUP BY order_id) AS p USING (order_id) WHERE ABS(u.paid-p.s) > 1e-6)
  UNION ALL SELECT '05. Balance = value - paid', 0, (SELECT COUNTIF(ABS(balance-(order_value-paid)) > 1e-6) FROM `sahyadri_b2b.un_orders`)
  UNION ALL SELECT '06. On-time null iff promise or delivery null', 0,
    (SELECT COUNTIF((on_time IS NULL) != (promised_delivery_date IS NULL OR delivered_on IS NULL)) FROM `sahyadri_b2b.un_orders`)
)
SELECT check_name, expected, actual, IF(actual=expected,'PASS','FAIL') AS status FROM checks ORDER BY check_name;
