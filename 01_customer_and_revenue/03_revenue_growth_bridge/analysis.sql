/* =============================================================================
   Case study · Revenue growth bridge (year-to-date, 2026 vs 2025)
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Year-to-date revenue is well ahead of last year. Before the board meeting,
   the managing director wants to know where the growth came from, because
   the answer changes the plan for next year:
     1. How much did revenue grow, like for like, January-September?
     2. Did growth come from new customers or from existing customers buying
        more, and how much did lost and declining customers take away?
     3. Was it driven by more orders or bigger orders?
     4. Which categories and segments contributed the growth?
     5. How concentrated is the growth in a few accounts?

   KEY RULES
     - Like-for-like periods: 1 Jan-30 Sep 2025 (prior year, PY) vs
       1 Jan-30 Sep 2026 (current year, CY). Data ends on 30 Sep 2026.
     - Revenue on orders not Cancelled or Returned; NULL discount = 0 %.
     - Customer bridge (each customer in exactly one group):
         New      = revenue in CY only        Lost     = revenue in PY only
         Grew     = CY > PY                   Declined = CY < PY
     - Orders x average order value (AOV) decomposition:
         change from order count = (orders CY - orders PY) x AOV PY
         change from order size  = (AOV CY - AOV PY) x orders CY
       The two parts add up exactly to the total change.
   ============================================================================= */

