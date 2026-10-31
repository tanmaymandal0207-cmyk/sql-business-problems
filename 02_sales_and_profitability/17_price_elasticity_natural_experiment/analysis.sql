/* =============================================================================
   Case study · Price elasticity from a natural experiment: do customers notice ±3 %?
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The price discipline study found that invoice prices are spread evenly
   within +/-3 % of the list price, with no customer, salesperson or product
   pattern: in effect, every order line gets a random price. ₹77.9 lakh was
   billed below list and ₹80.7 lakh above it. The CFO wants to standardise
   invoicing at list, but sales warns that customers will buy less if their
   prices rise. Because the deviations are random, they form a natural
   experiment. The pricing manager asks:
     1. Are the deviations really random (unrelated to customer, size or
        timing), so they can be used as an experiment?
     2. Do customers buy fewer units on lines priced above list, and more
        below it?
     3. Does a high price on a line make the customer less likely to buy
        that product again?
     4. What would billing every line at no less than list be worth, and how
        much volume could it risk at worst?

   METHOD
     - Lines of valid orders (not Cancelled or Returned). List in force =
       today's list price x the year's price factor (median invoice / list
       ratio of the year), as in the price discipline study.
     - Price deviation d = invoice price / list in force - 1.
     - Elasticity: the slope of ln(quantity) on ln(1 + d), with both centred
       within product x year (only variation in price around the same
       product's normal level is used). Standard error from the residuals;
       95 % interval = slope +/- 1.96 SE.
     - Discount is analysed the same way for comparison; unlike the price
       deviation, it is chosen by people and can depend on quantity.
     - Repeat purchase: did the customer buy the same product again within
       180 days (lines up to 31 Mar 2026), by price-deviation band.
   ============================================================================= */

DECLARE repeat_days      INT64 DEFAULT 180;
DECLARE last_repeat_line DATE  DEFAULT DATE '2026-03-31';

