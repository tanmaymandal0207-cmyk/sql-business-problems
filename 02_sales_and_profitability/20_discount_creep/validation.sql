/* =============================================================================
   Case study · Discount creep — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

WITH o AS (SELECT * FROM `sahyadri_b2b.dc_orders`),
     s AS (SELECT * FROM `sahyadri_b2b.dc_shuffles`),

src AS (
    SELECT COUNT(DISTINCT x.order_id) AS n,
           SUM(i.quantity * i.unit_price)                                     AS list_value,
           SUM(i.quantity * i.unit_price * IFNULL(i.discount_percent, 0) / 100) AS discount_value
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned')
),
per_customer AS (
    SELECT customer_id, COUNT(*) AS n, MAX(order_no) AS max_no, MIN(order_no) AS min_no,
           ANY_VALUE(customer_orders) AS stated, SUM(discount_dev) AS d_sum, SUM(years_dev) AS y_sum
    FROM o GROUP BY customer_id
),
eligible AS (
    SELECT * FROM o WHERE customer_orders >= 2
),

checks AS (
    SELECT '01. Orders = valid orders, list and discount value = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(list_value) FROM o) - (SELECT list_value FROM src)) > 1, 1, 0)
         + IF(ABS((SELECT SUM(discount_value) FROM o) - (SELECT discount_value FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Order numbers run 1..n within each customer', 0,
           (SELECT COUNTIF(min_no != 1 OR max_no != n OR stated != n) FROM per_customer)
    UNION ALL
    SELECT '03. Discount rate = discount / list value, between 0 and 20 %', 0,
           (SELECT COUNTIF(ABS(discount_rate - discount_value / list_value) > 1e-12 OR discount_rate < 0 OR discount_rate > 0.2) FROM o)
    UNION ALL
    SELECT '04. Deviations sum to zero within each customer', 0,
           (SELECT COUNTIF(ABS(d_sum) > 1e-9 OR ABS(y_sum) > 1e-9) FROM per_customer)
    UNION ALL
    SELECT '05. Time since first order starts at zero, never negative', 0,
           (SELECT COUNTIF((order_no = 1 AND years_since_first != 0) OR years_since_first < 0) FROM o)
    UNION ALL
    SELECT '06. 500 shuffled slopes, centred on zero', 0,
           ABS((SELECT COUNT(*) FROM s) - 500) + IF(ABS((SELECT AVG(slope_per_year) FROM s)) > 0.0005, 1, 0)
    UNION ALL
    SELECT '07. Pooled within slope = covariance / variance of the centred values', 0,
           (SELECT IF(ABS(SUM(years_dev * discount_dev) / SUM(years_dev * years_dev)
                          - COVAR_POP(years_dev, discount_dev) / VAR_POP(years_dev)) > 1e-9, 1, 0) FROM eligible)
    UNION ALL
    SELECT '08. Order-number bands add up to all orders', 0,
           ABS((SELECT SUM(n) FROM (SELECT COUNT(*) AS n FROM o GROUP BY CASE WHEN order_no = 1 THEN 1 WHEN order_no <= 3 THEN 2
                                     WHEN order_no <= 10 THEN 3 WHEN order_no <= 30 THEN 4 ELSE 5 END)) - (SELECT COUNT(*) FROM o))
    UNION ALL
    SELECT '09. First-year and later orders split every order of each customer', 0,
           (SELECT COUNTIF(first_year + later != n OR first_year = 0)
              FROM (SELECT customer_id, COUNTIF(years_since_first < 1) AS first_year, COUNTIF(years_since_first >= 1) AS later, COUNT(*) AS n
                      FROM o GROUP BY customer_id))
    UNION ALL
    SELECT '10. Segments add up to the customers with two or more orders', 0,
           ABS((SELECT SUM(n) FROM (SELECT COUNT(*) AS n FROM eligible GROUP BY customer_segment)) - (SELECT COUNT(*) FROM eligible))
         + ABS((SELECT COUNT(DISTINCT customer_id) FROM eligible) - (SELECT COUNTIF(n >= 2) FROM per_customer))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
