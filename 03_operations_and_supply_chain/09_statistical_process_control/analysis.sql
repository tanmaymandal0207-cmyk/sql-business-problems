/* =============================================================================
   Case study · Statistical process control for delivery and cancellations
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Every Monday the operations review discusses last week's late-delivery
   and cancellation rates. Managers react to every rise: a bad week triggers
   an investigation, a good week is praised. Most of those movements are
   normal week-to-week noise. Statistical process control (SPC) separates
   noise ("common cause") from real changes ("special cause"), so that the
   team investigates only weeks that are genuinely unusual:
     1. What range of weekly late-delivery and cancellation rates is normal?
     2. Which weeks were genuinely out of control, and on which rule?
     3. Has either process shifted since the baseline period?
     4. How many weekly "alarms" would a simple target-based rule have raised
        that SPC shows to be noise?

   METHOD — p-charts with Western Electric rules
     For each week t with n(t) orders and x(t) events (late or cancelled):
       p(t)       = x(t) / n(t)
       centre p   = total events / total orders over the baseline period
       sigma(t)   = SQRT(p (1 - p) / n(t))       (limits widen in small weeks)
       UCL / LCL  = p +/- 3 sigma(t)             (LCL floored at 0)
     Phase I (baseline): weeks starting 1 Jan 2024 - 30 Jun 2025 set p.
     Phase II (monitoring): weeks from 7 Jul 2025 are judged against it.
     Rules (each on its own row in the signals table):
       R1  one point beyond 3 sigma
       R2  2 of 3 consecutive points beyond 2 sigma on the same side
       R4  8 consecutive points on the same side of the centre line (shift)

   KEY RULES
     - Weeks are ISO weeks (Monday start) of the order date.
     - Late rate: Delivered orders with a promised and a final delivery date.
       Weeks after 31 Aug 2026 are excluded because many of their orders are
       not yet delivered.
     - Cancellation rate: closed orders (Delivered, Cancelled, Returned).
     - Naive rule for comparison: any week above the long-run average by more
       than 3 percentage points is treated as an alarm.
   ============================================================================= */

DECLARE first_week     DATE    DEFAULT DATE '2024-01-01';
DECLARE baseline_end   DATE    DEFAULT DATE '2025-06-30';
DECLARE last_week_late DATE    DEFAULT DATE '2026-08-31';
DECLARE last_week_all  DATE    DEFAULT DATE '2026-09-21';
DECLARE naive_margin   FLOAT64 DEFAULT 0.03;

-- -----------------------------------------------------------------------------
-- Step 1 · Weekly counts for both processes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.spc_weekly` AS
WITH final_delivery AS (
    SELECT order_id, MAX(delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
late AS (
    SELECT
        'Late delivery'                                         AS process,
        DATE_TRUNC(o.order_date, ISOWEEK)                       AS week_start,
        COUNT(*)                                                AS n,
        COUNTIF(f.final_delivery_date > o.promised_delivery_date) AS x
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN final_delivery              AS f ON f.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
      AND o.promised_delivery_date IS NOT NULL
      AND f.final_delivery_date IS NOT NULL
      AND DATE_TRUNC(o.order_date, ISOWEEK) BETWEEN first_week AND last_week_late
    GROUP BY week_start
),
cancel AS (
    SELECT
        'Cancellation'                                          AS process,
        DATE_TRUNC(order_date, ISOWEEK)                         AS week_start,
        COUNT(*)                                                AS n,
        COUNTIF(order_status = 'Cancelled')                     AS x
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status IN ('Delivered', 'Cancelled', 'Returned')
      AND DATE_TRUNC(order_date, ISOWEEK) BETWEEN first_week AND last_week_all
    GROUP BY week_start
)
SELECT *, IF(week_start <= baseline_end, 'Baseline', 'Monitoring') AS phase FROM late
UNION ALL
SELECT *, IF(week_start <= baseline_end, 'Baseline', 'Monitoring') FROM cancel;

-- -----------------------------------------------------------------------------
-- Step 2 · Control limits and zone positions for every week
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.spc_chart` AS
WITH centre AS (
    SELECT process, SUM(x) / SUM(n) AS p_bar
    FROM `sahyadri_b2b.spc_weekly`
    WHERE phase = 'Baseline'
    GROUP BY process
),
overall AS (
    SELECT process, SUM(x) / SUM(n) AS p_all
    FROM `sahyadri_b2b.spc_weekly`
    GROUP BY process
)
SELECT
    w.process,
    w.week_start,
    w.phase,
    w.n,
    w.x,
    w.x / w.n                                                      AS p,
    c.p_bar,
    SQRT(c.p_bar * (1 - c.p_bar) / w.n)                            AS sigma,
    c.p_bar + 3 * SQRT(c.p_bar * (1 - c.p_bar) / w.n)              AS ucl,
    GREATEST(c.p_bar - 3 * SQRT(c.p_bar * (1 - c.p_bar) / w.n), 0) AS lcl,
    (w.x / w.n - c.p_bar) / SQRT(c.p_bar * (1 - c.p_bar) / w.n)    AS z,
    w.x / w.n > o.p_all + naive_margin                             AS naive_alarm
FROM `sahyadri_b2b.spc_weekly` AS w
JOIN centre                     AS c ON c.process = w.process
JOIN overall                    AS o ON o.process = w.process;

