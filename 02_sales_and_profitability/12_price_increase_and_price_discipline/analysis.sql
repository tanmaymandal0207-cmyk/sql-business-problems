/* =============================================================================
   Case study · January price increase and price discipline
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   List prices go up every January. The commercial team is planning the
   next increase and the finance controller has three worries: that the
   last increases were not applied to every product and customer, that
   customers bought ahead in December at the old prices, and that invoice
   prices are typed in by hand and drift away from the list.
     1. How large was each January increase, and was it applied to every
        product?
     2. Did customers buy ahead of the increase?
     3. How closely do invoice prices follow the list, and how much is
        billed below it?
     4. Does any customer, salesperson or product get systematically lower
        invoice prices?

   METHOD
     - All order lines (the price is set when the order is entered).
     - products.selling_price is today's (2026) list price. The list in
       force in earlier years is inferred as selling_price x the year's
       median of unit_price / selling_price (the "price factor").
     - Line price deviation = unit_price / list in force - 1. This is the
       invoice price before discount; discounts are studied separately.
     - Price step per product = mean unit_price / selling_price this year
       / last year - 1. z = (product step - company step) / its standard
       error from line variation.
     - Over-dispersion of mean deviation by group:
       SUM n (group mean - overall mean)^2 / overall variance / (groups - 1).
       About 1 = groups differ only by chance. z = (ratio - 1) x
       SQRT((groups - 1) / 2).
     - Buying ahead: for customer x product pairs bought at least 4 times,
       quantity index = quantity / the pair's median quantity, and gap
       index = days to the next purchase of the pair / the pair's median
       gap. Buying ahead would show a high quantity index and a long gap
       after purchases made in late December.
   ============================================================================= */

DECLARE last_gap_date DATE    DEFAULT DATE '2026-03-31';
DECLARE min_purchases INT64   DEFAULT 4;
DECLARE z_flag        FLOAT64 DEFAULT 3.0;

-- -----------------------------------------------------------------------------
-- Step 1 · Line table with the list in force and the price deviation
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pi_lines` AS
WITH base AS (
    SELECT
        i.order_item_id, i.order_id, o.customer_id, o.employee_id, o.order_date, o.order_status,
        EXTRACT(YEAR FROM o.order_date)                       AS price_year,
        i.product_id, i.quantity, i.unit_price, p.selling_price,
        IFNULL(i.discount_percent, 0)                         AS discount_percent,
        i.unit_price / p.selling_price                        AS price_ratio
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
),
factor AS (
    SELECT DISTINCT price_year,
           PERCENTILE_CONT(price_ratio, 0.5) OVER (PARTITION BY price_year) AS price_factor
    FROM base
)
SELECT
    b.*, f.price_factor,
    b.selling_price * f.price_factor                          AS list_in_force,
    b.unit_price / (b.selling_price * f.price_factor) - 1     AS price_deviation
FROM base AS b
JOIN factor AS f ON f.price_year = b.price_year;

-- -----------------------------------------------------------------------------
-- Step 2 · Size of each increase, overall and by product
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pi_product_steps` AS
WITH py AS (
    SELECT product_id, price_year,
           COUNT(*)                                   AS lines,
           AVG(price_ratio)                           AS mean_ratio,
           VAR_SAMP(price_ratio)                      AS var_ratio
    FROM `sahyadri_b2b.pi_lines`
    GROUP BY product_id, price_year
),
company AS (
    SELECT DISTINCT price_year, price_factor FROM `sahyadri_b2b.pi_lines`
),
steps AS (
    SELECT
        cur.product_id, cur.price_year,
        prev.lines AS lines_prev, cur.lines AS lines_cur,
        cur.mean_ratio / prev.mean_ratio - 1                                   AS product_step,
        cc.price_factor / cp.price_factor - 1                                  AS company_step,
        -- standard error of the ratio of two means (delta method)
        (cur.mean_ratio / prev.mean_ratio)
          * SQRT(cur.var_ratio / cur.lines / POW(cur.mean_ratio, 2)
               + prev.var_ratio / prev.lines / POW(prev.mean_ratio, 2))        AS step_se
    FROM py AS cur
    JOIN py AS prev ON prev.product_id = cur.product_id AND prev.price_year = cur.price_year - 1
    JOIN company AS cc ON cc.price_year = cur.price_year
    JOIN company AS cp ON cp.price_year = cur.price_year - 1
    WHERE cur.lines >= 2 AND prev.lines >= 2
)
SELECT *, (product_step - company_step) / step_se AS z
FROM steps;

