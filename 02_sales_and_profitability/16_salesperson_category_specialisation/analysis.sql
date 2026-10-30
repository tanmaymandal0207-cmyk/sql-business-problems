/* =============================================================================
   Case study · Salesperson category specialisation: generalists or specialists?
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The Head of Sales is considering splitting the sales team by product
   line: fluid power (pneumatic, hydraulic, valves, pumps), mechanical and
   electrical (bearings, power transmission, motors, fasteners) and MRO
   consumables (cutting tools, safety equipment). The argument is that
   salespeople already specialise, and that specialists sell their
   categories at better prices. Before redrawing the team she asks:
     1. Does each salesperson's category mix differ from the company mix by
        more than random allocation of orders would produce?
     2. Is any difference explained by the customers they serve, or by the
        salesperson?
     3. Do salespeople give smaller discounts in the categories they sell
        most?
     4. How many customers would a product-line split hand to two or three
        salespeople?

   METHOD
     - Valid orders (not Cancelled or Returned) with a salesperson,
       January 2024 - September 2026. Net line value by category.
     - Specialisation index of a salesperson: D = 0.5 x SUM |share of the
       salesperson's revenue in category c - company share of c| (0 = the
       company mix exactly, 1 = completely different).
     - Two random benchmarks, 200 shuffles each, keeping every
       salesperson's number of orders:
         "Any order"     - salesperson labels shuffled across all orders
         "Same customer" - labels shuffled only among orders of the same
                           customer (keeps who serves whom; removes any
                           influence of the salesperson on what is bought)
       p-value = share of shuffles with D at least as large as observed.
     - Discount and focus: for every salesperson x category with 30+ lines,
       focus = category share / company share and the discount gap = their
       average discount % - the category average. Weighted correlation and
       slope across cells.
     - Product-line split: three groups as above; customers that bought in
       two or three groups in the last 12 months (Oct 2025 - Sep 2026).
   ============================================================================= */

DECLARE start_date    DATE  DEFAULT DATE '2024-01-01';
DECLARE end_date      DATE  DEFAULT DATE '2026-09-30';
DECLARE recent_start  DATE  DEFAULT DATE '2025-10-01';
DECLARE permutations  INT64 DEFAULT 200;
DECLARE min_lines     INT64 DEFAULT 30;
DECLARE prime         INT64 DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Order lines with salesperson, category and product line
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sp_lines` AS
SELECT
    o.order_id, o.customer_id, o.employee_id, o.order_date,
    pc.category_name                                                           AS category,
    CASE WHEN pc.category_name IN ('Pneumatic Components', 'Hydraulic Components', 'Valves & Fittings', 'Pumps')
              THEN 'Fluid power'
         WHEN pc.category_name IN ('Bearings', 'Power Transmission', 'Electric Motors & Drives', 'Fasteners')
              THEN 'Mechanical and electrical'
         ELSE 'MRO consumables' END                                            AS product_line,
    i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)      AS line_value,
    IFNULL(i.discount_percent, 0)                                              AS discount_pct
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
  AND o.employee_id IS NOT NULL
  AND o.order_date BETWEEN start_date AND end_date;

-- One row per order x category (the unit the shuffles move)
CREATE OR REPLACE TABLE `sahyadri_b2b.sp_order_categories` AS
SELECT order_id, customer_id, employee_id, category, SUM(line_value) AS value
FROM `sahyadri_b2b.sp_lines`
GROUP BY order_id, customer_id, employee_id, category;

-- -----------------------------------------------------------------------------
-- Step 2 · Observed specialisation and the two random benchmarks
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sp_shuffles` AS
WITH orders AS (
    SELECT DISTINCT order_id, customer_id, employee_id FROM `sahyadri_b2b.sp_order_categories`
),
positions AS (
    SELECT order_id, customer_id, employee_id,
           ROW_NUMBER() OVER (ORDER BY order_id)                          AS pos_all,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_id)  AS pos_cust
    FROM orders
),
reps AS (
    SELECT 0 AS b UNION ALL SELECT b FROM UNNEST(GENERATE_ARRAY(1, permutations)) AS b
),
benchmarks AS (
    SELECT 'Any order' AS benchmark UNION ALL SELECT 'Same customer'
),
hashed AS (
    SELECT k.benchmark, r.b, p.order_id, p.customer_id, p.pos_all, p.pos_cust,
           MOD(MOD(r.b * 7919 + p.order_id * 104729 + IF(k.benchmark = 'Any order', 1, 2) * 1299709, prime)
             * MOD(r.b * 7919 + p.order_id * 104729 + IF(k.benchmark = 'Any order', 1, 2) * 1299709, prime) + 12345, prime) AS h
    FROM benchmarks AS k
    CROSS JOIN reps AS r
    CROSS JOIN positions AS p
),
moved AS (
    -- b = 0 keeps the real salesperson; otherwise the order takes the salesperson
    -- of the order at its hashed position (across all orders, or within the customer)
    SELECT benchmark, b, order_id, customer_id,
           CASE WHEN b = 0 THEN pos_all
                WHEN benchmark = 'Any order' THEN ROW_NUMBER() OVER (PARTITION BY benchmark, b ORDER BY h, order_id)
                ELSE pos_all END                                                                       AS take_all,
           CASE WHEN b = 0 OR benchmark = 'Any order' THEN pos_cust
                ELSE ROW_NUMBER() OVER (PARTITION BY benchmark, b, customer_id ORDER BY h, order_id) END AS take_cust
    FROM hashed
)
SELECT m.benchmark, m.b, m.order_id,
       IF(m.benchmark = 'Any order', pa.employee_id, pc.employee_id) AS employee_id
