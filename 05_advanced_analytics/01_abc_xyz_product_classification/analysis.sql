/* =============================================================================
   Case study · ABC-XYZ product classification for inventory policy
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The purchasing team applies the same stocking rule to all 200 products.
   Working capital is tied up in slow items while important items run short.
   The supply chain head wants each product placed in an inventory policy
   class based on two questions:
     - ABC: how much does the product contribute to revenue?
     - XYZ: how predictable is its monthly demand?
   and wants to know:
     1. How many products and how much revenue fall in each ABC-XYZ cell?
     2. What stocking policy should each cell follow?
     3. Which products had no demand at all in the last 12 months?
     4. Which high-value products have erratic demand and need close review?

   KEY RULES
     - Period: last 12 complete months, Oct 2025 to Sep 2026.
     - Demand: quantity on orders not Cancelled or Returned, by order month.
     - Revenue: SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)).
     - ABC (revenue, cumulative share, highest first):
         A = products making up the first 80 % · B = next 15 % · C = last 5 %
     - XYZ (coefficient of variation, CV = std dev / mean of monthly quantity,
       months with no demand counted as zero):
         X = CV <= 0.5 (stable) · Y = 0.5 < CV <= 1.0 (variable) · Z = CV > 1.0 (erratic)
     - Products with no demand in the period are classed 'N' (no movement).
   ============================================================================= */

DECLARE period_start DATE DEFAULT DATE '2025-10-01';
DECLARE period_end   DATE DEFAULT DATE '2026-09-01';   -- first day of the last month

