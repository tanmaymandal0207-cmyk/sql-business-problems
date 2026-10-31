/* =============================================================================
   Case study · Order frequency vs order size — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of        DATE  DEFAULT DATE '2026-09-30';
DECLARE min_orders   INT64 DEFAULT 6;
DECLARE min_span     INT64 DEFAULT 90;
DECLARE permutations INT64 DEFAULT 500;

WITH o AS (SELECT * FROM `sahyadri_b2b.fs_orders`),
     c AS (SELECT * FROM `sahyadri_b2b.fs_customers`),
     p AS (SELECT * FROM `sahyadri_b2b.fs_permutation_slopes`),

src AS (
    SELECT x.order_id, x.customer_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY x.order_id, x.customer_id
),
src_customers AS (
    SELECT customer_id, COUNT(*) AS n FROM src GROUP BY customer_id HAVING COUNT(*) >= min_orders
),
prev AS (
    SELECT a.order_id, MAX(b.order_date) AS prev_date
    FROM o AS a
    JOIN o AS b ON b.customer_id = a.customer_id
               AND (b.order_date < a.order_date OR (b.order_date = a.order_date AND b.order_id < a.order_id))
    GROUP BY a.order_id
),
-- observed within-customer slope recomputed with REGR-free sums
direct AS (
    SELECT SUM(x * y) / SUM(x * x) AS slope
    FROM (
        SELECT LN(1 + gap_days) - AVG(LN(1 + gap_days)) OVER (PARTITION BY customer_id) AS x,
               ln_value - AVG(ln_value) OVER (PARTITION BY customer_id) AS y
        FROM o WHERE gap_days IS NOT NULL
    )
),

checks AS (
    SELECT '01. Orders of every customer with 6+ valid orders, value = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT SUM(n) FROM src_customers))
         + (SELECT COUNTIF(ABS(o.order_value - s.v) > 0.01) FROM o JOIN src AS s USING (order_id)) AS actual
    UNION ALL
    SELECT '02. Gap = days since the previous order, empty only for the first', 0,
           (SELECT COUNTIF(o.gap_days IS NULL AND o.seq != 1) + COUNTIF(o.gap_days IS NOT NULL AND o.seq = 1) FROM o)
         + (SELECT COUNTIF(DATE_DIFF(o.order_date, pv.prev_date, DAY) != o.gap_days) FROM o JOIN prev AS pv USING (order_id))
    UNION ALL
    SELECT '03. Value vs own average sums to zero for every customer', 0,
           (SELECT COUNTIF(ABS(t) > 1e-9) FROM (SELECT customer_id, SUM(ln_value_vs_own_avg) AS t FROM o GROUP BY customer_id))
    UNION ALL
    SELECT '04. One row per customer, orders and revenue add up', 0,
           ABS((SELECT COUNT(*) FROM c) - (SELECT COUNT(*) FROM src_customers))
         + IF(ABS((SELECT SUM(revenue) FROM c) - (SELECT SUM(order_value) FROM o)) > 1, 1, 0)
         + ABS((SELECT SUM(orders) FROM c) - (SELECT COUNT(*) FROM o))
    UNION ALL
    SELECT '05. Ordering rate = orders x 365 / max(days since first order, 90)', 0,
           (SELECT COUNTIF(ABS(c.orders_per_year - c.orders * 365 / GREATEST(DATE_DIFF(as_of, f.d, DAY), min_span)) > 1e-9)
              FROM c JOIN (SELECT customer_id, MIN(order_date) AS d FROM o GROUP BY customer_id) AS f USING (customer_id))
    UNION ALL
    SELECT '06. Typical order value lies between the customer''s smallest and largest order', 0,
           (SELECT COUNTIF(c.typical_order_value < m.lo - 0.01 OR c.typical_order_value > m.hi + 0.01)
              FROM c JOIN (SELECT customer_id, MIN(order_value) AS lo, MAX(order_value) AS hi FROM o GROUP BY customer_id) AS m USING (customer_id))
    UNION ALL
    SELECT '07. 501 slope rows (real + 500 shuffles), each over the same orders', 0,
           ABS((permutations + 1) - (SELECT COUNT(*) FROM p))
         + (SELECT COUNTIF(orders != (SELECT COUNTIF(gap_days IS NOT NULL) FROM o)) FROM p)
    UNION ALL
    SELECT '08. Real slope (b = 0) = direct recount', 0,
           (SELECT IF(ABS(p.slope - d.slope) > 1e-12, 1, 0) FROM p CROSS JOIN direct AS d WHERE p.b = 0)
    UNION ALL
    SELECT '09. Shuffled slopes differ from the real one (the shuffles move values)', 0,
           IF((SELECT COUNTIF(ABS(slope - (SELECT slope FROM p WHERE b = 0)) < 1e-15) FROM p WHERE b > 0) > 5, 1, 0)
    UNION ALL
    SELECT '10. Segments add up to all customers', 0,
           ABS((SELECT COUNT(*) FROM c) - (SELECT SUM(n) FROM (SELECT customer_segment, COUNT(*) AS n FROM c GROUP BY customer_segment)))
         + (SELECT COUNTIF(customer_segment IS NULL) FROM c)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
