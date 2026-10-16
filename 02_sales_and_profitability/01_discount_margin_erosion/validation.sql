/* =============================================================================
   Case study · Discount and margin erosion — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

WITH m AS (
    SELECT * FROM `sahyadri_b2b.sales_line_margin`
),

source_lines AS (
    SELECT i.*
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o
        ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),

checks AS (
    SELECT '01. Rows minus distinct order lines' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_item_id) FROM m) AS actual
    UNION ALL
    SELECT '02. Table rows vs in-scope source lines', 0,
           (SELECT COUNT(*) FROM m) - (SELECT COUNT(*) FROM source_lines)
    UNION ALL
    SELECT '03. Gross value vs source (paise)', 0,
           CAST(ROUND((SELECT SUM(gross_value) FROM m)
                    - (SELECT SUM(quantity * unit_price) FROM source_lines), 2) * 100 AS INT64)
    UNION ALL
    SELECT '04. Gross - discount <> net revenue (rows)', 0,
           (SELECT COUNTIF(ABS(gross_value - discount_amount - net_revenue) > 0.001) FROM m)
    UNION ALL
    SELECT '05. Lines missing a category or segment', 0,
           (SELECT COUNTIF(category_name IS NULL OR customer_segment IS NULL) FROM m)
    UNION ALL
    SELECT '06. Discount outside 0-100 %', 0,
           (SELECT COUNTIF(discount_percent < 0 OR discount_percent > 100) FROM m)
    UNION ALL
    SELECT '07. Cost-known flag inconsistent with line cost', 0,
           (SELECT COUNTIF(cost_known <> (line_cost IS NOT NULL)) FROM m)
    UNION ALL
    SELECT '08. Lines without cost vs products without cost', 0,
           (SELECT COUNTIF(NOT cost_known) FROM m)
         - (SELECT COUNT(*) FROM source_lines AS s
              JOIN `sahyadri_b2b.products` AS p ON p.product_id = s.product_id
             WHERE p.unit_cost IS NULL)
    UNION ALL
    SELECT '09. Discount band revenue vs total (paise)', 0,
           CAST(ROUND((SELECT SUM(b) FROM (SELECT SUM(net_revenue) AS b FROM m GROUP BY discount_band))
                    - (SELECT SUM(net_revenue) FROM m), 2) * 100 AS INT64)
    UNION ALL
    SELECT '10. Lines in an unexpected discount band', 0,
           (SELECT COUNTIF(
                (discount_band = '1. No discount'      AND discount_percent <> 0)
             OR (discount_band = '2. Up to 5%'         AND (discount_percent <= 0  OR discount_percent > 5))
             OR (discount_band = '3. Above 5% to 10%'  AND (discount_percent <= 5  OR discount_percent > 10))
             OR (discount_band = '4. Above 10% to 15%' AND (discount_percent <= 10 OR discount_percent > 15))
             OR (discount_band = '5. Above 15%'        AND discount_percent <= 15))
            FROM m)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
