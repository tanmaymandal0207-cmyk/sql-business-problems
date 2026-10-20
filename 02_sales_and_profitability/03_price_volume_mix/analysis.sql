/* =============================================================================
   Case study · Price-volume-mix analysis (year-to-date, 2026 vs 2025)
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Revenue for January-September grew 38.7 % (see the revenue growth bridge
   case study). That analysis showed growth came from existing customers and
   bigger orders, but it could not say whether "bigger" means customers bought
   more units or paid higher prices. Finance needs the split for the budget:
   price increases can be planned again, volume growth needs capacity and stock.
     1. How much of the revenue change came from price, from volume, and from
        a shift in product mix?
     2. How much came from products sold only in one of the two periods?
     3. By how much did realised prices rise, overall and by category?
     4. Which products drove the price and volume effects?

   KEY RULES
     - Periods: 1 Jan-30 Sep 2025 (PY) vs 1 Jan-30 Sep 2026 (CY).
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Realised price = revenue / quantity per product and period
       (after line discount).
     - Continuing product = sold in both periods.
     - Decomposition (continuing products), which adds up exactly:
         Price effect    = SUM((price CY - price PY) x quantity CY)
         Quantity effect = SUM((quantity CY - quantity PY) x price PY)
           Volume effect = (total qty CY - total qty PY) x average price PY
           Mix effect    = Quantity effect - Volume effect
       plus New products (CY revenue) and Discontinued products (- PY revenue).
   ============================================================================= */

