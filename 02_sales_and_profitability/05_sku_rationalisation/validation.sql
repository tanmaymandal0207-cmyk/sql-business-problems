/* =============================================================================
   Case study · SKU rationalisation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE low_margin   FLOAT64 DEFAULT 0.10;

WITH s AS (SELECT * FROM `sahyadri_b2b.sku_profitability`),

lines AS (
    SELECT
        i.product_id,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue,
        i.quantity * p.unit_cost                                              AS cost
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id   = i.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN window_start AND window_end
),
class_shares AS (
    SELECT
        SUM(IF(is_gp_core, gross_profit, 0)) / SUM(gross_profit)                              AS core_gp_share,
        (SUM(IF(is_gp_core, gross_profit, 0))
         - MIN(IF(is_gp_core, gross_profit, NULL))) / SUM(gross_profit)                       AS core_gp_share_without_last,
        (SELECT SUM(IF(revenue_class = 'A', revenue, 0)) / SUM(revenue) FROM s)               AS a_revenue_share,
        (SELECT (SUM(IF(revenue_class = 'A', revenue, 0)) - MIN(IF(revenue_class = 'A', revenue, NULL)))
                / SUM(revenue) FROM s)                                                         AS a_revenue_share_without_last,
        (SELECT SUM(IF(revenue_class = 'C', revenue, 0)) / SUM(revenue) FROM s)               AS c_revenue_share
    FROM s
    WHERE gross_profit IS NOT NULL AND revenue > 0
),

checks AS (
    SELECT '01. Duplicate products' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT product_id) FROM s) AS actual
    UNION ALL
    SELECT '02. Rows vs product master', 0,
           (SELECT COUNT(*) FROM s) - (SELECT COUNT(*) FROM `sahyadri_b2b.products`)
    UNION ALL
    SELECT '03. Revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM s) - (SELECT SUM(revenue) FROM lines), 0) AS INT64)
    UNION ALL
    SELECT '04. Gross profit vs independent recount (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(gross_profit) FROM s)
                    - (SELECT SUM(revenue - cost) FROM lines WHERE cost IS NOT NULL), 0) AS INT64)
    UNION ALL
    -- GP core must reach 80 % of GP, and would not without its smallest member
    SELECT '05. GP core is the minimum set reaching 80 % of GP', 0,
           (SELECT IF(core_gp_share >= 0.80 AND core_gp_share_without_last < 0.80, 0, 1) FROM class_shares)
    UNION ALL
    SELECT '06. Revenue classes: A is the minimum set to 80 %, C at most 5 %', 0,
           (SELECT IF(a_revenue_share >= 0.80 AND a_revenue_share_without_last < 0.80
                      AND c_revenue_share <= 0.05, 0, 1) FROM class_shares)
    UNION ALL
    SELECT '07. Revenue class present exactly for products with sales', 0,
           (SELECT COUNTIF((revenue_class IS NOT NULL) <> (revenue > 0)) FROM s)
    UNION ALL
    SELECT '08. Action inconsistent with its rule', 0,
           (SELECT COUNTIF(
                 (action = '1. Delist: no demand'            AND revenue <> 0)
              OR (action = '2. Fix cost data first'          AND (revenue = 0 OR gross_profit IS NOT NULL))
              OR (action = '3. Reprice or stop: loss-making' AND NOT gross_profit < 0)
              OR (action = '4. Delist review'                AND NOT (revenue_class = 'C' AND gp_margin < low_margin AND gross_profit >= 0))
              OR (action = '5. Reprice'                      AND NOT (revenue_class IN ('A', 'B') AND gp_margin < low_margin AND gross_profit >= 0))
              OR (action = '6. Protect'                      AND NOT (is_gp_core AND gp_margin >= low_margin))
              OR (action = '7. Maintain'                     AND NOT (NOT is_gp_core AND gp_margin >= low_margin)))
              FROM s)
    UNION ALL
    SELECT '09. No-demand products vs independent count', 0,
           (SELECT COUNTIF(action = '1. Delist: no demand') FROM s)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.products`
             WHERE product_id NOT IN (SELECT product_id FROM lines))
    UNION ALL
    SELECT '10. Products with no action', 0,
           (SELECT COUNTIF(action IS NULL) FROM s)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
