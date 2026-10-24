/* =============================================================================
   Case study · Time-to-reorder survival analysis
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Sales teams treat a customer as "lost" after an arbitrary silence, often
   90 days. That rule ignores two facts: different segments reorder at very
   different speeds, and a customer who has been quiet for a while may still
   be likely to come back. Simple averages of days-between-orders are also
   biased, because the most recent gap of every customer is still open (we do
   not yet know when, or whether, they will order again).

   Survival analysis handles those open gaps properly. The commercial head
   wants to know:
     1. After an order, how likely is a customer to order again within 30,
        60, 90, 180 and 365 days, by segment?
     2. What is the median time to the next order?
     3. Given that a customer has been silent for X days, how likely are they
        to order within the next 180 days? At what silence should a
        customer be treated as lost?

   METHOD — Kaplan-Meier estimator
     - Each order date of a customer starts a "spell". The spell ends when
       the customer orders again (event) or is still open at the as-of date
       (right-censored, duration = as-of - order date).
     - S(t) = probability of no reorder by day t
            = product over event days u <= t of (1 - d(u) / n(u)),
       where d(u) = spells ending with a reorder on day u and n(u) = spells
       still at risk (duration >= u).
     - Greenwood 95 % interval: Var[S(t)] = S(t)^2 * sum d / (n (n - d)).
     - Conditional probability of reordering within h days after x days of
       silence = 1 - S(x + h) / S(x).

   KEY RULES
     - Orders not Cancelled or Returned, 1 Jan 2024 - 30 Sep 2026; several
       orders by one customer on one day count as one order date.
   ============================================================================= */

DECLARE period_start DATE  DEFAULT DATE '2024-01-01';
DECLARE as_of_date   DATE  DEFAULT DATE '2026-09-30';
DECLARE horizon_days INT64 DEFAULT 180;