-- -----------------------------------------------------------------------------
-- Step 1 · Lines with the list in force and the price deviation
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pe_lines` AS
WITH base AS (
    SELECT
        i.order_item_id, i.order_id, o.customer_id, c.customer_segment, o.employee_id, o.order_date,
        EXTRACT(YEAR FROM o.order_date)                          AS price_year,
        i.product_id, i.quantity, i.unit_price, p.selling_price,
        IFNULL(i.discount_percent, 0)                            AS discount_pct,
        i.unit_price / p.selling_price                           AS price_ratio
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = i.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
factor AS (
    SELECT DISTINCT price_year, PERCENTILE_CONT(price_ratio, 0.5) OVER (PARTITION BY price_year) AS price_factor
    FROM base
)
SELECT
    b.*,
    b.selling_price * f.price_factor                             AS list_in_force,
    b.unit_price / (b.selling_price * f.price_factor) - 1        AS price_deviation,
    LN(b.quantity)                                               AS ln_qty,
    LN(b.unit_price / (b.selling_price * f.price_factor))        AS ln_price_dev,
    LN(1 - b.discount_pct / 100)                                 AS ln_discount_factor
FROM base AS b
JOIN factor AS f ON f.price_year = b.price_year;

-- Centred within product x year
CREATE OR REPLACE TABLE `sahyadri_b2b.pe_centred` AS
SELECT
    order_item_id, product_id, price_year, customer_id, order_date,
    ln_qty - AVG(ln_qty) OVER (PARTITION BY product_id, price_year)                         AS y,
    ln_price_dev - AVG(ln_price_dev) OVER (PARTITION BY product_id, price_year)             AS x_price,
    ln_discount_factor - AVG(ln_discount_factor) OVER (PARTITION BY product_id, price_year) AS x_discount,
    COUNT(*) OVER (PARTITION BY product_id, price_year)                                     AS cell_lines
FROM `sahyadri_b2b.pe_lines`;

SELECT
    COUNT(*)                                                                  AS lines,
    COUNT(DISTINCT product_id)                                                AS products,
    ROUND(100 * MIN(price_deviation), 2)                                      AS min_deviation_pct,
    ROUND(100 * MAX(price_deviation), 2)                                      AS max_deviation_pct,
    ROUND(100 * STDDEV_POP(price_deviation), 2)                               AS sd_deviation_pct,
    ROUND(SUM(IF(price_deviation < 0, quantity * (list_in_force - unit_price), 0)) / 1e5, 1) AS billed_below_list_lakh,
    ROUND(SUM(IF(price_deviation > 0, quantity * (unit_price - list_in_force), 0)) / 1e5, 1) AS billed_above_list_lakh
FROM `sahyadri_b2b.pe_lines`;

-- -----------------------------------------------------------------------------
-- Step 2 · Is the deviation random? (balance checks)
-- -----------------------------------------------------------------------------
SELECT 'Segment' AS dimension, customer_segment AS grp, COUNT(*) AS lines,
       ROUND(100 * AVG(price_deviation), 3) AS avg_deviation_pct,
       ROUND(100 * STDDEV_POP(price_deviation) / SQRT(COUNT(*)), 3) AS standard_error_pct
FROM `sahyadri_b2b.pe_lines` GROUP BY customer_segment
UNION ALL
SELECT 'Quantity band',
       CASE WHEN quantity <= 2 THEN '1. 1-2' WHEN quantity <= 10 THEN '2. 3-10' WHEN quantity <= 50 THEN '3. 11-50' ELSE '4. 51+' END,
       COUNT(*), ROUND(100 * AVG(price_deviation), 3), ROUND(100 * STDDEV_POP(price_deviation) / SQRT(COUNT(*)), 3)
FROM `sahyadri_b2b.pe_lines` GROUP BY 2
UNION ALL
SELECT 'Discount band',
       CASE WHEN discount_pct = 0 THEN '1. None' WHEN discount_pct <= 5 THEN '2. Up to 5 %' WHEN discount_pct <= 10 THEN '3. 5-10 %' ELSE '4. Over 10 %' END,
       COUNT(*), ROUND(100 * AVG(price_deviation), 3), ROUND(100 * STDDEV_POP(price_deviation) / SQRT(COUNT(*)), 3)
FROM `sahyadri_b2b.pe_lines` GROUP BY 2
UNION ALL
SELECT 'Year', CAST(price_year AS STRING), COUNT(*), ROUND(100 * AVG(price_deviation), 3),
       ROUND(100 * STDDEV_POP(price_deviation) / SQRT(COUNT(*)), 3)
FROM `sahyadri_b2b.pe_lines` GROUP BY price_year
ORDER BY dimension, grp;

-- Correlation of the deviation with line characteristics
SELECT
    ROUND(CORR(price_deviation, ln_qty), 4)                    AS corr_with_ln_quantity,
    ROUND(CORR(price_deviation, discount_pct), 4)              AS corr_with_discount,
    ROUND(CORR(price_deviation, LN(selling_price)), 4)         AS corr_with_ln_list_price,
    ROUND(CORR(ln_discount_factor, ln_qty), 4)                 AS discount_corr_with_ln_quantity
FROM `sahyadri_b2b.pe_lines`;

-- -----------------------------------------------------------------------------
-- Step 3 · Elasticity: quantity against price deviation (and against discount)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pe_elasticity` AS
WITH fits AS (
    SELECT 'Price deviation (random)' AS driver,
           COUNT(*) AS n, SUM(x_price * y) / SUM(x_price * x_price) AS slope,
           SUM(x_price * x_price) AS sxx, SUM(y * y) AS syy, SUM(x_price * y) AS sxy,
           COUNT(DISTINCT CONCAT(CAST(product_id AS STRING), '-', CAST(price_year AS STRING))) AS cells
    FROM `sahyadri_b2b.pe_centred`
    WHERE cell_lines >= 2
    UNION ALL
    SELECT 'Discount (chosen by people)',
           COUNT(*), SUM(x_discount * y) / SUM(x_discount * x_discount),
           SUM(x_discount * x_discount), SUM(y * y), SUM(x_discount * y),
           COUNT(DISTINCT CONCAT(CAST(product_id AS STRING), '-', CAST(price_year AS STRING)))
    FROM `sahyadri_b2b.pe_centred`
    WHERE cell_lines >= 2
)
SELECT
    driver, n, cells, slope,
    -- residual variance with one degree of freedom per product-year cell and one for the slope
    SQRT((syy - POW(sxy, 2) / sxx) / (n - cells - 1) / sxx)          AS standard_error
FROM fits;

SELECT
    driver, n AS lines,
    ROUND(slope, 3)                                         AS elasticity,
    ROUND(standard_error, 3)                                AS standard_error,
    ROUND(slope - 1.96 * standard_error, 3)                 AS ci_low,
    ROUND(slope + 1.96 * standard_error, 3)                 AS ci_high,
    ROUND(slope / standard_error, 2)                        AS t_statistic
FROM `sahyadri_b2b.pe_elasticity`
ORDER BY driver DESC;

