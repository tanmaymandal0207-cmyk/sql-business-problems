/* =============================================================================
   Case study · Time to cash with Kaplan-Meier: counting the orders not yet paid
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The payment behaviour study measured days to pay on fully paid orders
   only, and set payment terms from those figures. The credit controller
   points out that the slowest payers are the ones missing: an order still
   unpaid today never enters a "days to pay" average. Before the terms go
   into the new contracts she asks:
     1. How long does it really take to collect cash once unpaid orders are
        counted for the time they have been waiting?
     2. How much do paid-only figures understate it, by segment and for
        recent deliveries?
     3. What share of orders is still not settled 30, 60, 90 and 180
        days after delivery?
     4. Are the proposed terms realistic?

   METHOD
     - Valid orders (not Cancelled or Returned) with every shipment
       delivered, final delivery 1 Jan 2024 - 30 Sep 2026.
     - Clock starts at final delivery. Event = the day cumulative payments
       first reach 99 % of the order value (short payments of under 1 %
       count as settled). Paid before delivery = day 0.
     - Censored: orders not yet settled on 30 Sep 2026, observed for the
       days since delivery.
     - Kaplan-Meier: S(t) = product over event days u <= t of
       (1 - paid on day u / still waiting at the start of day u).
       Median = first day with S(t) <= 0.5. Greenwood standard errors.
       Restricted mean = area under S(t) up to 365 days (the average days
       to cash within the first year). A curve is not read beyond the
       longest time any of its orders has been followed.
     - Naive = the same orders, fully paid ones only (the payment
       behaviour study's method).
   ============================================================================= */

