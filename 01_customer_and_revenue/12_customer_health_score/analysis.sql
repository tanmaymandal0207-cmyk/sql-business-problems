/* =============================================================================
   Case study · Customer health score
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Account managers want one number per customer that says "this account is
   at risk". Several signals are available: how recently the customer
   ordered, how often, whether spend is rising or falling, how many product
   categories it buys, whether its deliveries were late, whether it pays,
   and whether its orders get cancelled. Before the score goes on the CRM
   dashboard, the commercial head wants proof that it works:
     1. Which signals actually predict that a customer stops buying?
     2. Does a combined score beat the simplest rule (days since last order)?
     3. How many of the customers who later left would the score have
        flagged in advance?
     4. Which current customers score lowest?

   METHOD
     - Snapshots: 31 Mar 2025 and 30 Sep 2025 (back-test, outcome known) and
       30 Sep 2026 (current scoring). At each snapshot, customers with an
       order in the previous 12 months are scored using data up to that date
       only.
     - Outcome (back-test): churned = no order (not Cancelled or Returned) in
       the 12 months after the snapshot.
     - Signals (12 months before the snapshot unless stated):
         recency       days since last order               (lower = healthier)
         frequency     orders                              (higher = healthier)
         trend         share of 12-month revenue earned in the last 6 months
         breadth       product categories bought
         late_share    share of delivered orders that arrived late
         unpaid_share  share of orders delivered 60-365 days before the
                       snapshot not fully paid by the snapshot date
         cancel_share  share of orders Cancelled or Returned
     - Points: each signal's percentile rank within its snapshot (0-100),
       turned so that 100 = healthiest. Health score = average of the seven.
     - AUC (area under the ROC curve), Mann-Whitney form with average ranks
       for ties: the probability that a randomly chosen retained customer
       scores higher than a randomly chosen churned one. 0.5 = no skill.
   ============================================================================= */

DECLARE snapshots       ARRAY<DATE> DEFAULT [DATE '2025-03-31', DATE '2025-09-30', DATE '2026-09-30'];
DECLARE current_snapshot DATE       DEFAULT DATE '2026-09-30';
DECLARE overdue_days    INT64       DEFAULT 60;

