/* =============================================================================
   Case study · Safety stock and reorder points
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Purchasing reorders by experience: "keep about a month of stock". That
   gives too much stock of slow, predictable items and too little of fast,
   erratic ones. The supply chain manager wants a reorder policy for every
   product, with service levels set by importance:
     1. How much safety stock does each product need, and what reorder point
        and order quantity follow from it?
     2. What does the policy cost in stock investment, and how much does
        differentiating service levels by ABC class save against a uniform
        high service level?
     3. Would it have worked? Backtest: with parameters set on one year of
        demand, how often would the next year's demand during the lead time
        have been covered?
     4. For which products does the method not fit, so that a different
        policy (make to order) is needed?

   METHOD
     Weekly demand per product, zero-filled. For the review year:
       d = mean weekly demand, s = standard deviation of weekly demand
     Safety stock  SS  = z * SQRT(L * s^2 + d^2 * sL^2)
                         L = supplier lead time (weeks), sL = its std dev
     Reorder point ROP = d * L + SS
     Order quantity EOQ = SQRT(2 * annual demand * order cost / (holding rate * unit cost))
     Average stock = SS + EOQ / 2
     Service level (cycle service level) by revenue class:
       A 98 % (z = 2.0537) · B 95 % (z = 1.6449) · C 90 % (z = 1.2816)
     Demand pattern: "Lumpy" if more than half the weeks have no demand or
     the coefficient of variation exceeds 1.5; otherwise "Regular".

   ASSUMPTIONS (declared below; the dataset has no supplier or stock data)
     - Supplier lead time 3 weeks with a standard deviation of 1 week.
     - Ordering cost ₹1,500 per purchase order line; holding cost 24 % a
       year of unit cost.

   KEY RULES
     - Demand = units on orders not Cancelled or Returned, by order week
       (ISO weeks starting Monday).
     - Training year: weeks starting 30 Sep 2024 - 22 Sep 2025.
       Review year:   weeks starting 29 Sep 2025 - 21 Sep 2026.
   ============================================================================= */

DECLARE train_start      DATE    DEFAULT DATE '2024-09-30';
DECLARE review_start     DATE    DEFAULT DATE '2025-09-29';
DECLARE last_week        DATE    DEFAULT DATE '2026-09-21';
DECLARE lead_time_weeks  FLOAT64 DEFAULT 3;
DECLARE lead_time_sd     FLOAT64 DEFAULT 1;
DECLARE order_cost       FLOAT64 DEFAULT 1500;
DECLARE holding_rate     FLOAT64 DEFAULT 0.24;