SELECT
    price_year,
    ROUND(ANY_VALUE(price_factor), 4)                                          AS price_factor,
    COUNT(*)                                                                   AS lines,
    ROUND(100 * (ANY_VALUE(price_factor) / LAG(ANY_VALUE(price_factor)) OVER (ORDER BY price_year) - 1), 2) AS january_increase_pct
FROM `sahyadri_b2b.pi_lines`
GROUP BY price_year
ORDER BY price_year;

SELECT
    price_year                                         AS increase_in_january,
    COUNT(*)                                           AS products,
    ROUND(100 * AVG(company_step), 2)                  AS company_step_pct,
    ROUND(100 * MIN(product_step), 2)                  AS min_product_step_pct,
    ROUND(100 * MAX(product_step), 2)                  AS max_product_step_pct,
    ROUND(100 * STDDEV(product_step), 2)               AS sd_product_step_pct,
    COUNTIF(ABS(z) >= z_flag)                          AS products_off_policy,
    ROUND(AVG(POW(z, 2)), 2)                           AS mean_z_squared
FROM `sahyadri_b2b.pi_product_steps`
GROUP BY price_year
ORDER BY price_year;

-- The step happens on 1 January: median price ratio by month
SELECT
    DATE_TRUNC(order_date, MONTH)                                  AS month_start,
    COUNT(*)                                                       AS lines,
    ROUND(APPROX_QUANTILES(price_ratio, 100)[OFFSET(50)], 4)       AS median_price_ratio
FROM `sahyadri_b2b.pi_lines`
GROUP BY month_start
ORDER BY month_start;

-- Products whose increase differs from the company step by |z| >= 3
SELECT s.price_year AS increase_in_january, s.product_id, p.product_name, s.lines_prev, s.lines_cur,
       ROUND(100 * s.product_step, 2) AS product_step_pct, ROUND(100 * s.company_step, 2) AS company_step_pct, ROUND(s.z, 2) AS z
FROM `sahyadri_b2b.pi_product_steps` AS s
JOIN `sahyadri_b2b.products` AS p ON p.product_id = s.product_id
WHERE ABS(s.z) >= z_flag
ORDER BY ABS(s.z) DESC;

-- Value of each increase: net revenue of the year minus the same lines at last year's prices
WITH f AS (
    SELECT DISTINCT price_year, price_factor FROM `sahyadri_b2b.pi_lines`
)
SELECT
    l.price_year,
    ROUND(SUM(l.quantity * l.unit_price * (1 - l.discount_percent / 100)) / 1e7, 2)          AS net_revenue_crore,
    ROUND(SUM(l.quantity * l.unit_price * (1 - l.discount_percent / 100)
              * (1 - p.price_factor / l.price_factor)) / 1e5, 1)                             AS value_of_increase_lakh
FROM `sahyadri_b2b.pi_lines` AS l
JOIN f AS p ON p.price_year = l.price_year - 1
WHERE l.order_status NOT IN ('Cancelled', 'Returned')
GROUP BY l.price_year
ORDER BY l.price_year;

-- -----------------------------------------------------------------------------
-- Step 3 · How closely do invoice prices follow the list?
-- -----------------------------------------------------------------------------
SELECT
    CAST(ROUND(100 * price_deviation) AS INT64)                 AS deviation_pct_rounded,
    COUNT(*)                                                    AS lines,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS share_pct
FROM `sahyadri_b2b.pi_lines`
GROUP BY deviation_pct_rounded
ORDER BY deviation_pct_rounded;

