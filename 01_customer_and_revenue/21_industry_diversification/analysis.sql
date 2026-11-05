/* =============================================================================
   Case study · Industry diversification: which verticals steady revenue and
   which make it swing?
   Category : Customer and revenue
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The board wants steadier monthly revenue for the working-capital plan.
   One director argues that the company is too dependent on Industrial
   Distribution and should "diversify into more industries"; another says
   the industries all move together anyway, so diversification would not
   help. The commercial director asks:
     1. Do the industries' monthly revenues move together, or do their
        swings cancel out?
     2. How much of the monthly swing does each industry contribute,
        against its share of revenue?
     3. What makes an industry volatile?
     4. Which industries should growth come from if steadiness matters?

   METHOD
     - Valid orders (not Cancelled or Returned), monthly revenue by customer
       industry, January 2024 - September 2026 (33 months). Customers with
       no industry are kept as "Unknown".
     - Each industry's swing = its monthly revenue minus its own straight-
       line trend (least squares). Company swing = the sum of the industry
       swings.
     - Risk contribution: Cov(industry swing, company swing) / Var(company
       swing). Contributions add up to 100 %.
     - Diversification: the sum of the industries' standard deviations
       against the company's. Independence test: 500 shuffles that move
       each industry's swings to random months (keeping each industry's
       own volatility) - if the industries are independent, the company
       swing should look like the shuffled ones.
     - Views with and without the March months (the year-end peak that
       every industry joins).
   ============================================================================= */

DECLARE shuffles INT64 DEFAULT 500;
DECLARE prime    INT64 DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Monthly revenue by industry and the swing around each trend
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.id_months` AS
WITH months AS (
    SELECT m, ROW_NUMBER() OVER (ORDER BY m) AS t
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2024-01-01', DATE '2026-09-01', INTERVAL 1 MONTH)) AS m
),
industries AS (
    SELECT DISTINCT IFNULL(industry, 'Unknown') AS industry FROM `sahyadri_b2b.customers`
),
revenue AS (
    SELECT IFNULL(c.industry, 'Unknown') AS industry, DATE_TRUNC(o.order_date, MONTH) AS m,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY industry, m
),
grid AS (
    SELECT n.industry, mo.m, mo.t, IFNULL(r.revenue, 0) AS revenue
    FROM industries AS n CROSS JOIN months AS mo
    LEFT JOIN revenue AS r ON r.industry = n.industry AND r.m = mo.m
),
trend AS (
    SELECT industry,
           COVAR_POP(t, revenue) / VAR_POP(t)                                         AS slope,
           AVG(revenue) - COVAR_POP(t, revenue) / VAR_POP(t) * AVG(t)                 AS intercept
    FROM grid GROUP BY industry
)
SELECT g.*, tr.intercept + tr.slope * g.t AS trend_revenue,
       g.revenue - (tr.intercept + tr.slope * g.t)                                    AS swing,
       EXTRACT(MONTH FROM g.m) = 3                                                    AS is_march,
       DENSE_RANK() OVER (ORDER BY g.industry)                                        AS industry_no
FROM grid AS g JOIN trend AS tr USING (industry);

-- -----------------------------------------------------------------------------
-- Step 2 · Do the industries move together?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.id_company` AS
SELECT m, t, is_march, SUM(revenue) AS revenue, SUM(swing) AS swing
FROM `sahyadri_b2b.id_months`
GROUP BY m, t, is_march;

-- Shuffles: each industry's swings moved to random months, then added up
CREATE OR REPLACE TABLE `sahyadri_b2b.id_shuffles` AS
WITH ranked AS (
    SELECT d.industry, d.t, d.swing, d.is_march, b,
           ROW_NUMBER() OVER (PARTITION BY b, d.industry, d.is_march
                              ORDER BY MOD(MOD(b * 7919 + d.t * 104729 + d.industry_no * 1299709, prime)
                                         * MOD(b * 7919 + d.t * 104729 + d.industry_no * 1299709, prime) + 12345, prime)) AS new_slot
    FROM `sahyadri_b2b.id_months` AS d
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, shuffles)) AS b
),
company AS (
    SELECT b, is_march, new_slot, SUM(swing) AS swing FROM ranked GROUP BY b, is_march, new_slot
)
SELECT b,
       STDDEV_POP(swing)                                                              AS sd_all_months,
       STDDEV_POP(IF(NOT is_march, swing, NULL))                                      AS sd_without_march
