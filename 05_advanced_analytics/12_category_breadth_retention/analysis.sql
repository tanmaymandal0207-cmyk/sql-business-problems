/* =============================================================================
   Case study · Category breadth and retention
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The cross-sell programme is sold internally on one claim: customers who
   buy from more product categories stay longer. The raw numbers look
   overwhelming. But customers who buy more categories also buy more often,
   and frequent buyers stay anyway. Before funding cross-sell targets, the
   commercial head wants to know:
     1. How strongly is category breadth linked to retention?
     2. Does breadth still matter for customers who buy equally often?
     3. For which customers does breadth matter most?
     4. Do broader customers also grow more?

   METHOD
     - Half-year panel: H = Jan-Jun or Jul-Dec. Base halves 2024 H1 - 2025 H2;
       outcome = the customer bought again in the following half
       (2024 H2 - 2026 H1). 2026 H2 is incomplete and not used as an outcome.
     - Breadth = distinct product categories bought in the base half.
     - Frequency band = orders in the base half: 1, 2, 3-4, 5-8, 9+.
     - Within each frequency band, Broad = breadth above the band median,
       Narrow = at or below it.
     - Pooled within-band difference: Mantel-Haenszel weighted average of
       (Broad - Narrow) retention, weight w = nB * nN / (nB + nN); standard
       error from the weighted binomial variances.

   KEY RULES
     - Revenue and activity: orders not Cancelled or Returned.
   ============================================================================= */

DECLARE last_base_half INT64 DEFAULT 3;   -- 0 = 2024 H1 ... 3 = 2025 H2

-- -----------------------------------------------------------------------------
-- Step 1 · Customer half-year panel
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.breadth_panel` AS
WITH lines AS (
    SELECT
        o.customer_id,
        o.order_id,
        (EXTRACT(YEAR FROM o.order_date) - 2024) * 2 + IF(EXTRACT(MONTH FROM o.order_date) > 6, 1, 0) AS half_index,
        p.category_id,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)                         AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
halves AS (
    SELECT
        customer_id,
        half_index,
        COUNT(DISTINCT category_id)                                    AS categories,
        COUNT(DISTINCT order_id)                                       AS orders,
        SUM(revenue)                                                   AS revenue
    FROM lines
    GROUP BY customer_id, half_index
),
panel AS (
    SELECT
        a.customer_id,
        a.half_index,
        a.categories,
        a.orders,
        a.revenue,
        n.customer_id IS NOT NULL                                      AS retained,
        IFNULL(n.revenue, 0)                                           AS next_revenue,
        CASE WHEN a.orders = 1 THEN '1. One order'
             WHEN a.orders = 2 THEN '2. Two orders'
             WHEN a.orders <= 4 THEN '3. 3-4 orders'
             WHEN a.orders <= 8 THEN '4. 5-8 orders'
             ELSE '5. 9+ orders' END                                   AS frequency_band
    FROM halves AS a
    LEFT JOIN halves AS n
      ON n.customer_id = a.customer_id AND n.half_index = a.half_index + 1
    WHERE a.half_index <= last_base_half
),
band_median AS (
    SELECT frequency_band, APPROX_QUANTILES(categories, 2)[OFFSET(1)] AS median_categories
    FROM panel
    GROUP BY frequency_band
)
SELECT
    p.*,
    m.median_categories,
    IF(p.categories > m.median_categories, 'Broad', 'Narrow')         AS breadth_group,
    CASE WHEN p.categories <= 2 THEN '1. 1-2'
         WHEN p.categories <= 4 THEN '2. 3-4'
         WHEN p.categories <= 6 THEN '3. 5-6'
         ELSE '4. 7+' END                                              AS breadth_band
FROM panel AS p
JOIN band_median AS m ON m.frequency_band = p.frequency_band;

-- -----------------------------------------------------------------------------
-- Step 2 · The raw link: retention by breadth
-- -----------------------------------------------------------------------------
SELECT
    breadth_band                                                       AS categories_in_half,
    COUNT(*)                                                           AS customer_halves,
    ROUND(AVG(orders), 1)                                              AS avg_orders,
    ROUND(100 * AVG(IF(retained, 1, 0)), 1)                            AS retained_next_half_pct,
    ROUND(100 * SUM(next_revenue) / SUM(revenue), 1)                   AS next_half_revenue_pct_of_base
FROM `sahyadri_b2b.breadth_panel`
GROUP BY breadth_band
ORDER BY breadth_band;

SELECT ROUND(CORR(categories, orders), 3) AS correlation_breadth_vs_orders
FROM `sahyadri_b2b.breadth_panel`;

-- -----------------------------------------------------------------------------
-- Step 3 · Same frequency, different breadth
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.breadth_within_band` AS
SELECT
    frequency_band,
    ANY_VALUE(median_categories)                                       AS median_categories,
    COUNTIF(breadth_group = 'Broad')                                   AS broad_n,
    COUNTIF(breadth_group = 'Narrow')                                  AS narrow_n,
    AVG(IF(breadth_group = 'Broad',  IF(retained, 1, 0), NULL))        AS broad_retention,
    AVG(IF(breadth_group = 'Narrow', IF(retained, 1, 0), NULL))        AS narrow_retention,
    SAFE_DIVIDE(SUM(IF(breadth_group = 'Broad', next_revenue, 0)),  SUM(IF(breadth_group = 'Broad', revenue, 0)))  AS broad_revenue_ratio,
    SAFE_DIVIDE(SUM(IF(breadth_group = 'Narrow', next_revenue, 0)), SUM(IF(breadth_group = 'Narrow', revenue, 0))) AS narrow_revenue_ratio
