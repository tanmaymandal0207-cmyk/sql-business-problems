/* =============================================================================
   Case study · Warehouse slotting by pick frequency
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The warehouse is being re-racked. Today, the products nearest the
   dispatch bay are the "A" products from the ABC classification, which
   ranks products by revenue. But pickers walk to a location once per order
   line, whatever the line is worth. The warehouse manager asks:
     1. How different is a ranking by pick frequency from the revenue ABC?
     2. How much walking would slotting by pick frequency save?
     3. Which products should move closer to (or away from) dispatch?
     4. Which products are picked together, so they should sit side by side?

   METHOD
     - Period: last 12 months (1 Oct 2025 - 30 Sep 2026); orders not
       Cancelled or Returned. One order line = one pick.
     - Pick ABC: products ranked by picks; A = first 80 % of picks,
       B = next 15 %, C = last 5 %. Revenue ABC: the same on revenue.
     - Travel model (assumptions, set as parameters): three zones holding a
       fixed number of products - Zone 1 the top 20 % of products, Zone 2
       the next 30 %, Zone 3 the rest - at 10, 25 and 45 metres from the
       dispatch bay. Each pick is a round trip. Products are placed in zones
       by revenue rank (today) or by pick rank (proposed).
   ============================================================================= */

DECLARE period_start DATE    DEFAULT DATE '2025-10-01';
DECLARE period_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE zone1_share  FLOAT64 DEFAULT 0.20;
DECLARE zone2_share  FLOAT64 DEFAULT 0.30;
DECLARE zone1_metres FLOAT64 DEFAULT 10;
DECLARE zone2_metres FLOAT64 DEFAULT 25;
DECLARE zone3_metres FLOAT64 DEFAULT 45;

