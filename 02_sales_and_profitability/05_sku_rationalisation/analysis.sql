/* =============================================================================
   Case study · SKU rationalisation: product profitability review
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The range has 200 products. Every product costs money to list, buy, stock,
   price and pick, whether it earns or not. The ABC-XYZ case study ranks
   products by revenue, which shows what sells but not what earns. The
   category managers want a margin-based review of the range:
     1. How concentrated is gross profit across products?
     2. Which products sell well but earn too little per sale (reprice), and
        which sell little and earn little (delist review)?
     3. What would repricing the low-margin sellers be worth?
     4. If the delist-review products were dropped, which customers depend
        on them?

   KEY RULES
     - Window: last 12 months, 1 Oct 2025 - 30 Sep 2026.
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Product cost: quantity * products.unit_cost (standard cost).
     - Gross profit (GP) = revenue - product cost. GP margin = GP / revenue.
     - Revenue class (same basis as the ABC-XYZ case study): products ranked
       by revenue; A = first 80 % of revenue, B = next 15 %, C = last 5 %.
     - GP rank: products ranked by GP. "GP core" = the products that earn the
       first 80 % of GP.
     - Low margin: GP margin below 10 % (declared as low_margin).
     - Action (first rule that applies):
         1. No sales in 12 months            -> Delist: no demand
         2. No unit cost in master           -> Fix cost data first
         3. GP below zero                    -> Reprice or stop: loss-making
         4. Class C and low margin           -> Delist review
         5. Class A or B and low margin      -> Reprice
         6. GP core                          -> Protect
         7. Otherwise                        -> Maintain
     - Dependent customer: a customer for whom the product is at least 10 %
       of their 12-month spend.
   ============================================================================= */