FROM `sahyadri_b2b.breadth_panel`
GROUP BY frequency_band;

SELECT
    frequency_band,
    median_categories,
    broad_n,
    narrow_n,
    ROUND(100 * broad_retention, 1)                                    AS broad_retained_pct,
    ROUND(100 * narrow_retention, 1)                                   AS narrow_retained_pct,
    ROUND(100 * (broad_retention - narrow_retention), 1)               AS difference_pts,
    ROUND(100 * broad_revenue_ratio, 1)                                AS broad_next_half_revenue_pct,
    ROUND(100 * narrow_revenue_ratio, 1)                               AS narrow_next_half_revenue_pct
FROM `sahyadri_b2b.breadth_within_band`
ORDER BY frequency_band;

-- Pooled within-band difference (Mantel-Haenszel weights) with a z-statistic
WITH w AS (
    SELECT
        *,
        broad_n * narrow_n / (broad_n + narrow_n)                      AS weight,
        broad_retention * (1 - broad_retention) / broad_n
          + narrow_retention * (1 - narrow_retention) / narrow_n       AS variance
    FROM `sahyadri_b2b.breadth_within_band`
    WHERE broad_n > 0 AND narrow_n > 0
)
SELECT
    COUNT(*)                                                           AS bands_compared,
    SUM(broad_n + narrow_n)                                            AS customer_halves,
    ROUND(100 * SUM(weight * (broad_retention - narrow_retention)) / SUM(weight), 1) AS pooled_difference_pts,
    ROUND((SUM(weight * (broad_retention - narrow_retention)) / SUM(weight))
          / (SQRT(SUM(weight * weight * variance)) / SUM(weight)), 2)  AS z_statistic
FROM w;

-- -----------------------------------------------------------------------------
-- Step 4 · One-order customers: does a broader first basket keep them?
-- -----------------------------------------------------------------------------
SELECT
    LEAST(categories, 5)                                               AS categories_in_the_one_order,
    COUNT(*)                                                           AS customer_halves,
    ROUND(100 * AVG(IF(retained, 1, 0)), 1)                            AS retained_next_half_pct,
    ROUND(AVG(revenue), 0)                                             AS avg_order_value
FROM `sahyadri_b2b.breadth_panel`
WHERE frequency_band = '1. One order'
GROUP BY categories_in_the_one_order
ORDER BY categories_in_the_one_order;