SELECT
    COUNT(*)                                                                                  AS lines,
    COUNTIF(ABS(unit_price - list_in_force) < 0.005)                                          AS lines_at_list_price,
    COUNTIF(unit_price = selling_price)                                                       AS lines_at_todays_list,
    ROUND(100 * MIN(price_deviation), 2)                                                      AS min_deviation_pct,
    ROUND(100 * MAX(price_deviation), 2)                                                      AS max_deviation_pct,
    ROUND(100 * STDDEV(price_deviation), 2)                                                   AS sd_deviation_pct,
    ROUND(CORR(price_deviation, discount_percent), 3)                                         AS corr_with_discount,
    ROUND(SUM(IF(unit_price < list_in_force, quantity * (list_in_force - unit_price), 0)) / 1e5, 1) AS billed_below_list_lakh,
    ROUND(SUM(IF(unit_price > list_in_force, quantity * (unit_price - list_in_force), 0)) / 1e5, 1) AS billed_above_list_lakh,
    ROUND(SUM(quantity * (unit_price - list_in_force)) / 1e5, 1)                              AS net_vs_list_lakh,
    ROUND(SUM(quantity * list_in_force) / 1e7, 2)                                             AS value_at_list_crore
FROM `sahyadri_b2b.pi_lines`;

-- Does any customer, salesperson or product get systematically different prices?
CREATE OR REPLACE TABLE `sahyadri_b2b.pi_dispersion` AS
WITH overall AS (
    SELECT AVG(price_deviation) AS m, VAR_SAMP(price_deviation) AS v FROM `sahyadri_b2b.pi_lines`
),
grouped AS (
              SELECT 'Customer'    AS dimension, CAST(customer_id AS STRING) AS member, COUNT(*) AS n, AVG(price_deviation) AS mean_dev
              FROM `sahyadri_b2b.pi_lines` GROUP BY customer_id
    UNION ALL SELECT 'Salesperson', IFNULL(CAST(employee_id AS STRING), 'Unassigned'), COUNT(*), AVG(price_deviation)
              FROM `sahyadri_b2b.pi_lines` GROUP BY employee_id
    UNION ALL SELECT 'Product',     CAST(product_id AS STRING), COUNT(*), AVG(price_deviation)
              FROM `sahyadri_b2b.pi_lines` GROUP BY product_id
    UNION ALL SELECT 'Discount band',
                     CASE WHEN discount_percent = 0 THEN '0 %' WHEN discount_percent < 5 THEN 'Under 5 %'
                          WHEN discount_percent < 10 THEN '5-10 %' ELSE '10 %+' END,
                     COUNT(*), AVG(price_deviation)
              FROM `sahyadri_b2b.pi_lines` GROUP BY 2
)
SELECT g.*, (g.mean_dev - o.m) / SQRT(o.v / g.n) AS member_z, o.m AS overall_mean, o.v AS overall_var
FROM grouped AS g CROSS JOIN overall AS o;

SELECT
    dimension,
    COUNT(*)                                                                  AS members,
    ROUND(SUM(POW(member_z, 2)) / (COUNT(*) - 1), 3)                          AS over_dispersion_ratio,
    ROUND((SUM(POW(member_z, 2)) / (COUNT(*) - 1) - 1) * SQRT((COUNT(*) - 1) / 2), 2) AS z,
    COUNTIF(ABS(member_z) >= z_flag)                                          AS members_beyond_z_flag,
    ROUND(100 * MIN(mean_dev), 2)                                             AS lowest_mean_dev_pct,
    ROUND(100 * MAX(mean_dev), 2)                                             AS highest_mean_dev_pct
FROM `sahyadri_b2b.pi_dispersion`
GROUP BY dimension
ORDER BY dimension;

