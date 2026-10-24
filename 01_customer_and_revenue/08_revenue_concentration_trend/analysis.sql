/* =============================================================================
   Case study · Revenue concentration trend
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The customer revenue risk study measured concentration at one point in
   time. The board now asks whether the business is becoming more or less
   dependent on a few customers, because lenders and investors read rising
   concentration as rising risk. The CFO wants concentration tracked over
   time with standard measures, and wants to know:
     1. Is revenue becoming more or less concentrated, quarter by quarter?
     2. How many "equally sized" customers is the business effectively
        relying on?
     3. Which customers drive the changes, and is the latest movement a
        trend or a one-off?
     4. Which segments are most concentrated?

   MEASURES (computed on customer revenue shares s_i within each period)
     - Top-1, top-5 and top-10 share
     - Herfindahl-Hirschman Index HHI = sum of s_i^2 (0 to 1; higher = more
       concentrated). Reported on the usual 0-10,000 scale as well.
     - Effective number of customers = 1 / HHI: the number of equal-sized
       customers that would give the same concentration.
     - Gini coefficient with customers sorted from smallest to largest:
         G = 2 * sum(i * x_i) / (n * sum(x_i)) - (n + 1) / n
       (0 = all customers equal; close to 1 = one customer has everything)

   KEY RULES
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Quarterly periods 2024 Q1 - 2026 Q3, and rolling 12-month windows
       ending each quarter from Dec 2024.
     - Customers with revenue in the period only.
   ============================================================================= */

DECLARE last_quarter DATE DEFAULT DATE '2026-07-01';

-- -----------------------------------------------------------------------------
-- Step 1 · Customer revenue per period (quarters and rolling 12-month windows)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.concentration_periods` AS
WITH quarterly AS (
    SELECT
        o.customer_id,
        DATE_TRUNC(o.order_date, QUARTER)                                          AS quarter_start,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND DATE_TRUNC(o.order_date, QUARTER) <= last_quarter
    GROUP BY o.customer_id, quarter_start
),
quarters AS (
    SELECT DISTINCT quarter_start FROM quarterly
)
SELECT 'Quarter' AS period_type, quarter_start AS period_start, quarter_start AS period_end_quarter,
       customer_id, revenue
FROM quarterly
UNION ALL
-- rolling 12 months = the quarter and the three before it
SELECT 'Rolling 12 months', DATE_SUB(q.quarter_start, INTERVAL 9 MONTH), q.quarter_start,
       x.customer_id, SUM(x.revenue)
FROM quarters  AS q
JOIN quarterly AS x
  ON x.quarter_start BETWEEN DATE_SUB(q.quarter_start, INTERVAL 9 MONTH) AND q.quarter_start
WHERE q.quarter_start >= DATE '2024-10-01'
GROUP BY q.quarter_start, x.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Concentration measures per period
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.concentration_measures` AS
WITH ranked AS (
    SELECT
        *,
        revenue / SUM(revenue) OVER (PARTITION BY period_type, period_end_quarter)            AS share,
        ROW_NUMBER() OVER (PARTITION BY period_type, period_end_quarter ORDER BY revenue DESC, customer_id) AS rank_desc,
        ROW_NUMBER() OVER (PARTITION BY period_type, period_end_quarter ORDER BY revenue ASC,  customer_id) AS rank_asc
    FROM `sahyadri_b2b.concentration_periods`
)
SELECT
    period_type,
    period_end_quarter,
    COUNT(*)                                                                  AS customers,
    SUM(revenue)                                                              AS revenue,
    MAX(share)                                                                AS top1_share,
    SUM(IF(rank_desc <= 5,  share, 0))                                        AS top5_share,
    SUM(IF(rank_desc <= 10, share, 0))                                        AS top10_share,
    SUM(share * share)                                                        AS hhi,
    1 / SUM(share * share)                                                    AS effective_customers,
    2 * SUM(rank_asc * revenue) / (COUNT(*) * SUM(revenue)) - (COUNT(*) + 1) / COUNT(*) AS gini
FROM ranked
GROUP BY period_type, period_end_quarter;

