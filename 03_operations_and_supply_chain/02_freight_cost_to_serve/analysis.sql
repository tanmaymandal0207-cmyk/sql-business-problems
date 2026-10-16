/* =============================================================================
   Case study · Freight cost-to-serve and minimum order value
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The company absorbs outbound freight on every order. The logistics manager
   believes small orders cost more to ship than they earn, and has proposed a
   minimum order value (MOV). Finance wants the evidence first:
     1. What does freight cost as a share of revenue, overall and by order size?
     2. After product cost and freight, which order sizes make or lose money?
     3. How much do split shipments add to freight?
     4. Which customer segments place the most small orders?
     5. What would a ₹10,000 minimum order value affect?

   KEY RULES
     - Scope: Delivered orders where every shipment has a freight cost and
       every line has a product cost (excluded orders are counted in
       validation.sql).
     - Revenue           = SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))
     - Product cost      = SUM(quantity * products.unit_cost)
     - Freight           = SUM(shipments.shipping_cost) for the order
     - Gross margin      = revenue - product cost
     - Contribution after freight = gross margin - freight
   ============================================================================= */

DECLARE mov_threshold FLOAT64 DEFAULT 10000;

-- -----------------------------------------------------------------------------
-- Step 1 · Order-level cost-to-serve table
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.order_cost_to_serve` AS
WITH order_lines AS (
    SELECT
        i.order_id,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue,
        SUM(i.quantity * p.unit_cost)                                             AS product_cost,
        COUNTIF(p.unit_cost IS NULL)                                              AS lines_without_cost
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.products`          AS p
        ON p.product_id = i.product_id
    GROUP BY i.order_id
),

order_freight AS (
    SELECT
        order_id,
        COUNT(*)              AS shipments,
        SUM(shipping_cost)    AS freight,
        COUNTIF(shipping_cost IS NULL) AS shipments_without_cost
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
)

SELECT
    o.order_id,
    o.customer_id,
    c.customer_segment,
    o.order_date,
    f.shipments,
    l.revenue,
    l.product_cost,
    f.freight,
    l.revenue - l.product_cost                    AS gross_margin,
    l.revenue - l.product_cost - f.freight        AS contribution_after_freight,
    CASE
        WHEN l.revenue <  10000  THEN '1. Under 10k'
        WHEN l.revenue <  25000  THEN '2. 10k-25k'
        WHEN l.revenue <  50000  THEN '3. 25k-50k'
        WHEN l.revenue < 100000  THEN '4. 50k-1L'
        WHEN l.revenue < 500000  THEN '5. 1L-5L'
        ELSE                          '6. 5L and above'
    END                                           AS order_size_band
FROM `sahyadri_b2b.sales_orders` AS o
JOIN order_lines                 AS l ON l.order_id = o.order_id
JOIN order_freight               AS f ON f.order_id = o.order_id
JOIN `sahyadri_b2b.customers`    AS c ON c.customer_id = o.customer_id
WHERE o.order_status = 'Delivered'
  AND l.lines_without_cost = 0
  AND f.shipments_without_cost = 0;

-- -----------------------------------------------------------------------------
-- Step 2 · Headline freight burden
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                    AS orders,
    ROUND(SUM(revenue), 2)                                      AS revenue,
    ROUND(SUM(freight), 2)                                      AS freight,
    ROUND(100 * SUM(freight) / SUM(revenue), 2)                 AS freight_pct_of_revenue,
    ROUND(100 * SUM(gross_margin) / SUM(revenue), 2)            AS gross_margin_pct,
    ROUND(100 * SUM(contribution_after_freight) / SUM(revenue), 2) AS contribution_pct,
    COUNTIF(contribution_after_freight < 0)                     AS loss_making_orders
FROM `sahyadri_b2b.order_cost_to_serve`;

-- -----------------------------------------------------------------------------
-- Step 3 · Cost-to-serve by order size
-- -----------------------------------------------------------------------------
SELECT
    order_size_band,
    COUNT(*)                                                    AS orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS pct_of_orders,
    ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)    AS pct_of_revenue,
    ROUND(AVG(freight), 0)                                      AS avg_freight_per_order,
    ROUND(100 * SUM(freight) / SUM(revenue), 2)                 AS freight_pct_of_revenue,
    ROUND(100 * SUM(gross_margin) / SUM(revenue), 2)            AS gross_margin_pct,
    ROUND(100 * SUM(contribution_after_freight) / SUM(revenue), 2) AS contribution_pct,
    ROUND(100 * COUNTIF(contribution_after_freight < 0) / COUNT(*), 1) AS pct_orders_loss_making,
    ROUND(SUM(contribution_after_freight), 2)                   AS contribution_after_freight
FROM `sahyadri_b2b.order_cost_to_serve`
GROUP BY order_size_band
ORDER BY order_size_band;

-- -----------------------------------------------------------------------------
-- Step 4 · Split shipments: what a second shipment costs
-- -----------------------------------------------------------------------------
SELECT
    IF(shipments > 1, 'Split shipment', 'Single shipment')     AS shipment_pattern,
    COUNT(*)                                                    AS orders,
    ROUND(AVG(freight), 0)                                      AS avg_freight_per_order,
    ROUND(100 * SUM(freight) / SUM(revenue), 2)                 AS freight_pct_of_revenue,
    ROUND(SUM(freight), 2)                                      AS freight
FROM `sahyadri_b2b.order_cost_to_serve`
GROUP BY shipment_pattern
ORDER BY shipment_pattern;

-- -----------------------------------------------------------------------------
-- Step 5 · Small orders by customer segment
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                                    AS orders,
    COUNTIF(revenue < mov_threshold)                            AS orders_below_mov,
    ROUND(100 * COUNTIF(revenue < mov_threshold) / COUNT(*), 1) AS pct_orders_below_mov,
    ROUND(100 * SUM(freight) / SUM(revenue), 2)                 AS freight_pct_of_revenue,
    ROUND(100 * SUM(contribution_after_freight) / SUM(revenue), 2) AS contribution_pct
FROM `sahyadri_b2b.order_cost_to_serve`
GROUP BY customer_segment
ORDER BY pct_orders_below_mov DESC;

-- -----------------------------------------------------------------------------
-- Step 6 · Minimum order value scenario (₹10,000)
-- -----------------------------------------------------------------------------
SELECT
    mov_threshold                                               AS minimum_order_value,
    COUNTIF(revenue < mov_threshold)                            AS orders_below_mov,
    COUNT(DISTINCT IF(revenue < mov_threshold, customer_id, NULL)) AS customers_affected,
    ROUND(SUM(IF(revenue < mov_threshold, revenue, 0)), 2)      AS revenue_below_mov,
    ROUND(100 * SUM(IF(revenue < mov_threshold, revenue, 0)) / SUM(revenue), 2)
                                                                AS pct_of_revenue,
    ROUND(SUM(IF(revenue < mov_threshold, freight, 0)), 2)      AS freight_on_orders_below_mov,
    ROUND(100 * SUM(IF(revenue < mov_threshold, freight, 0)) / SUM(freight), 1)
                                                                AS pct_of_freight,
    ROUND(SUM(IF(revenue < mov_threshold, contribution_after_freight, 0)), 2)
                                                                AS contribution_of_orders_below_mov
FROM `sahyadri_b2b.order_cost_to_serve`;