FROM company GROUP BY b;

WITH industry_sd AS (
    SELECT industry, STDDEV_POP(swing) AS sd, STDDEV_POP(IF(NOT is_march, swing, NULL)) AS sd_nm
    FROM `sahyadri_b2b.id_months` GROUP BY industry
),
observed AS (
    SELECT STDDEV_POP(swing) AS sd, STDDEV_POP(IF(NOT is_march, swing, NULL)) AS sd_nm, AVG(revenue) AS avg_revenue
    FROM `sahyadri_b2b.id_company`
)
SELECT
    ROUND(o.avg_revenue / 1e5, 1)                                                     AS avg_monthly_revenue_lakh,
    ROUND((SELECT SUM(sd) FROM industry_sd) / 1e5, 1)                                 AS sum_of_industry_sd_lakh,
    ROUND(o.sd / 1e5, 1)                                                              AS company_sd_lakh,
    ROUND((SELECT SUM(sd) FROM industry_sd) / o.sd, 2)                                AS diversification_ratio,
    ROUND(AVG(s.sd_all_months) / 1e5, 1)                                              AS company_sd_if_independent_lakh,
    ROUND(AVG(IF(s.sd_all_months >= o.sd, 1, 0)), 3)                                  AS share_of_shuffles_as_volatile,
    ROUND(o.sd_nm / 1e5, 1)                                                           AS company_sd_without_march_lakh,
    ROUND(AVG(s.sd_without_march) / 1e5, 1)                                           AS sd_without_march_if_independent_lakh,
    ROUND(AVG(IF(s.sd_without_march >= o.sd_nm, 1, 0)), 3)                            AS share_of_shuffles_as_volatile_without_march
FROM observed AS o
CROSS JOIN `sahyadri_b2b.id_shuffles` AS s
GROUP BY o.avg_revenue, o.sd, o.sd_nm;

-- Average correlation between industries' swings (all pairs), with and without March
WITH pairs AS (
    SELECT a.industry AS i1, b.industry AS i2,
           CORR(a.swing, b.swing)                                                     AS r_all,
           CORR(IF(a.is_march, NULL, a.swing), IF(b.is_march, NULL, b.swing))         AS r_without_march
    FROM `sahyadri_b2b.id_months` AS a
    JOIN `sahyadri_b2b.id_months` AS b ON b.t = a.t AND a.industry < b.industry
    GROUP BY a.industry, b.industry
)
SELECT COUNT(*) AS industry_pairs,
       ROUND(AVG(r_all), 3)                                                           AS avg_correlation,
       ROUND(AVG(r_without_march), 3)                                                 AS avg_correlation_without_march,
       COUNTIF(r_all > 0.5)                                                           AS pairs_above_0_5
FROM pairs;