FROM moved AS m
LEFT JOIN positions AS pa ON m.benchmark = 'Any order'     AND pa.pos_all = m.take_all
LEFT JOIN positions AS pc ON m.benchmark = 'Same customer' AND pc.customer_id = m.customer_id AND pc.pos_cust = m.take_cust;

CREATE OR REPLACE TABLE `sahyadri_b2b.sp_index` AS
WITH company AS (
    SELECT category, SUM(value) / (SELECT SUM(value) FROM `sahyadri_b2b.sp_order_categories`) AS company_share
    FROM `sahyadri_b2b.sp_order_categories`
    GROUP BY category
),
cells AS (
    SELECT s.benchmark, s.b, s.employee_id, oc.category, SUM(oc.value) AS value
    FROM `sahyadri_b2b.sp_shuffles` AS s
    JOIN `sahyadri_b2b.sp_order_categories` AS oc ON oc.order_id = s.order_id
    GROUP BY s.benchmark, s.b, s.employee_id, oc.category
),
full_grid AS (
    -- every salesperson x category, including categories a salesperson never sold
    SELECT e.benchmark, e.b, e.employee_id, c.category, c.company_share, IFNULL(x.value, 0) AS value,
           SUM(IFNULL(x.value, 0)) OVER (PARTITION BY e.benchmark, e.b, e.employee_id) AS employee_total
    FROM (SELECT DISTINCT benchmark, b, employee_id FROM cells) AS e
    CROSS JOIN company AS c
    LEFT JOIN cells AS x ON x.benchmark = e.benchmark AND x.b = e.b AND x.employee_id = e.employee_id AND x.category = c.category
)
SELECT benchmark, b, employee_id,
       SUM(value)                                                     AS revenue,
       0.5 * SUM(ABS(value / employee_total - company_share))         AS d_index
FROM full_grid
GROUP BY benchmark, b, employee_id;

-- Observed index against the two benchmarks, by salesperson
WITH obs AS (
    SELECT employee_id, revenue, d_index FROM `sahyadri_b2b.sp_index` WHERE b = 0 AND benchmark = 'Any order'
),
shuffled AS (
    SELECT i.benchmark, i.employee_id, AVG(i.d_index) AS mean_d,
           COUNTIF(i.d_index >= o.d_index - 1e-12) AS as_large
    FROM `sahyadri_b2b.sp_index` AS i
    JOIN obs AS o ON o.employee_id = i.employee_id
    WHERE i.b > 0
    GROUP BY i.benchmark, i.employee_id
),
top_cat AS (
    SELECT employee_id, category, focus,
           ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY focus DESC) AS rk
    FROM (
        SELECT oc.employee_id, oc.category,
               (SUM(oc.value) / SUM(SUM(oc.value)) OVER (PARTITION BY oc.employee_id))
             / (SUM(SUM(oc.value)) OVER (PARTITION BY oc.category) / SUM(SUM(oc.value)) OVER ()) AS focus
        FROM `sahyadri_b2b.sp_order_categories` AS oc
        GROUP BY oc.employee_id, oc.category
    )
)
SELECT
    o.employee_id, e.designation,
    ROUND(o.revenue / 1e7, 2)                                                            AS revenue_crore,
    ROUND(o.d_index, 3)                                                                  AS specialisation_index,
    ROUND(MAX(IF(s.benchmark = 'Any order', s.mean_d, NULL)), 3)                         AS random_any_order,
    ROUND((1 + MAX(IF(s.benchmark = 'Any order', s.as_large, NULL))) / (1 + permutations), 3)     AS p_any_order,
    ROUND(MAX(IF(s.benchmark = 'Same customer', s.mean_d, NULL)), 3)                     AS random_same_customer,
    ROUND((1 + MAX(IF(s.benchmark = 'Same customer', s.as_large, NULL))) / (1 + permutations), 3) AS p_same_customer,
    ANY_VALUE(t.category)                                                                AS most_over_sold_category,
    ROUND(ANY_VALUE(t.focus), 2)                                                         AS its_focus_index
FROM obs AS o
JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = o.employee_id
JOIN shuffled AS s ON s.employee_id = o.employee_id
JOIN top_cat AS t ON t.employee_id = o.employee_id AND t.rk = 1
GROUP BY o.employee_id, e.designation, o.revenue, o.d_index
ORDER BY o.d_index DESC;

