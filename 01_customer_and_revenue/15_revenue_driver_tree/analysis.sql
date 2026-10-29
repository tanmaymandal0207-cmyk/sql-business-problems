/* =============================================================================
   Case study · Revenue driver tree (LMDI decomposition)
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The board pack shows revenue growth as one number. The CEO wants a
   driver tree for next year's plan: did revenue grow because there were
   more customers, because each customer ordered more often, because orders
   had more lines, because each line had more units, or because each unit
   was worth more? And is the pattern the same in every segment and in both
   recent years?
     1. Which drivers explain revenue growth in 2025 and in 2026?
     2. Does the answer differ by segment?
     3. Which drivers are moving the right way, and which are hiding behind
        the total?

   METHOD
     - Net revenue on orders not Cancelled or Returned, in January-September
       windows of 2024, 2025 and 2026 (comparable year-to-date).
     - Driver tree: Revenue = Customers x Orders per customer x Lines per
       order x Units per line x Revenue per unit.
       (Revenue per unit mixes price, discount and product mix.)
     - Additive LMDI-I decomposition, exact with no residual:
         effect of driver x = L(R1, R0) x LN(x1 / x0),
         L(a, b) = (a - b) / (LN a - LN b), the logarithmic mean.
       The five effects add up exactly to R1 - R0.
     - Applied to the company and to each customer segment.
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- Step 1 · Driver values per segment and year
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dt_drivers` AS
WITH lines AS (
    SELECT o.order_id, o.customer_id, c.customer_segment, EXTRACT(YEAR FROM o.order_date) AS yr,
           i.quantity, i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND EXTRACT(MONTH FROM o.order_date) <= 9
),
both_levels AS (
    SELECT customer_segment AS scope, yr, customer_id, order_id, quantity, revenue FROM lines
    UNION ALL
    SELECT 'All customers', yr, customer_id, order_id, quantity, revenue FROM lines
)
SELECT
    scope, yr,
    SUM(revenue)                                                   AS revenue,
    COUNT(DISTINCT customer_id)                                    AS customers,
    COUNT(DISTINCT order_id)                                       AS orders,
    COUNT(*)                                                       AS lines,
    SUM(quantity)                                                  AS units,
    COUNT(DISTINCT order_id) / COUNT(DISTINCT customer_id)         AS orders_per_customer,
    COUNT(*) / COUNT(DISTINCT order_id)                            AS lines_per_order,
    SUM(quantity) / COUNT(*)                                       AS units_per_line,
    SUM(revenue) / SUM(quantity)                                   AS revenue_per_unit
FROM both_levels
GROUP BY scope, yr;

SELECT scope, yr, ROUND(revenue / 1e7, 2) AS revenue_crore, customers, orders, lines, units,
       ROUND(orders_per_customer, 2) AS orders_per_customer, ROUND(lines_per_order, 3) AS lines_per_order,
       ROUND(units_per_line, 2) AS units_per_line, ROUND(revenue_per_unit, 1) AS revenue_per_unit
FROM `sahyadri_b2b.dt_drivers`
ORDER BY scope, yr;

-- -----------------------------------------------------------------------------
-- Step 2 · LMDI decomposition of each year's change
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dt_effects` AS
WITH pairs AS (
    SELECT
        b.scope, CONCAT(CAST(a.yr AS STRING), ' -> ', CAST(b.yr AS STRING)) AS period,
        a.revenue AS r0, b.revenue AS r1,
        (b.revenue - a.revenue) / (LN(b.revenue) - LN(a.revenue))         AS log_mean,
        LN(b.customers / a.customers)                                      AS ln_customers,
        LN(b.orders_per_customer / a.orders_per_customer)                  AS ln_orders_per_customer,
        LN(b.lines_per_order / a.lines_per_order)                          AS ln_lines_per_order,
        LN(b.units_per_line / a.units_per_line)                            AS ln_units_per_line,
        LN(b.revenue_per_unit / a.revenue_per_unit)                        AS ln_revenue_per_unit
    FROM `sahyadri_b2b.dt_drivers` AS a
    JOIN `sahyadri_b2b.dt_drivers` AS b ON b.scope = a.scope AND b.yr = a.yr + 1
)
SELECT
    scope, period, r0, r1, r1 - r0 AS change,
    log_mean * ln_customers            AS eff_customers,
    log_mean * ln_orders_per_customer  AS eff_orders_per_customer,
    log_mean * ln_lines_per_order      AS eff_lines_per_order,
    log_mean * ln_units_per_line       AS eff_units_per_line,
    log_mean * ln_revenue_per_unit     AS eff_revenue_per_unit,
    ln_customers, ln_orders_per_customer, ln_lines_per_order, ln_units_per_line, ln_revenue_per_unit
FROM pairs;

SELECT
    scope, period,
    ROUND(r0 / 1e7, 2)                                 AS revenue_from_crore,
    ROUND(r1 / 1e7, 2)                                 AS revenue_to_crore,
    ROUND(100 * (r1 / r0 - 1), 1)                      AS growth_pct,
    ROUND(eff_customers / 1e5, 1)                      AS customers_lakh,
    ROUND(eff_orders_per_customer / 1e5, 1)            AS orders_per_customer_lakh,
    ROUND(eff_lines_per_order / 1e5, 1)                AS lines_per_order_lakh,
    ROUND(eff_units_per_line / 1e5, 1)                 AS units_per_line_lakh,
    ROUND(eff_revenue_per_unit / 1e5, 1)               AS revenue_per_unit_lakh
FROM `sahyadri_b2b.dt_effects`
ORDER BY period, scope = 'All customers' DESC, scope;

-- Shares of each year's change, company level
SELECT
    period,
    ROUND(100 * eff_customers / change, 1)             AS customers_pct,
    ROUND(100 * eff_orders_per_customer / change, 1)   AS orders_per_customer_pct,
    ROUND(100 * eff_lines_per_order / change, 1)       AS lines_per_order_pct,
    ROUND(100 * eff_units_per_line / change, 1)        AS units_per_line_pct,
    ROUND(100 * eff_revenue_per_unit / change, 1)      AS revenue_per_unit_pct
FROM `sahyadri_b2b.dt_effects`
WHERE scope = 'All customers'
ORDER BY period;

-- -----------------------------------------------------------------------------
-- Step 3 · Percentage change of each driver (what moved, and which way)
-- -----------------------------------------------------------------------------
SELECT
    scope, period,
    ROUND(100 * (EXP(ln_customers) - 1), 1)            AS customers_pct,
    ROUND(100 * (EXP(ln_orders_per_customer) - 1), 1)  AS orders_per_customer_pct,
    ROUND(100 * (EXP(ln_lines_per_order) - 1), 1)      AS lines_per_order_pct,
    ROUND(100 * (EXP(ln_units_per_line) - 1), 1)       AS units_per_line_pct,
    ROUND(100 * (EXP(ln_revenue_per_unit) - 1), 1)     AS revenue_per_unit_pct,
    ROUND(100 * (r1 / r0 - 1), 1)                      AS revenue_pct
FROM `sahyadri_b2b.dt_effects`
ORDER BY scope, period;

-- Revenue per unit split: list price level against product and discount mix
-- (list price level = average January price factor change; see the price increase study)
WITH unit_rev AS (
    SELECT EXTRACT(YEAR FROM o.order_date) AS yr,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) / SUM(i.quantity) AS revenue_per_unit,
           SUM(i.quantity * p.selling_price) / SUM(i.quantity)                                         AS list_per_unit_today,
           SUM(i.quantity * i.unit_price) / SUM(i.quantity * p.selling_price)                          AS price_level,
           1 - SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) / SUM(i.quantity * i.unit_price) AS discount_rate
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND EXTRACT(MONTH FROM o.order_date) <= 9
    GROUP BY yr
)
SELECT
    yr,
    ROUND(revenue_per_unit, 1)                                                AS revenue_per_unit,
    ROUND(100 * (revenue_per_unit / LAG(revenue_per_unit) OVER (ORDER BY yr) - 1), 1)       AS revenue_per_unit_change_pct,
    ROUND(100 * (list_per_unit_today / LAG(list_per_unit_today) OVER (ORDER BY yr) - 1), 1) AS product_mix_change_pct,
    ROUND(100 * (price_level / LAG(price_level) OVER (ORDER BY yr) - 1), 1)                 AS price_level_change_pct,
    ROUND(100 * discount_rate, 2)                                                           AS discount_pct
FROM unit_rev
ORDER BY yr;
