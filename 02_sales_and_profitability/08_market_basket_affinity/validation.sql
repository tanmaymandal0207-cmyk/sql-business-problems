/* =============================================================================
   Case study · Market basket affinity — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start    DATE  DEFAULT DATE '2024-01-01';
DECLARE period_end      DATE  DEFAULT DATE '2026-09-30';
DECLARE min_pair_orders INT64 DEFAULT 15;

WITH bi AS (SELECT * FROM `sahyadri_b2b.basket_items`),
     r  AS (SELECT * FROM `sahyadri_b2b.basket_pair_results`),

in_scope_orders AS (
    SELECT order_id FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned') AND order_date BETWEEN period_start AND period_end
),
-- category co-occurrence recounted per order with conditional counts
order_categories AS (
    SELECT order_id, ARRAY_AGG(DISTINCT category_id) AS cats FROM bi GROUP BY order_id
),
category_recount AS (
    SELECT x.item_a, x.item_b,
           COUNTIF(x.item_a IN UNNEST(o.cats) AND x.item_b IN UNNEST(o.cats)) AS both_orders
    FROM (SELECT item_a, item_b FROM r WHERE level = 'Category') AS x
    CROSS JOIN order_categories AS o
    GROUP BY x.item_a, x.item_b
),
product_pairs_15 AS (
    SELECT x.product_id AS a, y.product_id AS b
    FROM (SELECT DISTINCT order_id, product_id FROM bi) AS x
    JOIN (SELECT DISTINCT order_id, product_id FROM bi) AS y
      ON y.order_id = x.order_id AND y.product_id > x.product_id
    GROUP BY x.product_id, y.product_id
    HAVING COUNT(*) >= min_pair_orders
),
-- chi-square recomputed as the sum of (observed - expected)^2 / expected over the 4 cells
chi_recount AS (
    SELECT level, item_a, item_b, chi_square,
           POW(a - ea, 2) / ea + POW(b - eb, 2) / eb + POW(c - ec, 2) / ec + POW(d - ed, 2) / ed AS chi_alt
    FROM (
        SELECT level, item_a, item_b, chi_square,
               both_orders AS a, orders_a - both_orders AS b, orders_b - both_orders AS c,
               total_orders - orders_a - orders_b + both_orders AS d,
               orders_a * orders_b / total_orders                                   AS ea,
               orders_a * (total_orders - orders_b) / total_orders                  AS eb,
               (total_orders - orders_a) * orders_b / total_orders                  AS ec,
               (total_orders - orders_a) * (total_orders - orders_b) / total_orders AS ed
        FROM r
    )
),

checks AS (
    SELECT '01. Basket orders vs in-scope orders' AS check_name, 0 AS expected,
           (SELECT COUNT(DISTINCT order_id) FROM bi) - (SELECT COUNT(*) FROM in_scope_orders) AS actual
    UNION ALL
    SELECT '02. Category pairs tested vs 10 x 9 / 2', 0,
           (SELECT COUNTIF(level = 'Category') FROM r) - 45
    UNION ALL
    SELECT '03. 2x2 tables with a negative cell', 0,
           (SELECT COUNTIF(orders_a - both_orders < 0 OR orders_b - both_orders < 0
                           OR total_orders - orders_a - orders_b + both_orders < 0) FROM r)
    UNION ALL
    SELECT '04. Category co-occurrence vs independent per-order recount', 0,
           (SELECT COUNT(*) FROM r JOIN category_recount AS c
              ON c.item_a = r.item_a AND c.item_b = r.item_b
             WHERE r.level = 'Category' AND r.both_orders <> c.both_orders)
    UNION ALL
    SELECT '05. Product pairs tested vs independent count of pairs with 15+ orders', 0,
           (SELECT COUNTIF(level = 'Product') FROM r) - (SELECT COUNT(*) FROM product_pairs_15)
    UNION ALL
    SELECT '06. Product pairs below the minimum co-occurrence', 0,
           (SELECT COUNTIF(level = 'Product' AND both_orders < min_pair_orders) FROM r)
    UNION ALL
    SELECT '07. Chi-square vs (O - E)^2 / E formula', 0,
           (SELECT COUNTIF(ABS(chi_square - chi_alt) > 1e-6 * GREATEST(chi_square, 1)) FROM chi_recount)
    UNION ALL
    SELECT '08. Significant or actionable flag inconsistent with its rule', 0,
           (SELECT COUNTIF(significant <> (chi_square >= chi_square_critical)
                        OR actionable <> (significant AND lift >= 1.5
                                          AND GREATEST(confidence_a_to_b, confidence_b_to_a) >= 0.10)) FROM r)
    UNION ALL
    SELECT '09. Confidence outside 0-1, or support above confidence', 0,
           (SELECT COUNTIF(confidence_a_to_b < 0 OR confidence_a_to_b > 1 OR confidence_b_to_a > 1
                           OR support > LEAST(confidence_a_to_b, confidence_b_to_a)) FROM r)
    UNION ALL
    SELECT '10. Lift not equal to confidence(A -> B) / support(B)', 0,
           (SELECT COUNTIF(ABS(lift - confidence_a_to_b / (orders_b / total_orders)) > 1e-9) FROM r)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
