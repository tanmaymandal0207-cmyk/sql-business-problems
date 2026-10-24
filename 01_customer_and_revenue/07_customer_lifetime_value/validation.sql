/* =============================================================================
   Case study · Customer lifetime value — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE p1_start      DATE    DEFAULT DATE '2024-10-01';
DECLARE p1_end        DATE    DEFAULT DATE '2025-09-30';
DECLARE p2_start      DATE    DEFAULT DATE '2025-10-01';
DECLARE p2_end        DATE    DEFAULT DATE '2026-09-30';
DECLARE discount_rate FLOAT64 DEFAULT 0.12;
DECLARE horizon_years INT64   DEFAULT 5;

WITH v AS (SELECT * FROM `sahyadri_b2b.customer_lifetime_value`),
     r AS (SELECT * FROM `sahyadri_b2b.clv_retention_bands`),

p2_lines AS (
    SELECT o.customer_id,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN p2_start AND p2_end
),
p1_customers AS (
    SELECT DISTINCT customer_id FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned') AND order_date BETWEEN p1_start AND p1_end
),
-- annuity factor recomputed by summing the five discounted terms one by one
explicit_factor AS (
    SELECT frequency_band,
           SUM(POW(retention_rate / (1 + discount_rate), t)) AS factor
    FROM r CROSS JOIN UNNEST(GENERATE_ARRAY(1, horizon_years)) AS t
    GROUP BY frequency_band
),

checks AS (
    SELECT '01. Duplicate customers' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM v) AS actual
    UNION ALL
    SELECT '02. Customers vs active customers in the last 12 months', 0,
           (SELECT COUNT(*) FROM v) - (SELECT COUNT(DISTINCT customer_id) FROM p2_lines)
    UNION ALL
    SELECT '03. Revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM v) - (SELECT SUM(revenue) FROM p2_lines), 0) AS INT64)
    UNION ALL
    SELECT '04. Retention bands vs customers active in the first year', 0,
           (SELECT SUM(customers) FROM r) - (SELECT COUNT(*) FROM p1_customers)
    UNION ALL
    SELECT '05. Smoothed rate not equal to (retained + 1) / (customers + 2)', 0,
           (SELECT COUNTIF(ABS(retention_rate - (retained + 1) / (customers + 2)) > 1e-12) FROM r)
    UNION ALL
    SELECT '06. Interval does not contain the rate, or falls outside 0-1', 0,
           (SELECT COUNTIF(retention_low > retention_rate OR retention_high < retention_rate
                           OR retention_low < 0 OR retention_high > 1) FROM r)
    UNION ALL
    SELECT '07. Closed-form CLV multiple vs explicit sum of 5 terms', 0,
           (SELECT COUNTIF(ABS(v.clv_multiple - ROUND(e.factor, 4)) > 0.0001)
              FROM v JOIN explicit_factor AS e ON e.frequency_band = v.frequency_band)
    UNION ALL
    SELECT '08. CLV not equal to margin x multiple (within rounding)', 0,
           (SELECT COUNTIF(ABS(clv - annual_margin * clv_multiple) > 0.0001 * ABS(annual_margin) + 0.01) FROM v)
    UNION ALL
    SELECT '09. CLV outside its low-high range', 0,
           (SELECT COUNTIF(annual_margin >= 0 AND (clv < clv_low - 0.01 OR clv > clv_high + 0.01)) FROM v)
    UNION ALL
    SELECT '10. Frequency band inconsistent with orders', 0,
           (SELECT COUNTIF((frequency_band = '1 order'    AND orders_12m <> 1)
                        OR (frequency_band = '2-5 orders' AND (orders_12m < 2 OR orders_12m > 5))
                        OR (frequency_band = '6+ orders'  AND orders_12m < 6)) FROM v)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
