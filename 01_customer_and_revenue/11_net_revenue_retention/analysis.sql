/* =============================================================================
   Case study · Net and gross revenue retention
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The company is preparing an information memorandum for a lender. The
   lender asks for two standard measures of the quality of recurring B2B
   revenue: net revenue retention (NRR) and gross revenue retention (GRR),
   tracked quarter by quarter. The CFO also wants to know:
     1. How much of last year's customer revenue is kept, lost, shrunk or
        expanded a year later?
     2. Is retention improving or deteriorating?
     3. How much of NRR is price increase rather than customers buying more?
     4. Which segments and customer sizes retain best, and how much does
        NRR depend on a handful of expanding accounts?

   METHOD (for each quarter end Q, from Dec 2025 to Sep 2026)
     - Base revenue B   = customer revenue in the 12 months ending 12 months
                          before Q.
     - Current revenue C = customer revenue in the 12 months ending at Q.
     - Base customers: B > 0.
       Churn        = B for customers with C = 0
       Contraction  = B - C for customers with 0 < C < B
       Expansion    = C - B for customers with C > B
       NRR = sum of C over base customers / sum of B
       GRR = sum of LEAST(B, C) / sum of B   (= 1 - churn% - contraction%)
       Logo retention = base customers with C > 0 / base customers
     - New revenue: C of customers with B = 0 (new or returning after a year).
     - Constant-price NRR: the same calculation on revenue valued at the
       current (2026) list price: quantity x list price x (1 - discount %),
       which removes the January price increases.

   KEY RULES
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
   ============================================================================= */

DECLARE quarter_ends     ARRAY<DATE> DEFAULT [DATE '2025-12-31', DATE '2026-03-31', DATE '2026-06-30', DATE '2026-09-30'];
DECLARE last_quarter_end DATE        DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Customer base and current revenue for each quarter end
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.revenue_retention_customers` AS
WITH quarters AS (
    SELECT quarter_end FROM UNNEST(quarter_ends) AS quarter_end
),
lines AS (
    SELECT
        o.customer_id,
        o.order_date,
        i.quantity * i.unit_price      * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue,
        i.quantity * p.selling_price   * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue_at_list
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
windowed AS (
    SELECT
        q.quarter_end,
        l.customer_id,
        SUM(IF(l.order_date >  DATE_SUB(q.quarter_end, INTERVAL 24 MONTH)
           AND l.order_date <= DATE_SUB(q.quarter_end, INTERVAL 12 MONTH), l.revenue, 0))         AS base_revenue,
        SUM(IF(l.order_date >  DATE_SUB(q.quarter_end, INTERVAL 12 MONTH)
           AND l.order_date <= q.quarter_end, l.revenue, 0))                                      AS current_revenue,
        SUM(IF(l.order_date >  DATE_SUB(q.quarter_end, INTERVAL 24 MONTH)
           AND l.order_date <= DATE_SUB(q.quarter_end, INTERVAL 12 MONTH), l.revenue_at_list, 0)) AS base_revenue_at_list,
        SUM(IF(l.order_date >  DATE_SUB(q.quarter_end, INTERVAL 12 MONTH)
           AND l.order_date <= q.quarter_end, l.revenue_at_list, 0))                              AS current_revenue_at_list
    FROM quarters AS q
    JOIN lines AS l
      ON l.order_date >  DATE_SUB(q.quarter_end, INTERVAL 24 MONTH)
     AND l.order_date <= q.quarter_end
    GROUP BY q.quarter_end, l.customer_id
)
SELECT
    w.*,
    c.customer_name,
    c.customer_segment,
    CASE WHEN w.base_revenue = 0                            THEN 'New or returning'
         WHEN w.current_revenue = 0                         THEN 'Churned'
         WHEN w.current_revenue < w.base_revenue            THEN 'Contracted'
         WHEN w.current_revenue > w.base_revenue            THEN 'Expanded'
         ELSE 'Flat' END                                                   AS movement,
    CASE WHEN w.base_revenue = 0          THEN NULL
         WHEN w.base_revenue >= 5000000   THEN '1. Rs 50 lakh+'
         WHEN w.base_revenue >= 1000000   THEN '2. Rs 10-50 lakh'
         WHEN w.base_revenue >= 200000    THEN '3. Rs 2-10 lakh'
         ELSE                                  '4. Under Rs 2 lakh' END    AS base_size_band
FROM windowed AS w
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = w.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · NRR, GRR and the revenue bridge for every quarter end
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.revenue_retention_quarterly` AS
SELECT
    quarter_end,
    COUNTIF(base_revenue > 0)                                                        AS base_customers,
    COUNTIF(base_revenue > 0 AND current_revenue > 0)                                AS retained_customers,
    COUNTIF(base_revenue = 0)                                                        AS new_or_returning_customers,
    SUM(base_revenue)                                                                AS base_revenue,
    SUM(IF(movement = 'Churned', base_revenue, 0))                                   AS churn,
    SUM(IF(movement = 'Contracted', base_revenue - current_revenue, 0))              AS contraction,
    SUM(IF(movement = 'Expanded', current_revenue - base_revenue, 0))                AS expansion,
    SUM(IF(base_revenue = 0, current_revenue, 0))                                    AS new_revenue,
    SUM(current_revenue)                                                             AS current_revenue,
    SUM(IF(base_revenue > 0, current_revenue, 0)) / SUM(base_revenue)                AS nrr,
    SUM(IF(base_revenue > 0, LEAST(base_revenue, current_revenue), 0)) / SUM(base_revenue) AS grr,
    COUNTIF(base_revenue > 0 AND current_revenue > 0) / COUNTIF(base_revenue > 0)    AS logo_retention,
    SUM(IF(base_revenue_at_list > 0, current_revenue_at_list, 0)) / SUM(base_revenue_at_list) AS nrr_at_constant_price