DECLARE py_start DATE DEFAULT DATE '2025-01-01';
DECLARE py_end   DATE DEFAULT DATE '2025-09-30';
DECLARE cy_start DATE DEFAULT DATE '2026-01-01';
DECLARE cy_end   DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Order lines in either period, labelled PY or CY
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ytd_revenue_lines` AS
SELECT
    CASE
        WHEN o.order_date BETWEEN py_start AND py_end THEN 'PY'
        ELSE 'CY'
    END                                                                       AS period,
    o.order_id,
    o.order_date,
    o.customer_id,
    c.customer_segment,
    pc.category_name,
    i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)    AS revenue
FROM `sahyadri_b2b.sales_order_items`  AS i
JOIN `sahyadri_b2b.sales_orders`       AS o  ON o.order_id     = i.order_id
JOIN `sahyadri_b2b.customers`          AS c  ON c.customer_id  = o.customer_id
JOIN `sahyadri_b2b.products`           AS p  ON p.product_id   = i.product_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
  AND (o.order_date BETWEEN py_start AND py_end
       OR o.order_date BETWEEN cy_start AND cy_end);

-- -----------------------------------------------------------------------------
-- Step 2 · Headline: revenue, orders, customers and AOV, PY vs CY
-- -----------------------------------------------------------------------------
WITH by_period AS (
    SELECT
        period,
        SUM(revenue)                AS revenue,
        COUNT(DISTINCT order_id)    AS orders,
        COUNT(DISTINCT customer_id) AS customers
    FROM `sahyadri_b2b.ytd_revenue_lines`
    GROUP BY period
)
SELECT
    py.revenue                                        AS revenue_py,
    cy.revenue                                        AS revenue_cy,
    ROUND(100 * (cy.revenue / py.revenue - 1), 1)     AS revenue_growth_pct,
    py.orders                                         AS orders_py,
    cy.orders                                         AS orders_cy,
    py.customers                                      AS customers_py,
    cy.customers                                      AS customers_cy,
    ROUND(py.revenue / py.orders, 2)                  AS aov_py,
    ROUND(cy.revenue / cy.orders, 2)                  AS aov_cy
FROM by_period AS py
CROSS JOIN by_period AS cy
WHERE py.period = 'PY'
  AND cy.period = 'CY';

-- -----------------------------------------------------------------------------
-- Step 3 · Customer bridge: PY revenue -> CY revenue
-- -----------------------------------------------------------------------------
WITH customer_periods AS (
    SELECT
        customer_id,
        SUM(IF(period = 'PY', revenue, 0)) AS revenue_py,
        SUM(IF(period = 'CY', revenue, 0)) AS revenue_cy
    FROM `sahyadri_b2b.ytd_revenue_lines`
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN revenue_py = 0              THEN '1. New customers'
        WHEN revenue_cy > revenue_py     THEN '2. Existing customers - grew'
        WHEN revenue_cy < revenue_py
         AND revenue_cy > 0              THEN '3. Existing customers - declined'
        WHEN revenue_cy = 0              THEN '4. Lost customers'
        ELSE                                  '5. Unchanged'
    END                                       AS bridge_group,
    COUNT(*)                                  AS customers,
    ROUND(SUM(revenue_py), 2)                 AS revenue_py,
    ROUND(SUM(revenue_cy), 2)                 AS revenue_cy,
    ROUND(SUM(revenue_cy - revenue_py), 2)    AS revenue_change
FROM customer_periods
GROUP BY bridge_group
ORDER BY bridge_group;

-- -----------------------------------------------------------------------------
-- Step 4 · Order count vs order size: exact decomposition of the change
-- -----------------------------------------------------------------------------
WITH by_period AS (
    SELECT period, SUM(revenue) AS revenue, COUNT(DISTINCT order_id) AS orders
    FROM `sahyadri_b2b.ytd_revenue_lines`
    GROUP BY period
),
pivoted AS (
    SELECT
        MAX(IF(period = 'PY', revenue, NULL)) AS rev_py,
        MAX(IF(period = 'CY', revenue, NULL)) AS rev_cy,
        MAX(IF(period = 'PY', orders,  NULL)) AS ord_py,
        MAX(IF(period = 'CY', orders,  NULL)) AS ord_cy
    FROM by_period
)
SELECT
    ROUND(rev_cy - rev_py, 2)                                    AS total_change,
    ROUND((ord_cy - ord_py) * (rev_py / ord_py), 2)              AS change_from_more_orders,
    ROUND((rev_cy / ord_cy - rev_py / ord_py) * ord_cy, 2)       AS change_from_bigger_orders,
    ROUND(100 * (ord_cy / ord_py - 1), 1)                        AS order_count_growth_pct,
    ROUND(100 * ((rev_cy / ord_cy) / (rev_py / ord_py) - 1), 1)  AS aov_growth_pct
FROM pivoted;

-- -----------------------------------------------------------------------------
-- Step 5 · Contribution to growth by product category
-- -----------------------------------------------------------------------------
SELECT
    category_name,
    ROUND(SUM(IF(period = 'PY', revenue, 0)), 2)                        AS revenue_py,
    ROUND(SUM(IF(period = 'CY', revenue, 0)), 2)                        AS revenue_cy,
    ROUND(100 * (SUM(IF(period = 'CY', revenue, 0))
                 / SUM(IF(period = 'PY', revenue, 0)) - 1), 1)          AS growth_pct,
    ROUND(100 * SUM(IF(period = 'CY', revenue, -revenue))
          / SUM(SUM(IF(period = 'CY', revenue, -revenue))) OVER (), 1)  AS pct_of_total_growth
FROM `sahyadri_b2b.ytd_revenue_lines`
GROUP BY category_name
ORDER BY pct_of_total_growth DESC;

-- -----------------------------------------------------------------------------
-- Step 6 · Contribution to growth by customer segment
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    ROUND(SUM(IF(period = 'PY', revenue, 0)), 2)                        AS revenue_py,
    ROUND(SUM(IF(period = 'CY', revenue, 0)), 2)                        AS revenue_cy,
    ROUND(100 * (SUM(IF(period = 'CY', revenue, 0))
                 / SUM(IF(period = 'PY', revenue, 0)) - 1), 1)          AS growth_pct,
    ROUND(100 * SUM(IF(period = 'CY', revenue, -revenue))
          / SUM(SUM(IF(period = 'CY', revenue, -revenue))) OVER (), 1)  AS pct_of_total_growth
FROM `sahyadri_b2b.ytd_revenue_lines`
GROUP BY customer_segment
ORDER BY pct_of_total_growth DESC;

-- -----------------------------------------------------------------------------
-- Step 7 · Growth concentration: top 10 customers by revenue added
-- -----------------------------------------------------------------------------
WITH customer_change AS (
    SELECT
        l.customer_id,
        SUM(IF(l.period = 'PY', l.revenue, 0)) AS revenue_py,
        SUM(IF(l.period = 'CY', l.revenue, 0)) AS revenue_cy,
        SUM(IF(l.period = 'CY', l.revenue, -l.revenue)) AS revenue_change
    FROM `sahyadri_b2b.ytd_revenue_lines` AS l
    GROUP BY l.customer_id
)
SELECT
    cc.customer_id,
    cu.customer_name,
    cu.customer_segment,
    ROUND(cc.revenue_py, 2)                                            AS revenue_py,
    ROUND(cc.revenue_cy, 2)                                            AS revenue_cy,
    ROUND(cc.revenue_change, 2)                                        AS revenue_change,
    ROUND(100 * cc.revenue_change / SUM(cc.revenue_change) OVER (), 1) AS pct_of_net_growth
FROM customer_change           AS cc
JOIN `sahyadri_b2b.customers`  AS cu
    ON cu.customer_id = cc.customer_id
ORDER BY cc.revenue_change DESC
LIMIT 10;