-- -----------------------------------------------------------------------------
-- Step 1 · Spells: one row per customer order date, with duration and event flag
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.reorder_spells` AS
WITH order_days AS (
    SELECT DISTINCT o.customer_id, c.customer_segment, o.order_date
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.customers`    AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN period_start AND as_of_date
),
with_next AS (
    SELECT
        *,
        LEAD(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS next_order_date
    FROM order_days
)
SELECT
    customer_id,
    customer_segment,
    order_date                                                       AS spell_start,
    next_order_date,
    next_order_date IS NOT NULL                                      AS reordered,
    DATE_DIFF(IFNULL(next_order_date, as_of_date), order_date, DAY)  AS duration_days
FROM with_next;

-- -----------------------------------------------------------------------------
-- Step 2 · Kaplan-Meier curve for every segment and for all customers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.reorder_survival_curve` AS
WITH spells AS (
    SELECT customer_segment AS curve, duration_days, reordered FROM `sahyadri_b2b.reorder_spells`
    UNION ALL
    SELECT 'All customers', duration_days, reordered FROM `sahyadri_b2b.reorder_spells`
),
by_day AS (
    SELECT
        curve,
        duration_days                    AS t,
        COUNTIF(reordered)               AS events,
        COUNTIF(NOT reordered)           AS censored,
        COUNT(*)                         AS leaving
    FROM spells
    GROUP BY curve, duration_days
),
at_risk AS (
    SELECT
        *,
        -- spells still at risk at day t = all spells with duration >= t
        SUM(leaving) OVER (PARTITION BY curve ORDER BY t DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n_at_risk
    FROM by_day
),
terms AS (
    SELECT
        *,
        IF(events > 0 AND events < n_at_risk, LN(1 - events / n_at_risk), 0)          AS log_term,
        events = n_at_risk AND events > 0                                              AS curve_hits_zero,
        IF(events > 0 AND events < n_at_risk, events / (n_at_risk * (n_at_risk - events)), 0) AS greenwood_term
    FROM at_risk
)
SELECT
    curve,
    t,
    n_at_risk,
    events,
    censored,
    IF(LOGICAL_OR(curve_hits_zero) OVER w, 0,
       EXP(SUM(log_term) OVER w))                                     AS survival,
    SUM(greenwood_term) OVER w                                        AS greenwood_sum
FROM terms
WINDOW w AS (PARTITION BY curve ORDER BY t ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);

-- Helper: S(t) for every day 0-1000 (S stays flat between event days)
CREATE OR REPLACE TABLE `sahyadri_b2b.reorder_survival_daily` AS
WITH days AS (
    SELECT curve, d
    FROM (SELECT DISTINCT curve FROM `sahyadri_b2b.reorder_survival_curve`)
    CROSS JOIN UNNEST(GENERATE_ARRAY(0, 1000)) AS d
)
SELECT
    x.curve,
    x.d                                                                         AS t,
    IFNULL(LAST_VALUE(c.survival IGNORE NULLS)
             OVER (PARTITION BY x.curve ORDER BY x.d), 1)                       AS survival,
    IFNULL(LAST_VALUE(c.greenwood_sum IGNORE NULLS)
             OVER (PARTITION BY x.curve ORDER BY x.d), 0)                       AS greenwood_sum
FROM days AS x
LEFT JOIN `sahyadri_b2b.reorder_survival_curve` AS c
       ON c.curve = x.curve AND c.t = x.d;

-- -----------------------------------------------------------------------------
-- Step 3 · Probability of a reorder within 30 / 60 / 90 / 180 / 365 days,
--          with Greenwood 95 % intervals at 90 days
-- -----------------------------------------------------------------------------
WITH spell_counts AS (
    SELECT customer_segment AS curve, COUNT(*) AS spells FROM `sahyadri_b2b.reorder_spells` GROUP BY customer_segment
    UNION ALL
    SELECT 'All customers', COUNT(*) FROM `sahyadri_b2b.reorder_spells`
)
SELECT
    s.curve,
    ANY_VALUE(k.spells)                                                           AS spells,
    ROUND(100 * (1 - MAX(IF(s.t = 30,  s.survival, NULL))), 1)                    AS reorder_30d_pct,
    ROUND(100 * (1 - MAX(IF(s.t = 60,  s.survival, NULL))), 1)                    AS reorder_60d_pct,
    ROUND(100 * (1 - MAX(IF(s.t = 90,  s.survival, NULL))), 1)                    AS reorder_90d_pct,
    ROUND(100 * (1 - MAX(IF(s.t = 90,  s.survival * (1 + 1.96 * SQRT(s.greenwood_sum)), NULL))), 1) AS reorder_90d_low,
    ROUND(100 * (1 - MAX(IF(s.t = 90,  s.survival * (1 - 1.96 * SQRT(s.greenwood_sum)), NULL))), 1) AS reorder_90d_high,
    ROUND(100 * (1 - MAX(IF(s.t = 180, s.survival, NULL))), 1)                    AS reorder_180d_pct,
    ROUND(100 * (1 - MAX(IF(s.t = 365, s.survival, NULL))), 1)                    AS reorder_365d_pct,
    MIN(IF(s.survival <= 0.5, s.t, NULL))                                         AS median_days_to_reorder
FROM `sahyadri_b2b.reorder_survival_daily` AS s
JOIN spell_counts AS k ON k.curve = s.curve
GROUP BY s.curve
ORDER BY median_days_to_reorder;

-- -----------------------------------------------------------------------------
-- Step 4 · When is a quiet customer really lost?
--          P(reorder within the next 180 days | already silent for x days)
-- -----------------------------------------------------------------------------
WITH checkpoints AS (
    SELECT d FROM UNNEST([30, 60, 90, 180, 270, 365, 540]) AS d
),
spells_by_curve AS (
    SELECT customer_segment AS curve, duration_days FROM `sahyadri_b2b.reorder_spells`
    UNION ALL
    SELECT 'All customers', duration_days FROM `sahyadri_b2b.reorder_spells`
),
risk_at AS (
    -- spells still at risk at x days: below about 30 the estimate is unstable
    SELECT s.curve, c.d, COUNTIF(s.duration_days >= c.d) AS spells_at_risk
    FROM spells_by_curve AS s
    CROSS JOIN checkpoints AS c
    GROUP BY s.curve, c.d
)
SELECT
    a.curve,
    a.t                                                              AS days_silent,
    ROUND(100 * (1 - b.survival / a.survival), 1)                    AS pct_reorder_next_180d,
    ROUND(100 * a.survival, 1)                                       AS pct_of_spells_still_silent,
    r.spells_at_risk
FROM `sahyadri_b2b.reorder_survival_daily` AS a
JOIN `sahyadri_b2b.reorder_survival_daily` AS b
  ON b.curve = a.curve AND b.t = a.t + horizon_days
JOIN risk_at AS r
  ON r.curve = a.curve AND r.d = a.t
WHERE a.survival > 0
ORDER BY a.curve, a.t;

-- -----------------------------------------------------------------------------
-- Step 5 · Why censoring matters: median of completed gaps only vs Kaplan-Meier
-- -----------------------------------------------------------------------------
WITH naive AS (
    SELECT DISTINCT
        customer_segment,
        PERCENTILE_CONT(duration_days, 0.5) OVER (PARTITION BY customer_segment) AS naive_median_completed_only
    FROM `sahyadri_b2b.reorder_spells`
    WHERE reordered
),
open_spells AS (
    SELECT customer_segment, COUNTIF(NOT reordered) AS open_spells,
           ROUND(AVG(IF(NOT reordered, duration_days, NULL)), 0) AS avg_open_spell_days,
           -- naive: treats every open spell as "never reordered"
           ROUND(100 * COUNTIF(reordered AND duration_days <= 365) / COUNT(*), 1) AS naive_reorder_365d_pct
    FROM `sahyadri_b2b.reorder_spells`
    GROUP BY customer_segment
),
km AS (
    SELECT curve,
           MIN(IF(survival <= 0.5, t, NULL))                           AS km_median_days,
           ROUND(100 * (1 - MAX(IF(t = 365, survival, NULL))), 1)      AS km_reorder_365d_pct
    FROM `sahyadri_b2b.reorder_survival_daily`
    GROUP BY curve
)
SELECT
    o.customer_segment,
    o.open_spells,
    o.avg_open_spell_days,
    n.naive_median_completed_only,
    k.km_median_days,
    o.naive_reorder_365d_pct,
    k.km_reorder_365d_pct
FROM open_spells AS o
JOIN naive       AS n ON n.customer_segment = o.customer_segment
JOIN km          AS k ON k.curve            = o.customer_segment
ORDER BY k.km_median_days;
