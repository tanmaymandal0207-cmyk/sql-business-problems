/* =============================================================================
   Case study · Category breadth and retention — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE last_base_half INT64 DEFAULT 3;

WITH p AS (SELECT * FROM `sahyadri_b2b.breadth_panel`),
     w AS (SELECT * FROM `sahyadri_b2b.breadth_within_band`),

source_lines AS (
    SELECT o.customer_id, o.order_id, p.category_id,
           (EXTRACT(YEAR FROM o.order_date) - 2024) * 2 + IF(EXTRACT(MONTH FROM o.order_date) > 6, 1, 0) AS half_index,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
source_halves AS (
    SELECT customer_id, half_index, COUNT(DISTINCT category_id) AS categories, SUM(revenue) AS revenue
    FROM source_lines GROUP BY customer_id, half_index
),

checks AS (
    SELECT '01. Duplicate customer-half rows' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(half_index AS STRING))) FROM p) AS actual
    UNION ALL
    SELECT '02. Base revenue vs source, halves 0-3 (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM p)
                    - (SELECT SUM(revenue) FROM source_lines WHERE half_index <= last_base_half), 0) AS INT64)
    UNION ALL
    SELECT '03. Retained flag vs independent recount', 0,
           (SELECT COUNTIF(p.retained != (s.customer_id IS NOT NULL)) FROM p
              LEFT JOIN source_halves AS s ON s.customer_id = p.customer_id AND s.half_index = p.half_index + 1)
    UNION ALL
    SELECT '04. Next-half revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(next_revenue) FROM p)
                    - (SELECT SUM(s.revenue) FROM source_halves AS s
                        JOIN source_halves AS b ON b.customer_id = s.customer_id AND b.half_index = s.half_index - 1
                       WHERE b.half_index <= last_base_half), 0) AS INT64)
    UNION ALL
    SELECT '05. Categories vs source recount', 0,
           (SELECT COUNTIF(p.categories != s.categories) FROM p
              JOIN source_halves AS s USING (customer_id, half_index))
    UNION ALL
    SELECT '06. Frequency band inconsistent with orders', 0,
           (SELECT COUNTIF(frequency_band != CASE WHEN orders = 1 THEN '1. One order'
                                                  WHEN orders = 2 THEN '2. Two orders'
                                                  WHEN orders <= 4 THEN '3. 3-4 orders'
                                                  WHEN orders <= 8 THEN '4. 5-8 orders'
                                                  ELSE '5. 9+ orders' END) FROM p)
    UNION ALL
    SELECT '07. Breadth group inconsistent with band median', 0,
           (SELECT COUNTIF(breadth_group != IF(categories > median_categories, 'Broad', 'Narrow')) FROM p)
    UNION ALL
    SELECT '08. Within-band counts vs panel rows', 0,
           (SELECT SUM(broad_n + narrow_n) FROM w) - (SELECT COUNT(*) FROM p)
    UNION ALL
    SELECT '09. Within-band retention vs panel recount', 0,
           (SELECT COUNTIF(ABS(IFNULL(w.narrow_retention, -1) - IFNULL(x.r, -1)) > 1e-12) FROM w
              JOIN (SELECT frequency_band, AVG(IF(retained, 1, 0)) AS r FROM p WHERE breadth_group = 'Narrow' GROUP BY frequency_band) AS x
             USING (frequency_band))
    UNION ALL
    SELECT '10. Base halves present: exactly 0-3', 0,
           ABS((SELECT COUNT(DISTINCT half_index) FROM p) - 4)
         + (SELECT COUNTIF(half_index < 0 OR half_index > last_base_half) FROM p)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