FROM `sahyadri_b2b.revenue_retention_customers`
GROUP BY quarter_end;

SELECT
    quarter_end,
    base_customers,
    retained_customers,
    ROUND(base_revenue / 1e7, 2)                       AS base_revenue_crore,
    ROUND(-churn / 1e7, 2)                             AS churn_crore,
    ROUND(-contraction / 1e7, 2)                       AS contraction_crore,
    ROUND(expansion / 1e7, 2)                          AS expansion_crore,
    ROUND(new_revenue / 1e7, 2)                        AS new_or_returning_crore,
    ROUND(current_revenue / 1e7, 2)                    AS current_revenue_crore,
    ROUND(100 * nrr, 1)                                AS nrr_pct,
    ROUND(100 * grr, 1)                                AS grr_pct,
    ROUND(100 * logo_retention, 1)                     AS logo_retention_pct,
    ROUND(100 * nrr_at_constant_price, 1)              AS nrr_constant_price_pct
FROM `sahyadri_b2b.revenue_retention_quarterly`
ORDER BY quarter_end;

-- -----------------------------------------------------------------------------
-- Step 3 · Latest quarter by segment and by base size
-- -----------------------------------------------------------------------------
SELECT
    'Segment' AS dimension,
    customer_segment AS value_band,
    COUNTIF(base_revenue > 0)                                                        AS base_customers,
    ROUND(SUM(base_revenue) / 1e5, 1)                                                AS base_revenue_lakh,
    ROUND(100 * SUM(IF(base_revenue > 0, current_revenue, 0)) / SUM(base_revenue), 1) AS nrr_pct,
    ROUND(100 * SUM(IF(base_revenue > 0, LEAST(base_revenue, current_revenue), 0)) / SUM(base_revenue), 1) AS grr_pct,
    ROUND(100 * COUNTIF(base_revenue > 0 AND current_revenue > 0) / COUNTIF(base_revenue > 0), 1) AS logo_retention_pct
FROM `sahyadri_b2b.revenue_retention_customers`
WHERE quarter_end = last_quarter_end AND base_revenue > 0
GROUP BY customer_segment
UNION ALL
SELECT
    'Base size',
    base_size_band,
    COUNT(*),
    ROUND(SUM(base_revenue) / 1e5, 1),
    ROUND(100 * SUM(current_revenue) / SUM(base_revenue), 1),
    ROUND(100 * SUM(LEAST(base_revenue, current_revenue)) / SUM(base_revenue), 1),
    ROUND(100 * COUNTIF(current_revenue > 0) / COUNT(*), 1)
FROM `sahyadri_b2b.revenue_retention_customers`
WHERE quarter_end = last_quarter_end AND base_revenue > 0
GROUP BY base_size_band
ORDER BY dimension DESC, value_band;

-- -----------------------------------------------------------------------------
-- Step 4 · How much does NRR depend on the largest expanders?
-- -----------------------------------------------------------------------------
WITH ranked AS (
    SELECT
        quarter_end,
        customer_id,
        customer_name,
        base_revenue,
        current_revenue,
        current_revenue - base_revenue                                               AS change,
        ROW_NUMBER() OVER (PARTITION BY quarter_end ORDER BY current_revenue - base_revenue DESC, customer_id) AS expansion_rank
    FROM `sahyadri_b2b.revenue_retention_customers`
    WHERE base_revenue > 0
)
SELECT
    quarter_end,
    ROUND(100 * SUM(current_revenue) / SUM(base_revenue), 1)                         AS nrr_pct,
    ROUND(100 * SUM(IF(expansion_rank > 1,  current_revenue, base_revenue)) / SUM(base_revenue), 1) AS nrr_without_top_1_pct,
    ROUND(100 * SUM(IF(expansion_rank > 5,  current_revenue, base_revenue)) / SUM(base_revenue), 1) AS nrr_without_top_5_pct,
    ROUND(100 * SUM(IF(expansion_rank > 10, current_revenue, base_revenue)) / SUM(base_revenue), 1) AS nrr_without_top_10_pct
FROM ranked
GROUP BY quarter_end
ORDER BY quarter_end;

-- Largest movements in the latest quarter
SELECT
    movement,
    customer_name,
    customer_segment,
    ROUND(base_revenue / 1e5, 1)                       AS base_lakh,
    ROUND(current_revenue / 1e5, 1)                    AS current_lakh,
    ROUND((current_revenue - base_revenue) / 1e5, 1)   AS change_lakh
FROM `sahyadri_b2b.revenue_retention_customers`
WHERE quarter_end = last_quarter_end AND base_revenue > 0
  AND movement IN ('Expanded', 'Churned', 'Contracted')
QUALIFY ROW_NUMBER() OVER (PARTITION BY movement ORDER BY ABS(current_revenue - base_revenue) DESC) <= 5
ORDER BY movement, ABS(current_revenue - base_revenue) DESC;
