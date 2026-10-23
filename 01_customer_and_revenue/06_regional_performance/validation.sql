/* =============================================================================
   Case study · Regional performance and market coverage — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start DATE DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE DEFAULT DATE '2026-09-30';
DECLARE py_start     DATE DEFAULT DATE '2025-01-01';
DECLARE py_end       DATE DEFAULT DATE '2025-09-30';
DECLARE cy_start     DATE DEFAULT DATE '2026-01-01';
DECLARE cy_end       DATE DEFAULT DATE '2026-09-30';

WITH s AS (SELECT * FROM `sahyadri_b2b.state_performance`),

lines AS (
    SELECT
        o.customer_id,
        o.order_date,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
-- largest customer per state recomputed with a self-join instead of MAX over a CTE
customer_rev AS (
    SELECT c.state, l.customer_id, SUM(l.revenue) AS rev
    FROM lines AS l
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = l.customer_id
    WHERE l.order_date BETWEEN window_start AND window_end
    GROUP BY c.state, l.customer_id
),
largest AS (
    SELECT a.state, a.rev
    FROM customer_rev AS a
    LEFT JOIN customer_rev AS b ON b.state = a.state AND b.rev > a.rev
    WHERE b.customer_id IS NULL
),
measured AS (
    SELECT
        COUNT(*)                                                    AS n,
        COUNTIF(d.final_delivery_date <= o.promised_delivery_date)  AS on_time
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN (SELECT order_id, MAX(delivery_date) AS final_delivery_date
            FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS d ON d.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date BETWEEN window_start AND window_end
      AND o.promised_delivery_date IS NOT NULL
      AND d.final_delivery_date IS NOT NULL
),

checks AS (
    SELECT '01. Duplicate states' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT state) FROM s) AS actual
    UNION ALL
    SELECT '02. States vs distinct states in customer master', 0,
           (SELECT COUNT(*) FROM s) - (SELECT COUNT(DISTINCT state) FROM `sahyadri_b2b.customers`)
    UNION ALL
    SELECT '03. Registered customers vs customer master', 0,
           (SELECT SUM(registered_customers) FROM s) - (SELECT COUNT(*) FROM `sahyadri_b2b.customers`)
    UNION ALL
    SELECT '04. Active customers vs source', 0,
           (SELECT SUM(active_customers) FROM s)
         - (SELECT COUNT(DISTINCT customer_id) FROM lines WHERE order_date BETWEEN window_start AND window_end)
    UNION ALL
    SELECT '05. 12-month revenue vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue_12m) FROM s)
                    - (SELECT SUM(revenue) FROM lines WHERE order_date BETWEEN window_start AND window_end), 0) AS INT64)
    UNION ALL
    SELECT '06. YTD revenue (both years) vs source (rupees, rounded)', 0,
           CAST(ROUND((SELECT SUM(revenue_py_ytd) + SUM(revenue_cy_ytd) FROM s)
                    - (SELECT SUM(revenue) FROM lines
                        WHERE order_date BETWEEN py_start AND py_end
                           OR order_date BETWEEN cy_start AND cy_end), 0) AS INT64)
    UNION ALL
    SELECT '07. States not mapped to a region', 0,
           (SELECT COUNTIF(region = 'Unmapped') FROM s)
    UNION ALL
    SELECT '08. Largest-customer share vs independent recount', 0,
           (SELECT COUNT(*) FROM s JOIN largest AS l ON l.state = s.state
             WHERE ABS(s.largest_customer_share - ROUND(l.rev / s.revenue_12m, 4)) > 0.0001)
    UNION ALL
    SELECT '09. Measured and on-time deliveries vs source', 0,
           (SELECT SUM(measured_deliveries) FROM s) - (SELECT n FROM measured)
         + CAST(ROUND((SELECT SUM(on_time_rate * measured_deliveries) FROM s) - (SELECT on_time FROM measured), 0) AS INT64)
    UNION ALL
    SELECT '10. Activation rate outside 0-1, or active above registered', 0,
           (SELECT COUNTIF(activation_rate < 0 OR activation_rate > 1 OR active_customers > registered_customers) FROM s)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
