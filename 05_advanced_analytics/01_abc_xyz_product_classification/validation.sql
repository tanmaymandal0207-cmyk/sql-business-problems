/* =============================================================================
   Case study · ABC-XYZ product classification — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start DATE DEFAULT DATE '2025-10-01';
DECLARE period_end   DATE DEFAULT DATE '2026-09-01';

WITH a AS (
    SELECT * FROM `sahyadri_b2b.product_abc_xyz`
),

source_lines AS (
    SELECT i.product_id, i.quantity,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND DATE_TRUNC(o.order_date, MONTH) BETWEEN period_start AND period_end
),

class_bounds AS (
    SELECT abc_class, MIN(revenue_12m) AS min_rev, MAX(revenue_12m) AS max_rev,
           MAX(cumulative_revenue_pct) AS max_cum_pct
    FROM a GROUP BY abc_class
),

checks AS (
    SELECT '01. Rows minus distinct products' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT product_id) FROM a) AS actual
    UNION ALL
    SELECT '02. Table rows vs products master', 0,
           (SELECT COUNT(*) FROM a) - (SELECT COUNT(*) FROM `sahyadri_b2b.products`)
    UNION ALL
    -- revenue is rounded per product: allow ₹0.005 per product
    SELECT '03. Revenue vs source lines in period outside rounding (1 = yes)', 0,
           IF(ABS((SELECT SUM(revenue_12m) FROM a) - (SELECT SUM(revenue) FROM source_lines))
              > 0.005 * (SELECT COUNT(*) FROM a), 1, 0)
    UNION ALL
    SELECT '04. Quantity vs source lines in period', 0,
           (SELECT SUM(quantity_12m) FROM a) - (SELECT SUM(quantity) FROM source_lines)
    UNION ALL
    SELECT '05. A/B/C classes overlap in revenue (1 = yes)', 0,
           IF((SELECT min_rev FROM class_bounds WHERE abc_class = 'A')
                < (SELECT max_rev FROM class_bounds WHERE abc_class = 'B')
           OR (SELECT min_rev FROM class_bounds WHERE abc_class = 'B')
                < (SELECT max_rev FROM class_bounds WHERE abc_class = 'C'), 1, 0)
    UNION ALL
    SELECT '06. A class does not reach 80 % or B does not reach 95 % (1 = yes)', 0,
           IF((SELECT max_cum_pct FROM class_bounds WHERE abc_class = 'A') < 80
           OR (SELECT max_cum_pct FROM class_bounds WHERE abc_class = 'B') < 95, 1, 0)
    UNION ALL
    SELECT '07. XYZ class inconsistent with CV thresholds', 0,
           (SELECT COUNTIF(
                (xyz_class = 'X' AND demand_cv > 0.5)
             OR (xyz_class = 'Y' AND (demand_cv <= 0.5 OR demand_cv > 1.0))
             OR (xyz_class = 'Z' AND demand_cv <= 1.0))
            FROM a)
    UNION ALL
    SELECT '08. N class inconsistent with zero demand', 0,
           (SELECT COUNTIF((abc_class = 'N') <> (quantity_12m = 0)) FROM a)
    UNION ALL
    SELECT '09. Months with demand outside 0-12', 0,
           (SELECT COUNTIF(months_with_demand < 0 OR months_with_demand > 12) FROM a)
    UNION ALL
    SELECT '10. Products without a stocking policy', 0,
           (SELECT COUNTIF(stocking_policy IS NULL) FROM a)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