DECLARE window_start   DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE low_margin     FLOAT64 DEFAULT 0.10;
DECLARE dependent_pct  FLOAT64 DEFAULT 0.10;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per product: revenue, gross profit, classes and action
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sku_profitability` AS
WITH product_sales AS (
    SELECT
        i.product_id,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue,
        SUM(i.quantity * p.unit_cost)                                              AS product_cost,
        SUM(i.quantity)                                                            AS units,
        COUNT(DISTINCT o.order_id)                                                 AS orders,
        COUNT(DISTINCT o.customer_id)                                              AS customers
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id   = i.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN window_start AND window_end
    GROUP BY i.product_id
),
base AS (
    SELECT
        p.product_id,
        p.product_name,
        pc.category_name,
        p.unit_cost,
        p.selling_price,
        IFNULL(s.revenue, 0)                                      AS revenue,
        IFNULL(s.units, 0)                                        AS units,
        IFNULL(s.orders, 0)                                       AS orders,
        IFNULL(s.customers, 0)                                    AS customers,
        IF(p.unit_cost IS NULL, NULL, s.revenue - s.product_cost) AS gross_profit
    FROM `sahyadri_b2b.products`           AS p
    JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
    LEFT JOIN product_sales                AS s  ON s.product_id   = p.product_id
),
revenue_rank AS (
    SELECT
        product_id,
        -- revenue of all products ranked above this one, as a share of the total
        IFNULL(SUM(revenue) OVER (ORDER BY revenue DESC, product_id
                                  ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
          / SUM(revenue) OVER ()                                  AS revenue_share_before
    FROM base
    WHERE revenue > 0
),
gp_rank AS (
    SELECT
        product_id,
        IFNULL(SUM(gross_profit) OVER (ORDER BY gross_profit DESC, product_id
                                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
          / SUM(gross_profit) OVER ()                             AS gp_share_before
    FROM base
    WHERE revenue > 0 AND gross_profit IS NOT NULL
),
classified AS (
    SELECT
        b.*,
        SAFE_DIVIDE(b.gross_profit, b.revenue)                    AS gp_margin_raw,
        CASE
            WHEN r.product_id IS NULL                THEN NULL
            WHEN r.revenue_share_before < 0.80       THEN 'A'
            WHEN r.revenue_share_before < 0.95       THEN 'B'
            ELSE 'C'
        END                                                       AS revenue_class,
        g.gp_share_before,
        g.gp_share_before < 0.80                                  AS is_gp_core
    FROM base              AS b
    LEFT JOIN revenue_rank AS r ON r.product_id = b.product_id
    LEFT JOIN gp_rank      AS g ON g.product_id = b.product_id
)
SELECT
    product_id,
    product_name,
    category_name,
    unit_cost,
    selling_price,
    ROUND(revenue, 2)                   AS revenue,
    units,
    orders,
    customers,
    ROUND(gross_profit, 2)              AS gross_profit,
    ROUND(gp_margin_raw, 4)             AS gp_margin,
    revenue_class,
    ROUND(gp_share_before, 4)           AS gp_share_before,
    IFNULL(is_gp_core, FALSE)           AS is_gp_core,
    CASE
        WHEN revenue = 0                                     THEN '1. Delist: no demand'
        WHEN gross_profit IS NULL                            THEN '2. Fix cost data first'
        WHEN gross_profit < 0                                THEN '3. Reprice or stop: loss-making'
        WHEN revenue_class = 'C' AND gp_margin_raw < low_margin THEN '4. Delist review'
        WHEN gp_margin_raw < low_margin                      THEN '5. Reprice'
        WHEN is_gp_core                                      THEN '6. Protect'
        ELSE '7. Maintain'
    END                                 AS action
FROM classified;

-- -----------------------------------------------------------------------------
-- Step 2 · Gross profit concentration: how many products earn 80 % of GP?
--          And how margin varies by revenue class
-- -----------------------------------------------------------------------------
SELECT
    COUNTIF(is_gp_core)                                                       AS products_earning_80pct_of_gp,
    COUNTIF(gross_profit IS NOT NULL AND revenue > 0)                         AS products_ranked,
    ROUND(100 * SUM(IF(is_gp_core, revenue, 0)) / SUM(revenue), 1)            AS gp_core_pct_of_revenue,
    ROUND(100 * SUM(gross_profit) / SUM(IF(gross_profit IS NOT NULL, revenue, 0)), 1) AS company_gp_margin_pct
FROM `sahyadri_b2b.sku_profitability`;

SELECT
    IFNULL(revenue_class, 'No sales')                                AS revenue_class,
    COUNT(*)                                                         AS products,
    ROUND(SUM(revenue), 2)                                           AS revenue,
    ROUND(SUM(gross_profit), 2)                                      AS gross_profit,
    ROUND(100 * SAFE_DIVIDE(SUM(gross_profit),
                            SUM(IF(gross_profit IS NOT NULL, revenue, 0))), 1) AS gp_margin_pct,
    COUNTIF(gp_margin < low_margin)                                  AS low_margin_products,
    ROUND(SUM(IF(gp_margin < low_margin, revenue, 0)), 2)            AS low_margin_revenue
FROM `sahyadri_b2b.sku_profitability`
GROUP BY revenue_class
ORDER BY revenue_class IS NULL, revenue_class;

-- -----------------------------------------------------------------------------
-- Step 3 · Action summary
-- -----------------------------------------------------------------------------
SELECT
    action,
    COUNT(*)                                                     AS products,
    ROUND(SUM(revenue), 2)                                       AS revenue,
    ROUND(SUM(gross_profit), 2)                                  AS gross_profit,
    ROUND(100 * SAFE_DIVIDE(SUM(gross_profit), SUM(revenue)), 1) AS gp_margin_pct
FROM `sahyadri_b2b.sku_profitability`
GROUP BY action
ORDER BY action;

-- -----------------------------------------------------------------------------
-- Step 4 · Repricing: GP gained if each low-margin seller reached a 10 % margin
--          at the same volume. Revenue needed = cost / (1 - 10 %).
-- -----------------------------------------------------------------------------
SELECT
    product_id,
    product_name,
    category_name,
    revenue_class,
    action,
    revenue,
    ROUND(100 * gp_margin, 1)                                                AS gp_margin_pct,
    ROUND((revenue - gross_profit) / (1 - low_margin) - revenue, 2)          AS gp_gain_at_10pct_margin,
    ROUND(100 * ((revenue - gross_profit) / (1 - low_margin) / revenue - 1), 1) AS price_rise_needed_pct
FROM `sahyadri_b2b.sku_profitability`
WHERE action IN ('3. Reprice or stop: loss-making', '5. Reprice')
ORDER BY gp_gain_at_10pct_margin DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Delisting impact: which customers depend on the delist-review products?
-- -----------------------------------------------------------------------------
WITH customer_product AS (
    SELECT
        o.customer_id,
        i.product_id,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN window_start AND window_end
    GROUP BY o.customer_id, i.product_id
),
customer_share AS (
    SELECT
        customer_id,
        product_id,
        revenue,
        revenue / SUM(revenue) OVER (PARTITION BY customer_id) AS share_of_customer_spend
    FROM customer_product
)
SELECT
    s.product_id,
    s.product_name,
    s.category_name,
    s.revenue,
    ROUND(100 * s.gp_margin, 1)                                     AS gp_margin_pct,
    s.orders,
    s.customers,
    COUNTIF(c.share_of_customer_spend >= dependent_pct)             AS dependent_customers,
    IF(COUNTIF(c.share_of_customer_spend >= dependent_pct) > 0,
       'Agree a substitute with dependent customers first',
       'Delist candidate')                                          AS recommendation
FROM `sahyadri_b2b.sku_profitability` AS s
JOIN customer_share                   AS c ON c.product_id = s.product_id
WHERE s.action = '4. Delist review'
GROUP BY s.product_id, s.product_name, s.category_name, s.revenue, s.gp_margin, s.orders, s.customers
ORDER BY dependent_customers, s.revenue;
