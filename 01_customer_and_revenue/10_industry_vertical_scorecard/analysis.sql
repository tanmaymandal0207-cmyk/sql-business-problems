/* =============================================================================
   Case study · Industry vertical scorecard
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Sales coverage and marketing are organised by region and segment, but
   customers buy for very different reasons in different industries. The
   commercial head is planning next year's industry focus (trade shows,
   application engineers, industry price lists) and wants a scorecard of
   every industry the company sells to:
     1. How big is each industry, and how fast is it growing?
     2. Is the growth broad, or does it rest on one customer?
     3. Which industries earn better margins, and is that the industry
        itself or simply its customer-segment mix?
     4. Which industries keep their customers and pay quickly?
     5. Where should the company invest, reprice, harvest or review?

   KEY RULES
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Periods: Current = 1 Oct 2025 - 30 Sep 2026; Prior = 1 Oct 2024 -
       30 Sep 2025 (like-for-like 12 months).
     - Industry from the customer master; NULL shown as 'Not recorded'.
     - Gross margin: revenue - quantity x unit_cost, on lines with a known
       cost; margin % = margin / revenue of those lines.
     - Mix-expected margin: each industry's revenue by segment x the
       company-wide margin % of that segment. Margin gap = actual - expected.
     - Retention: share of Prior-period customers who bought in Current.
     - Payment speed: median days from final delivery to last payment,
       Paid and Delivered orders delivered in the Current period.
     - Portfolio quadrants for industries with Rs 1 crore or more in Current:
       growth and margin each compared with the company figure.
   ============================================================================= */

DECLARE current_start DATE    DEFAULT DATE '2025-10-01';
DECLARE prior_start   DATE    DEFAULT DATE '2024-10-01';
DECLARE as_of         DATE    DEFAULT DATE '2026-09-30';
DECLARE min_revenue   FLOAT64 DEFAULT 10000000;