-- -----------------------------------------------------------------------------
-- Step 3 · Western Electric rule signals
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.spc_signals` AS
WITH flagged AS (
    SELECT
        *,
        SIGN(z)                                                                         AS side,
        -- R2: count of the last 3 points beyond 2 sigma on each side
        COUNTIF(z >  2) OVER (PARTITION BY process ORDER BY week_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS high_2s_in_3,
        COUNTIF(z < -2) OVER (PARTITION BY process ORDER BY week_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS low_2s_in_3,
        -- R4: points above / below the centre among the last 8
        COUNTIF(z > 0)  OVER (PARTITION BY process ORDER BY week_start ROWS BETWEEN 7 PRECEDING AND CURRENT ROW) AS above_in_8,
        COUNTIF(z < 0)  OVER (PARTITION BY process ORDER BY week_start ROWS BETWEEN 7 PRECEDING AND CURRENT ROW) AS below_in_8,
        COUNT(*)        OVER (PARTITION BY process ORDER BY week_start ROWS BETWEEN 7 PRECEDING AND CURRENT ROW) AS points_in_8
    FROM `sahyadri_b2b.spc_chart`
)
SELECT process, week_start, phase, n, x, p, p_bar, z, 'R1 beyond 3 sigma' AS rule,
       IF(z > 0, 'High', 'Low') AS direction
FROM flagged WHERE ABS(z) > 3
UNION ALL
SELECT process, week_start, phase, n, x, p, p_bar, z, 'R2 2 of 3 beyond 2 sigma',
       IF(high_2s_in_3 >= 2, 'High', 'Low')
FROM flagged WHERE (high_2s_in_3 >= 2 AND z > 2) OR (low_2s_in_3 >= 2 AND z < -2)
UNION ALL
SELECT process, week_start, phase, n, x, p, p_bar, z, 'R4 8 on one side',
       IF(above_in_8 = 8, 'High', 'Low')
FROM flagged WHERE points_in_8 = 8 AND (above_in_8 = 8 OR below_in_8 = 8);

-- Summary: normal range and signals by process and phase
WITH signal_weeks AS (
    SELECT process, phase, COUNT(DISTINCT week_start) AS spc_signal_weeks
    FROM `sahyadri_b2b.spc_signals`
    GROUP BY process, phase
),
typical_week AS (
    -- control limits for a week of median size, the "normal range" quoted in reviews
    SELECT DISTINCT process, phase,
           PERCENTILE_CONT(n, 0.5) OVER (PARTITION BY process, phase) AS median_orders
    FROM `sahyadri_b2b.spc_chart`
)
SELECT
    c.process,
    c.phase,
    COUNT(*)                                                         AS weeks,
    ROUND(100 * ANY_VALUE(c.p_bar), 2)                               AS centre_line_pct,
    ROUND(100 * SUM(c.x) / SUM(c.n), 2)                              AS actual_rate_pct,
    ROUND(100 * MIN(c.lcl), 1)                                       AS lowest_lcl_pct,
    ROUND(100 * MAX(c.ucl), 1)                                       AS highest_ucl_pct,
    ANY_VALUE(t.median_orders)                                       AS median_orders_per_week,
    ROUND(100 * GREATEST(ANY_VALUE(c.p_bar) - 3 * SQRT(ANY_VALUE(c.p_bar) * (1 - ANY_VALUE(c.p_bar)) / ANY_VALUE(t.median_orders)), 0), 1) AS typical_lcl_pct,
    ROUND(100 * (ANY_VALUE(c.p_bar) + 3 * SQRT(ANY_VALUE(c.p_bar) * (1 - ANY_VALUE(c.p_bar)) / ANY_VALUE(t.median_orders))), 1)           AS typical_ucl_pct,
    COUNTIF(c.naive_alarm)                                           AS naive_alarms,
    IFNULL(ANY_VALUE(g.spc_signal_weeks), 0)                         AS spc_signal_weeks
FROM `sahyadri_b2b.spc_chart` AS c
JOIN typical_week            AS t ON t.process = c.process AND t.phase = c.phase
LEFT JOIN signal_weeks       AS g ON g.process = c.process AND g.phase = c.phase
GROUP BY c.process, c.phase
ORDER BY c.process, c.phase;

-- -----------------------------------------------------------------------------
-- Step 4 · The signal weeks
-- -----------------------------------------------------------------------------
SELECT
    process,
    week_start,
    phase,
    rule,
    direction,
    n                                  AS orders,
    x                                  AS events,
    ROUND(100 * p, 1)                  AS rate_pct,
    ROUND(100 * p_bar, 1)              AS centre_pct,
    ROUND(z, 2)                        AS z
FROM `sahyadri_b2b.spc_signals`
ORDER BY process, week_start, rule;

-- -----------------------------------------------------------------------------
-- Step 5 · Has the process shifted? Monitoring vs baseline (two-proportion z)
-- -----------------------------------------------------------------------------
WITH t AS (
    SELECT
        process,
        SUM(IF(phase = 'Baseline',   x, 0)) AS x1, SUM(IF(phase = 'Baseline',   n, 0)) AS n1,
        SUM(IF(phase = 'Monitoring', x, 0)) AS x2, SUM(IF(phase = 'Monitoring', n, 0)) AS n2
    FROM `sahyadri_b2b.spc_weekly`
    GROUP BY process
)
SELECT
    process,
    ROUND(100 * x1 / n1, 2)                                                       AS baseline_rate_pct,
    ROUND(100 * x2 / n2, 2)                                                       AS monitoring_rate_pct,
    ROUND((x2 / n2 - x1 / n1)
          / SQRT((x1 + x2) / (n1 + n2) * (1 - (x1 + x2) / (n1 + n2)) * (1 / n1 + 1 / n2)), 2) AS z_score
FROM t
ORDER BY process;