SELECT
    period_type,
    period_end_quarter,
    customers,
    ROUND(revenue, 0)                         AS revenue,
    ROUND(100 * top1_share, 1)                AS top1_pct,
    ROUND(100 * top5_share, 1)                AS top5_pct,
    ROUND(100 * top10_share, 1)               AS top10_pct,
    ROUND(10000 * hhi, 0)                     AS hhi_points,
    ROUND(effective_customers, 1)             AS effective_customers,
    ROUND(gini, 3)                            AS gini
FROM `sahyadri_b2b.concentration_measures`
ORDER BY period_type, period_end_quarter;

-- -----------------------------------------------------------------------------
-- Step 3 · Who is the largest customer each quarter, and how big is the gap?
-- -----------------------------------------------------------------------------
WITH ranked AS (
    SELECT
        p.period_end_quarter,
        p.customer_id,
        p.revenue,
        p.revenue / SUM(p.revenue) OVER (PARTITION BY p.period_end_quarter)              AS share,
        ROW_NUMBER() OVER (PARTITION BY p.period_end_quarter ORDER BY p.revenue DESC, p.customer_id) AS rn
    FROM `sahyadri_b2b.concentration_periods` AS p
    WHERE p.period_type = 'Quarter'
)
SELECT
    r1.period_end_quarter                     AS quarter_start,
    c.customer_name                           AS largest_customer,
    ROUND(r1.revenue, 0)                      AS largest_revenue,
    ROUND(100 * r1.share, 1)                  AS largest_pct,
    ROUND(100 * r2.share, 1)                  AS second_pct
FROM ranked AS r1
JOIN ranked AS r2 ON r2.period_end_quarter = r1.period_end_quarter AND r2.rn = 2
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = r1.customer_id
WHERE r1.rn = 1
ORDER BY r1.period_end_quarter;

-- -----------------------------------------------------------------------------
-- Step 4 · Is the latest quarter a trend or a one-off? Concentration with and
--          without the single largest order of each quarter
-- -----------------------------------------------------------------------------
WITH order_revenue AS (
    SELECT
        o.order_id,
        o.customer_id,
        DATE_TRUNC(o.order_date, QUARTER)                                          AS quarter_start,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND DATE_TRUNC(o.order_date, QUARTER) <= last_quarter
    GROUP BY o.order_id, o.customer_id, quarter_start
),
without_top AS (
    SELECT * FROM order_revenue
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY quarter_start ORDER BY revenue DESC, order_id) > 1
),
shares AS (
    SELECT quarter_start, customer_id,
           SUM(revenue) / SUM(SUM(revenue)) OVER (PARTITION BY quarter_start) AS share
    FROM without_top
    GROUP BY quarter_start, customer_id
)
SELECT
    s.quarter_start,
    ROUND(10000 * m.hhi, 0)                                AS hhi_points,
    ROUND(10000 * SUM(s.share * s.share), 0)               AS hhi_points_without_largest_order,
    ROUND(1 / SUM(s.share * s.share), 1)                   AS effective_customers_without_largest_order
FROM shares AS s
JOIN `sahyadri_b2b.concentration_measures` AS m
  ON m.period_type = 'Quarter' AND m.period_end_quarter = s.quarter_start
GROUP BY s.quarter_start, m.hhi
ORDER BY s.quarter_start;

-- -----------------------------------------------------------------------------
-- Step 5 · Concentration within each segment (last 12 months)
-- -----------------------------------------------------------------------------
WITH seg AS (
    SELECT
        c.customer_segment,
        p.customer_id,
        p.revenue,
        p.revenue / SUM(p.revenue) OVER (PARTITION BY c.customer_segment) AS share
    FROM `sahyadri_b2b.concentration_periods` AS p
    JOIN `sahyadri_b2b.customers`             AS c ON c.customer_id = p.customer_id
    WHERE p.period_type = 'Rolling 12 months' AND p.period_end_quarter = last_quarter
)
SELECT
    customer_segment,
    COUNT(*)                                   AS customers,
    ROUND(SUM(revenue), 0)                     AS revenue_12m,
    ROUND(100 * MAX(share), 1)                 AS top1_pct_of_segment,
    ROUND(10000 * SUM(share * share), 0)       AS hhi_points,
    ROUND(1 / SUM(share * share), 1)           AS effective_customers
FROM seg
GROUP BY customer_segment
ORDER BY hhi_points DESC;