-- -----------------------------------------------------------------------------
-- Step 4 · Did customers buy ahead of the increase?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pi_repeat_purchases` AS
WITH buys AS (
    SELECT customer_id, product_id, order_id, order_date, quantity,
           COUNT(*) OVER (PARTITION BY customer_id, product_id)                         AS purchases,
           LEAD(order_date) OVER (PARTITION BY customer_id, product_id ORDER BY order_date, order_id) AS next_date
    FROM `sahyadri_b2b.pi_lines`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
),
pairs AS (
    SELECT *,
           DATE_DIFF(next_date, order_date, DAY)                                       AS gap_days,
           PERCENTILE_CONT(quantity, 0.5) OVER (PARTITION BY customer_id, product_id)  AS median_qty
    FROM buys
    WHERE purchases >= min_purchases
)
SELECT
    p.*,
    PERCENTILE_CONT(gap_days, 0.5) OVER (PARTITION BY customer_id, product_id)         AS median_gap,
    CASE WHEN EXTRACT(MONTH FROM order_date) = 12 AND EXTRACT(DAY FROM order_date) >= 16 THEN '1. Late December'
         WHEN EXTRACT(MONTH FROM order_date) = 1  AND EXTRACT(DAY FROM order_date) <= 15 THEN '2. Early January'
         WHEN EXTRACT(MONTH FROM order_date) = 3  AND EXTRACT(DAY FROM order_date) >= 16 THEN '3. Late March'
         ELSE '4. Rest of year' END                                                    AS purchase_window
FROM pairs AS p;

SELECT
    purchase_window,
    COUNT(*)                                                                   AS purchases,
    ROUND(AVG(quantity / median_qty), 3)                                       AS mean_quantity_index,
    ROUND(AVG(IF(quantity > median_qty, 1, 0)) * 100, 1)                       AS pct_above_usual_qty,
    COUNTIF(gap_days IS NOT NULL AND median_gap > 0)                           AS purchases_with_next,
    ROUND(AVG(IF(median_gap > 0, gap_days / median_gap, NULL)), 3)             AS mean_gap_index,
    ROUND(AVG(IF(median_gap > 0 AND gap_days IS NOT NULL, IF(gap_days > median_gap, 1, 0), NULL)) * 100, 1) AS pct_longer_gap_than_usual
FROM `sahyadri_b2b.pi_repeat_purchases`
WHERE order_date <= last_gap_date
GROUP BY purchase_window
ORDER BY purchase_window;

-- Late December against the rest of the year: two-proportion z-tests
WITH r AS (
    SELECT purchase_window = '1. Late December'                                   AS late_dec,
           IF(quantity > median_qty, 1, 0)                                        AS above_qty,
           IF(median_gap > 0 AND gap_days IS NOT NULL, IF(gap_days > median_gap, 1, 0), NULL) AS longer_gap
    FROM `sahyadri_b2b.pi_repeat_purchases`
    WHERE order_date <= last_gap_date AND purchase_window IN ('1. Late December', '4. Rest of year')
),
s AS (
    SELECT
        COUNTIF(late_dec) AS n1, COUNTIF(NOT late_dec) AS n2,
        AVG(IF(late_dec, above_qty, NULL)) AS q1, AVG(IF(NOT late_dec, above_qty, NULL)) AS q2, AVG(above_qty) AS q,
        COUNTIF(late_dec AND longer_gap IS NOT NULL) AS m1, COUNTIF(NOT late_dec AND longer_gap IS NOT NULL) AS m2,
        AVG(IF(late_dec, longer_gap, NULL)) AS g1, AVG(IF(NOT late_dec, longer_gap, NULL)) AS g2, AVG(longer_gap) AS g
    FROM r
)
SELECT
    'Bought more than usual' AS test, ROUND(100 * q1, 1) AS late_december_pct, ROUND(100 * q2, 1) AS rest_of_year_pct,
    ROUND((q1 - q2) / SQRT(q * (1 - q) * (1 / n1 + 1 / n2)), 2) AS z
FROM s
UNION ALL
SELECT
    'Waited longer than usual to buy again', ROUND(100 * g1, 1), ROUND(100 * g2, 1),
    ROUND((g1 - g2) / SQRT(g * (1 - g) * (1 / m1 + 1 / m2)), 2)
FROM s;

-- Orders per month as an index of the year's monthly average (seasonality around January)
WITH m AS (
    SELECT EXTRACT(YEAR FROM order_date) AS yr, EXTRACT(MONTH FROM order_date) AS mo, COUNT(DISTINCT order_id) AS orders
    FROM `sahyadri_b2b.pi_lines`
    WHERE order_status NOT IN ('Cancelled', 'Returned') AND order_date < DATE '2026-01-01'
    GROUP BY yr, mo
),
indexed AS (
    SELECT *, orders / AVG(orders) OVER (PARTITION BY yr) AS month_index FROM m
)
SELECT
    mo                                                                                  AS month,
    SUM(IF(yr = 2024, orders, 0))                                                       AS orders_2024,
    SUM(IF(yr = 2025, orders, 0))                                                       AS orders_2025,
    ROUND(AVG(month_index), 2)                                                          AS index_vs_year_average
FROM indexed
GROUP BY mo
ORDER BY mo;
