/* =============================================================================
   Case study · Missing data mechanism — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE min_group INT64   DEFAULT 30;

WITH ob AS (SELECT * FROM `sahyadri_b2b.md_observations`),
     t AS (SELECT * FROM `sahyadri_b2b.md_tests`),

src AS (
    SELECT 'Order promise date' AS field, COUNT(*) - COUNT(promised_delivery_date) AS missing, COUNT(*) AS n FROM `sahyadri_b2b.sales_orders`
    UNION ALL SELECT 'Order salesperson', COUNT(*) - COUNT(employee_id), COUNT(*) FROM `sahyadri_b2b.sales_orders`
    UNION ALL SELECT 'Line discount', COUNT(*) - COUNT(discount_percent), COUNT(*) FROM `sahyadri_b2b.sales_order_items`
    UNION ALL SELECT 'Payment method', COUNT(*) - COUNT(payment_method), COUNT(*) FROM `sahyadri_b2b.payments`
    UNION ALL SELECT 'Shipment freight cost', COUNT(*) - COUNT(shipping_cost), COUNT(*) FROM `sahyadri_b2b.shipments`
    UNION ALL SELECT 'Shipment delivery date', COUNT(*) - COUNT(delivery_date), COUNT(*) FROM `sahyadri_b2b.shipments`
),
per_dim AS (
    SELECT field, dimension, COUNT(*) AS n, COUNT(DISTINCT record_id) AS nd, COUNTIF(is_missing) AS x
    FROM ob GROUP BY field, dimension
),
-- check 03: Pearson chi-square on the full 2 x k table, a second way
pooled AS (
    SELECT field, dimension, IF(n < min_group, 'Other', grp) AS grp, SUM(n) AS n, SUM(x) AS x
    FROM (SELECT field, dimension, grp, COUNT(*) AS n, COUNTIF(is_missing) AS x FROM ob GROUP BY field, dimension, grp)
    GROUP BY field, dimension, IF(n < min_group, 'Other', grp)
),
pearson AS (
    SELECT field, dimension,
           SUM(POW(x - e1, 2) / e1 + POW((n - x) - (n - e1), 2) / (n - e1)) AS chi
    FROM (SELECT *, n * SUM(x) OVER (PARTITION BY field, dimension) / SUM(n) OVER (PARTITION BY field, dimension) AS e1 FROM pooled)
    GROUP BY field, dimension
),
salesperson_revenue AS (
    SELECT SUM(IF(o.employee_id IS NULL, i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100), 0)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),

checks AS (
    SELECT '01. Missing counts per field = source COUNT(*) - COUNT(column)' AS check_name, 0 AS expected,
           (SELECT COUNTIF(p.x != s.missing OR p.nd != s.n)
              FROM (SELECT field, MAX(x) AS x, MAX(nd) AS nd FROM per_dim GROUP BY field) AS p JOIN src AS s USING (field)) AS actual
    UNION ALL
    SELECT '02. Every dimension covers every record exactly once', 0,
           (SELECT COUNTIF(p.n != s.n OR p.nd != s.n OR p.x != s.missing) FROM per_dim AS p JOIN src AS s USING (field))
    UNION ALL
    SELECT '03. Chi-square = Pearson statistic on the full missing / present table', 0,
           (SELECT COUNTIF(ABS(t.chi_square - p.chi) > 1e-6) FROM t JOIN pearson AS p USING (field, dimension))
    UNION ALL
    SELECT '04. Groups under 30 records pooled, every other group has 30+', 0,
           (SELECT COUNTIF(grp != 'Other' AND n < min_group) FROM pooled)
    UNION ALL
    SELECT '05. Critical values exceed the degrees of freedom and rise with them', 0,
           (SELECT COUNTIF(critical_1pct <= df) FROM t)
         + (SELECT COUNTIF(c1 < c0) FROM (SELECT critical_1pct AS c1, LAG(critical_1pct) OVER (ORDER BY df, critical_1pct) AS c0 FROM t) WHERE c0 IS NOT NULL)
    UNION ALL
    SELECT '06. Delivery date is blank for every shipment still in transit', 0,
           (SELECT COUNTIF(NOT is_missing) FROM ob WHERE field = 'Shipment delivery date' AND grp = 'In Transit')
    UNION ALL
    SELECT '07. Unattributed revenue = recount from source', 0,
           (SELECT COUNTIF(ABS(amount_lakh - ROUND((SELECT v FROM salesperson_revenue) / 1e5, 2)) > 0.005)
              FROM `sahyadri_b2b.md_impact` WHERE field = 'Order salesperson')
         + ABS(6 - (SELECT COUNT(*) FROM `sahyadri_b2b.md_impact`))
    UNION ALL
    SELECT '08. Each test counts the field''s records and missing values', 0,
           (SELECT COUNTIF(t.records != s.n OR t.missing != s.missing) FROM t JOIN src AS s USING (field))
    UNION ALL
    SELECT '09. Highest group rate >= overall rate >= lowest group rate', 0,
           (SELECT COUNTIF(highest_rate < missing / records - 1e-12 OR min_rate > missing / records + 1e-12 OR highest_rate != max_rate) FROM t)
    UNION ALL
    SELECT '10. Dispersion ratio = chi-square / degrees of freedom', 0,
           (SELECT COUNTIF(ABS(dispersion_ratio - chi_square / df) > 1e-12 OR df != groups - 1) FROM t)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