DECLARE as_of           DATE    DEFAULT DATE '2026-09-30';
DECLARE first_delivery  DATE    DEFAULT DATE '2024-01-01';
DECLARE settled_share   FLOAT64 DEFAULT 0.99;
DECLARE horizon         INT64   DEFAULT 365;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per delivered order: time to cash or time waiting so far
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.tc_orders` AS
WITH value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id
),
delivered AS (
    SELECT order_id, MAX(delivery_date) AS delivered_on
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
    HAVING COUNT(delivery_date) = COUNT(*)
),
running AS (
    SELECT order_id, payment_date,
           SUM(amount) OVER (PARTITION BY order_id ORDER BY payment_date, payment_id) AS paid_so_far
    FROM `sahyadri_b2b.payments`
    WHERE payment_date <= as_of
),
base AS (
    SELECT o.order_id, o.customer_id, c.customer_segment, o.payment_status, v.order_value, d.delivered_on
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN value AS v ON v.order_id = o.order_id
    JOIN delivered AS d ON d.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND d.delivered_on BETWEEN first_delivery AND as_of
),
settled AS (
    SELECT b.order_id, MIN(r.payment_date) AS settled_on
    FROM base AS b JOIN running AS r ON r.order_id = b.order_id
    WHERE r.paid_so_far >= settled_share * b.order_value
    GROUP BY b.order_id
)
SELECT
    b.*,
    s.settled_on,
    s.settled_on IS NOT NULL                                                          AS settled,
    IF(s.settled_on IS NOT NULL,
       GREATEST(DATE_DIFF(s.settled_on, b.delivered_on, DAY), 0),
       DATE_DIFF(as_of, b.delivered_on, DAY))                                         AS days,
    CONCAT(CAST(EXTRACT(YEAR FROM b.delivered_on) AS STRING), IF(EXTRACT(MONTH FROM b.delivered_on) <= 6, ' H1', ' H2')) AS cohort
FROM base AS b
LEFT JOIN settled AS s ON s.order_id = b.order_id;

SELECT
    COUNT(*)                                                                          AS orders,
    COUNTIF(settled)                                                                  AS settled,
    COUNTIF(NOT settled)                                                              AS not_yet_settled,
    COUNTIF(NOT settled AND days > 180)                                               AS unsettled_over_180_days,
    ROUND(SUM(IF(NOT settled, order_value, 0)) / 1e5, 1)                              AS unsettled_value_lakh,
    COUNTIF(settled AND payment_status != 'Paid')                                     AS settled_but_status_not_paid,
    COUNTIF(NOT settled AND payment_status = 'Paid')                                  AS status_paid_but_short
FROM `sahyadri_b2b.tc_orders`;

-- -----------------------------------------------------------------------------
-- Step 2 · Kaplan-Meier curves by group (company, segment, delivery half-year)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.tc_curves` AS
WITH grouped AS (
    SELECT 'Company' AS dimension, 'All' AS grp, days, settled FROM `sahyadri_b2b.tc_orders`
    UNION ALL
    SELECT 'Segment', customer_segment, days, settled FROM `sahyadri_b2b.tc_orders`
    UNION ALL
    SELECT 'Delivery half-year', cohort, days, settled FROM `sahyadri_b2b.tc_orders`
),
by_day AS (
    SELECT dimension, grp, days AS t, COUNTIF(settled) AS events, COUNT(*) AS leaving
    FROM grouped GROUP BY dimension, grp, days
),
risk AS (
    SELECT *,
           SUM(leaving) OVER (PARTITION BY dimension, grp ORDER BY t DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS at_risk
    FROM by_day
),
steps AS (
    SELECT *,
           -- 1 - d / n is never 0 here unless every order still waiting is paid that day
           SUM(IF(events = at_risk, -1e6, LN(1 - events / at_risk)))
             OVER (PARTITION BY dimension, grp ORDER BY t ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS log_s,
           SUM(IF(events < at_risk, events / (at_risk * (at_risk - events)), 0))
             OVER (PARTITION BY dimension, grp ORDER BY t ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS greenwood_sum
    FROM risk
)
SELECT dimension, grp, t, events, leaving, at_risk,
       EXP(log_s)                                                                     AS survival,
       EXP(log_s) * SQRT(greenwood_sum)                                               AS survival_se,
       LEAD(t) OVER (PARTITION BY dimension, grp ORDER BY t)                          AS next_t
FROM steps;

-- -----------------------------------------------------------------------------
-- Step 3 · Kaplan-Meier against paid-only figures
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.tc_summary` AS
WITH checkpoints AS (
    SELECT 30 AS x UNION ALL SELECT 60 UNION ALL SELECT 90 UNION ALL SELECT 180
),
-- S at day x = S after the last day with a change on or before x (1 if none)
s_at AS (
    SELECT dimension, grp, x, survival, survival_se
    FROM (
        SELECT c.dimension, c.grp, k.x, c.survival, c.survival_se,
               ROW_NUMBER() OVER (PARTITION BY c.dimension, c.grp, k.x ORDER BY c.t DESC) AS rk
        FROM `sahyadri_b2b.tc_curves` AS c JOIN checkpoints AS k ON c.t <= k.x
    )
    WHERE rk = 1
),
km AS (
    SELECT dimension, grp,
           MAX(t)                                                                     AS longest_follow_up,
           MIN(IF(survival <= 0.5, t, NULL))                                          AS km_median,
           -- restricted mean to the horizon: S = 1 before the first day, then the area under each step
           LEAST(MIN(t), horizon)
             + SUM(survival * (LEAST(IFNULL(next_t, horizon), horizon) - LEAST(t, horizon))) AS km_restricted_mean
    FROM `sahyadri_b2b.tc_curves`
    GROUP BY dimension, grp
),
naive AS (
    SELECT 'Company' AS dimension, 'All' AS grp, days, settled FROM `sahyadri_b2b.tc_orders`
    UNION ALL SELECT 'Segment', customer_segment, days, settled FROM `sahyadri_b2b.tc_orders`
    UNION ALL SELECT 'Delivery half-year', cohort, days, settled FROM `sahyadri_b2b.tc_orders`
),
naive_stats AS (
    SELECT dimension, grp, COUNT(*) AS orders, COUNTIF(NOT settled) AS censored,
           APPROX_QUANTILES(IF(settled, days, NULL), 100)[OFFSET(50)]                AS naive_median,
           AVG(IF(settled, days, NULL))                                              AS naive_mean
    FROM naive GROUP BY dimension, grp
)
SELECT
    n.dimension, n.grp, n.orders, n.censored, n.naive_median, n.naive_mean, k.km_median, k.longest_follow_up,
    -- a curve says nothing beyond the longest time any of its orders has been followed
    IF(k.longest_follow_up >= horizon, k.km_restricted_mean, NULL)                    AS km_restricted_mean,
    IF(k.longest_follow_up >= 30,  IFNULL(MAX(IF(s.x = 30,  s.survival, NULL)), 1), NULL) AS s30,
    IF(k.longest_follow_up >= 60,  IFNULL(MAX(IF(s.x = 60,  s.survival, NULL)), 1), NULL) AS s60,
    IF(k.longest_follow_up >= 90,  IFNULL(MAX(IF(s.x = 90,  s.survival, NULL)), 1), NULL) AS s90,
    IF(k.longest_follow_up >= 180, IFNULL(MAX(IF(s.x = 180, s.survival, NULL)), 1), NULL) AS s180,
    MAX(IF(s.x = 90, s.survival_se, NULL))                                            AS s90_se
FROM naive_stats AS n
JOIN km AS k ON k.dimension = n.dimension AND k.grp = n.grp
LEFT JOIN s_at AS s ON s.dimension = n.dimension AND s.grp = n.grp
GROUP BY n.dimension, n.grp, n.orders, n.censored, n.naive_median, n.naive_mean, k.km_median, k.longest_follow_up, k.km_restricted_mean;

SELECT
    dimension, grp, orders, censored, longest_follow_up,
    naive_median                                                                      AS paid_only_median_days,
    km_median                                                                         AS km_median_days,
    ROUND(naive_mean, 1)                                                              AS paid_only_mean_days,
    ROUND(km_restricted_mean, 1)                                                      AS km_mean_days_within_year,
    ROUND(100 * s30, 1)                                                               AS still_unpaid_30d_pct,
    ROUND(100 * s60, 1)                                                               AS still_unpaid_60d_pct,
    ROUND(100 * s90, 1)                                                               AS still_unpaid_90d_pct,
    ROUND(100 * 1.96 * s90_se, 1)                                                     AS ci95_halfwidth_90d_pts,
    ROUND(100 * s180, 1)                                                              AS still_unpaid_180d_pct
FROM `sahyadri_b2b.tc_summary`
ORDER BY CASE dimension WHEN 'Company' THEN 1 WHEN 'Segment' THEN 2 ELSE 3 END, grp;

-- -----------------------------------------------------------------------------
-- Step 4 · Are the proposed terms realistic?
-- -----------------------------------------------------------------------------
-- Terms proposed by the payment behaviour study; share of orders still unpaid at the term
WITH terms AS (
    SELECT 'Enterprise' AS grp, 60 AS term_days UNION ALL SELECT 'Distributor', 30
    UNION ALL SELECT 'Mid-Market', 45 UNION ALL SELECT 'SMB', 15
),
at_term AS (
    SELECT tm.grp, tm.term_days, c.survival,
           ROW_NUMBER() OVER (PARTITION BY tm.grp ORDER BY c.t DESC) AS rk
    FROM terms AS tm
    JOIN `sahyadri_b2b.tc_curves` AS c ON c.dimension = 'Segment' AND c.grp = tm.grp AND c.t <= tm.term_days
),
paid_only AS (
    SELECT o.customer_segment AS grp, tm.term_days,
           COUNTIF(o.days > tm.term_days) / COUNT(*) AS beyond_paid_only
    FROM `sahyadri_b2b.tc_orders` AS o JOIN terms AS tm ON tm.grp = o.customer_segment
    WHERE o.settled
    GROUP BY o.customer_segment, tm.term_days
)
SELECT
    a.grp                                                                             AS segment,
    a.term_days,
    ROUND(100 * p.beyond_paid_only, 1)                                                AS beyond_term_paid_only_pct,
    ROUND(100 * a.survival, 1)                                                        AS beyond_term_km_pct
FROM at_term AS a
JOIN paid_only AS p ON p.grp = a.grp
WHERE a.rk = 1
ORDER BY a.term_days DESC;
