/* =============================================================================
   Case study · Revenue growth bridge — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE py_start DATE DEFAULT DATE '2025-01-01';
DECLARE py_end   DATE DEFAULT DATE '2025-09-30';
DECLARE cy_start DATE DEFAULT DATE '2026-01-01';
DECLARE cy_end   DATE DEFAULT DATE '2026-09-30';

WITH l AS (
    SELECT * FROM `sahyadri_b2b.ytd_revenue_lines`
),

source_lines AS (
    SELECT i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND (o.order_date BETWEEN py_start AND py_end OR o.order_date BETWEEN cy_start AND cy_end)
),

total_change AS (
    SELECT SUM(IF(period = 'CY', revenue, -revenue)) AS change FROM l
),

customer_periods AS (
    SELECT customer_id,
           SUM(IF(period = 'PY', revenue, 0)) AS py,
           SUM(IF(period = 'CY', revenue, 0)) AS cy
    FROM l GROUP BY customer_id
),

orders_by_period AS (
    SELECT
        SUM(IF(period = 'PY', revenue, 0))               AS rev_py,
        SUM(IF(period = 'CY', revenue, 0))               AS rev_cy,
        COUNT(DISTINCT IF(period = 'PY', order_id, NULL)) AS ord_py,
        COUNT(DISTINCT IF(period = 'CY', order_id, NULL)) AS ord_cy
    FROM l
),

checks AS (
    SELECT '01. Table rows vs in-scope source lines' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM l) - (SELECT COUNT(*) FROM source_lines) AS actual
    UNION ALL
    SELECT '02. Revenue vs source (paise)', 0,
           CAST(ROUND((SELECT SUM(revenue) FROM l) - (SELECT SUM(revenue) FROM source_lines), 2) * 100 AS INT64)
    UNION ALL
    SELECT '03. Rows whose period label does not match the order date', 0,
           (SELECT COUNTIF(
                (period = 'PY' AND order_date NOT BETWEEN py_start AND py_end)
             OR (period = 'CY' AND order_date NOT BETWEEN cy_start AND cy_end)) FROM l)
    UNION ALL
    -- every customer's change, summed, equals the company change
    SELECT '04. Customer changes vs total change (paise)', 0,
           CAST(ROUND((SELECT SUM(cy - py) FROM customer_periods) - (SELECT change FROM total_change), 2) * 100 AS INT64)
    UNION ALL
    -- new + grew + declined + lost cover every customer exactly once
    SELECT '05. Customers not in exactly one bridge group', 0,
           (SELECT COUNT(*) FROM customer_periods)
         - (SELECT COUNTIF(py = 0 AND cy > 0) + COUNTIF(py > 0 AND cy > py)
                 + COUNTIF(py > 0 AND cy > 0 AND cy < py) + COUNTIF(py > 0 AND cy = 0)
                 + COUNTIF(py > 0 AND cy = py)
            FROM customer_periods)
    UNION ALL
    SELECT '06. Order-count + order-size parts vs total change (paise)', 0,
           CAST(ROUND((SELECT (ord_cy - ord_py) * (rev_py / ord_py)
                            + (rev_cy / ord_cy - rev_py / ord_py) * ord_cy
                       FROM orders_by_period)
                    - (SELECT change FROM total_change), 2) * 100 AS INT64)
    UNION ALL
    SELECT '07. Category changes vs total change (paise)', 0,
           CAST(ROUND((SELECT SUM(c) FROM (SELECT SUM(IF(period = 'CY', revenue, -revenue)) AS c
                                           FROM l GROUP BY category_name))
                    - (SELECT change FROM total_change), 2) * 100 AS INT64)
    UNION ALL
    SELECT '08. Segment changes vs total change (paise)', 0,
           CAST(ROUND((SELECT SUM(c) FROM (SELECT SUM(IF(period = 'CY', revenue, -revenue)) AS c
                                           FROM l GROUP BY customer_segment))
                    - (SELECT change FROM total_change), 2) * 100 AS INT64)
    UNION ALL
    SELECT '09. NULL or negative revenue lines', 0,
           (SELECT COUNTIF(revenue IS NULL OR revenue < 0) FROM l)
    UNION ALL
    SELECT '10. Lines missing a category or segment', 0,
           (SELECT COUNTIF(category_name IS NULL OR customer_segment IS NULL) FROM l)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
