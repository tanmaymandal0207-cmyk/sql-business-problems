/* =============================================================================
   Case study · Gross margin bridge
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Revenue grew by about a third in the latest 12 months, and gross margin
   in rupees grew with it. The board pack shows gross margin % moving too,
   and the CFO has to explain the movement in one slide: how much came
   from selling more, from selling a different mix, from list price
   increases and from discounting?
     1. How did gross margin (Rs and %) change between the two periods?
     2. What did volume, mix, price and discount each contribute?
     3. Which product categories drove the change?
     4. How much did new and discontinued products contribute?

   METHOD
     - Periods: Prior = 1 Oct 2024 - 30 Sep 2025, Current = 1 Oct 2025 -
       30 Sep 2026. Orders not Cancelled or Returned.
     - Cell = product x customer segment, so that "mix" covers both what is
       sold and to whom (segments carry very different discounts).
     - For each cell: q = units, P = list-level price before discount
       (gross value / q), d = average discount (1 - net / gross),
       c = unit cost (one current cost per product).
       Unit margin m = P (1 - d) - c.
     - Bridge (continuing cells, sold in both periods), exact:
         Volume   = (Q1 - Q0) x (prior gross margin per unit, all continuing cells)
         Mix      = SUM (q1 - q0) x m0  -  Volume
         Price    = SUM q1 x (P1 - P0) x (1 - d0)
         Discount = SUM q1 x P1 x (d0 - d1)
       plus New cells (sold only in Current) and Lost cells (only in Prior).
     - Gross margin % walk: the same steps applied in sequence, recomputing
       margin % after each one.
     - Lines for products with no unit cost are excluded (reported).
   ============================================================================= */

DECLARE current_start DATE DEFAULT DATE '2025-10-01';
DECLARE prior_start   DATE DEFAULT DATE '2024-10-01';
DECLARE period_end    DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Cell table: product x segment, both periods
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.margin_bridge_cells` AS
WITH lines AS (
    SELECT
        IF(o.order_date >= current_start, 'Current', 'Prior')                    AS period,
        i.product_id,
        c.customer_segment,
        i.quantity,
        i.quantity * i.unit_price                                                AS gross_value,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)    AS net_revenue,
        p.unit_cost
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.customers`         AS c ON c.customer_id = o.customer_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN prior_start AND period_end
      AND p.unit_cost IS NOT NULL
),
cells AS (
    SELECT
        product_id,
        customer_segment,
        ANY_VALUE(unit_cost)                                                     AS unit_cost,
        SUM(IF(period = 'Prior',   quantity, 0))                                 AS q0,
        SUM(IF(period = 'Current', quantity, 0))                                 AS q1,
        SUM(IF(period = 'Prior',   gross_value, 0))                              AS gross0,
        SUM(IF(period = 'Current', gross_value, 0))                              AS gross1,
        SUM(IF(period = 'Prior',   net_revenue, 0))                              AS net0,
        SUM(IF(period = 'Current', net_revenue, 0))                              AS net1
    FROM lines
    GROUP BY product_id, customer_segment
)
SELECT
    c.*,
    pc.category_name,
    CASE WHEN q0 > 0 AND q1 > 0 THEN 'Continuing'
         WHEN q1 > 0            THEN 'New'
         ELSE                        'Lost' END                                  AS cell_status,
    SAFE_DIVIDE(gross0, q0)                                                      AS p0,
    SAFE_DIVIDE(gross1, q1)                                                      AS p1,
    1 - SAFE_DIVIDE(net0, gross0)                                                AS d0,
    1 - SAFE_DIVIDE(net1, gross1)                                                AS d1,
    c.net0 - c.q0 * c.unit_cost                                                      AS margin0,
    c.net1 - c.q1 * c.unit_cost                                                      AS margin1
FROM cells AS c
JOIN `sahyadri_b2b.products`           AS p  ON p.product_id = c.product_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id;