-- -----------------------------------------------------------------------------
-- Step 1 · Weekly demand per product, zero-filled over both years
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.weekly_product_demand` AS
WITH weeks AS (
    SELECT week_start FROM UNNEST(GENERATE_DATE_ARRAY(train_start, last_week, INTERVAL 1 WEEK)) AS week_start
),
demand AS (
    SELECT
        i.product_id,
        DATE_TRUNC(o.order_date, ISOWEEK)                                          AS week_start,
        SUM(i.quantity)                                                            AS units,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND DATE_TRUNC(o.order_date, ISOWEEK) BETWEEN train_start AND last_week
    GROUP BY i.product_id, week_start
)
SELECT
    p.product_id,
    w.week_start,
    IF(w.week_start >= review_start, 'Review', 'Training')  AS period,
    IFNULL(d.units, 0)                                       AS units,
    IFNULL(d.revenue, 0)                                     AS revenue
FROM `sahyadri_b2b.products` AS p
CROSS JOIN weeks             AS w
LEFT JOIN demand             AS d ON d.product_id = p.product_id AND d.week_start = w.week_start;

-- -----------------------------------------------------------------------------
-- Step 2 · Policy per product: class, demand statistics, SS, ROP, EOQ
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.safety_stock_policy` AS
WITH stats AS (
    SELECT
        product_id,
        period,
        AVG(units)                         AS mean_weekly,
        STDDEV_SAMP(units)                 AS sd_weekly,
        COUNTIF(units = 0) / COUNT(*)      AS zero_week_share,
        SUM(revenue)                       AS revenue
    FROM `sahyadri_b2b.weekly_product_demand`
    GROUP BY product_id, period
),
review AS (SELECT * FROM stats WHERE period = 'Review'),
abc AS (
    SELECT
        product_id,
        CASE
            WHEN revenue = 0 THEN 'No demand'
            WHEN IFNULL(SUM(revenue) OVER (ORDER BY revenue DESC, product_id
                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) / SUM(revenue) OVER () < 0.80 THEN 'A'
            WHEN IFNULL(SUM(revenue) OVER (ORDER BY revenue DESC, product_id
                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) / SUM(revenue) OVER () < 0.95 THEN 'B'
            ELSE 'C'
        END AS abc_class
    FROM review
),
policy_inputs AS (
    SELECT
        r.product_id,
        a.abc_class,
        r.mean_weekly,
        r.sd_weekly,
        SAFE_DIVIDE(r.sd_weekly, r.mean_weekly)                         AS cv,
        r.zero_week_share,
        CASE a.abc_class WHEN 'A' THEN 0.98 WHEN 'B' THEN 0.95 WHEN 'C' THEN 0.90 END   AS service_level,
        CASE a.abc_class WHEN 'A' THEN 2.0537 WHEN 'B' THEN 1.6449 WHEN 'C' THEN 1.2816 END AS z
    FROM review AS r
    JOIN abc    AS a ON a.product_id = r.product_id
)
SELECT
    i.product_id,
    p.product_name,
    pc.category_name,
    p.unit_cost,
    i.abc_class,
    CASE
        WHEN i.abc_class = 'No demand'                     THEN 'No demand'
        WHEN i.zero_week_share > 0.5 OR i.cv > 1.5         THEN 'Lumpy'
        ELSE 'Regular'
    END                                                                     AS demand_pattern,
    ROUND(i.mean_weekly, 3)                                                 AS mean_weekly_units,
    ROUND(i.sd_weekly, 3)                                                   AS sd_weekly_units,
    ROUND(i.cv, 3)                                                          AS cv,
    ROUND(i.zero_week_share, 3)                                             AS zero_week_share,
    i.service_level,
    i.z,
    CEIL(i.z * SQRT(lead_time_weeks * POW(i.sd_weekly, 2)
                    + POW(i.mean_weekly, 2) * POW(lead_time_sd, 2)))        AS safety_stock_units,
    CEIL(i.mean_weekly * lead_time_weeks
         + i.z * SQRT(lead_time_weeks * POW(i.sd_weekly, 2)
                      + POW(i.mean_weekly, 2) * POW(lead_time_sd, 2)))      AS reorder_point_units,
    CEIL(SAFE_DIVIDE(SQRT(2 * i.mean_weekly * 52 * order_cost),
                     SQRT(holding_rate * p.unit_cost)))                     AS eoq_units,
    -- uniform alternative: every product at the A-class 98 % level
    CEIL(2.0537 * SQRT(lead_time_weeks * POW(i.sd_weekly, 2)
                       + POW(i.mean_weekly, 2) * POW(lead_time_sd, 2)))     AS safety_stock_units_uniform_98
FROM policy_inputs                    AS i
JOIN `sahyadri_b2b.products`          AS p  ON p.product_id   = i.product_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id;

-- -----------------------------------------------------------------------------
-- Step 3 · Stock investment by class, and saving against a uniform 98 % policy
-- -----------------------------------------------------------------------------
SELECT
    abc_class,
    COUNT(*)                                                                          AS products,
    COUNTIF(demand_pattern = 'Lumpy')                                                 AS lumpy_products,
    ANY_VALUE(service_level)                                                          AS service_level,
    ROUND(SUM(safety_stock_units * unit_cost), 0)                                     AS safety_stock_value,
    ROUND(SUM((safety_stock_units + eoq_units / 2) * unit_cost), 0)                   AS average_stock_value,
    ROUND(SUM(safety_stock_units_uniform_98 * unit_cost), 0)                          AS safety_stock_value_uniform_98,
    ROUND(SUM((safety_stock_units_uniform_98 - safety_stock_units) * unit_cost), 0)   AS saving_vs_uniform
FROM `sahyadri_b2b.safety_stock_policy`
WHERE abc_class <> 'No demand' AND unit_cost IS NOT NULL
GROUP BY abc_class
ORDER BY abc_class;

-- -----------------------------------------------------------------------------
-- Step 4 · Backtest: parameters from the training year, demand from the review year
--          A replenishment cycle is "covered" when demand in the L weeks after
--          the reorder point is reached does not exceed the reorder point.
--          Approximated by every rolling 3-week window of review-year demand.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.safety_stock_backtest` AS
WITH train AS (
    SELECT product_id, AVG(units) AS mean_weekly, STDDEV_SAMP(units) AS sd_weekly
    FROM `sahyadri_b2b.weekly_product_demand`
    WHERE period = 'Training'
    GROUP BY product_id
),
rop AS (
    SELECT
        t.product_id,
        p.abc_class,
        p.demand_pattern,
        p.service_level,
        t.mean_weekly * lead_time_weeks
          + p.z * SQRT(lead_time_weeks * POW(t.sd_weekly, 2) + POW(t.mean_weekly, 2) * POW(lead_time_sd, 2)) AS reorder_point
    FROM train AS t
    JOIN `sahyadri_b2b.safety_stock_policy` AS p ON p.product_id = t.product_id
    WHERE p.abc_class <> 'No demand'
),
windows AS (
    SELECT
        product_id,
        week_start,
        SUM(units) OVER (PARTITION BY product_id ORDER BY week_start ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS lead_time_demand,
        COUNT(*)   OVER (PARTITION BY product_id ORDER BY week_start ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS weeks_in_window
    FROM `sahyadri_b2b.weekly_product_demand`
    WHERE period = 'Review'
)
SELECT
    r.product_id,
    r.abc_class,
    r.demand_pattern,
    r.service_level,
    COUNT(*)                                          AS windows,
    COUNTIF(w.lead_time_demand <= r.reorder_point)    AS covered_windows
FROM rop     AS r
JOIN windows AS w ON w.product_id = r.product_id
WHERE w.weeks_in_window = 3
GROUP BY r.product_id, r.abc_class, r.demand_pattern, r.service_level;

SELECT
    abc_class,
    demand_pattern,
    COUNT(*)                                                          AS products,
    ANY_VALUE(service_level)                                          AS target_service_level,
    ROUND(SUM(covered_windows) / SUM(windows), 4)                     AS achieved_coverage,
    COUNTIF(covered_windows / windows < service_level)                AS products_below_target
FROM `sahyadri_b2b.safety_stock_backtest`
GROUP BY abc_class, demand_pattern
ORDER BY abc_class, demand_pattern;

-- Diagnostic: was the shortfall caused by demand growth? Re-run the backtest
-- with training demand scaled by the actual unit growth between the two years.
-- (Uses review-year information, so it is a diagnosis, not a usable policy.)
WITH growth AS (
    SELECT SUM(IF(period = 'Review', units, 0)) / SUM(IF(period = 'Training', units, 0)) AS factor
    FROM `sahyadri_b2b.weekly_product_demand`
),
train AS (
    SELECT product_id, AVG(units) AS mean_weekly, STDDEV_SAMP(units) AS sd_weekly
    FROM `sahyadri_b2b.weekly_product_demand`
    WHERE period = 'Training'
    GROUP BY product_id
),
rop AS (
    SELECT
        t.product_id, p.abc_class, p.demand_pattern, p.service_level,
        t.mean_weekly * g.factor * lead_time_weeks
          + p.z * SQRT(lead_time_weeks * POW(t.sd_weekly * g.factor, 2)
                       + POW(t.mean_weekly * g.factor, 2) * POW(lead_time_sd, 2)) AS reorder_point
    FROM train AS t
    CROSS JOIN growth AS g
    JOIN `sahyadri_b2b.safety_stock_policy` AS p ON p.product_id = t.product_id
    WHERE p.abc_class <> 'No demand'
),
windows AS (
    SELECT
        product_id,
        SUM(units) OVER (PARTITION BY product_id ORDER BY week_start ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS lead_time_demand,
        COUNT(*)   OVER (PARTITION BY product_id ORDER BY week_start ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS weeks_in_window
    FROM `sahyadri_b2b.weekly_product_demand`
    WHERE period = 'Review'
)
SELECT
    r.abc_class,
    r.demand_pattern,
    ANY_VALUE(r.service_level)                                                  AS target_service_level,
    ROUND(COUNTIF(w.lead_time_demand <= r.reorder_point) / COUNT(*), 4)         AS growth_adjusted_coverage,
    ROUND(ANY_VALUE(g.factor), 4)                                               AS unit_growth_factor
FROM rop AS r
JOIN windows AS w ON w.product_id = r.product_id
CROSS JOIN growth AS g
WHERE w.weeks_in_window = 3
GROUP BY r.abc_class, r.demand_pattern
ORDER BY r.abc_class, r.demand_pattern;

-- -----------------------------------------------------------------------------
-- Step 5 · Reorder table for the 10 highest-revenue regular products
-- -----------------------------------------------------------------------------
SELECT
    s.product_id,
    s.product_name,
    s.abc_class,
    s.mean_weekly_units,
    s.sd_weekly_units,
    s.safety_stock_units,
    s.reorder_point_units,
    s.eoq_units,
    ROUND(s.safety_stock_units * s.unit_cost, 0)       AS safety_stock_value
FROM `sahyadri_b2b.safety_stock_policy` AS s
JOIN (SELECT product_id, SUM(revenue) AS revenue
        FROM `sahyadri_b2b.weekly_product_demand` WHERE period = 'Review' GROUP BY product_id) AS r
  ON r.product_id = s.product_id
WHERE s.demand_pattern = 'Regular'
ORDER BY r.revenue DESC
LIMIT 10;
