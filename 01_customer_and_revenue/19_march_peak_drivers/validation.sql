/* =============================================================================
   Case study · Who drives the March peak? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE large_order FLOAT64 DEFAULT 500000;

WITH o AS (SELECT * FROM `sahyadri_b2b.mp_orders`),
     co AS (SELECT * FROM `sahyadri_b2b.mp_company`),
     g AS (SELECT * FROM `sahyadri_b2b.mp_groups`),
     cu AS (SELECT * FROM `sahyadri_b2b.mp_customers`),

src AS (
    SELECT COUNT(DISTINCT x.order_id) AS n,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned') AND EXTRACT(MONTH FROM x.order_date) BETWEEN 1 AND 6
),
y2026 AS (
    SELECT SUM(IF(mo = 3, order_value, 0)) AS mar, SUM(IF(mo != 3, order_value, 0)) / 5 AS base,
           COUNTIF(mo = 3) AS mar_orders, COUNT(DISTINCT IF(mo = 3, customer_id, NULL)) AS mar_customers
    FROM o WHERE yr = 2026
),
binomial AS (
    SELECT dimension,
           SUM(POW(march_orders - (march_orders + base_orders) * p, 2) / ((march_orders + base_orders) * p * (1 - p))) AS chi
    FROM (SELECT *, SUM(march_orders) OVER (PARTITION BY dimension) / SUM(march_orders + base_orders) OVER (PARTITION BY dimension) AS p FROM g)
    GROUP BY dimension
),
pearson AS (
    SELECT dimension,
           SUM(POW(march_orders - expected_march_orders, 2) / expected_march_orders
             + POW(base_orders - (base_orders + march_orders - expected_march_orders), 2) / (base_orders + march_orders - expected_march_orders)) AS chi
    FROM g GROUP BY dimension
),
pairs AS (
    SELECT a.excess_orders AS x, b.excess_orders AS y
    FROM cu AS a JOIN cu AS b ON b.customer_id = a.customer_id AND a.yr = 2025 AND b.yr = 2026
),

checks AS (
    SELECT '01. Orders = valid January-June orders, value = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src)) + IF(ABS((SELECT SUM(order_value) FROM o) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. 2026 March and baseline figures = recount', 0,
           (SELECT COUNTIF(ABS(co.march_revenue - y.mar) > 0.01 OR ABS(co.base_revenue - y.base) > 0.01
                           OR co.march_orders != y.mar_orders OR co.march_customers != y.mar_customers)
              FROM co CROSS JOIN y2026 AS y WHERE co.yr = 2026)
    UNION ALL
    SELECT '03. Uplift shares (customers, frequency, order value) add up to 100 %', 0,
           (SELECT COUNTIF(ABS(LN(march_customers / base_customers) + LN((march_orders / march_customers) / (base_orders / base_customers))
                               + LN((march_revenue / march_orders) / (base_revenue / base_orders)) - LN(march_revenue / base_revenue)) > 1e-9) FROM co)
    UNION ALL
    SELECT '04. Group orders add up to all orders in each dimension', 0,
           (SELECT COUNTIF(t != (SELECT COUNT(*) FROM o)) FROM (SELECT dimension, SUM(march_orders + base_orders) AS t FROM g GROUP BY dimension))
    UNION ALL
    SELECT '05. Expected March orders add up to actual March orders', 0,
           (SELECT COUNTIF(ABS(e - m) > 1e-6) FROM (SELECT dimension, SUM(expected_march_orders) AS e, SUM(march_orders) AS m FROM g GROUP BY dimension))
    UNION ALL
    SELECT '06. Chi-square = binomial form of the same test', 0,
           (SELECT COUNTIF(ABS(p.chi - b.chi) > 1e-6) FROM pearson AS p JOIN binomial AS b USING (dimension))
    UNION ALL
    SELECT '07. Excess orders = March orders - baseline monthly orders, spiker rule applied', 0,
           (SELECT COUNTIF(ABS(excess_orders - (march_orders - base_orders_per_month)) > 1e-9
                           OR spiker != (march_orders >= 2 * base_orders_per_month AND excess_orders >= 2)) FROM cu)
    UNION ALL
    SELECT '08. One customer row per year with January-June orders', 0,
           (SELECT COUNT(*) FROM (SELECT yr, COUNT(*) AS n FROM cu GROUP BY yr) AS a
              JOIN (SELECT yr, COUNT(DISTINCT customer_id) AS n FROM o GROUP BY yr) AS b USING (yr) WHERE a.n != b.n)
    UNION ALL
    SELECT '09. Persistence correlation = COVAR / (SD x SD)', 0,
           (SELECT IF(ABS(CORR(x, y) - COVAR_POP(x, y) / (STDDEV_POP(x) * STDDEV_POP(y))) > 1e-9, 1, 0) FROM pairs)
    UNION ALL
    SELECT '10. Revenue without large orders never exceeds revenue', 0,
           (SELECT COUNTIF(march_revenue_excl_large > march_revenue + 0.01 OR base_revenue_excl_large > base_revenue + 0.01) FROM co)
         + ABS(3 - (SELECT COUNT(*) FROM co))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
