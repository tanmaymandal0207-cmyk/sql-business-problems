/* =============================================================================
   Case study · Revenue driver tree (LMDI) — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

WITH d AS (SELECT * FROM `sahyadri_b2b.dt_drivers`),
     e AS (SELECT * FROM `sahyadri_b2b.dt_effects`),

src_orders AS (
    SELECT o.order_id, o.customer_id, EXTRACT(YEAR FROM o.order_date) AS yr
    FROM `sahyadri_b2b.sales_orders` AS o
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND EXTRACT(MONTH FROM o.order_date) <= 9
),
src_lines AS (
    SELECT s.yr, i.quantity, i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue,
           i.quantity * i.unit_price AS gross, i.quantity * p.selling_price AS list_today
    FROM src_orders AS s
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = s.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
),
src_year AS (
    SELECT yr, SUM(revenue) AS revenue, COUNT(*) AS lines, SUM(quantity) AS units,
           SUM(revenue) / SUM(quantity) AS rpu, SUM(list_today) / SUM(quantity) AS lpu,
           SUM(gross) / SUM(list_today) AS price_level, SUM(revenue) / SUM(gross) AS net_share
    FROM src_lines GROUP BY yr
),
src_counts AS (
    SELECT yr, COUNT(DISTINCT customer_id) AS customers, COUNT(*) AS orders FROM src_orders GROUP BY yr
),
all_rows AS (SELECT * FROM d WHERE scope = 'All customers'),

checks AS (
    SELECT '01. Company revenue per year = source (rupees)' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM all_rows AS a JOIN src_year AS s USING (yr) WHERE ABS(a.revenue - s.revenue) > 0.5) AS actual
    UNION ALL
    SELECT '02. Segment revenues add up to the company (rupees)', 0,
           (SELECT COUNT(*) FROM all_rows AS a JOIN (SELECT yr, SUM(revenue) AS r FROM d WHERE scope != 'All customers' GROUP BY yr) AS s USING (yr)
             WHERE ABS(a.revenue - s.r) > 0.5)
    UNION ALL
    SELECT '03. Revenue = product of the five drivers', 0,
           (SELECT COUNTIF(ABS(customers * orders_per_customer * lines_per_order * units_per_line * revenue_per_unit / revenue - 1) > 1e-9) FROM d)
    UNION ALL
    SELECT '04. LMDI effects add up exactly to the change (rupees)', 0,
           (SELECT COUNTIF(ABS(eff_customers + eff_orders_per_customer + eff_lines_per_order + eff_units_per_line + eff_revenue_per_unit - change) > 0.01) FROM e)
    UNION ALL
    SELECT '05. Customers and orders per year = source recount', 0,
           (SELECT COUNT(*) FROM all_rows AS a JOIN src_counts AS s USING (yr) WHERE a.customers != s.customers OR a.orders != s.orders)
    UNION ALL
    SELECT '06. Lines and units per year = source recount', 0,
           (SELECT COUNT(*) FROM all_rows AS a JOIN src_year AS s USING (yr) WHERE a.lines != s.lines OR a.units != s.units)
    UNION ALL
    SELECT '07. Segment customers and orders add up to the company', 0,
           (SELECT COUNT(*) FROM all_rows AS a JOIN (SELECT yr, SUM(customers) AS c, SUM(orders) AS o FROM d WHERE scope != 'All customers' GROUP BY yr) AS s USING (yr)
             WHERE a.customers != s.c OR a.orders != s.o)
    UNION ALL
    SELECT '08. Every effect has the sign of its driver change', 0,
           (SELECT COUNTIF(SIGN(eff_customers) != SIGN(ln_customers) OR SIGN(eff_orders_per_customer) != SIGN(ln_orders_per_customer)
                        OR SIGN(eff_lines_per_order) != SIGN(ln_lines_per_order) OR SIGN(eff_units_per_line) != SIGN(ln_units_per_line)
                        OR SIGN(eff_revenue_per_unit) != SIGN(ln_revenue_per_unit)) FROM e)
    UNION ALL
    SELECT '09. Two periods for each of the five scopes', 0,
           (SELECT COUNT(*) FROM e) - 10
    UNION ALL
    SELECT '10. Revenue per unit = independent source recount', 0,
           (SELECT COUNT(*) FROM all_rows AS a JOIN src_year AS s USING (yr) WHERE ABS(a.revenue_per_unit - s.rpu) > 1e-6)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