-- -----------------------------------------------------------------------------
-- Step 3 · Each industry's share of revenue and of the swing
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.id_contribution` AS
WITH joined AS (
    SELECT d.industry, d.revenue, d.swing, c.swing AS company_swing, d.is_march
    FROM `sahyadri_b2b.id_months` AS d JOIN `sahyadri_b2b.id_company` AS c USING (t)
),
company_var AS (
    SELECT VAR_POP(swing) AS v, VAR_POP(IF(NOT is_march, swing, NULL)) AS v_nm FROM `sahyadri_b2b.id_company`
)
SELECT
    j.industry,
    SUM(j.revenue) / (SELECT SUM(revenue) FROM `sahyadri_b2b.id_company`)            AS revenue_share,
    COVAR_POP(j.swing, j.company_swing) / ANY_VALUE(cv.v)                             AS risk_share,
    COVAR_POP(IF(j.is_march, NULL, j.swing), IF(j.is_march, NULL, j.company_swing)) / ANY_VALUE(cv.v_nm) AS risk_share_without_march,
    STDDEV_POP(j.swing) / AVG(j.revenue)                                              AS swing_cv,
    CORR(j.swing, j.company_swing - j.swing)                                          AS corr_with_rest
FROM joined AS j CROSS JOIN company_var AS cv
GROUP BY j.industry;

WITH top_customer AS (
    SELECT IFNULL(c.industry, 'Unknown') AS industry, c.customer_id,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY industry, c.customer_id
),
concentration AS (
    SELECT industry, COUNT(*) AS customers, MAX(revenue) / SUM(revenue) AS top_customer_share
    FROM top_customer GROUP BY industry
)
SELECT
    k.industry,
    n.customers,
    ROUND(100 * k.revenue_share, 1)                                                   AS revenue_share_pct,
    ROUND(100 * k.risk_share, 1)                                                      AS risk_share_pct,
    ROUND(k.risk_share / k.revenue_share, 2)                                          AS risk_per_revenue,
    ROUND(100 * k.risk_share_without_march, 1)                                        AS risk_share_without_march_pct,
    ROUND(k.swing_cv, 2)                                                              AS swing_cv,
    ROUND(k.corr_with_rest, 2)                                                        AS corr_with_rest_of_company,
    ROUND(100 * n.top_customer_share, 1)                                              AS top_customer_share_pct
FROM `sahyadri_b2b.id_contribution` AS k
JOIN concentration AS n USING (industry)
ORDER BY k.risk_share DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · What makes an industry volatile, and a growth test
-- -----------------------------------------------------------------------------
WITH concentration AS (
    SELECT industry, MAX(revenue) / SUM(revenue) AS top_share, COUNT(*) AS customers
    FROM (
        SELECT IFNULL(c.industry, 'Unknown') AS industry, c.customer_id,
               SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
        FROM `sahyadri_b2b.sales_orders` AS o
        JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
        JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
        WHERE o.order_status NOT IN ('Cancelled', 'Returned')
        GROUP BY industry, c.customer_id
    )
    GROUP BY industry
)
SELECT
    ROUND(CORR(k.swing_cv, n.top_share), 2)                                           AS corr_volatility_vs_top_customer_share,
    ROUND(CORR(k.swing_cv, n.customers), 2)                                           AS corr_volatility_vs_customer_count,
    ROUND(CORR(k.swing_cv, k.revenue_share), 2)                                       AS corr_volatility_vs_size
FROM `sahyadri_b2b.id_contribution` AS k
JOIN concentration AS n USING (industry);

-- If the next Rs 1 crore of yearly revenue came from one industry with its current pattern,
-- how would the company's monthly swing change? (scales that industry's revenue and swing)
WITH base AS (
    SELECT SUM(revenue) / 33 * 12 AS yearly FROM `sahyadri_b2b.id_company`
),
scenarios AS (
    SELECT k.industry, 1e7 / (k.revenue_share * b.yearly) AS growth_factor
    FROM `sahyadri_b2b.id_contribution` AS k CROSS JOIN base AS b
),
scaled AS (
    SELECT s.industry AS grown, d.t,
           SUM(IF(d.industry = s.industry, d.swing * (1 + s.growth_factor), d.swing)) AS swing,
           SUM(IF(d.industry = s.industry, d.revenue * (1 + s.growth_factor), d.revenue)) AS revenue
    FROM scenarios AS s CROSS JOIN `sahyadri_b2b.id_months` AS d
    GROUP BY s.industry, d.t
)
SELECT
    grown                                                                             AS industry_that_grows,
    ROUND(100 * STDDEV_POP(swing) / AVG(revenue), 2)                                  AS company_swing_cv_pct,
    ROUND(100 * (STDDEV_POP(swing) / AVG(revenue)
                 - (SELECT STDDEV_POP(swing) / AVG(revenue) FROM `sahyadri_b2b.id_company`)), 2) AS change_vs_today_pts
FROM scaled
GROUP BY grown
ORDER BY company_swing_cv_pct;
