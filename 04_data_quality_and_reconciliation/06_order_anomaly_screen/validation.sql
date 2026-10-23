/* =============================================================================
   Case study · Order anomaly screen — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start    DATE    DEFAULT DATE '2024-01-01';
DECLARE period_end      DATE    DEFAULT DATE '2026-09-30';
DECLARE qty_multiple    FLOAT64 DEFAULT 10;
DECLARE price_tolerance FLOAT64 DEFAULT 0.10;
DECLARE min_history     INT64   DEFAULT 20;

WITH a AS (SELECT * FROM `sahyadri_b2b.order_line_anomalies`),
     r AS (SELECT * FROM `sahyadri_b2b.order_anomaly_review`),

src_orders AS (
    SELECT * FROM `sahyadri_b2b.sales_orders` WHERE order_date BETWEEN period_start AND period_end
),
src_lines AS (
    SELECT i.* FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN src_orders AS o ON o.order_id = i.order_id
),
product_lines AS (
    SELECT product_id, COUNT(*) AS n FROM src_lines GROUP BY product_id
),
-- median property: at least half the product's lines on each side of the median
median_test AS (
    SELECT
        product_id,
        COUNT(*)                                     AS n,
        COUNTIF(quantity <= product_median_qty)      AS at_or_below,
        COUNTIF(quantity >= product_median_qty)      AS at_or_above
    FROM a
    GROUP BY product_id
),
order_gross AS (
    SELECT order_id, SUM(quantity * unit_price) AS g FROM src_lines GROUP BY order_id
),
line_flags AS (
    SELECT order_id,
           COUNTIF(flag_q1_product_qty OR flag_q2_customer_qty OR flag_p1_price OR flag_v1_order_value) AS flagged_lines
    FROM a GROUP BY order_id
),

checks AS (
    SELECT '01. Duplicate order lines' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_item_id) FROM a) AS actual
    UNION ALL
    SELECT '02. Lines vs source lines in the period', 0,
           (SELECT COUNT(*) FROM a) - (SELECT COUNT(*) FROM src_lines)
    UNION ALL
    SELECT '03. Review orders vs source orders (and no duplicates)', 0,
           (SELECT COUNT(*) FROM r) - (SELECT COUNT(*) FROM src_orders)
         + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM r)
    UNION ALL
    SELECT '04. Product median fails the median property', 0,
           (SELECT COUNTIF(at_or_below < n / 2 OR at_or_above < n / 2) FROM median_test)
    UNION ALL
    SELECT '05. Q1 flag inconsistent with its rule', 0,
           (SELECT COUNTIF(a.flag_q1_product_qty <> (p.n >= min_history AND a.quantity >= qty_multiple * a.product_median_qty))
              FROM a JOIN product_lines AS p ON p.product_id = a.product_id)
    UNION ALL
    SELECT '06. P1 flag inconsistent with its rule', 0,
           (SELECT COUNTIF(flag_p1_price <> (ABS(unit_price - quarter_median_price) > price_tolerance * quarter_median_price + 0.01)
                           AND ABS(ABS(unit_price - quarter_median_price) - price_tolerance * quarter_median_price) > 0.01) FROM a)
    UNION ALL
    SELECT '07. Order gross vs source (orders differing by more than 1 paisa)', 0,
           (SELECT COUNT(DISTINCT a.order_id) FROM a JOIN order_gross AS g ON g.order_id = a.order_id
             WHERE ABS(a.order_gross - g.g) > 0.01)
    UNION ALL
    SELECT '08. Order flagged without a flagged line, or the reverse', 0,
           (SELECT COUNTIF(r.is_flagged <> (l.flagged_lines > 0)) FROM r JOIN line_flags AS l ON l.order_id = r.order_id)
    UNION ALL
    SELECT '09. Outcome inconsistent with status and payment', 0,
           (SELECT COUNTIF(
                 (outcome LIKE '2.%' AND order_status NOT IN ('Cancelled', 'Returned'))
              OR (outcome LIKE '4.%' AND order_status NOT IN ('Pending', 'Processing', 'Shipped'))
              OR (outcome LIKE '1.%' AND (order_status <> 'Delivered' OR amount_paid < order_value - 0.05))
              OR (outcome LIKE '3.%' AND (order_status <> 'Delivered' OR amount_paid >= order_value - 0.05))) FROM r)
    UNION ALL
    SELECT '10. Amount paid vs source payments (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(amount_paid) FROM r)
                    - (SELECT SUM(amount) FROM `sahyadri_b2b.payments`
                        WHERE order_id IN (SELECT order_id FROM src_orders)), 0) AS INT64)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