-- -----------------------------------------------------------------------------
-- Step 1 · Product classification table
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.product_abc_xyz` AS
WITH months AS (
    SELECT month_start
    FROM UNNEST(GENERATE_DATE_ARRAY(period_start, period_end, INTERVAL 1 MONTH)) AS month_start
),

monthly_demand AS (
    SELECT
        i.product_id,
        DATE_TRUNC(o.order_date, MONTH)                                           AS month_start,
        SUM(i.quantity)                                                           AS quantity,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o
        ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND DATE_TRUNC(o.order_date, MONTH) BETWEEN period_start AND period_end
    GROUP BY i.product_id, month_start
),

-- every product x every month, with zero where nothing was sold
product_month AS (
    SELECT
        p.product_id,
        m.month_start,
        IFNULL(d.quantity, 0) AS quantity,
        IFNULL(d.revenue, 0)  AS revenue
    FROM `sahyadri_b2b.products` AS p
    CROSS JOIN months            AS m
    LEFT JOIN monthly_demand     AS d
        ON d.product_id  = p.product_id
       AND d.month_start = m.month_start
),

product_stats AS (
    SELECT
        product_id,
        SUM(revenue)                              AS revenue_12m,
        SUM(quantity)                             AS quantity_12m,
        COUNTIF(quantity > 0)                     AS months_with_demand,
        AVG(quantity)                             AS avg_monthly_qty,
        STDDEV_SAMP(quantity)                     AS stddev_monthly_qty,
        SAFE_DIVIDE(STDDEV_SAMP(quantity), AVG(quantity)) AS demand_cv
    FROM product_month
    GROUP BY product_id
),

ranked AS (
    SELECT
        *,
        SAFE_DIVIDE(revenue_12m, SUM(revenue_12m) OVER ()) AS revenue_share,
        SAFE_DIVIDE(
            SUM(revenue_12m) OVER (ORDER BY revenue_12m DESC, product_id
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
            SUM(revenue_12m) OVER ())                       AS cumulative_share
    FROM product_stats
),

classified AS (
    SELECT
        *,
        CASE
            WHEN revenue_12m = 0                         THEN 'N'
            WHEN cumulative_share - revenue_share < 0.80 THEN 'A'
            WHEN cumulative_share - revenue_share < 0.95 THEN 'B'
            ELSE                                              'C'
        END AS abc_class,
        CASE
            WHEN quantity_12m = 0  THEN 'N'
            WHEN demand_cv <= 0.5  THEN 'X'
            WHEN demand_cv <= 1.0  THEN 'Y'
            ELSE                        'Z'
        END AS xyz_class
    FROM ranked
)

SELECT
    c.product_id,
    p.product_name,
    pc.category_name,
    ROUND(c.revenue_12m, 2)               AS revenue_12m,
    c.quantity_12m,
    c.months_with_demand,
    ROUND(c.avg_monthly_qty, 2)           AS avg_monthly_qty,
    ROUND(c.demand_cv, 3)                 AS demand_cv,
    ROUND(100 * c.cumulative_share, 2)    AS cumulative_revenue_pct,
    c.abc_class,
    c.xyz_class,
    CONCAT(c.abc_class, c.xyz_class)      AS abc_xyz,
    CASE
        WHEN c.abc_class = 'N'                     THEN '5. Review for discontinuation'
        WHEN CONCAT(c.abc_class, c.xyz_class) IN ('AX', 'AY', 'BX')
                                                   THEN '1. Keep in stock, high service level'
        WHEN CONCAT(c.abc_class, c.xyz_class) IN ('AZ', 'BZ')
                                                   THEN '3. Stock on forecast, review monthly'
        WHEN CONCAT(c.abc_class, c.xyz_class) IN ('BY', 'CX')
                                                   THEN '2. Keep in stock, standard service level'
        ELSE                                            '4. Make or buy to order, minimal stock'
    END                                   AS stocking_policy
FROM classified                         AS c
JOIN `sahyadri_b2b.products`            AS p  ON p.product_id   = c.product_id
JOIN `sahyadri_b2b.product_categories`  AS pc ON pc.category_id = p.category_id;

-- -----------------------------------------------------------------------------
-- Step 2 · ABC-XYZ matrix: products and revenue share per cell
-- -----------------------------------------------------------------------------
SELECT
    abc_class,
    COUNTIF(xyz_class = 'X')                                          AS x_products,
    COUNTIF(xyz_class = 'Y')                                          AS y_products,
    COUNTIF(xyz_class = 'Z')                                          AS z_products,
    COUNTIF(xyz_class = 'N')                                          AS no_demand_products,
    COUNT(*)                                                          AS products,
    ROUND(100 * SUM(revenue_12m) / SUM(SUM(revenue_12m)) OVER (), 1)  AS pct_of_revenue
FROM `sahyadri_b2b.product_abc_xyz`
GROUP BY abc_class
ORDER BY abc_class;

-- -----------------------------------------------------------------------------
-- Step 3 · Stocking policy summary
-- -----------------------------------------------------------------------------
SELECT
    stocking_policy,
    STRING_AGG(DISTINCT abc_xyz ORDER BY abc_xyz)                     AS cells,
    COUNT(*)                                                          AS products,
    ROUND(SUM(revenue_12m), 2)                                        AS revenue_12m,
    ROUND(100 * SUM(revenue_12m) / SUM(SUM(revenue_12m)) OVER (), 1)  AS pct_of_revenue
FROM `sahyadri_b2b.product_abc_xyz`
GROUP BY stocking_policy
ORDER BY stocking_policy;

-- -----------------------------------------------------------------------------
-- Step 4 · High-value products with erratic demand (AZ) — review list
-- -----------------------------------------------------------------------------
SELECT
    product_id,
    product_name,
    category_name,
    revenue_12m,
    months_with_demand,
    avg_monthly_qty,
    demand_cv
FROM `sahyadri_b2b.product_abc_xyz`
WHERE abc_xyz = 'AZ'
ORDER BY revenue_12m DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Products with no demand in the last 12 months
-- -----------------------------------------------------------------------------
SELECT
    a.product_id,
    a.product_name,
    a.category_name,
    MAX(o.order_date)                                    AS last_order_date_ever,
    COUNT(DISTINCT o.order_id)                           AS orders_ever
FROM `sahyadri_b2b.product_abc_xyz`        AS a
LEFT JOIN `sahyadri_b2b.sales_order_items` AS i ON i.product_id = a.product_id
LEFT JOIN `sahyadri_b2b.sales_orders`      AS o
    ON o.order_id = i.order_id
   AND o.order_status NOT IN ('Cancelled', 'Returned')
WHERE a.abc_class = 'N'
GROUP BY a.product_id, a.product_name, a.category_name
ORDER BY last_order_date_ever DESC, a.product_id;
