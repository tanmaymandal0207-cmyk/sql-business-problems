/* =============================================================================
   Case study · Customer master de-duplication — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

WITH k AS (SELECT * FROM `sahyadri_b2b.customer_name_keys`),
     d AS (SELECT * FROM `sahyadri_b2b.customer_duplicate_candidates`),
     m AS (SELECT * FROM `sahyadri_b2b.customer_master_map`),

in_scope_revenue AS (
    SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS total
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),

checks AS (
    SELECT '01. Name-key rows vs customer master' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM k) - (SELECT COUNT(*) FROM `sahyadri_b2b.customers`) AS actual
    UNION ALL
    SELECT '02. Duplicate customer IDs in name-key table', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM k)
    UNION ALL
    SELECT '03. Empty or NULL normalised names', 0,
           (SELECT COUNTIF(normalised_name IS NULL OR normalised_name = '') FROM k)
    UNION ALL
    SELECT '04. Revenue vs in-scope line items (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM k) - (SELECT total FROM in_scope_revenue), 0) AS INT64)
    UNION ALL
    SELECT '05. Pairs that are self-matches or out of order', 0,
           (SELECT COUNTIF(customer_id_a >= customer_id_b) FROM d)
    UNION ALL
    -- recount pairs independently: for each name group of n records there are n(n-1)/2 pairs
    SELECT '06. Pair count vs independent recount', 0,
           (SELECT COUNT(*) FROM d)
         - (SELECT SUM(DIV(n * (n - 1), 2)) FROM (
                SELECT COUNT(*) AS n FROM k GROUP BY normalised_name HAVING COUNT(*) > 1))
    UNION ALL
    SELECT '07. Customers mapped as duplicate more than once', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT duplicate_customer_id) FROM m)
    UNION ALL
    SELECT '08. Master records that are also mapped as duplicates', 0,
           (SELECT COUNT(*) FROM m WHERE master_customer_id IN (SELECT duplicate_customer_id FROM m))
    UNION ALL
    SELECT '09. Mapping rows vs high-confidence pairs', 0,
           (SELECT COUNT(*) FROM m) - (SELECT COUNTIF(match_confidence = 'High') FROM d)
    UNION ALL
    SELECT '10. Masters with fewer orders than their duplicate', 0,
           (SELECT COUNTIF(master_orders < duplicate_orders) FROM m)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
