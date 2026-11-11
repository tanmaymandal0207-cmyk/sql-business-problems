/* Validation · Duplicate receipts — run after analysis.sql. All PASS. */
WITH checks AS (
  SELECT '01. Rows = all source payments' AS check_name, 0 AS expected,
    ABS((SELECT COUNT(*) FROM `sahyadri_b2b.dr_receipts`) - (SELECT COUNT(*) FROM `sahyadri_b2b.payments`)) AS actual
  UNION ALL SELECT '02. Groups share order, date and amount', 0,
    (SELECT COUNT(*) FROM (SELECT order_id, payment_date, amount, COUNT(DISTINCT payment_id) AS n, COUNT(*) AS r FROM `sahyadri_b2b.dr_receipts` GROUP BY order_id, payment_date, amount HAVING MAX(CAST(in_dup_group AS INT64)) = 1) WHERE n != r OR n < 2)
  UNION ALL SELECT '03. Exactly one original per group', 0,
    (SELECT COUNT(*) FROM (SELECT order_id, payment_date, amount FROM `sahyadri_b2b.dr_receipts` WHERE in_dup_group GROUP BY order_id, payment_date, amount HAVING COUNTIF(NOT is_duplicate) != 1))
  UNION ALL SELECT '04. Duplicate amount = group total - original', 0,
    (SELECT COUNT(*) FROM (SELECT order_id, payment_date, amount, SUM(amount) AS t, SUM(IF(is_duplicate, amount, 0)) AS d FROM `sahyadri_b2b.dr_receipts` GROUP BY order_id, payment_date, amount HAVING in_dup_group) WHERE ABS(d - (t - amount)) > 1e-6)
  UNION ALL SELECT '05. One row per payment_id', 0, (SELECT COUNT(*) - COUNT(DISTINCT payment_id) FROM `sahyadri_b2b.dr_receipts`)
)
SELECT check_name, expected, actual, IF(actual=expected,'PASS','FAIL') AS status FROM checks ORDER BY check_name;
