/* =============================================================================
   Case study · Who drives the March peak?
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   March, the last month of the Indian financial year, is the biggest month
   every year: revenue runs about 60 % above trend. The sales director wants
   to plan the next March deliberately: pre-book stock and dispatch capacity
   and call the customers who will order. He asks:
     1. Is the March peak more customers ordering, more orders from each,
        or bigger orders?
     2. Is it a few large "budget-flush" accounts, or nearly everyone?
     3. Does it come from particular segments or industries?
     4. Do the same customers spike every March, so they can be targeted?

   METHOD
     - Valid orders (not Cancelled or Returned), 2024 - 2026.
     - Baseline for each year: the monthly average of January, February,
       April, May and June of the same year (the months around March).
       March index = March / baseline.
     - Decomposition: revenue = active customers x orders per active
       customer x average order value; each driver's share of the March
       uplift is its log change divided by the log change in revenue
       (the shares add up to 100 %).
     - Segment and industry: chi-square test of whether March is the same
       share of every group's orders (2 x k table, March against baseline
       months, all three years pooled); z for each group.
     - Persistence: for customers ordering in both 2025 and 2026, the
       correlation of their March excess orders (March - baseline) between
       the two years, and how often a 2025 "spiker" (at least 2 extra
       orders and double its baseline) spiked again in 2026.
   ============================================================================= */

DECLARE large_order FLOAT64 DEFAULT 500000;

-- -----------------------------------------------------------------------------
-- Step 1 · Orders in March and in the baseline months
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mp_orders` AS
SELECT
    o.order_id, o.customer_id, c.customer_segment, IFNULL(c.industry, 'Unknown') AS industry,
    o.order_date, EXTRACT(YEAR FROM o.order_date) AS yr, EXTRACT(MONTH FROM o.order_date) AS mo,
    IF(EXTRACT(MONTH FROM o.order_date) = 3, 'March', 'Baseline') AS period,
    SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
  AND EXTRACT(MONTH FROM o.order_date) IN (1, 2, 3, 4, 5, 6)
GROUP BY o.order_id, o.customer_id, c.customer_segment, c.industry, o.order_date;

-- -----------------------------------------------------------------------------
-- Step 2 · March against the baseline, and the decomposition of the uplift
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mp_company` AS
WITH monthly AS (
    SELECT yr, mo, period, COUNT(*) AS orders, COUNT(DISTINCT customer_id) AS customers, SUM(order_value) AS revenue,
           SUM(IF(order_value < large_order, order_value, 0)) AS revenue_excl_large
    FROM `sahyadri_b2b.mp_orders`
    GROUP BY yr, mo, period
)
SELECT
    yr,
    MAX(IF(period = 'March', revenue, NULL))              AS march_revenue,
    AVG(IF(period = 'Baseline', revenue, NULL))           AS base_revenue,
    MAX(IF(period = 'March', orders, NULL))               AS march_orders,
    AVG(IF(period = 'Baseline', orders, NULL))            AS base_orders,
    MAX(IF(period = 'March', customers, NULL))            AS march_customers,
    AVG(IF(period = 'Baseline', customers, NULL))         AS base_customers,
    MAX(IF(period = 'March', revenue_excl_large, NULL))   AS march_revenue_excl_large,
    AVG(IF(period = 'Baseline', revenue_excl_large, NULL)) AS base_revenue_excl_large
FROM monthly
GROUP BY yr;

SELECT
    yr,
    ROUND(march_revenue / 1e5, 1)                                                   AS march_revenue_lakh,
    ROUND(base_revenue / 1e5, 1)                                                    AS baseline_month_lakh,
    ROUND(100 * (march_revenue / base_revenue - 1), 1)                              AS revenue_uplift_pct,
    ROUND(100 * (march_customers / base_customers - 1), 1)                          AS customers_uplift_pct,
    ROUND(100 * ((march_orders / march_customers) / (base_orders / base_customers) - 1), 1) AS orders_per_customer_uplift_pct,
    ROUND(100 * ((march_revenue / march_orders) / (base_revenue / base_orders) - 1), 1)     AS order_value_uplift_pct,
    -- shares of the log uplift (add to 100 %)
    ROUND(100 * LN(march_customers / base_customers) / LN(march_revenue / base_revenue), 1)                                   AS share_customers_pct,
    ROUND(100 * LN((march_orders / march_customers) / (base_orders / base_customers)) / LN(march_revenue / base_revenue), 1)  AS share_frequency_pct,
    ROUND(100 * LN((march_revenue / march_orders) / (base_revenue / base_orders)) / LN(march_revenue / base_revenue), 1)      AS share_order_value_pct,
    ROUND(100 * (march_revenue_excl_large / base_revenue_excl_large - 1), 1)        AS uplift_without_large_orders_pct
FROM `sahyadri_b2b.mp_company`
ORDER BY yr;

