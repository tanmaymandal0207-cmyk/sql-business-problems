/* =============================================================================
   Case study · Does discount buy volume?
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Salespeople defend deep discounts by saying they win bigger orders. The
   pooled data seems to agree: lines with higher discounts have higher
   quantities. Earlier studies showed discounts are set by segment and cost
   margin. The CFO now asks the causal question:
     1. When the SAME customer buys the SAME product with a bigger discount,
        does it buy more units?
     2. How much of the pooled relationship is just segment and customer
        mix (big buyers get big discounts)?
     3. Is any response large enough to pay for the discount?
     4. Does the answer differ by segment?

   METHOD
     - Unit of analysis: order line (orders not Cancelled or Returned).
       d = discount % (NULL = 0), y = LN(quantity).
     - Pooled slope:   b = COVAR_POP(d, y) / VAR_POP(d)  (log points per
       discount point; x 100 = % more units per discount point).
     - Within-pair (fixed-effects) slope: d and y are demeaned within each
       customer x product pair, using pairs with 3+ purchases and some
       variation in discount; b_w = SUM(d' y') / SUM(d'^2).
       Its t-statistic uses residual variance with n - pairs - 1 degrees of
       freedom.
     - Break-even volume response: one more discount point lowers the net
       price by 1 % of the pre-discount price. With unit margin m (as a share
       of that price, after the current average discount), gross profit is
       unchanged only if units rise by m / (m - 0.01) - 1.
   ============================================================================= */

DECLARE min_purchases INT64 DEFAULT 3;

-- -----------------------------------------------------------------------------
-- Step 1 · Line table with discount, log quantity and pair identifiers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.discount_response_lines` AS
SELECT
    i.order_item_id,
    o.customer_id,
    i.product_id,
    c.customer_segment,
    o.order_date,
    i.quantity,
    LN(i.quantity)                                                       AS ln_quantity,
    IFNULL(i.discount_percent, 0)                                        AS discount_pct,
    i.unit_price,
    p.unit_cost,
    COUNT(*)                     OVER (PARTITION BY o.customer_id, i.product_id) AS pair_purchases,
    AVG(IFNULL(i.discount_percent, 0)) OVER (PARTITION BY o.customer_id, i.product_id) AS pair_mean_discount,
    AVG(LN(i.quantity))          OVER (PARTITION BY o.customer_id, i.product_id) AS pair_mean_ln_quantity,
    STDDEV_POP(IFNULL(i.discount_percent, 0)) OVER (PARTITION BY o.customer_id, i.product_id) AS pair_discount_sd
FROM `sahyadri_b2b.sales_order_items` AS i
JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
JOIN `sahyadri_b2b.customers`         AS c ON c.customer_id = o.customer_id
JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned');

-- -----------------------------------------------------------------------------
-- Step 2 · Pooled, between-segment and within-pair slopes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.discount_response_estimates` AS
WITH pooled AS (
    SELECT
        'A. Pooled (all lines)'                                          AS model,
        COUNT(*)                                                         AS lines,
        CAST(NULL AS INT64)                                              AS pairs,
        COVAR_POP(discount_pct, ln_quantity) / VAR_POP(discount_pct)     AS slope,
        CORR(discount_pct, ln_quantity)                                  AS correlation,
        COUNT(*) - 2                                                     AS degrees_of_freedom
    FROM `sahyadri_b2b.discount_response_lines`
),
within_segment AS (
    -- demeaned within segment: removes segment-level discount policy
    SELECT
        'B. Within segment'                                              AS model,
        COUNT(*)                                                         AS lines,
        CAST(NULL AS INT64)                                              AS pairs,
        SUM(dd * yy) / SUM(dd * dd)                                      AS slope,
        SUM(dd * yy) / SQRT(SUM(dd * dd) * SUM(yy * yy))                 AS correlation,
        COUNT(*) - 4 - 1                                                 AS degrees_of_freedom
    FROM (
        SELECT discount_pct - AVG(discount_pct) OVER (PARTITION BY customer_segment) AS dd,
               ln_quantity  - AVG(ln_quantity)  OVER (PARTITION BY customer_segment) AS yy
        FROM `sahyadri_b2b.discount_response_lines`
    )
),
within_pair AS (
    SELECT
        'C. Within customer x product (fixed effects)'                   AS model,
        COUNT(*)                                                         AS lines,
        COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(product_id AS STRING))) AS pairs,
        SUM((discount_pct - pair_mean_discount) * (ln_quantity - pair_mean_ln_quantity))
          / SUM(POW(discount_pct - pair_mean_discount, 2))                AS slope,
        SUM((discount_pct - pair_mean_discount) * (ln_quantity - pair_mean_ln_quantity))
          / SQRT(SUM(POW(discount_pct - pair_mean_discount, 2)) * SUM(POW(ln_quantity - pair_mean_ln_quantity, 2))) AS correlation,
        COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(product_id AS STRING))) - 1 AS degrees_of_freedom
    FROM `sahyadri_b2b.discount_response_lines`
    WHERE pair_purchases >= min_purchases AND pair_discount_sd > 0
)
SELECT
    *,
    correlation * SQRT(degrees_of_freedom) / SQRT(1 - correlation * correlation) AS t_stat
