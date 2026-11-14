/* Validation · Next order due — run after analysis.sql. All PASS. */
WITH checks AS (
  SELECT '01. Scored = customers with 3+ orders' AS check_name, 0 AS expected,
    ABS((SELECT COUNT(*) FROM `sahyadri_b2b.no_due`) - (SELECT COUNT(*) FROM (SELECT customer_id FROM `sahyadri_b2b.sales_orders` WHERE order_status NOT IN ('Cancelled') AND order_date <= DATE '2026-09-30' GROUP BY customer_id HAVING COUNT(*) >= 3))) AS actual
  UNION ALL SELECT '02. Gaps per customer = orders - 1', 0,
    (SELECT COUNT(*) FROM `sahyadri_b2b.no_gaps` AS g JOIN (SELECT customer_id, COUNT(*) AS n FROM `sahyadri_b2b.sales_orders` WHERE order_status NOT IN ('Cancelled') AND order_date <= DATE '2026-09-30' GROUP BY customer_id) AS c USING (customer_id) WHERE g.orders != c.n)
  UNION ALL SELECT '03. due = last + median gap', 0,
    (SELECT COUNTIF(due_date != DATE_ADD(last_date, INTERVAL median_gap DAY)) FROM `sahyadri_b2b.no_due`)
  UNION ALL SELECT '04. overdue flags = threshold logic', 0,
    (SELECT COUNTIF(is_overdue != (days_since_last > median_gap) OR is_far_overdue != (days_since_last > p90_gap)) FROM `sahyadri_b2b.no_due`)
  UNION ALL SELECT '05. No null rhythms or due dates', 0,
    (SELECT COUNTIF(median_gap IS NULL OR due_date IS NULL) FROM `sahyadri_b2b.no_due`)
  UNION ALL SELECT '06. One row per customer', 0,
    (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM `sahyadri_b2b.no_due`)
)
SELECT check_name, expected, actual, IF(actual=expected,'PASS','FAIL') AS status FROM checks ORDER BY check_name;