-- -----------------------------------------------------------------------------
-- Step 1 · Customer revenue and margin per period, tagged with industry
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.industry_customer_period` AS
WITH lines AS (
    SELECT
        o.order_id,
        o.customer_id,
        IF(o.order_date >= current_start, 'Current', 'Prior')                      AS period,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)      AS revenue,
        IF(p.unit_cost IS NULL, NULL,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) - i.quantity * p.unit_cost) AS margin
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date >= prior_start
      AND o.order_date <= as_of
)
SELECT
    l.customer_id,
    IFNULL(c.industry, 'Not recorded')                    AS industry,
    c.customer_segment,
    l.period,
    COUNT(DISTINCT l.order_id)                            AS orders,
    SUM(l.revenue)                                        AS revenue,
    SUM(IF(l.margin IS NOT NULL, l.revenue, 0))           AS costed_revenue,
    SUM(l.margin)                                         AS margin
FROM lines AS l
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = l.customer_id
GROUP BY l.customer_id, industry, c.customer_segment, l.period;

-- -----------------------------------------------------------------------------
-- Step 2 · Industry scorecard
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.industry_scorecard` AS
WITH segment_margin AS (
    SELECT customer_segment, SUM(margin) / SUM(costed_revenue) AS segment_margin_pct
    FROM `sahyadri_b2b.industry_customer_period`
    WHERE period = 'Current'
    GROUP BY customer_segment
),
customer_change AS (
    SELECT
        customer_id,
        ANY_VALUE(industry)                                         AS industry,
        SUM(IF(period = 'Current', revenue, 0))                     AS revenue_current,
        SUM(IF(period = 'Prior', revenue, 0))                       AS revenue_prior
    FROM `sahyadri_b2b.industry_customer_period`
    GROUP BY customer_id
),
largest_grower AS (
    SELECT industry, customer_id AS top_grower_id,
           revenue_current - revenue_prior AS top_grower_increase
    FROM customer_change
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY industry ORDER BY revenue_current - revenue_prior DESC, customer_id) = 1
),
largest_customer AS (
    SELECT industry, MAX(revenue_current) AS largest_customer_revenue
    FROM customer_change
    GROUP BY industry
),
registered AS (
    SELECT IFNULL(industry, 'Not recorded') AS industry, COUNT(*) AS registered_customers
    FROM `sahyadri_b2b.customers`
    GROUP BY industry
),
payment_speed AS (
    SELECT
        IFNULL(c.industry, 'Not recorded')                          AS industry,
        APPROX_QUANTILES(DATE_DIFF(p.paid_date, d.final_delivery_date, DAY), 2)[OFFSET(1)] AS median_days_delivery_to_paid,
        COUNT(*)                                                    AS paid_orders
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN (SELECT order_id, MAX(delivery_date) AS final_delivery_date
          FROM `sahyadri_b2b.shipments` GROUP BY order_id
          HAVING COUNT(delivery_date) = COUNT(*))                   AS d ON d.order_id = o.order_id
    JOIN (SELECT order_id, MAX(payment_date) AS paid_date
          FROM `sahyadri_b2b.payments` GROUP BY order_id)          AS p ON p.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'Delivered' AND o.payment_status = 'Paid'
      AND d.final_delivery_date >= current_start AND d.final_delivery_date <= as_of
    GROUP BY industry
),
industry_period AS (
    SELECT
        k.industry,
        COUNT(DISTINCT IF(k.period = 'Current', k.customer_id, NULL))               AS active_customers,
        COUNT(DISTINCT IF(k.period = 'Prior', k.customer_id, NULL))                 AS prior_customers,
        SUM(IF(k.period = 'Current', k.revenue, 0))                                 AS revenue_current,
        SUM(IF(k.period = 'Prior', k.revenue, 0))                                   AS revenue_prior,
        SUM(IF(k.period = 'Current', k.orders, 0))                                  AS orders_current,
        SUM(IF(k.period = 'Current', k.margin, 0))                                  AS margin_current,
        SUM(IF(k.period = 'Current', k.costed_revenue, 0))                          AS costed_revenue_current,
        SUM(IF(k.period = 'Current', k.costed_revenue * s.segment_margin_pct, 0))   AS expected_margin_current
    FROM `sahyadri_b2b.industry_customer_period` AS k
    JOIN segment_margin AS s ON s.customer_segment = k.customer_segment
    GROUP BY k.industry
),
retained AS (
    SELECT industry,
           COUNTIF(revenue_prior > 0 AND revenue_current > 0)                       AS retained_customers
    FROM customer_change
    GROUP BY industry
)
SELECT
    p.industry,
    g.registered_customers,
    p.active_customers,
    p.revenue_current,
    p.revenue_prior,
    SAFE_DIVIDE(p.revenue_current, p.revenue_prior) - 1                             AS growth_pct,
    SAFE_DIVIDE(p.revenue_current - lg.top_grower_increase,
                p.revenue_prior) - 1                                               AS growth_pct_without_top_grower,
    lg.top_grower_id,
    lg.top_grower_increase,
    lc.largest_customer_revenue / p.revenue_current                                 AS largest_customer_share,
    p.margin_current / p.costed_revenue_current                                     AS margin_pct,
    p.expected_margin_current / p.costed_revenue_current                            AS mix_expected_margin_pct,
    (p.margin_current - p.expected_margin_current) / p.costed_revenue_current       AS margin_gap_pct,
    SAFE_DIVIDE(r.retained_customers, p.prior_customers)                            AS retention_pct,
    p.prior_customers,
    p.revenue_current / p.orders_current                                            AS avg_order_value,
    ps.median_days_delivery_to_paid,
    ps.paid_orders
FROM industry_period AS p
JOIN registered       AS g  ON g.industry  = p.industry
JOIN largest_grower   AS lg ON lg.industry = p.industry
JOIN largest_customer AS lc ON lc.industry = p.industry
JOIN retained         AS r  ON r.industry  = p.industry
LEFT JOIN payment_speed AS ps ON ps.industry = p.industry;

SELECT
    industry,
    registered_customers,
    active_customers,
    ROUND(revenue_current / 1e5, 1)                       AS revenue_lakh,
    ROUND(100 * revenue_current / SUM(revenue_current) OVER (), 1) AS revenue_share_pct,
    ROUND(100 * growth_pct, 1)                            AS growth_pct,
    ROUND(100 * growth_pct_without_top_grower, 1)         AS growth_without_top_grower_pct,
    ROUND(100 * largest_customer_share, 1)                AS largest_customer_pct,
    ROUND(100 * margin_pct, 1)                            AS margin_pct,
    ROUND(100 * margin_gap_pct, 1)                        AS margin_vs_mix_pts,
    ROUND(100 * retention_pct, 1)                         AS retention_pct,
    ROUND(avg_order_value, 0)                             AS avg_order_value,
    median_days_delivery_to_paid