FROM (
    SELECT * FROM pooled
    UNION ALL SELECT * FROM within_segment
    UNION ALL SELECT * FROM within_pair
);

SELECT
    model,
    lines,
    pairs,
    ROUND(100 * slope, 2)                                                AS pct_more_units_per_discount_point,
    ROUND(correlation, 3)                                                AS correlation,
    ROUND(t_stat, 1)                                                     AS t_stat
FROM `sahyadri_b2b.discount_response_estimates`
ORDER BY model;

-- Why the pooled slope is misleading: segments differ in both discount and order size
SELECT
    customer_segment,
    COUNT(*)                                                             AS lines,
    ROUND(AVG(discount_pct), 2)                                          AS avg_discount_pct,
    ROUND(EXP(AVG(ln_quantity)), 1)                                      AS geometric_mean_units
FROM `sahyadri_b2b.discount_response_lines`
GROUP BY customer_segment
ORDER BY avg_discount_pct DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · Within-pair response by segment, and by size of discount change
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                                             AS lines,
    COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(product_id AS STRING))) AS pairs,
    ROUND(100 * SUM((discount_pct - pair_mean_discount) * (ln_quantity - pair_mean_ln_quantity))
          / SUM(POW(discount_pct - pair_mean_discount, 2)), 2)           AS pct_more_units_per_discount_point,
    ROUND(SQRT(AVG(POW(discount_pct - pair_mean_discount, 2))), 2)       AS within_pair_discount_sd_points
FROM `sahyadri_b2b.discount_response_lines`
WHERE pair_purchases >= min_purchases AND pair_discount_sd > 0
GROUP BY customer_segment
ORDER BY customer_segment;

-- Units bought when the discount is above vs below the pair's own average
SELECT
    CASE WHEN discount_pct - pair_mean_discount <= -2 THEN '1. 2+ points below own average'
         WHEN discount_pct - pair_mean_discount <   0 THEN '2. 0-2 points below'
         WHEN discount_pct - pair_mean_discount <   2 THEN '3. 0-2 points above'
         ELSE                                              '4. 2+ points above' END AS discount_vs_own_average,
    COUNT(*)                                                             AS lines,
    ROUND(AVG(discount_pct - pair_mean_discount), 2)                     AS avg_discount_gap_points,
    ROUND(100 * (EXP(AVG(ln_quantity - pair_mean_ln_quantity)) - 1), 1) AS units_vs_own_average_pct
FROM `sahyadri_b2b.discount_response_lines`
WHERE pair_purchases >= min_purchases AND pair_discount_sd > 0
GROUP BY discount_vs_own_average
ORDER BY discount_vs_own_average;

-- -----------------------------------------------------------------------------
-- Step 4 · Does the response pay for the discount?
-- -----------------------------------------------------------------------------
WITH avg_line AS (
    -- revenue-weighted average discount and cost as a share of the transaction price
    SELECT
        SUM(quantity * unit_price * discount_pct / 100) / SUM(quantity * unit_price) AS avg_discount,
        SUM(quantity * unit_cost) / SUM(quantity * unit_price)                         AS cost_share_of_price
    FROM `sahyadri_b2b.discount_response_lines`
    WHERE unit_cost IS NOT NULL
),
estimate AS (
    SELECT slope FROM `sahyadri_b2b.discount_response_estimates`
    WHERE model LIKE 'C.%'
)
SELECT
    ROUND(100 * a.avg_discount, 2)                                       AS avg_discount_pct,
    ROUND(100 * (1 - a.avg_discount - a.cost_share_of_price), 2)         AS margin_pct_of_price_before,
    ROUND(100 * (1 - a.avg_discount - 0.01 - a.cost_share_of_price), 2)  AS margin_pct_of_price_after_1_point,
    -- units needed so that gross profit is unchanged after one more discount point
    ROUND(100 * ((1 - a.avg_discount - a.cost_share_of_price)
                 / (1 - a.avg_discount - 0.01 - a.cost_share_of_price) - 1), 1) AS breakeven_extra_units_pct,
    ROUND(100 * e.slope, 2)                                              AS measured_extra_units_pct,
    ROUND(100 * ((1 + e.slope) * (1 - a.avg_discount - 0.01 - a.cost_share_of_price)
                 / (1 - a.avg_discount - a.cost_share_of_price) - 1), 1) AS gross_profit_change_pct
FROM avg_line AS a
CROSS JOIN estimate AS e;