DECLARE py_start DATE DEFAULT DATE '2025-01-01';
DECLARE py_end   DATE DEFAULT DATE '2025-09-30';
DECLARE cy_start DATE DEFAULT DATE '2026-01-01';
DECLARE cy_end   DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Product-level PY / CY quantity, revenue and realised price
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.product_price_volume` AS
WITH lines AS (
    SELECT
        i.product_id,
        IF(o.order_date BETWEEN py_start AND py_end, 'PY', 'CY')                 AS period,
        i.quantity,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)   AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND (o.order_date BETWEEN py_start AND py_end
           OR o.order_date BETWEEN cy_start AND cy_end)
),
by_product AS (
    SELECT
        product_id,
        SUM(IF(period = 'PY', quantity, 0)) AS qty_py,
        SUM(IF(period = 'CY', quantity, 0)) AS qty_cy,
        SUM(IF(period = 'PY', revenue, 0))  AS revenue_py,
        SUM(IF(period = 'CY', revenue, 0))  AS revenue_cy
    FROM lines
    GROUP BY product_id
)
SELECT
    b.product_id,
    p.product_name,
    pc.category_name,
    b.qty_py,
    b.qty_cy,
    b.revenue_py,
    b.revenue_cy,
    SAFE_DIVIDE(b.revenue_py, b.qty_py)                                  AS price_py,
    SAFE_DIVIDE(b.revenue_cy, b.qty_cy)                                  AS price_cy,
    CASE
        WHEN b.qty_py > 0 AND b.qty_cy > 0 THEN 'Continuing'
        WHEN b.qty_py = 0                  THEN 'New'
        ELSE                                    'Discontinued'
    END                                                                  AS product_status,
    IF(b.qty_py > 0 AND b.qty_cy > 0,
       (SAFE_DIVIDE(b.revenue_cy, b.qty_cy) - SAFE_DIVIDE(b.revenue_py, b.qty_py)) * b.qty_cy,
       0)                                                                AS price_effect,
    IF(b.qty_py > 0 AND b.qty_cy > 0,
       (b.qty_cy - b.qty_py) * SAFE_DIVIDE(b.revenue_py, b.qty_py),
       0)                                                                AS quantity_effect
FROM by_product                        AS b
JOIN `sahyadri_b2b.products`           AS p  ON p.product_id   = b.product_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Revenue bridge: PY -> price -> volume -> mix -> new/discontinued -> CY
-- -----------------------------------------------------------------------------
WITH continuing AS (
    SELECT
        SUM(qty_py)          AS qty_py,
        SUM(qty_cy)          AS qty_cy,
        SUM(revenue_py)      AS revenue_py,
        SUM(price_effect)    AS price_effect,
        SUM(quantity_effect) AS quantity_effect
    FROM `sahyadri_b2b.product_price_volume`
    WHERE product_status = 'Continuing'
),
totals AS (
    SELECT
        SUM(revenue_py)                                            AS revenue_py,
        SUM(revenue_cy)                                            AS revenue_cy,
        SUM(IF(product_status = 'New', revenue_cy, 0))             AS new_products,
        -SUM(IF(product_status = 'Discontinued', revenue_py, 0))   AS discontinued_products
    FROM `sahyadri_b2b.product_price_volume`
)
SELECT
    ROUND(t.revenue_py, 2)                                                      AS revenue_py,
    ROUND(c.price_effect, 2)                                                    AS price_effect,
    ROUND((c.qty_cy - c.qty_py) * (c.revenue_py / c.qty_py), 2)                 AS volume_effect,
    ROUND(c.quantity_effect - (c.qty_cy - c.qty_py) * (c.revenue_py / c.qty_py), 2) AS mix_effect,
    ROUND(t.new_products, 2)                                                    AS new_products,
    ROUND(t.discontinued_products, 2)                                           AS discontinued_products,
    ROUND(t.revenue_cy, 2)                                                      AS revenue_cy,
    ROUND(t.revenue_cy - t.revenue_py, 2)                                       AS total_change
FROM continuing AS c
CROSS JOIN totals AS t;

-- -----------------------------------------------------------------------------
-- Step 3 · Realised price change by category (continuing products,
--          weighted by CY quantity, so mix does not distort the comparison)
-- -----------------------------------------------------------------------------
SELECT
    category_name,
    COUNT(*)                                                                   AS continuing_products,
    ROUND(100 * (SUM(price_cy * qty_cy) / SUM(price_py * qty_cy) - 1), 1)      AS price_change_pct,
    ROUND(100 * (SUM(qty_cy) / SUM(qty_py) - 1), 1)                            AS unit_volume_change_pct,
    ROUND(SUM(price_effect), 2)                                                AS price_effect,
    ROUND(SUM(quantity_effect), 2)                                             AS quantity_effect
FROM `sahyadri_b2b.product_price_volume`
WHERE product_status = 'Continuing'
GROUP BY category_name
UNION ALL
SELECT
    'All categories',
    COUNT(*),
    ROUND(100 * (SUM(price_cy * qty_cy) / SUM(price_py * qty_cy) - 1), 1),
    ROUND(100 * (SUM(qty_cy) / SUM(qty_py) - 1), 1),
    ROUND(SUM(price_effect), 2),
    ROUND(SUM(quantity_effect), 2)
FROM `sahyadri_b2b.product_price_volume`
WHERE product_status = 'Continuing'
ORDER BY price_change_pct DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Products driving the quantity effect (largest volume gains and losses)
-- -----------------------------------------------------------------------------
(
SELECT 'Largest gains' AS direction, product_id, product_name, category_name,
       qty_py, qty_cy, ROUND(quantity_effect, 2) AS quantity_effect,
       ROUND(100 * (price_cy / price_py - 1), 1) AS price_change_pct
FROM `sahyadri_b2b.product_price_volume`
WHERE product_status = 'Continuing'
ORDER BY quantity_effect DESC
LIMIT 5
)
UNION ALL
(
SELECT 'Largest losses', product_id, product_name, category_name,
       qty_py, qty_cy, ROUND(quantity_effect, 2),
       ROUND(100 * (price_cy / price_py - 1), 1)
FROM `sahyadri_b2b.product_price_volume`
WHERE product_status = 'Continuing'
ORDER BY quantity_effect ASC
LIMIT 5
);