-- -----------------------------------------------------------------------------
-- Step 3 · Segments and industries: is the uplift everywhere?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mp_groups` AS
WITH by_group AS (
    SELECT 'Segment' AS dimension, customer_segment AS grp, period, COUNT(*) AS orders, SUM(order_value) AS revenue
    FROM `sahyadri_b2b.mp_orders` GROUP BY customer_segment, period
    UNION ALL
    SELECT 'Industry', industry, period, COUNT(*), SUM(order_value)
    FROM `sahyadri_b2b.mp_orders` GROUP BY industry, period
),
wide AS (
    SELECT dimension, grp,
           SUM(IF(period = 'March', orders, 0))     AS march_orders,
           SUM(IF(period = 'Baseline', orders, 0))  AS base_orders,
           SUM(IF(period = 'March', revenue, 0))    AS march_revenue,
           SUM(IF(period = 'Baseline', revenue, 0)) AS base_revenue
    FROM by_group GROUP BY dimension, grp
)
SELECT
    w.*,
    -- index: March monthly orders / baseline monthly orders (5 baseline months a year)
    w.march_orders / (w.base_orders / 5)                                                        AS order_index,
    w.march_revenue / (w.base_revenue / 5)                                                      AS revenue_index,
    -- expected March orders if March were the same share of the group's orders as of all orders
    (w.march_orders + w.base_orders) * SUM(w.march_orders) OVER (PARTITION BY w.dimension)
      / SUM(w.march_orders + w.base_orders) OVER (PARTITION BY w.dimension)                    AS expected_march_orders
FROM wide AS w;

SELECT
    dimension, grp,
    march_orders, ROUND(expected_march_orders, 1)                 AS expected_march_orders,
    ROUND(order_index, 2)                                         AS march_order_index,
    ROUND(revenue_index, 2)                                       AS march_revenue_index,
    ROUND((march_orders - expected_march_orders)
          / SQRT(expected_march_orders * (1 - expected_march_orders / (march_orders + base_orders))), 2) AS z
FROM `sahyadri_b2b.mp_groups`
WHERE base_orders >= 50
ORDER BY dimension DESC, order_index DESC;

-- Homogeneity test: does any dimension change its order mix in March?
SELECT
    dimension,
    COUNT(*)                                                                     AS groups,
    ROUND(SUM(POW(march_orders - expected_march_orders, 2) / expected_march_orders
            + POW(base_orders - (base_orders + march_orders - expected_march_orders), 2)
              / (base_orders + march_orders - expected_march_orders)), 2)        AS chi_square,
    COUNT(*) - 1                                                                 AS df,
    ROUND((COUNT(*) - 1) * POW(1 - 2 / (9 * (COUNT(*) - 1)) + 1.6449 * SQRT(2 / (9 * (COUNT(*) - 1))), 3), 2) AS critical_5pct
FROM `sahyadri_b2b.mp_groups`
GROUP BY dimension;

-- -----------------------------------------------------------------------------
-- Step 4 · Breadth and persistence at customer level
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mp_customers` AS
SELECT
    customer_id, yr,
    COUNTIF(period = 'March')                                  AS march_orders,
    COUNTIF(period = 'Baseline') / 5                           AS base_orders_per_month,
    COUNTIF(period = 'March') - COUNTIF(period = 'Baseline') / 5 AS excess_orders,
    COUNTIF(period = 'March') >= 2 * COUNTIF(period = 'Baseline') / 5
      AND COUNTIF(period = 'March') - COUNTIF(period = 'Baseline') / 5 >= 2 AS spiker
FROM `sahyadri_b2b.mp_orders`
GROUP BY customer_id, yr;

SELECT
    yr,
    COUNT(*)                                                                     AS customers_active_jan_jun,
    COUNTIF(excess_orders > 0)                                                   AS ordered_more_in_march,
    ROUND(100 * COUNTIF(excess_orders > 0) / COUNT(*), 1)                        AS ordered_more_pct,
    ROUND(SUM(excess_orders), 1)                                                 AS total_excess_orders,
    ROUND(SUM(IF(excess_orders >= 3, excess_orders, 0)), 1)                      AS excess_from_customers_with_3_plus_extra,
    COUNTIF(spiker)                                                              AS spikers
FROM `sahyadri_b2b.mp_customers`
GROUP BY yr
ORDER BY yr;

SELECT
    COUNT(*)                                                                     AS customers_in_both_years,
    ROUND(CORR(a.excess_orders, b.excess_orders), 3)                             AS corr_excess_2025_2026,
    COUNTIF(a.spiker)                                                            AS spikers_2025,
    COUNTIF(a.spiker AND b.spiker)                                               AS spiked_again_2026,
    ROUND(100 * COUNTIF(a.spiker AND b.spiker) / NULLIF(COUNTIF(a.spiker), 0), 1) AS repeat_rate_pct,
    ROUND(100 * COUNTIF(b.spiker) / COUNT(*), 1)                                 AS spike_rate_2026_all_pct,
    ROUND(100 * COUNTIF(b.spiker AND NOT a.spiker) / NULLIF(COUNTIF(NOT a.spiker), 0), 1) AS spike_rate_2026_non_spikers_pct
FROM `sahyadri_b2b.mp_customers` AS a
JOIN `sahyadri_b2b.mp_customers` AS b ON b.customer_id = a.customer_id AND a.yr = 2025 AND b.yr = 2026;