-- -----------------------------------------------------------------------------
-- Step 1 · Signals for every customer at every snapshot (point-in-time)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.health_signals` AS
WITH snaps AS (
    SELECT snapshot_date FROM UNNEST(snapshots) AS snapshot_date
),
orders AS (
    SELECT
        o.order_id, o.customer_id, o.order_date, o.order_status, o.promised_delivery_date,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue,
        COUNT(DISTINCT p.category_id)                                              AS categories
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    GROUP BY o.order_id, o.customer_id, o.order_date, o.order_status, o.promised_delivery_date
),
order_categories AS (
    SELECT DISTINCT o.customer_id, o.order_date, p.category_id
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
delivery AS (
    SELECT order_id, IF(COUNT(delivery_date) = COUNT(*), MAX(delivery_date), NULL) AS final_delivery_date
    FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
paid_by_snapshot AS (
    SELECT s.snapshot_date, p.order_id, SUM(p.amount) AS paid
    FROM snaps AS s
    JOIN `sahyadri_b2b.payments` AS p ON p.payment_date <= s.snapshot_date
    GROUP BY s.snapshot_date, p.order_id
),
-- order-level facts per snapshot, using only information dated on or before it
order_snap AS (
    SELECT
        s.snapshot_date,
        o.*,
        d.final_delivery_date,
        o.order_status NOT IN ('Cancelled', 'Returned')                                   AS is_valid,
        -- delivered and measurable by the snapshot
        IF(d.final_delivery_date <= s.snapshot_date AND o.promised_delivery_date IS NOT NULL,
           d.final_delivery_date > o.promised_delivery_date, NULL)                         AS late_flag,
        -- delivered 60-365 days before the snapshot: was it fully paid by then?
        IF(o.order_status = 'Delivered'
           AND d.final_delivery_date <= DATE_SUB(s.snapshot_date, INTERVAL overdue_days DAY)
           AND d.final_delivery_date >  DATE_SUB(s.snapshot_date, INTERVAL 365 DAY),
           IFNULL(pb.paid, 0) < o.revenue - 0.05,
           NULL)                                                                           AS unpaid_flag
    FROM snaps AS s
    JOIN orders AS o
      ON o.order_date <= s.snapshot_date
     AND o.order_date >  DATE_SUB(s.snapshot_date, INTERVAL 365 DAY)
    LEFT JOIN delivery AS d ON d.order_id = o.order_id
    LEFT JOIN paid_by_snapshot AS pb ON pb.snapshot_date = s.snapshot_date AND pb.order_id = o.order_id
),
signals AS (
    SELECT
        snapshot_date,
        customer_id,
        MAX(IF(is_valid, order_date, NULL))                                                AS last_order_date,
        COUNTIF(is_valid)                                                                  AS orders_12m,
        SUM(IF(is_valid, revenue, 0))                                                      AS revenue_12m,
        SAFE_DIVIDE(SUM(IF(is_valid AND order_date > DATE_SUB(snapshot_date, INTERVAL 182 DAY), revenue, 0)),
                    SUM(IF(is_valid, revenue, 0)))                                         AS trend_share,
        AVG(IF(late_flag, 1, IF(late_flag IS NULL, NULL, 0)))                              AS late_share,
        AVG(IF(unpaid_flag, 1, IF(unpaid_flag IS NULL, NULL, 0)))                          AS unpaid_share,
        AVG(IF(is_valid, 0, 1))                                                            AS cancel_share
    FROM order_snap
    GROUP BY snapshot_date, customer_id
    HAVING COUNTIF(is_valid) > 0
),
breadth AS (
    SELECT s.snapshot_date, c.customer_id, COUNT(DISTINCT c.category_id) AS categories_12m
    FROM snaps AS s
    JOIN order_categories AS c
      ON c.order_date <= s.snapshot_date AND c.order_date > DATE_SUB(s.snapshot_date, INTERVAL 365 DAY)
    GROUP BY s.snapshot_date, c.customer_id
),
outcome AS (
    SELECT s.snapshot_date, o.customer_id, COUNTIF(o.order_status NOT IN ('Cancelled', 'Returned')) AS orders_next_12m
    FROM snaps AS s
    JOIN orders AS o
      ON o.order_date > s.snapshot_date AND o.order_date <= DATE_ADD(s.snapshot_date, INTERVAL 365 DAY)
    GROUP BY s.snapshot_date, o.customer_id
)
SELECT
    g.*,
    DATE_DIFF(g.snapshot_date, g.last_order_date, DAY)                                     AS recency_days,
    b.categories_12m,
    s.snapshot_date < current_snapshot                                                     AS is_backtest,
    IF(s.snapshot_date < current_snapshot, IFNULL(o.orders_next_12m, 0) = 0, NULL)         AS churned
FROM signals AS g
JOIN snaps   AS s ON s.snapshot_date = g.snapshot_date
JOIN breadth AS b ON b.snapshot_date = g.snapshot_date AND b.customer_id = g.customer_id
LEFT JOIN outcome AS o ON o.snapshot_date = g.snapshot_date AND o.customer_id = g.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Points per signal and the composite health score
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.health_scores` AS
WITH filled AS (
    -- customers with no measurable deliveries / payments take the snapshot average
    SELECT
        h.*,
        IFNULL(h.late_share,   AVG(h.late_share)   OVER (PARTITION BY h.snapshot_date)) AS late_share_f,
        IFNULL(h.unpaid_share, AVG(h.unpaid_share) OVER (PARTITION BY h.snapshot_date)) AS unpaid_share_f
    FROM `sahyadri_b2b.health_signals` AS h
),
points AS (
    SELECT
        *,
        100 * PERCENT_RANK() OVER (PARTITION BY snapshot_date ORDER BY recency_days DESC)   AS pts_recency,
        100 * PERCENT_RANK() OVER (PARTITION BY snapshot_date ORDER BY orders_12m)          AS pts_frequency,
        100 * PERCENT_RANK() OVER (PARTITION BY snapshot_date ORDER BY trend_share)         AS pts_trend,
        100 * PERCENT_RANK() OVER (PARTITION BY snapshot_date ORDER BY categories_12m)      AS pts_breadth,
        100 * PERCENT_RANK() OVER (PARTITION BY snapshot_date ORDER BY late_share_f DESC)   AS pts_delivery,
        100 * PERCENT_RANK() OVER (PARTITION BY snapshot_date ORDER BY unpaid_share_f DESC) AS pts_payment,
        100 * PERCENT_RANK() OVER (PARTITION BY snapshot_date ORDER BY cancel_share DESC)   AS pts_cancellation
    FROM filled
)
SELECT
    *,
    (pts_recency + pts_frequency + pts_trend + pts_breadth + pts_delivery + pts_payment + pts_cancellation) / 7 AS health_score,
    -- revised score: only the signals that predict in the right direction (Step 3)
    (pts_recency + pts_frequency + pts_breadth) / 3                                                        AS activity_score