-- -----------------------------------------------------------------------------
-- Step 2 · The bridge in rupees
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.margin_bridge` AS
WITH cont AS (
    SELECT * FROM `sahyadri_b2b.margin_bridge_cells` WHERE cell_status = 'Continuing'
),
totals AS (
    SELECT SUM(q0) AS q0_total, SUM(q1) AS q1_total, SUM(margin0) / SUM(q0) AS margin_per_unit0
    FROM cont
),
effects AS (
    SELECT
        (t.q1_total - t.q0_total) * t.margin_per_unit0                                      AS volume,
        SUM((c.q1 - c.q0) * (c.p0 * (1 - c.d0) - c.unit_cost))
          - (t.q1_total - t.q0_total) * t.margin_per_unit0                                  AS mix,
        SUM(c.q1 * (c.p1 - c.p0) * (1 - c.d0))                                              AS price,
        SUM(c.q1 * c.p1 * (c.d0 - c.d1))                                                    AS discount
    FROM cont AS c
    CROSS JOIN totals AS t
    GROUP BY t.q1_total, t.q0_total, t.margin_per_unit0
)
SELECT
    (SELECT SUM(margin0) FROM `sahyadri_b2b.margin_bridge_cells`)                           AS margin_prior,
    e.volume,
    e.mix,
    e.price,
    e.discount,
    (SELECT SUM(margin1) FROM `sahyadri_b2b.margin_bridge_cells` WHERE cell_status = 'New')  AS new_cells,
    -(SELECT SUM(margin0) FROM `sahyadri_b2b.margin_bridge_cells` WHERE cell_status = 'Lost') AS lost_cells,
    (SELECT SUM(margin1) FROM `sahyadri_b2b.margin_bridge_cells`)                           AS margin_current,
    (SELECT SUM(net0) FROM `sahyadri_b2b.margin_bridge_cells`)                              AS revenue_prior,
    (SELECT SUM(net1) FROM `sahyadri_b2b.margin_bridge_cells`)                              AS revenue_current
FROM effects AS e;

SELECT step, ROUND(amount / 1e5, 1) AS amount_lakh
FROM (
    SELECT 1 AS ord, 'Gross margin, prior 12 months' AS step, margin_prior AS amount FROM `sahyadri_b2b.margin_bridge`
    UNION ALL SELECT 2, 'Volume',                       volume     FROM `sahyadri_b2b.margin_bridge`
    UNION ALL SELECT 3, 'Mix (product x segment)',      mix        FROM `sahyadri_b2b.margin_bridge`
    UNION ALL SELECT 4, 'List price',                   price      FROM `sahyadri_b2b.margin_bridge`
    UNION ALL SELECT 5, 'Discount',                     discount   FROM `sahyadri_b2b.margin_bridge`
    UNION ALL SELECT 6, 'New product-segment cells',    new_cells  FROM `sahyadri_b2b.margin_bridge`
    UNION ALL SELECT 7, 'Lost product-segment cells',   lost_cells FROM `sahyadri_b2b.margin_bridge`
    UNION ALL SELECT 8, 'Gross margin, current 12 months', margin_current FROM `sahyadri_b2b.margin_bridge`
)
ORDER BY ord;

-- -----------------------------------------------------------------------------
-- Step 3 · Gross margin % walk (continuing cells, steps applied in sequence)
-- -----------------------------------------------------------------------------
WITH cont AS (
    SELECT * FROM `sahyadri_b2b.margin_bridge_cells` WHERE cell_status = 'Continuing'
),
stages AS (
    SELECT
        -- prior: prior units, prior prices, prior discounts
        SUM(q0 * (p0 * (1 - d0) - unit_cost)) / SUM(q0 * p0 * (1 - d0))   AS gm_prior,
        -- current mix, prior prices and discounts
        SUM(q1 * (p0 * (1 - d0) - unit_cost)) / SUM(q1 * p0 * (1 - d0))   AS gm_after_mix,
        -- current mix and prices, prior discounts
        SUM(q1 * (p1 * (1 - d0) - unit_cost)) / SUM(q1 * p1 * (1 - d0))   AS gm_after_price,
        -- current everything
        SUM(q1 * (p1 * (1 - d1) - unit_cost)) / SUM(q1 * p1 * (1 - d1))   AS gm_current
    FROM cont
)
SELECT
    ROUND(100 * gm_prior, 2)                                    AS gm_pct_prior,
    ROUND(100 * (gm_after_mix   - gm_prior), 2)                 AS mix_pts,
    ROUND(100 * (gm_after_price - gm_after_mix), 2)             AS price_pts,
    ROUND(100 * (gm_current     - gm_after_price), 2)           AS discount_pts,
    ROUND(100 * gm_current, 2)                                  AS gm_pct_current,
    ROUND(100 * (SELECT SUM(margin0) / SUM(net0) FROM `sahyadri_b2b.margin_bridge_cells`), 2) AS gm_pct_prior_all_cells,
    ROUND(100 * (SELECT SUM(margin1) / SUM(net1) FROM `sahyadri_b2b.margin_bridge_cells`), 2) AS gm_pct_current_all_cells
FROM stages;

-- Sensitivity: products carry one current unit cost. If supplier costs rose
-- between the periods, part of the "price" effect is cost recovery. How much
-- prior-period cost inflation would cancel each effect?
WITH cont AS (
    SELECT * FROM `sahyadri_b2b.margin_bridge_cells` WHERE cell_status = 'Continuing'
)
SELECT
    ROUND(100 * SUM(c.q1 * c.unit_cost) / SUM(c.q1 * c.p1 * (1 - c.d1)), 2)              AS cost_as_pct_of_current_revenue,
    ROUND(100 * (SELECT price FROM `sahyadri_b2b.margin_bridge`) / SUM(c.q1 * c.unit_cost), 2) AS cost_inflation_that_cancels_price_effect_pct,
    -- margin % in the prior period if prior costs had been x % lower than today's
    ROUND(100 * SUM(c.q0 * (c.p0 * (1 - c.d0) - c.unit_cost / 1.05)) / SUM(c.q0 * c.p0 * (1 - c.d0)), 2) AS gm_pct_prior_if_costs_rose_5pct,
    ROUND(100 * SUM(c.q1 * (c.p1 * (1 - c.d1) - c.unit_cost)) / SUM(c.q1 * c.p1 * (1 - c.d1)), 2)        AS gm_pct_current
FROM cont AS c;

-- Discount change by segment (continuing cells, revenue-weighted)
SELECT
    customer_segment,
    ROUND(100 * (1 - SUM(net0) / SUM(gross0)), 2)               AS discount_pct_prior,
    ROUND(100 * (1 - SUM(net1) / SUM(gross1)), 2)               AS discount_pct_current,
    ROUND(SUM(q1 * p1 * (d0 - d1)) / 1e5, 1)                    AS discount_effect_lakh,
    ROUND(100 * SUM(net1) / SUM(SUM(net1)) OVER (), 1)          AS share_of_current_revenue_pct,
    ROUND(100 * SUM(net0) / SUM(SUM(net0)) OVER (), 1)          AS share_of_prior_revenue_pct
FROM `sahyadri_b2b.margin_bridge_cells`
WHERE cell_status = 'Continuing'
GROUP BY customer_segment
ORDER BY customer_segment;

-- -----------------------------------------------------------------------------
-- Step 4 · Bridge by product category
-- -----------------------------------------------------------------------------
WITH cont AS (
    SELECT * FROM `sahyadri_b2b.margin_bridge_cells` WHERE cell_status = 'Continuing'
),
unit0 AS (
    SELECT SUM(margin0) / SUM(q0) AS m0 FROM cont
)
SELECT
    c.category_name,
    ROUND(SUM(c.margin0) / 1e5, 1)                                                           AS margin_prior_lakh,
    ROUND(SUM((c.q1 - c.q0) * (c.p0 * (1 - c.d0) - c.unit_cost)) / 1e5, 1)                   AS volume_and_mix_lakh,
    ROUND(SUM(c.q1 * (c.p1 - c.p0) * (1 - c.d0)) / 1e5, 1)                                   AS price_lakh,
    ROUND(SUM(c.q1 * c.p1 * (c.d0 - c.d1)) / 1e5, 1)                                         AS discount_lakh,
    ROUND(SUM(c.margin1) / 1e5, 1)                                                           AS margin_current_lakh,
    ROUND(100 * SUM(c.margin0) / SUM(c.net0), 1)                                             AS gm_pct_prior,
    ROUND(100 * SUM(c.margin1) / SUM(c.net1), 1)                                             AS gm_pct_current
FROM cont AS c
GROUP BY c.category_name
ORDER BY margin_current_lakh DESC;

-- Excluded lines (products with no unit cost)
SELECT
    COUNT(*)                                                                                 AS excluded_lines,
    ROUND(SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) / 1e5, 1) AS excluded_revenue_lakh
FROM `sahyadri_b2b.sales_orders`      AS o
JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
  AND o.order_date BETWEEN prior_start AND period_end
  AND p.unit_cost IS NULL;
