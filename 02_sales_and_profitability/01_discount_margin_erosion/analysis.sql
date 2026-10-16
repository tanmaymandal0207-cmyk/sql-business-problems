/* =============================================================================
   Case study · Discount and margin erosion
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Revenue is growing, but finance reports that gross margin is thin. Sales
   teams are allowed to give line discounts of up to 18 % without a formal
   approval rule. The commercial director wants to know:
     1. How much revenue is given away in discounts, and what gross margin
        is left?
     2. How does gross margin change as the discount deepens?
     3. Which categories, customer segments and salespeople discount most,
        and what does it cost in margin?
     4. How many order lines were sold below cost, and what did that lose?

   KEY RULES
     - Scope: order lines on orders that are not Cancelled or Returned.
     - Gross value      = quantity * unit_price (price before line discount)
     - Net revenue      = gross value * (1 - IFNULL(discount_percent, 0) / 100)
     - Discount amount  = gross value - net revenue
     - Line cost        = quantity * products.unit_cost
     - Gross margin     = net revenue - line cost; reported only for lines
                          whose product has a unit cost (cost-known lines)
     - Below cost       = net revenue < line cost
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- Step 1 · Line-level margin table
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sales_line_margin` AS
SELECT
    i.order_item_id,
    i.order_id,
    o.order_date,
    o.employee_id,
    o.customer_id,
    c.customer_segment,
    i.product_id,
    pc.category_name,
    i.quantity,
    IFNULL(i.discount_percent, 0)                                         AS discount_percent,
    CASE
        WHEN IFNULL(i.discount_percent, 0) = 0   THEN '1. No discount'
        WHEN i.discount_percent <= 5             THEN '2. Up to 5%'
        WHEN i.discount_percent <= 10            THEN '3. Above 5% to 10%'
        WHEN i.discount_percent <= 15            THEN '4. Above 10% to 15%'
        ELSE                                          '5. Above 15%'
    END                                                                   AS discount_band,
    i.quantity * i.unit_price                                             AS gross_value,
    i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS net_revenue,
    i.quantity * i.unit_price * IFNULL(i.discount_percent, 0) / 100       AS discount_amount,
    p.unit_cost IS NOT NULL                                               AS cost_known,
    i.quantity * p.unit_cost                                              AS line_cost
FROM `sahyadri_b2b.sales_order_items`        AS i
JOIN `sahyadri_b2b.sales_orders`             AS o  ON o.order_id     = i.order_id
JOIN `sahyadri_b2b.customers`                AS c  ON c.customer_id  = o.customer_id
JOIN `sahyadri_b2b.products`                 AS p  ON p.product_id   = i.product_id
JOIN `sahyadri_b2b.product_categories`       AS pc ON pc.category_id = p.category_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned');

-- -----------------------------------------------------------------------------
-- Step 2 · Headline: discount given and margin left
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                       AS order_lines,
    ROUND(SUM(gross_value), 2)                                     AS gross_value,
    ROUND(SUM(discount_amount), 2)                                 AS discount_given,
    ROUND(100 * SUM(discount_amount) / SUM(gross_value), 2)        AS discount_pct_of_gross,
    ROUND(SUM(net_revenue), 2)                                     AS net_revenue,
    ROUND(100 * SUM(IF(cost_known, net_revenue - line_cost, 0))
          / SUM(IF(cost_known, net_revenue, 0)), 2)                AS gross_margin_pct,
    COUNTIF(NOT cost_known)                                        AS lines_without_cost
FROM `sahyadri_b2b.sales_line_margin`;

-- -----------------------------------------------------------------------------
-- Step 3 · Gross margin by discount band
-- -----------------------------------------------------------------------------
SELECT
    discount_band,
    COUNT(*)                                                       AS order_lines,
    ROUND(SUM(net_revenue), 2)                                     AS net_revenue,
    ROUND(100 * SUM(net_revenue) / SUM(SUM(net_revenue)) OVER (), 1) AS pct_of_revenue,
    ROUND(100 * SUM(IF(cost_known, net_revenue - line_cost, 0))
          / SUM(IF(cost_known, net_revenue, 0)), 2)                AS gross_margin_pct,
    COUNTIF(cost_known AND net_revenue < line_cost)                AS lines_below_cost
FROM `sahyadri_b2b.sales_line_margin`
GROUP BY discount_band
ORDER BY discount_band;

-- -----------------------------------------------------------------------------
-- Step 4 · Category view
-- -----------------------------------------------------------------------------
SELECT
    category_name,
    ROUND(SUM(net_revenue), 2)                                     AS net_revenue,
    ROUND(100 * SUM(discount_amount) / SUM(gross_value), 2)        AS discount_pct_of_gross,
    ROUND(100 * SUM(IF(cost_known, net_revenue - line_cost, 0))
          / SUM(IF(cost_known, net_revenue, 0)), 2)                AS gross_margin_pct,
    COUNTIF(cost_known AND net_revenue < line_cost)                AS lines_below_cost
FROM `sahyadri_b2b.sales_line_margin`
GROUP BY category_name
ORDER BY net_revenue DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Customer segment view
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    ROUND(SUM(net_revenue), 2)                                     AS net_revenue,
    ROUND(100 * SUM(discount_amount) / SUM(gross_value), 2)        AS discount_pct_of_gross,
    ROUND(100 * SUM(IF(cost_known, net_revenue - line_cost, 0))
          / SUM(IF(cost_known, net_revenue, 0)), 2)                AS gross_margin_pct
FROM `sahyadri_b2b.sales_line_margin`
GROUP BY customer_segment
ORDER BY discount_pct_of_gross DESC;

-- -----------------------------------------------------------------------------
-- Step 6 · Salesperson view
-- -----------------------------------------------------------------------------
SELECT
    m.employee_id,
    e.employee_name,
    COUNT(*)                                                       AS order_lines,
    ROUND(SUM(m.net_revenue), 2)                                   AS net_revenue,
    ROUND(100 * SUM(m.discount_amount) / SUM(m.gross_value), 2)    AS discount_pct_of_gross,
    ROUND(100 * COUNTIF(m.discount_percent > 10) / COUNT(*), 1)    AS pct_lines_above_10pct,
    ROUND(100 * SUM(IF(m.cost_known, m.net_revenue - m.line_cost, 0))
          / SUM(IF(m.cost_known, m.net_revenue, 0)), 2)            AS gross_margin_pct,
    ROUND(SUM(IF(m.cost_known AND m.net_revenue < m.line_cost,
                 m.line_cost - m.net_revenue, 0)), 2)              AS below_cost_loss
FROM `sahyadri_b2b.sales_line_margin` AS m
LEFT JOIN `sahyadri_b2b.employees`     AS e
    ON e.employee_id = m.employee_id
GROUP BY m.employee_id, e.employee_name
ORDER BY discount_pct_of_gross DESC;

-- -----------------------------------------------------------------------------
-- Step 7 · Below-cost sales: was the price already below cost, or did the
--          discount push it below?
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN gross_value < line_cost THEN 'Price below cost before discount'
        ELSE                              'Discount pushed price below cost'
    END                                                            AS below_cost_reason,
    COUNT(*)                                                       AS order_lines,
    ROUND(SUM(net_revenue), 2)                                     AS net_revenue,
    ROUND(SUM(line_cost - net_revenue), 2)                         AS loss_below_cost,
    ROUND(AVG(discount_percent), 1)                                AS avg_discount_pct
FROM `sahyadri_b2b.sales_line_margin`
WHERE cost_known
  AND net_revenue < line_cost
GROUP BY below_cost_reason
ORDER BY loss_below_cost DESC;

-- -----------------------------------------------------------------------------
-- Step 8 · Scenario: margin recovered if line discounts had been capped at 10 %
--          (assumes the same volume would still have been sold — an upper bound)
-- -----------------------------------------------------------------------------
SELECT
    COUNTIF(discount_percent > 10)                                     AS lines_above_cap,
    ROUND(SUM(IF(discount_percent > 10,
                 gross_value * (discount_percent - 10) / 100, 0)), 2)  AS revenue_recovered,
    ROUND(100 * SUM(IF(cost_known, net_revenue - line_cost, 0))
          / SUM(IF(cost_known, net_revenue, 0)), 2)                    AS gross_margin_pct_actual,
    ROUND(100 * SUM(IF(cost_known,
                       gross_value * (1 - LEAST(discount_percent, 10) / 100) - line_cost, 0))
          / SUM(IF(cost_known,
                   gross_value * (1 - LEAST(discount_percent, 10) / 100), 0)), 2)
                                                                       AS gross_margin_pct_capped
FROM `sahyadri_b2b.sales_line_margin`;