-- Team-level test: revenue-weighted average index against each benchmark
WITH team AS (
    SELECT benchmark, b, SUM(revenue * d_index) / SUM(revenue) AS team_d
    FROM `sahyadri_b2b.sp_index`
    GROUP BY benchmark, b
)
SELECT
    t.benchmark,
    ROUND(o.team_d, 3)                                                               AS observed_team_index,
    ROUND(AVG(t.team_d), 3)                                                          AS random_mean,
    ROUND(APPROX_QUANTILES(t.team_d, 100)[OFFSET(95)], 3)                            AS random_95th,
    ROUND((1 + COUNTIF(t.team_d >= o.team_d - 1e-12)) / (1 + COUNT(*)), 3)           AS p_value
FROM team AS t
CROSS JOIN (SELECT team_d FROM team WHERE b = 0 AND benchmark = 'Any order') AS o
WHERE t.b > 0
GROUP BY t.benchmark, o.team_d
ORDER BY t.benchmark;

-- -----------------------------------------------------------------------------
-- Step 3 · Do salespeople discount less in the categories they sell most?
-- -----------------------------------------------------------------------------
WITH cells AS (
    SELECT employee_id, category, COUNT(*) AS lines, SUM(line_value) AS value, AVG(discount_pct) AS avg_discount
    FROM `sahyadri_b2b.sp_lines`
    GROUP BY employee_id, category
),
shares AS (
    SELECT c.*,
           (value / SUM(value) OVER (PARTITION BY employee_id))
         / (SUM(value) OVER (PARTITION BY category) / SUM(value) OVER ())                       AS focus,
           avg_discount - SUM(avg_discount * lines) OVER (PARTITION BY category)
                          / SUM(lines) OVER (PARTITION BY category)                             AS discount_gap
    FROM cells AS c
),
used AS (
    SELECT *, LN(focus) AS ln_focus FROM shares WHERE lines >= min_lines
),
moments AS (
    SELECT SUM(lines) AS w,
           SUM(lines * ln_focus) / SUM(lines) AS mx, SUM(lines * discount_gap) / SUM(lines) AS my
    FROM used
)
SELECT
    COUNT(*)                                                                                     AS cells,
    SUM(u.lines)                                                                                 AS lines,
    ROUND(SUM(u.lines * (u.ln_focus - m.mx) * (u.discount_gap - m.my))
          / SQRT(SUM(u.lines * POW(u.ln_focus - m.mx, 2)) * SUM(u.lines * POW(u.discount_gap - m.my, 2))), 3) AS weighted_corr,
    ROUND(SUM(u.lines * (u.ln_focus - m.mx) * (u.discount_gap - m.my)) / SUM(u.lines * POW(u.ln_focus - m.mx, 2)), 3)
                                                                                                 AS discount_pts_per_unit_ln_focus,
    -- approximate t statistic, treating each cell as one observation
    ROUND(SUM(u.lines * (u.ln_focus - m.mx) * (u.discount_gap - m.my))
          / SQRT(SUM(u.lines * POW(u.ln_focus - m.mx, 2)) * SUM(u.lines * POW(u.discount_gap - m.my, 2)))
          * SQRT((COUNT(*) - 2) / (1 - POW(SUM(u.lines * (u.ln_focus - m.mx) * (u.discount_gap - m.my))
          / SQRT(SUM(u.lines * POW(u.ln_focus - m.mx, 2)) * SUM(u.lines * POW(u.discount_gap - m.my, 2))), 2))), 2) AS approx_t,
    ROUND(MIN(u.focus), 2)                                                                       AS min_focus,
    ROUND(MAX(u.focus), 2)                                                                       AS max_focus,
    ROUND(MIN(u.discount_gap), 2)                                                                AS min_discount_gap_pts,
    ROUND(MAX(u.discount_gap), 2)                                                                AS max_discount_gap_pts
FROM used AS u
CROSS JOIN moments AS m;

-- -----------------------------------------------------------------------------
-- Step 4 · What a product-line split would do to customer coverage
-- -----------------------------------------------------------------------------
WITH recent AS (
    SELECT customer_id,
           COUNT(DISTINCT product_line)                    AS product_lines,
           COUNT(DISTINCT employee_id)                     AS salespeople_today,
           SUM(line_value)                                 AS revenue
    FROM `sahyadri_b2b.sp_lines`
    WHERE order_date >= recent_start
    GROUP BY customer_id
)
SELECT
    product_lines                                                         AS product_lines_bought,
    COUNT(*)                                                              AS customers,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                      AS customers_pct,
    ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)              AS revenue_pct,
    ROUND(AVG(salespeople_today), 2)                                      AS avg_salespeople_today,
    ROUND(100 * AVG(IF(salespeople_today = 1, 1, 0)), 1)                  AS served_by_one_today_pct
FROM recent
GROUP BY product_lines
ORDER BY product_lines;
