/* =============================================================================
   Case study · Gross margin bridge — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE current_start DATE DEFAULT DATE '2025-10-01';
DECLARE prior_start   DATE DEFAULT DATE '2024-10-01';
DECLARE period_end    DATE DEFAULT DATE '2026-09-30';

WITH c AS (SELECT * FROM `sahyadri_b2b.margin_bridge_cells`),
     b AS (SELECT * FROM `sahyadri_b2b.margin_bridge`),

source_lines AS (
    SELECT o.order_date, p.unit_cost, i.quantity,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS net
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN prior_start AND period_end
),

checks AS (
    SELECT '01. Duplicate product-segment cells' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(product_id AS STRING), '|', customer_segment)) FROM c) AS actual
    UNION ALL
    SELECT '02. Net revenue vs source costed lines (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(net0 + net1) FROM c) - (SELECT SUM(net) FROM source_lines WHERE unit_cost IS NOT NULL), 0) AS INT64)
    UNION ALL
    SELECT '03. Current margin vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(margin1) FROM c)
                    - (SELECT SUM(net - quantity * unit_cost) FROM source_lines
                        WHERE unit_cost IS NOT NULL AND order_date >= current_start), 0) AS INT64)
    UNION ALL
    SELECT '04. Bridge: prior + effects = current (rupees, rounded)', 0,
           CAST(ROUND((SELECT margin_prior + volume + mix + price + discount + new_cells + lost_cells - margin_current FROM b), 0) AS INT64)
    UNION ALL
    SELECT '05. Cell status inconsistent with quantities', 0,
           (SELECT COUNTIF((cell_status = 'Continuing' AND (q0 = 0 OR q1 = 0))
                        OR (cell_status = 'New' AND (q0 != 0 OR q1 = 0))
                        OR (cell_status = 'Lost' AND (q1 != 0 OR q0 = 0))) FROM c)
    UNION ALL
    SELECT '06. Price x (1 - discount) x units != net revenue', 0,
           (SELECT COUNTIF((q0 > 0 AND ABS(q0 * p0 * (1 - d0) - net0) > 0.01)
                        OR (q1 > 0 AND ABS(q1 * p1 * (1 - d1) - net1) > 0.01)) FROM c)
    UNION ALL
    SELECT '07. Continuing-cell effects explain the continuing-cell margin change', 0,
           CAST(ROUND((SELECT SUM(margin1 - margin0) FROM c WHERE cell_status = 'Continuing')
                    - (SELECT volume + mix + price + discount FROM b), 0) AS INT64)
    UNION ALL
    SELECT '08. Volume + mix = sum of (q1 - q0) x prior unit margin (rupees, rounded)', 0,
           CAST(ROUND((SELECT volume + mix FROM b)
                    - (SELECT SUM((q1 - q0) * (p0 * (1 - d0) - unit_cost)) FROM c WHERE cell_status = 'Continuing'), 0) AS INT64)
    UNION ALL
    SELECT '09. Category price and discount effects add up to the bridge (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(x.price_cat + x.discount_cat) FROM (
                         SELECT category_name,
                                SUM(q1 * (p1 - p0) * (1 - d0)) AS price_cat,
                                SUM(q1 * p1 * (d0 - d1))       AS discount_cat
                         FROM c WHERE cell_status = 'Continuing' GROUP BY category_name) AS x)
                    - (SELECT price + discount FROM b), 0) AS INT64)
    UNION ALL
    SELECT '10. Prior margin vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT margin_prior FROM b)
                    - (SELECT SUM(net - quantity * unit_cost) FROM source_lines
                        WHERE unit_cost IS NOT NULL AND order_date < current_start), 0) AS INT64)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
