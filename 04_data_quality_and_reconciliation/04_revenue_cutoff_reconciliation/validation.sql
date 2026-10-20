/* =============================================================================
   Case study · Revenue cut-off reconciliation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE as_of_date DATE DEFAULT DATE '2026-09-30';

WITH r AS (
    SELECT * FROM `sahyadri_b2b.revenue_recognition_basis`
),
basis AS (
    SELECT * FROM r WHERE recognition_status <> 'Delivered - no delivery date'
),

-- exposure at a given date = ordered on or before it, delivered after it (or not yet)
exposure AS (
    SELECT
        SUM(IF(order_date <= DATE '2025-03-31'
               AND (delivery_date > DATE '2025-03-31' OR delivery_date IS NULL), revenue, 0)) AS mar_2025,
        SUM(IF(order_date <= DATE '2026-03-31'
               AND (delivery_date > DATE '2026-03-31' OR delivery_date IS NULL), revenue, 0)) AS mar_2026,
        SUM(IF(order_date <= as_of_date
               AND (delivery_date > as_of_date OR delivery_date IS NULL), revenue, 0))        AS as_of
    FROM basis
),

fy_2025_26 AS (
    SELECT
        SUM(IF(order_date    BETWEEN DATE '2025-04-01' AND DATE '2026-03-31', revenue, 0))
      - SUM(IF(delivery_date BETWEEN DATE '2025-04-01' AND DATE '2026-03-31', revenue, 0)) AS cutoff_difference
    FROM basis
),

checks AS (
    SELECT '01. Rows minus distinct orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM r) AS actual
    UNION ALL
    SELECT '02. Rows vs in-scope orders in source', 0,
           (SELECT COUNT(*) FROM r)
         - (SELECT COUNT(*) FROM `sahyadri_b2b.sales_orders` WHERE order_status NOT IN ('Cancelled', 'Returned'))
    UNION ALL
    SELECT '03. Revenue vs in-scope line items (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM r)
                    - (SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))
                         FROM `sahyadri_b2b.sales_order_items` AS i
                         JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
                        WHERE o.order_status NOT IN ('Cancelled', 'Returned')), 0) AS INT64)
    UNION ALL
    -- every rupee booked on order basis is either recognised on delivery basis or still open
    SELECT '04. Order basis vs delivery basis + open (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM basis)
                    - (SELECT SUM(revenue) FROM basis WHERE delivery_date IS NOT NULL)
                    - (SELECT SUM(revenue) FROM basis WHERE recognition_status = 'Not yet delivered'), 0) AS INT64)
    UNION ALL
    -- financial-year cut-off difference = closing exposure - opening exposure
    SELECT '05. FY2025-26 difference vs change in March exposure (rupees, rounded)', 0,
           CAST(ROUND((SELECT cutoff_difference FROM fy_2025_26)
                    - (SELECT mar_2026 - mar_2025 FROM exposure), 0) AS INT64)
    UNION ALL
    SELECT '06. Exposure at as-of date vs not-yet-delivered revenue (rupees, rounded)', 0,
           CAST(ROUND((SELECT as_of FROM exposure)
                    - (SELECT SUM(revenue) FROM basis WHERE recognition_status = 'Not yet delivered'), 0) AS INT64)
    UNION ALL
    SELECT '07. Delivered rows without a delivery date in the comparison', 0,
           (SELECT COUNTIF(recognition_status = 'Delivered' AND delivery_date IS NULL) FROM r)
    UNION ALL
    SELECT '08. Not-yet-delivered rows with a delivery date', 0,
           (SELECT COUNTIF(recognition_status = 'Not yet delivered' AND delivery_date IS NOT NULL) FROM r)
    UNION ALL
    SELECT '09. Delivery dates after the as-of date', 0,
           (SELECT COUNTIF(delivery_date > as_of_date) FROM r)
    UNION ALL
    SELECT '10. Delivery dates before the order date', 0,
           (SELECT COUNTIF(delivery_date < order_date) FROM r)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