FROM `sahyadri_b2b.industry_scorecard`
ORDER BY revenue_current DESC;

-- Company reference values
SELECT
    ROUND(100 * (SUM(IF(period = 'Current', revenue, 0)) / SUM(IF(period = 'Prior', revenue, 0)) - 1), 1) AS company_growth_pct,
    ROUND(100 * SUM(IF(period = 'Current', margin, 0)) / SUM(IF(period = 'Current', costed_revenue, 0)), 1) AS company_margin_pct
FROM `sahyadri_b2b.industry_customer_period`;

-- -----------------------------------------------------------------------------
-- Step 3 · Is margin the industry or the segment mix?
-- -----------------------------------------------------------------------------
SELECT
    k.industry,
    ROUND(100 * SUM(IF(k.customer_segment = 'Distributor', k.revenue, 0)) / SUM(k.revenue), 1) AS distributor_pct,
    ROUND(100 * SUM(IF(k.customer_segment = 'Enterprise',  k.revenue, 0)) / SUM(k.revenue), 1) AS enterprise_pct,
    ROUND(100 * SUM(IF(k.customer_segment = 'Mid-Market',  k.revenue, 0)) / SUM(k.revenue), 1) AS mid_market_pct,
    ROUND(100 * SUM(IF(k.customer_segment = 'SMB',         k.revenue, 0)) / SUM(k.revenue), 1) AS smb_pct,
    ROUND(100 * ANY_VALUE(s.margin_pct), 1)                                 AS margin_pct,
    ROUND(100 * ANY_VALUE(s.mix_expected_margin_pct), 1)                    AS mix_expected_margin_pct,
    ROUND(100 * ANY_VALUE(s.margin_gap_pct), 1)                             AS margin_vs_mix_pts
FROM `sahyadri_b2b.industry_customer_period` AS k
JOIN `sahyadri_b2b.industry_scorecard`       AS s ON s.industry = k.industry
WHERE k.period = 'Current'
GROUP BY k.industry
ORDER BY margin_vs_mix_pts DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Portfolio: invest, reprice, harvest or review
-- -----------------------------------------------------------------------------
WITH company AS (
    SELECT
        SUM(IF(period = 'Current', revenue, 0)) / SUM(IF(period = 'Prior', revenue, 0)) - 1   AS growth_pct,
        SUM(IF(period = 'Current', margin, 0)) / SUM(IF(period = 'Current', costed_revenue, 0)) AS margin_pct
    FROM `sahyadri_b2b.industry_customer_period`
)
SELECT
    s.industry,
    ROUND(s.revenue_current / 1e5, 1)                                       AS revenue_lakh,
    ROUND(100 * s.growth_pct, 1)                                            AS growth_pct,
    ROUND(100 * s.growth_pct_without_top_grower, 1)                         AS growth_without_top_grower_pct,
    ROUND(100 * s.margin_pct, 1)                                            AS margin_pct,
    CASE
        WHEN s.growth_pct >= c.growth_pct AND s.margin_pct >= c.margin_pct THEN '1. Invest'
        WHEN s.growth_pct >= c.growth_pct                                                    THEN '2. Grow but reprice'
        WHEN s.margin_pct >= c.margin_pct                                   THEN '3. Harvest'
        ELSE '4. Review' END                                                AS quadrant,
    IF(s.growth_pct >= c.growth_pct AND s.growth_pct_without_top_grower < c.growth_pct,
       'Growth rests on one customer', NULL)                               AS caution
FROM `sahyadri_b2b.industry_scorecard` AS s
CROSS JOIN company AS c
WHERE s.revenue_current >= min_revenue
ORDER BY quadrant, s.revenue_current DESC;

-- Who drove each industry's growth?
SELECT
    s.industry,
    c.customer_name                                                         AS top_grower,
    ROUND(s.top_grower_increase / 1e5, 1)                                   AS top_grower_increase_lakh,
    ROUND((s.revenue_current - s.revenue_prior) / 1e5, 1)                   AS industry_increase_lakh,
    ROUND(100 * SAFE_DIVIDE(s.top_grower_increase, s.revenue_current - s.revenue_prior), 1) AS top_grower_share_of_increase_pct
FROM `sahyadri_b2b.industry_scorecard` AS s
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = s.top_grower_id
WHERE s.revenue_current >= min_revenue
ORDER BY top_grower_share_of_increase_pct DESC;
