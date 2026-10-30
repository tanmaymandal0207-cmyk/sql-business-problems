/* =============================================================================
   Case study · Salesperson category specialisation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE start_date    DATE  DEFAULT DATE '2024-01-01';
DECLARE end_date      DATE  DEFAULT DATE '2026-09-30';
DECLARE recent_start  DATE  DEFAULT DATE '2025-10-01';
DECLARE permutations  INT64 DEFAULT 200;

WITH l  AS (SELECT * FROM `sahyadri_b2b.sp_lines`),
     oc AS (SELECT * FROM `sahyadri_b2b.sp_order_categories`),
     sh AS (SELECT * FROM `sahyadri_b2b.sp_shuffles`),
     ix AS (SELECT * FROM `sahyadri_b2b.sp_index`),

src AS (
    SELECT COUNT(*) AS n, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.employee_id IS NOT NULL
      AND o.order_date BETWEEN start_date AND end_date
),
real_orders AS (SELECT DISTINCT order_id, customer_id, employee_id FROM oc),
real_counts AS (SELECT employee_id, COUNT(*) AS n FROM real_orders GROUP BY employee_id),
real_cust_counts AS (SELECT customer_id, employee_id, COUNT(*) AS n FROM real_orders GROUP BY customer_id, employee_id),
shuffle_counts AS (SELECT benchmark, b, employee_id, COUNT(*) AS n FROM sh GROUP BY benchmark, b, employee_id),
shuffle_cust_counts AS (
    SELECT s.b, r.customer_id, s.employee_id, COUNT(*) AS n
    FROM sh AS s JOIN real_orders AS r ON r.order_id = s.order_id
    WHERE s.benchmark = 'Same customer'
    GROUP BY s.b, r.customer_id, s.employee_id
),
-- check 07: index rebuilt from the lines
direct AS (
    SELECT e.employee_id, 0.5 * SUM(ABS(IFNULL(x.v, 0) / e.t - c.share)) AS d
    FROM (SELECT employee_id, SUM(line_value) AS t FROM l GROUP BY employee_id) AS e
    CROSS JOIN (SELECT category, SUM(line_value) / (SELECT SUM(line_value) FROM l) AS share FROM l GROUP BY category) AS c
    LEFT JOIN (SELECT employee_id, category, SUM(line_value) AS v FROM l GROUP BY employee_id, category) AS x
      ON x.employee_id = e.employee_id AND x.category = c.category
    GROUP BY e.employee_id
),

checks AS (
    SELECT '01. Lines = valid order lines with a salesperson in the period (count and value)' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM l) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(line_value) FROM l) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Order x category values add up to the lines', 0,
           IF(ABS((SELECT SUM(value) FROM oc) - (SELECT SUM(line_value) FROM l)) > 1, 1, 0)
         + (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(order_id AS STRING), category)) FROM oc)
    UNION ALL
    SELECT '03. Every order appears once in every shuffle', 0,
           (SELECT COUNTIF(n != (SELECT COUNT(*) FROM real_orders) OR nd != n)
              FROM (SELECT benchmark, b, COUNT(*) AS n, COUNT(DISTINCT order_id) AS nd FROM sh GROUP BY benchmark, b))
         + ABS(2 * (permutations + 1) - (SELECT COUNT(DISTINCT CONCAT(benchmark, CAST(b AS STRING))) FROM sh))
    UNION ALL
    SELECT '04. Every shuffle keeps each salesperson''s number of orders', 0,
           (SELECT COUNT(*) FROM shuffle_counts AS s FULL OUTER JOIN real_counts AS r ON r.employee_id = s.employee_id
             WHERE s.n IS NULL OR r.n IS NULL OR s.n != r.n)
    UNION ALL
    SELECT '05. Same-customer shuffles keep each customer''s salespeople and their order counts', 0,
           (SELECT COUNT(*) FROM shuffle_cust_counts AS s
              LEFT JOIN real_cust_counts AS r ON r.customer_id = s.customer_id AND r.employee_id = s.employee_id
             WHERE r.n IS NULL OR r.n != s.n)
    UNION ALL
    SELECT '06. b = 0 keeps the real salesperson on every order', 0,
           (SELECT COUNT(*) FROM sh JOIN real_orders AS r USING (order_id) WHERE sh.b = 0 AND sh.employee_id != r.employee_id)
    UNION ALL
    SELECT '07. Observed specialisation index = rebuild from order lines', 0,
           (SELECT COUNTIF(ABS(i.d_index - d.d) > 1e-9) FROM ix AS i JOIN direct AS d USING (employee_id)
             WHERE i.b = 0)
         + ABS((SELECT COUNT(*) FROM direct) - (SELECT COUNT(*) FROM ix WHERE b = 0 AND benchmark = 'Any order'))
    UNION ALL
    SELECT '08. Index between 0 and 1, salesperson revenues add to the total in every shuffle', 0,
           (SELECT COUNTIF(d_index < 0 OR d_index > 1) FROM ix)
         + (SELECT COUNTIF(ABS(t - (SELECT SUM(value) FROM oc)) > 1) FROM (SELECT benchmark, b, SUM(revenue) AS t FROM ix GROUP BY benchmark, b))
    UNION ALL
    SELECT '09. Ten categories mapped to three product lines, each category to one line', 0,
           ABS(10 - (SELECT COUNT(DISTINCT category) FROM l)) + ABS(3 - (SELECT COUNT(DISTINCT product_line) FROM l))
         + (SELECT COUNTIF(k != 1) FROM (SELECT category, COUNT(DISTINCT product_line) AS k FROM l GROUP BY category))
    UNION ALL
    SELECT '10. Recent customers by product lines bought add up to all recent customers', 0,
           ABS((SELECT COUNT(*) FROM (SELECT customer_id, COUNT(DISTINCT product_line) AS k FROM l WHERE order_date >= recent_start GROUP BY customer_id) WHERE k BETWEEN 1 AND 3)
             - (SELECT COUNT(DISTINCT customer_id) FROM l WHERE order_date >= recent_start))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
