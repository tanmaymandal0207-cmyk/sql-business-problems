/* Validation · Selling below cost — run after analysis.sql. All PASS. */
WITH nm AS (SELECT * FROM `sahyadri_b2b.nm_lines`),
checks AS (
  SELECT '01. Lines = source non-cancelled lines with known cost' AS check_name, 0 AS expected,
    ABS((SELECT COUNT(*) FROM nm) - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders` AS o
      JOIN `sahyadri_b2b.sales_order_items` AS i USING (order_id) JOIN `sahyadri_b2b.products` AS p USING (product_id)
      WHERE o.order_date BETWEEN DATE '2024-01-01' AND DATE '2026-09-30' AND o.order_status != 'Cancelled' AND p.unit_cost IS NOT NULL)) AS actual
  UNION ALL SELECT '02. No null line values or margins', 0, (SELECT COUNTIF(line_value IS NULL OR line_margin IS NULL) FROM nm)
  UNION ALL SELECT '03. below_cost = net price < unit_cost', 0,
    (SELECT COUNTIF(below_cost != (unit_price*(1-discount_pct/100) < unit_cost)) FROM nm)
  UNION ALL SELECT '04. list_below_cost = list < unit_cost', 0,
    (SELECT COUNTIF(list_below_cost != (list_price < unit_cost)) FROM nm)
  UNION ALL SELECT '05. list-caused subset of below-cost', 0,
    (SELECT COUNTIF(list_below_cost AND NOT below_cost) FROM nm)
  UNION ALL SELECT '06. One row per order line', 0,
    (SELECT COUNT(*) - COUNT(DISTINCT (order_id, product_id)) FROM (SELECT order_id, product_id FROM nm))
)
SELECT check_name, expected, actual, IF(actual=expected,'PASS','FAIL') AS status FROM checks ORDER BY check_name;
