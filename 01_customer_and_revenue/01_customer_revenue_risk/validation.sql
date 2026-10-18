/* =============================================================================
   Case study 01 · Customer revenue risk — validation checks (version 1)
   Dialect : Google BigQuery Standard SQL
   Self-contained: recomputes the version 1 revenue logic, so it can be run on
   its own, before or after analysis.sql. Every row should return status = 'PASS'.

   Checks 01–06 test structure and reconciliation.
   Checks 07–10 confirm that the dataset still matches the figures documented in
   README.md (sections 7 and 10). A FAIL there means the data has changed and the
   documented numbers must be re-confirmed, not that the query is wrong.
   ============================================================================= */

WITH items AS (
    SELECT * FROM `sahyadri_b2b.sales_order_items`
),

orders AS (
    SELECT * FROM `sahyadri_b2b.sales_orders`
),

-- version 1 revenue formula, unchanged: NULL discount lines drop out of SUM()
order_level AS (
    SELECT
        o.customer_id,
        o.order_id,
        SUM(i.quantity * i.unit_price * (1 - i.discount_percent / 100)) AS net_sales
    FROM items AS i
    JOIN orders AS o
        ON o.order_id = i.order_id
    GROUP BY o.customer_id, o.order_id
),

customer_level AS (
    SELECT
        customer_id,
        COUNT(order_id)                       AS total_orders,
        SUM(net_sales)                        AS net_sales,
        MAX(net_sales)                        AS largest_order,
        SAFE_DIVIDE(MAX(net_sales), SUM(net_sales)) * 100 AS largest_order_pct
    FROM order_level
    GROUP BY customer_id
),

company AS (
    SELECT SUM(quantity * unit_price * (1 - discount_percent / 100)) AS company_sales
    FROM items
),

checks AS (
    SELECT '01. Duplicate order_id in sales_orders' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM orders) AS actual
    UNION ALL
    SELECT '02. Line items with no matching order header', 0,
           (SELECT COUNT(*) FROM items AS i
              LEFT JOIN orders AS o ON o.order_id = i.order_id
             WHERE o.order_id IS NULL)
    UNION ALL
    SELECT '03. Order rows after join vs distinct ordered orders', 0,
           (SELECT COUNT(*) FROM order_level) - (SELECT COUNT(DISTINCT order_id) FROM items)
    UNION ALL
    -- customer revenue must reconcile to company revenue (allow ₹0.01 for float rounding)
    SELECT '04. Customer revenue vs company revenue outside ₹0.01 (1 = yes)', 0,
           IF(ABS((SELECT SUM(net_sales) FROM customer_level)
                  - (SELECT company_sales FROM company)) > 0.01, 1, 0)
    UNION ALL
    SELECT '05. Largest-order share outside 0–100 %', 0,
           (SELECT COUNTIF(largest_order_pct < 0 OR largest_order_pct > 100.0001)
              FROM customer_level)
    UNION ALL
    SELECT '06. Line items with NULL or non-positive quantity or price', 0,
           (SELECT COUNTIF(quantity IS NULL OR quantity <= 0
                           OR unit_price IS NULL OR unit_price < 0)
              FROM items)
    UNION ALL
    -- documented figures (README section 7 and 10)
    SELECT '07. Customers in result (5+ orders) — documented 305', 305,
           (SELECT COUNTIF(total_orders >= 5) FROM customer_level)
    UNION ALL
    SELECT '08. Line items with NULL discount_percent — documented 336', 336,
           (SELECT COUNTIF(discount_percent IS NULL) FROM items)
    UNION ALL
    SELECT '09. Cancelled orders included in v1 — documented 534', 534,
           (SELECT COUNTIF(order_status = 'Cancelled') FROM orders)
    UNION ALL
    SELECT '10. Returned orders included in v1 — documented 75', 75,
           (SELECT COUNTIF(order_status = 'Returned') FROM orders)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;

/* -----------------------------------------------------------------------------
   Reference figures for the version 1 reconciliation (README section 7):
   company net sales ₹95,18,90,079.55 · rank 1 customer 1042, ₹7,04,11,352.22.
   Revenue bridge by order status, for the version 2 scope change:

SELECT
    o.order_status,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)), 2)
        AS net_sales_null_discount_as_zero
FROM `sahyadri_b2b.sales_order_items` AS i
JOIN `sahyadri_b2b.sales_orders` AS o
    ON o.order_id = i.order_id
GROUP BY o.order_status
ORDER BY net_sales_null_discount_as_zero DESC;
----------------------------------------------------------------------------- */
