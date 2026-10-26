/* =============================================================================
   Case study · Does discount buy volume? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE min_purchases INT64 DEFAULT 3;

WITH l AS (SELECT * FROM `sahyadri_b2b.discount_response_lines`),
     e AS (SELECT * FROM `sahyadri_b2b.discount_response_estimates`),

source_lines AS (
    SELECT i.*, o.customer_id
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
-- pair-level sums for an algebraic recomputation of the fixed-effects slope:
-- b = SUM_pairs (Sxy - n*mx*my) / SUM_pairs (Sxx - n*mx^2)
pair_sums AS (
    SELECT customer_id, product_id, COUNT(*) AS n,
           SUM(discount_pct * ln_quantity) AS sxy, SUM(discount_pct * discount_pct) AS sxx,
           AVG(discount_pct) AS mx, AVG(ln_quantity) AS my, STDDEV_POP(discount_pct) AS sd
    FROM l
    GROUP BY customer_id, product_id
),
eligible_pairs AS (
    SELECT * FROM pair_sums WHERE n >= min_purchases AND sd > 0
),

checks AS (
    SELECT '01. Lines vs source valid order lines' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM l) - (SELECT COUNT(*) FROM source_lines)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_item_id) FROM l) AS actual
    UNION ALL
    SELECT '02. Pooled slope vs sums-of-squares recount', 0,
           (SELECT COUNTIF(ABS(e.slope - x.b) > 1e-9) FROM e
              CROSS JOIN (SELECT SUM((discount_pct - md) * (ln_quantity - my)) / SUM(POW(discount_pct - md, 2)) AS b
                          FROM l CROSS JOIN (SELECT AVG(discount_pct) AS md, AVG(ln_quantity) AS my FROM l)) AS x
             WHERE e.model LIKE 'A.%')
    UNION ALL
    SELECT '03. Fixed-effects slope vs pair-sum algebra', 0,
           (SELECT COUNTIF(ABS(e.slope - x.b) > 1e-9) FROM e
              CROSS JOIN (SELECT SUM(sxy - n * mx * my) / SUM(sxx - n * mx * mx) AS b FROM eligible_pairs) AS x
             WHERE e.model LIKE 'C.%')
    UNION ALL
    SELECT '04. Pair mean discount vs GROUP BY recount', 0,
           (SELECT COUNTIF(ABS(l.pair_mean_discount - p.mx) > 1e-9 OR l.pair_purchases != p.n)
              FROM l JOIN pair_sums AS p USING (customer_id, product_id))
    UNION ALL
    SELECT '05. Fixed-effects lines vs eligible-pair recount', 0,
           (SELECT lines FROM e WHERE model LIKE 'C.%') - (SELECT SUM(n) FROM eligible_pairs)
    UNION ALL
    SELECT '06. Fixed-effects pairs vs eligible-pair recount', 0,
           (SELECT pairs FROM e WHERE model LIKE 'C.%') - (SELECT COUNT(*) FROM eligible_pairs)
    UNION ALL
    SELECT '07. Non-positive quantities or wrong log', 0,
           (SELECT COUNTIF(quantity <= 0 OR ABS(ln_quantity - LN(quantity)) > 1e-12) FROM l)
    UNION ALL
    SELECT '08. Within-pair demeaned discount does not sum to zero', 0,
           (SELECT COUNTIF(ABS(s) > 1e-6) FROM (
               SELECT SUM(discount_pct - pair_mean_discount) AS s FROM l GROUP BY customer_id, product_id))
    UNION ALL
    SELECT '09. Discount outside 0-100 %', 0,
           (SELECT COUNTIF(discount_pct < 0 OR discount_pct > 100) FROM l)
    UNION ALL
    SELECT '10. NULL discounts set to 0 vs source NULL count', 0,
           (SELECT COUNTIF(discount_percent IS NULL) FROM source_lines)
         - (SELECT COUNT(*) FROM l JOIN source_lines AS s USING (order_item_id) WHERE s.discount_percent IS NULL AND l.discount_pct = 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
