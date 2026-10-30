/* =============================================================================
   Case study · Gateway categories — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE follow_days      INT64 DEFAULT 365;
DECLARE last_first_order DATE  DEFAULT DATE '2025-09-30';
DECLARE permutations     INT64 DEFAULT 1000;

WITH g AS (SELECT * FROM `sahyadri_b2b.gw_scored`),
     ps AS (SELECT * FROM `sahyadri_b2b.gw_permutation_stats`),

valid AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, o.order_date
),
first_date AS (
    SELECT customer_id, MIN(order_date) AS d FROM valid GROUP BY customer_id
),
first_id AS (
    SELECT v.customer_id, MIN(v.order_id) AS order_id, f.d
    FROM valid AS v JOIN first_date AS f ON f.customer_id = v.customer_id AND v.order_date = f.d
    GROUP BY v.customer_id, f.d
),
-- category values on each customer's first order
first_cat_values AS (
    SELECT g.customer_id, p.category_id,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM g
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = g.first_order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    GROUP BY g.customer_id, p.category_id
),
-- 12-month outcome recount
later AS (
    SELECT g.customer_id, COUNT(v.order_id) AS orders_12m, IFNULL(SUM(v.order_value), 0) AS revenue_12m
    FROM g
    LEFT JOIN valid AS v
      ON v.customer_id = g.customer_id
     AND (v.order_date > g.first_order_date OR (v.order_date = g.first_order_date AND v.order_id > g.first_order_id))
     AND v.order_date <= DATE_ADD(g.first_order_date, INTERVAL follow_days DAY)
    GROUP BY g.customer_id
),
cell_means AS (
    SELECT customer_segment, size_band, AVG(revenue_12m) AS m_rev, AVG(IF(came_back, 1, 0)) AS m_back
    FROM g GROUP BY customer_segment, size_band
),
bands AS (
    SELECT size_band, COUNT(*) AS n, MIN(first_order_value) AS lo, MAX(first_order_value) AS hi FROM g GROUP BY size_band
),
real_counts AS (
    SELECT gateway_category, COUNT(*) AS n,
           AVG(IF(came_back, 1, 0) - expected_came_back) AS r_back,
           AVG(revenue_12m - expected_revenue_12m)       AS r_rev
    FROM g GROUP BY gateway_category
),

checks AS (
    SELECT '01. One row per customer whose first valid order is on or before the cut-off' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM g) - (SELECT COUNT(*) FROM first_date WHERE d <= last_first_order))
         + (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM g) AS actual
    UNION ALL
    SELECT '02. First order = earliest valid order (date, then order id)', 0,
           (SELECT COUNTIF(g.first_order_id != f.order_id OR g.first_order_date != f.d)
              FROM g JOIN first_id AS f ON f.customer_id = g.customer_id)
    UNION ALL
    SELECT '03. Gateway category has the largest value on the first order', 0,
           (SELECT COUNT(*) FROM g
              JOIN first_cat_values AS a ON a.customer_id = g.customer_id AND a.category_id = g.gateway_category_id
              JOIN first_cat_values AS b ON b.customer_id = g.customer_id AND b.v > a.v + 1e-6)
    UNION ALL
    SELECT '04. First-order value and category count = source recount', 0,
           (SELECT COUNTIF(ABS(g.first_order_value - x.v) > 0.01 OR g.first_order_categories != x.k)
              FROM g JOIN (SELECT customer_id, SUM(v) AS v, COUNT(*) AS k FROM first_cat_values GROUP BY customer_id) AS x
                ON x.customer_id = g.customer_id)
    UNION ALL
    SELECT '05. 12-month orders and revenue = independent recount', 0,
           (SELECT COUNTIF(g.orders_12m != l.orders_12m OR ABS(g.revenue_12m - l.revenue_12m) > 0.01)
              FROM g JOIN later AS l ON l.customer_id = g.customer_id)
    UNION ALL
    SELECT '06. Came back = any later order, and new categories <= categories <= 10', 0,
           (SELECT COUNTIF(came_back != (orders_12m > 0) OR new_categories_12m > categories_12m OR categories_12m > 10
                           OR (orders_12m = 0 AND (revenue_12m != 0 OR categories_12m != 0))) FROM g)
    UNION ALL
    SELECT '07. Three size bands of near-equal size that do not overlap', 0,
           ABS(3 - (SELECT COUNT(*) FROM bands))
         + (SELECT COUNTIF(n < FLOOR((SELECT COUNT(*) FROM g) / 3)) FROM bands)
         + (SELECT COUNT(*) FROM bands AS a JOIN bands AS b ON b.size_band = a.size_band + 1 WHERE a.hi > b.lo)
    UNION ALL
    SELECT '08. Expected outcomes = segment x size cell means', 0,
           (SELECT COUNTIF(ABS(g.expected_revenue_12m - c.m_rev) > 0.01 OR ABS(g.expected_came_back - c.m_back) > 1e-12)
              FROM g JOIN cell_means AS c ON c.customer_segment = g.customer_segment AND c.size_band = g.size_band)
    UNION ALL
    SELECT '09. 1,001 label sets, each keeping every category''s customer count', 0,
           ABS((permutations + 1) - (SELECT COUNT(DISTINCT b) FROM ps))
         + (SELECT COUNT(*) FROM ps JOIN real_counts AS r USING (gateway_category) WHERE ps.n != r.n)
         + (SELECT COUNTIF(k != (SELECT COUNT(*) FROM real_counts)) FROM (SELECT b, COUNT(*) AS k FROM ps GROUP BY b))
    UNION ALL
    SELECT '10. Real-label residuals (b = 0) = direct recount', 0,
           (SELECT COUNTIF(ABS(p.resid_came_back - r.r_back) > 1e-9 OR ABS(p.resid_revenue - r.r_rev) > 0.01)
              FROM ps AS p JOIN real_counts AS r USING (gateway_category) WHERE p.b = 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
