/* =============================================================================
   Case study · Cross-sell white-space analysis
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The company sells ten product categories, but many customers buy only a
   few of them. Selling more categories to existing customers is usually
   cheaper than winning new ones. The sales head wants to know:
     1. How many categories do customers buy, and how does that relate to
        their value?
     2. Which categories are under-penetrated in each customer segment?
     3. Where is the "white space": categories a customer does not buy but
        most similar customers do, and roughly what is it worth?

   KEY RULES
     - Window: last 12 months, 1 Oct 2025 - 30 Sep 2026.
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Active customer: at least one in-scope order in the window.
     - Penetration: share of a segment's active customers who bought the
       category in the window.
     - White-space gap: an active customer who did not buy a category that at
       least `min_penetration` (60 %) of their segment peers bought.
     - Gap value (indicative): the median 12-month spend on that category
       among buyers in the same segment.
   ============================================================================= */

DECLARE window_start    DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end      DATE    DEFAULT DATE '2026-09-30';
DECLARE min_penetration FLOAT64 DEFAULT 0.60;

-- -----------------------------------------------------------------------------
-- Step 1 · Customer x category spend grid (every active customer x every category)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_category_spend` AS
WITH spend AS (
    SELECT
        o.customer_id,
        p.category_id,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue_12m
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id   = i.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN window_start AND window_end
    GROUP BY o.customer_id, p.category_id
),
active_customers AS (
    SELECT DISTINCT s.customer_id, c.customer_segment
    FROM spend AS s
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = s.customer_id
)
SELECT
    a.customer_id,
    a.customer_segment,
    pc.category_id,
    pc.category_name,
    IFNULL(s.revenue_12m, 0)       AS revenue_12m,
    s.customer_id IS NOT NULL      AS bought
FROM active_customers                  AS a
CROSS JOIN `sahyadri_b2b.product_categories` AS pc
LEFT JOIN spend                        AS s
    ON s.customer_id = a.customer_id
   AND s.category_id = pc.category_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Category breadth vs customer value
-- -----------------------------------------------------------------------------
WITH breadth AS (
    SELECT customer_id, COUNTIF(bought) AS categories_bought, SUM(revenue_12m) AS revenue_12m
    FROM `sahyadri_b2b.customer_category_spend`
    GROUP BY customer_id
)
SELECT
    categories_bought,
    COUNT(*)                                                           AS customers,
    ROUND(AVG(revenue_12m), 0)                                         AS avg_revenue_12m,
    ROUND(100 * SUM(revenue_12m) / SUM(SUM(revenue_12m)) OVER (), 1)   AS pct_of_revenue
FROM breadth
GROUP BY categories_bought
ORDER BY categories_bought;

-- -----------------------------------------------------------------------------
-- Step 3 · Penetration by segment and category (% of active customers buying)
-- -----------------------------------------------------------------------------
SELECT
    category_name,
    ROUND(100 * AVG(IF(customer_segment = 'Enterprise',  IF(bought, 1, 0), NULL)), 0) AS enterprise_pct,
    ROUND(100 * AVG(IF(customer_segment = 'Distributor', IF(bought, 1, 0), NULL)), 0) AS distributor_pct,
    ROUND(100 * AVG(IF(customer_segment = 'Mid-Market',  IF(bought, 1, 0), NULL)), 0) AS mid_market_pct,
    ROUND(100 * AVG(IF(customer_segment = 'SMB',         IF(bought, 1, 0), NULL)), 0) AS smb_pct,
    ROUND(100 * AVG(IF(bought, 1, 0)), 0)                                              AS all_customers_pct
FROM `sahyadri_b2b.customer_category_spend`
GROUP BY category_name
ORDER BY all_customers_pct;

-- -----------------------------------------------------------------------------
-- Step 4 · White-space gaps: categories a customer does not buy although most
--          of their segment peers do, valued at the peers' median spend
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cross_sell_gaps` AS
WITH segment_category AS (
    SELECT DISTINCT
        customer_segment,
        category_id,
        AVG(IF(bought, 1, 0)) OVER (PARTITION BY customer_segment, category_id) AS penetration
    FROM `sahyadri_b2b.customer_category_spend`
),
peer_median_spend AS (
    SELECT DISTINCT
        customer_segment,
        category_id,
        PERCENTILE_CONT(revenue_12m, 0.5) OVER (PARTITION BY customer_segment, category_id) AS median_spend
    FROM `sahyadri_b2b.customer_category_spend`
    WHERE bought
)
SELECT
    g.customer_id,
    g.customer_segment,
    g.category_name,
    ROUND(sc.penetration * 100, 0)     AS segment_penetration_pct,
    ROUND(pm.median_spend, 2)          AS indicative_gap_value
FROM `sahyadri_b2b.customer_category_spend` AS g
JOIN segment_category  AS sc
    ON sc.customer_segment = g.customer_segment AND sc.category_id = g.category_id
JOIN peer_median_spend AS pm
    ON pm.customer_segment = g.customer_segment AND pm.category_id = g.category_id
WHERE NOT g.bought
  AND sc.penetration >= min_penetration;

-- Summary by segment
SELECT
    customer_segment,
    COUNT(DISTINCT customer_id)                  AS customers_with_gaps,
    COUNT(*)                                     AS gaps,
    ROUND(SUM(indicative_gap_value), 2)          AS indicative_gap_value
FROM `sahyadri_b2b.cross_sell_gaps`
GROUP BY customer_segment
ORDER BY indicative_gap_value DESC;

-- Summary by category
SELECT
    category_name,
    COUNT(*)                                     AS customers_not_buying,
    ROUND(SUM(indicative_gap_value), 2)          AS indicative_gap_value
FROM `sahyadri_b2b.cross_sell_gaps`
GROUP BY category_name
ORDER BY indicative_gap_value DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Top 10 customers by white-space value (account plan list)
-- -----------------------------------------------------------------------------
SELECT
    g.customer_id,
    c.customer_name,
    g.customer_segment,
    COUNT(*)                                                AS missing_categories,
    STRING_AGG(g.category_name, ', ' ORDER BY g.indicative_gap_value DESC) AS categories_to_offer,
    ROUND(SUM(g.indicative_gap_value), 2)                   AS indicative_gap_value
FROM `sahyadri_b2b.cross_sell_gaps` AS g
JOIN `sahyadri_b2b.customers`       AS c ON c.customer_id = g.customer_id
GROUP BY g.customer_id, c.customer_name, g.customer_segment
ORDER BY indicative_gap_value DESC
LIMIT 10;