FROM points;

-- -----------------------------------------------------------------------------
-- Step 3 · Which signals predict churn? AUC for each signal and the score
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.health_auc` AS
WITH backtest AS (
    SELECT * FROM `sahyadri_b2b.health_scores` WHERE is_backtest
),
long AS (
              SELECT churned, '01. Recency'                      AS signal, pts_recency      AS value FROM backtest
    UNION ALL SELECT churned, '02. Frequency',                               pts_frequency            FROM backtest
    UNION ALL SELECT churned, '03. Trend',                                   pts_trend                FROM backtest
    UNION ALL SELECT churned, '04. Breadth',                                 pts_breadth              FROM backtest
    UNION ALL SELECT churned, '05. Delivery (late share)',                   pts_delivery             FROM backtest
    UNION ALL SELECT churned, '06. Payment (unpaid share)',                  pts_payment              FROM backtest
    UNION ALL SELECT churned, '07. Cancellations',                           pts_cancellation         FROM backtest
    UNION ALL SELECT churned, '08. Health score (all seven)',                health_score             FROM backtest
    UNION ALL SELECT churned, '09. Health score without recency',
                     (pts_frequency + pts_trend + pts_breadth + pts_delivery + pts_payment + pts_cancellation) / 6 FROM backtest
    UNION ALL SELECT churned, '10. Activity score (recency, frequency, breadth)', activity_score  FROM backtest
),
ranked AS (
    -- average rank for ties, pooled over both back-test snapshots
    SELECT
        *,
        RANK() OVER (PARTITION BY signal ORDER BY value)
          + (COUNT(*) OVER (PARTITION BY signal, value) - 1) / 2                           AS avg_rank
    FROM long
)
SELECT
    signal,
    COUNTIF(NOT churned)                                                                  AS retained,
    COUNTIF(churned)                                                                      AS churned,
    -- AUC: probability a retained customer scores higher than a churned one
    (SUM(IF(NOT churned, avg_rank, 0)) - COUNTIF(NOT churned) * (COUNTIF(NOT churned) + 1) / 2)
      / (COUNTIF(NOT churned) * COUNTIF(churned))                                         AS auc
FROM ranked
GROUP BY signal;

SELECT signal, retained, churned, ROUND(auc, 3) AS auc
FROM `sahyadri_b2b.health_auc`
ORDER BY signal;

-- -----------------------------------------------------------------------------
-- Step 4 · How many leavers would the score have flagged? Churn by score band
-- -----------------------------------------------------------------------------
WITH banded AS (
    SELECT
        *,
        NTILE(5) OVER (PARTITION BY snapshot_date ORDER BY health_score, customer_id)       AS score_quintile,
        NTILE(5) OVER (PARTITION BY snapshot_date ORDER BY activity_score, customer_id)     AS activity_quintile,
        NTILE(5) OVER (PARTITION BY snapshot_date ORDER BY recency_days DESC, customer_id)  AS recency_quintile
    FROM `sahyadri_b2b.health_scores`
    WHERE is_backtest
)
SELECT
    'Health score' AS ranking,
    score_quintile                                                                        AS quintile_1_is_worst,
    COUNT(*)                                                                              AS customers,
    COUNTIF(churned)                                                                      AS churned,
    ROUND(100 * AVG(IF(churned, 1, 0)), 1)                                                AS churn_rate_pct,
    ROUND(100 * COUNTIF(churned) / SUM(COUNTIF(churned)) OVER (), 1)                      AS share_of_all_churners_pct,
    ROUND(SUM(revenue_12m) / 1e5, 1)                                                      AS revenue_12m_lakh
FROM banded
GROUP BY score_quintile
UNION ALL
SELECT
    'Recency only',
    recency_quintile,
    COUNT(*),
    COUNTIF(churned),
    ROUND(100 * AVG(IF(churned, 1, 0)), 1),
    ROUND(100 * COUNTIF(churned) / SUM(COUNTIF(churned)) OVER (), 1),
    ROUND(SUM(revenue_12m) / 1e5, 1)
FROM banded
GROUP BY recency_quintile
UNION ALL
SELECT
    'Activity score',
    activity_quintile,
    COUNT(*),
    COUNTIF(churned),
    ROUND(100 * AVG(IF(churned, 1, 0)), 1),
    ROUND(100 * COUNTIF(churned) / SUM(COUNTIF(churned)) OVER (), 1),
    ROUND(SUM(revenue_12m) / 1e5, 1)
FROM banded
GROUP BY activity_quintile
ORDER BY ranking, quintile_1_is_worst;

-- Revenue at stake: churners' prior-year revenue captured by the bottom quintile
WITH banded AS (
    SELECT *,
           NTILE(5) OVER (PARTITION BY snapshot_date ORDER BY health_score, customer_id)   AS score_quintile,
           NTILE(5) OVER (PARTITION BY snapshot_date ORDER BY activity_score, customer_id) AS activity_quintile
    FROM `sahyadri_b2b.health_scores`
    WHERE is_backtest
)
SELECT
    ROUND(SUM(IF(churned, revenue_12m, 0)) / 1e5, 1)                                      AS churners_revenue_lakh,
    ROUND(100 * SUM(IF(churned AND score_quintile = 1, revenue_12m, 0)) / SUM(IF(churned, revenue_12m, 0)), 1)    AS health_bottom_quintile_captures_pct,
    ROUND(100 * SUM(IF(churned AND activity_quintile = 1, revenue_12m, 0)) / SUM(IF(churned, revenue_12m, 0)), 1) AS activity_bottom_quintile_captures_pct
FROM banded;

-- -----------------------------------------------------------------------------
-- Step 5 · Current scores: the lowest-scoring customers with meaningful revenue
-- -----------------------------------------------------------------------------
SELECT
    h.customer_id,
    c.customer_name,
    c.customer_segment,
    ROUND(h.activity_score, 1)                                                            AS activity_score,
    ROUND(h.health_score, 1)                                                              AS health_score,
    h.recency_days,
    h.orders_12m,
    ROUND(h.revenue_12m / 1e5, 1)                                                         AS revenue_12m_lakh,
    ROUND(100 * h.trend_share, 0)                                                         AS pct_of_revenue_in_last_6m,
    h.categories_12m,
    ROUND(100 * h.unpaid_share, 0)                                                        AS unpaid_pct
FROM `sahyadri_b2b.health_scores` AS h
JOIN `sahyadri_b2b.customers`     AS c ON c.customer_id = h.customer_id
WHERE h.snapshot_date = current_snapshot
  AND h.revenue_12m >= 500000
ORDER BY h.activity_score
LIMIT 12;