-- Units per line by deviation band, relative to the product-year average
SELECT
    CASE WHEN l.price_deviation < -0.02 THEN '1. 2-3 % below list'
         WHEN l.price_deviation < -0.01 THEN '2. 1-2 % below'
         WHEN l.price_deviation < 0      THEN '3. 0-1 % below'
         WHEN l.price_deviation < 0.01   THEN '4. 0-1 % above'
         WHEN l.price_deviation < 0.02   THEN '5. 1-2 % above'
         ELSE '6. 2-3 % above' END                                           AS price_band,
    COUNT(*)                                                                 AS lines,
    ROUND(100 * (EXP(AVG(c.y)) - 1), 1)                                      AS units_vs_product_normal_pct,
    ROUND(100 * STDDEV_SAMP(c.y) / SQRT(COUNT(*)), 1)                        AS standard_error_pct
FROM `sahyadri_b2b.pe_lines` AS l
JOIN `sahyadri_b2b.pe_centred` AS c ON c.order_item_id = l.order_item_id
GROUP BY price_band
ORDER BY price_band;

-- -----------------------------------------------------------------------------
-- Step 4 · Does a high price stop the customer buying the product again?
-- -----------------------------------------------------------------------------
WITH repeat_flag AS (
    SELECT a.order_item_id, a.price_deviation,
           COUNTIF(b.order_item_id IS NOT NULL) > 0 AS bought_again
    FROM `sahyadri_b2b.pe_lines` AS a
    LEFT JOIN `sahyadri_b2b.pe_lines` AS b
      ON b.customer_id = a.customer_id AND b.product_id = a.product_id
     AND b.order_date > a.order_date AND b.order_date <= DATE_ADD(a.order_date, INTERVAL repeat_days DAY)
    WHERE a.order_date <= last_repeat_line
    GROUP BY a.order_item_id, a.price_deviation
)
SELECT
    CASE WHEN price_deviation < -0.01 THEN '1. More than 1 % below list'
         WHEN price_deviation <= 0.01 THEN '2. Within 1 % of list'
         ELSE '3. More than 1 % above list' END                              AS price_band,
    COUNT(*)                                                                 AS lines,
    ROUND(100 * AVG(IF(bought_again, 1, 0)), 1)                              AS bought_again_in_180_days_pct,
    ROUND(100 * SQRT(AVG(IF(bought_again, 1, 0)) * (1 - AVG(IF(bought_again, 1, 0))) / COUNT(*)), 1) AS standard_error_pts
FROM repeat_flag
GROUP BY price_band
ORDER BY price_band;

-- -----------------------------------------------------------------------------
-- Step 5 · What billing at no less than list would be worth
-- -----------------------------------------------------------------------------
-- each below-list line re-priced at list, with quantity adjusted by the elasticity: q x (list / price)^elasticity
WITH e AS (SELECT slope, standard_error FROM `sahyadri_b2b.pe_elasticity` WHERE driver LIKE 'Price%'),
scenarios AS (
    SELECT 'If customers ignored price (0)' AS scenario, 0.0 AS elasticity FROM e
    UNION ALL SELECT 'At the estimated elasticity', slope FROM e
    UNION ALL SELECT 'At the 95 % interval''s worst end', slope - 1.96 * standard_error FROM e
    UNION ALL SELECT 'If customers were unit-elastic (-1)', -1.0 FROM e
),
below AS (
    SELECT quantity, unit_price, list_in_force, order_date
    FROM `sahyadri_b2b.pe_lines`
    WHERE unit_price < list_in_force
)
SELECT
    s.scenario,
    ROUND(s.elasticity, 3)                                                                           AS elasticity,
    COUNT(*)                                                                                         AS lines_below_list,
    ROUND(SUM(b.quantity * b.unit_price) / 1e5, 1)                                                   AS revenue_now_lakh,
    ROUND(SUM(b.quantity * EXP(s.elasticity * LN(b.list_in_force / b.unit_price)) * b.list_in_force) / 1e5, 1) AS revenue_at_list_lakh,
    ROUND((SUM(b.quantity * EXP(s.elasticity * LN(b.list_in_force / b.unit_price)) * b.list_in_force)
           - SUM(b.quantity * b.unit_price)) / 1e5, 1)                                               AS gain_lakh,
    ROUND((SUM(b.quantity * EXP(s.elasticity * LN(b.list_in_force / b.unit_price)) * b.list_in_force)
           - SUM(b.quantity * b.unit_price)) / 1e5 * 365 / (DATE_DIFF(MAX(b.order_date), MIN(b.order_date), DAY) + 1), 1) AS gain_per_year_lakh
FROM below AS b
CROSS JOIN scenarios AS s
GROUP BY s.scenario, s.elasticity
ORDER BY s.elasticity DESC;