-- -----------------------------------------------------------------------------
-- Step 1 · Picks, units and revenue per product, with both rankings
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.slotting_products` AS
WITH lines AS (
    SELECT
        i.order_id,
        i.product_id,
        i.quantity,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN period_start AND period_end
),
by_product AS (
    SELECT product_id, COUNT(*) AS picks, SUM(quantity) AS units, SUM(revenue) AS revenue
    FROM lines
    GROUP BY product_id
),
ranked AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (ORDER BY picks DESC, revenue DESC, product_id)          AS pick_rank,
        ROW_NUMBER() OVER (ORDER BY revenue DESC, picks DESC, product_id)          AS revenue_rank,
        SUM(picks)   OVER (ORDER BY picks DESC, revenue DESC, product_id) / SUM(picks) OVER ()     AS cum_pick_share,
        SUM(revenue) OVER (ORDER BY revenue DESC, picks DESC, product_id) / SUM(revenue) OVER () AS cum_revenue_share,
        COUNT(*) OVER ()                                                           AS products
    FROM by_product AS b
)
SELECT
    r.*,
    p.product_name,
    pc.category_name,
    CASE WHEN cum_pick_share    - picks / SUM(picks) OVER ()     < 0.80 THEN 'A'
         WHEN cum_pick_share    - picks / SUM(picks) OVER ()     < 0.95 THEN 'B'
         ELSE 'C' END                                                              AS pick_class,
    CASE WHEN cum_revenue_share - revenue / SUM(revenue) OVER () < 0.80 THEN 'A'
         WHEN cum_revenue_share - revenue / SUM(revenue) OVER () < 0.95 THEN 'B'
         ELSE 'C' END                                                              AS revenue_class,
    CASE WHEN pick_rank    <= CEIL(zone1_share * products) THEN 1
         WHEN pick_rank    <= CEIL((zone1_share + zone2_share) * products) THEN 2
         ELSE 3 END                                                                AS zone_by_picks,
    CASE WHEN revenue_rank <= CEIL(zone1_share * products) THEN 1
         WHEN revenue_rank <= CEIL((zone1_share + zone2_share) * products) THEN 2
         ELSE 3 END                                                                AS zone_by_revenue
FROM ranked AS r
JOIN `sahyadri_b2b.products`           AS p  ON p.product_id = r.product_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id;

-- Concentration of picks and revenue
SELECT
    COUNT(*)                                                                       AS products_picked,
    SUM(picks)                                                                     AS picks,
    COUNTIF(pick_class = 'A')                                                      AS pick_a_products,
    COUNTIF(revenue_class = 'A')                                                   AS revenue_a_products,
    ROUND(CORR(picks, revenue), 3)                                                 AS correlation_picks_revenue,
    ROUND(CORR(picks, units), 3)                                                   AS correlation_picks_units,
    (SELECT COUNT(*) FROM `sahyadri_b2b.products`) - COUNT(*)                      AS products_never_picked
FROM `sahyadri_b2b.slotting_products`;

-- The most-picked products and where revenue ranks them
SELECT product_id, product_name, category_name, picks,
       ROUND(100 * picks / SUM(picks) OVER (), 1) AS share_of_picks_pct,
       ROUND(revenue / 1e5, 1) AS revenue_lakh, pick_rank, revenue_rank, revenue_class
FROM `sahyadri_b2b.slotting_products`
QUALIFY pick_rank <= 8
ORDER BY pick_rank;

-- -----------------------------------------------------------------------------
-- Step 2 · How different are the two classifications?
-- -----------------------------------------------------------------------------
SELECT
    pick_class,
    COUNTIF(revenue_class = 'A')                                                   AS revenue_a,
    COUNTIF(revenue_class = 'B')                                                   AS revenue_b,
    COUNTIF(revenue_class = 'C')                                                   AS revenue_c,
    COUNT(*)                                                                       AS products,
    ROUND(100 * SUM(picks) / SUM(SUM(picks)) OVER (), 1)                           AS share_of_picks_pct,
    ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)                       AS share_of_revenue_pct
FROM `sahyadri_b2b.slotting_products`
GROUP BY pick_class
ORDER BY pick_class;

-- -----------------------------------------------------------------------------
-- Step 3 · Travel: zones by revenue (today) vs by picks (proposed)
-- -----------------------------------------------------------------------------
WITH travel AS (
    SELECT
        SUM(picks * 2 * CASE zone_by_revenue WHEN 1 THEN zone1_metres WHEN 2 THEN zone2_metres ELSE zone3_metres END) AS metres_by_revenue,
        SUM(picks * 2 * CASE zone_by_picks   WHEN 1 THEN zone1_metres WHEN 2 THEN zone2_metres ELSE zone3_metres END) AS metres_by_picks,
        SUM(picks)                                                                 AS picks
    FROM `sahyadri_b2b.slotting_products`
)
SELECT
    picks,
    ROUND(metres_by_revenue / 1000, 1)                                             AS km_per_year_by_revenue,
    ROUND(metres_by_picks / 1000, 1)                                               AS km_per_year_by_picks,
    ROUND(100 * (1 - metres_by_picks / metres_by_revenue), 1)                      AS travel_saving_pct,
    ROUND(metres_by_revenue / picks, 1)                                            AS metres_per_pick_by_revenue,
    ROUND(metres_by_picks / picks, 1)                                              AS metres_per_pick_by_picks
FROM travel;

SELECT
    zone,
    COUNTIF(zone_by_revenue = zone)                                                AS products_by_revenue,
    SUM(IF(zone_by_revenue = zone, picks, 0))                                      AS picks_by_revenue,
    COUNTIF(zone_by_picks = zone)                                                  AS products_by_picks,
    SUM(IF(zone_by_picks = zone, picks, 0))                                        AS picks_by_picks
FROM `sahyadri_b2b.slotting_products`
CROSS JOIN UNNEST([1, 2, 3]) AS zone
GROUP BY zone
ORDER BY zone;

-- -----------------------------------------------------------------------------
-- Step 4 · Products to move
-- -----------------------------------------------------------------------------
SELECT
    IF(zone_by_picks < zone_by_revenue, 'Move closer', 'Move further') AS move,
    product_id,
    product_name,
    category_name,
    picks,
    ROUND(revenue / 1e5, 1)                                                        AS revenue_lakh,
    pick_rank,
    revenue_rank,
    zone_by_revenue                                                                AS zone_today,
    zone_by_picks                                                                  AS zone_proposed
FROM `sahyadri_b2b.slotting_products`
WHERE zone_by_picks != zone_by_revenue
QUALIFY ROW_NUMBER() OVER (PARTITION BY zone_by_picks < zone_by_revenue
                           ORDER BY ABS(pick_rank - revenue_rank) DESC) <= 8
ORDER BY move, ABS(pick_rank - revenue_rank) DESC;

SELECT
    COUNTIF(zone_by_picks < zone_by_revenue)                                       AS products_moving_closer,
    COUNTIF(zone_by_picks > zone_by_revenue)                                       AS products_moving_further,
    COUNTIF(zone_by_picks = zone_by_revenue)                                       AS products_staying
FROM `sahyadri_b2b.slotting_products`;

-- -----------------------------------------------------------------------------
-- Step 5 · Products picked together (Zone 1 candidates to place side by side)
-- -----------------------------------------------------------------------------
WITH lines AS (
    SELECT DISTINCT i.order_id, i.product_id
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN period_start AND period_end
)
SELECT
    a.product_id                                                                   AS product_a,
    pa.product_name                                                                AS product_a_name,
    b.product_id                                                                   AS product_b,
    pb.product_name                                                                AS product_b_name,
    COUNT(*)                                                                       AS orders_together
FROM lines AS a
JOIN lines AS b ON b.order_id = a.order_id AND b.product_id > a.product_id
JOIN `sahyadri_b2b.slotting_products` AS pa ON pa.product_id = a.product_id
JOIN `sahyadri_b2b.slotting_products` AS pb ON pb.product_id = b.product_id
GROUP BY product_a, product_a_name, product_b, product_b_name
ORDER BY orders_together DESC
LIMIT 8;
