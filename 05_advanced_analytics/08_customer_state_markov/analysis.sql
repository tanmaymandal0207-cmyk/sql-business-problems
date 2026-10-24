/* =============================================================================
   Case study · Customer state transitions (Markov chain model)
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script with a
              WHILE loop)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Customers move between states every quarter: big buyers become small
   buyers, small buyers go quiet, quiet customers come back or are lost. The
   CFO wants a simple, explainable model of those movements to answer:
     1. How likely is a customer in each state to move to every other state
        next quarter?
     2. If nothing changes and no new customers are won, how many customers
        will be in each state over the next four quarters, and what revenue
        does the existing base generate?
     3. Is the model accurate? Backtest: fitted only on data to September
        2025, how well does it predict the September 2026 state mix?
     4. Where does the base settle in the long run, and what would a
        win-back programme for silent customers be worth?

   METHOD — first-order Markov chain
     - State of a customer in a quarter (from the quarter of their first
       order onwards):
         1. High            : quarter revenue >= high_value (₹2 lakh)
         2. Low             : quarter revenue > 0 but below ₹2 lakh
         3. Silent 1 quarter: no order this quarter; last order 1 quarter ago
         4. Silent 2 quarters
         5. Silent 3 quarters
         6. Lost            : no order for 4 or more quarters
       Silence is split by duration so that the chain keeps the "memory" it
       needs: the chance of coming back depends on how long a customer has
       been silent, and a single "dormant" state would break the Markov
       assumption (see the README, which compares both designs).
     - Transition probability P(i -> j) = transitions from i to j / all
       transitions from i, over consecutive quarter pairs.
     - Projection: customers in state j next quarter
                 = sum over i of (customers in i now x P(i -> j)),
       repeated quarter by quarter in a WHILE loop.
     - Revenue per customer-quarter for High and Low = average over the last
       four quarters; Dormant and Lost earn nothing.

   KEY RULES
     - Orders not Cancelled or Returned; NULL discount = 0 %.
     - Quarters 2024 Q1 - 2026 Q3. The model has no new-customer inflow:
       it describes the existing base only.
   ============================================================================= */

DECLARE high_value       FLOAT64 DEFAULT 200000;
DECLARE last_quarter     DATE    DEFAULT DATE '2026-07-01';   -- 2026 Q3
DECLARE backtest_quarter DATE    DEFAULT DATE '2025-07-01';   -- 2025 Q3
DECLARE horizon          INT64   DEFAULT 4;
DECLARE long_run         INT64   DEFAULT 40;
DECLARE winback_uplift   FLOAT64 DEFAULT 0.10;    -- scenario: +10 points Dormant -> Low
DECLARE current_step     INT64   DEFAULT 0;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per customer per quarter with revenue and state
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_quarter_state` AS
WITH quarterly AS (
    SELECT
        o.customer_id,
        DATE_TRUNC(o.order_date, QUARTER)                                           AS quarter_start,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND DATE_TRUNC(o.order_date, QUARTER) <= last_quarter
    GROUP BY o.customer_id, quarter_start
),
quarters AS (
    SELECT quarter_start
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2024-01-01', last_quarter, INTERVAL 3 MONTH)) AS quarter_start
),
first_quarter AS (
    SELECT customer_id, MIN(quarter_start) AS first_quarter FROM quarterly GROUP BY customer_id
),
grid AS (
    SELECT f.customer_id, q.quarter_start, IFNULL(x.revenue, 0) AS revenue
    FROM first_quarter AS f
    JOIN quarters      AS q ON q.quarter_start >= f.first_quarter
    LEFT JOIN quarterly AS x ON x.customer_id = f.customer_id AND x.quarter_start = q.quarter_start
)
SELECT
    customer_id,
    quarter_start,
    revenue,
    CASE
        WHEN revenue >= high_value THEN '1. High'
        WHEN revenue > 0           THEN '2. Low'
        WHEN quarters_silent = 1   THEN '3. Silent 1 quarter'
        WHEN quarters_silent = 2   THEN '4. Silent 2 quarters'
        WHEN quarters_silent = 3   THEN '5. Silent 3 quarters'
        ELSE '6. Lost'
    END AS state
FROM (
    SELECT
        *,
        DATE_DIFF(quarter_start,
                  MAX(IF(revenue > 0, quarter_start, NULL))
                      OVER (PARTITION BY customer_id ORDER BY quarter_start
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
                  QUARTER) AS quarters_silent
    FROM grid
);

-- -----------------------------------------------------------------------------
-- Step 2 · Transition matrices: full history, and history to the backtest date
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.state_transitions` AS
WITH pairs AS (
    SELECT
        state                                                                AS from_state,
        LEAD(state) OVER (PARTITION BY customer_id ORDER BY quarter_start)  AS to_state,
        LEAD(quarter_start) OVER (PARTITION BY customer_id ORDER BY quarter_start) AS to_quarter
    FROM `sahyadri_b2b.customer_quarter_state`
),
both_fits AS (
    SELECT 'Full history' AS fit, from_state, to_state FROM pairs WHERE to_state IS NOT NULL
    UNION ALL
    SELECT 'To backtest date', from_state, to_state FROM pairs WHERE to_state IS NOT NULL AND to_quarter <= backtest_quarter
)
SELECT
    fit,
    from_state,
    to_state,
    COUNT(*)                                                         AS transitions,
    COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY fit, from_state)     AS probability
FROM both_fits
GROUP BY fit, from_state, to_state;

-- Scenario matrix: a win-back programme moves 10 more points of silent
-- customers (1-3 quarters) back to Low each quarter, taken from the
-- "stay silent" transition (Silent k -> Silent k+1, or Silent 3 -> Lost)
INSERT INTO `sahyadri_b2b.state_transitions` (fit, from_state, to_state, transitions, probability)
SELECT
    'Win-back scenario',
    from_state,
    to_state,
    transitions,
    probability
      + CASE
            WHEN from_state IN ('3. Silent 1 quarter', '4. Silent 2 quarters', '5. Silent 3 quarters')
             AND to_state = '2. Low'                                                   THEN  winback_uplift
            WHEN (from_state = '3. Silent 1 quarter'  AND to_state = '4. Silent 2 quarters')
              OR (from_state = '4. Silent 2 quarters' AND to_state = '5. Silent 3 quarters')
              OR (from_state = '5. Silent 3 quarters' AND to_state = '6. Lost')         THEN -winback_uplift
            ELSE 0
        END
FROM `sahyadri_b2b.state_transitions`
WHERE fit = 'Full history';

-- The transition matrix (full history), one row per "from" state
SELECT
    from_state,
    SUM(transitions)                                                      AS transitions_from,
    ROUND(100 * SUM(IF(to_state = '1. High', probability, 0)), 1)         AS to_high_pct,
    ROUND(100 * SUM(IF(to_state = '2. Low',  probability, 0)), 1)         AS to_low_pct,
    ROUND(100 * SUM(IF(to_state LIKE '%Silent%', probability, 0)), 1)     AS to_silent_pct,
    ROUND(100 * SUM(IF(to_state = '6. Lost', probability, 0)), 1)         AS to_lost_pct
FROM `sahyadri_b2b.state_transitions`
WHERE fit = 'Full history'
GROUP BY from_state
ORDER BY from_state;

-- -----------------------------------------------------------------------------
-- Step 3 · Projection: apply the matrix quarter by quarter (WHILE loop)
--          run = 'Forecast'  starts at 2026 Q3 with the full-history matrix
--          run = 'Backtest'  starts at 2025 Q3 with the matrix fitted to then
--          run = 'Win-back'  starts at 2026 Q3 with the scenario matrix
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.markov_projection` AS
SELECT 'Forecast' AS run, 0 AS step, state, CAST(COUNT(*) AS FLOAT64) AS customers
FROM `sahyadri_b2b.customer_quarter_state`
WHERE quarter_start = last_quarter
GROUP BY state
UNION ALL
SELECT 'Backtest', 0, state, CAST(COUNT(*) AS FLOAT64)
FROM `sahyadri_b2b.customer_quarter_state`
WHERE quarter_start = backtest_quarter
GROUP BY state
UNION ALL
SELECT 'Win-back', 0, state, CAST(COUNT(*) AS FLOAT64)
FROM `sahyadri_b2b.customer_quarter_state`
WHERE quarter_start = last_quarter
GROUP BY state;

SET current_step = 0;
WHILE current_step < long_run DO
    INSERT INTO `sahyadri_b2b.markov_projection` (run, step, state, customers)
    SELECT
        p.run,
        p.step + 1,
        m.to_state,
        SUM(p.customers * m.probability)
    FROM `sahyadri_b2b.markov_projection` AS p
    JOIN `sahyadri_b2b.state_transitions` AS m
      ON m.from_state = p.state
     AND m.fit = CASE p.run
                     WHEN 'Forecast' THEN 'Full history'
                     WHEN 'Backtest' THEN 'To backtest date'
                     ELSE 'Win-back scenario'
                 END
    WHERE p.step = current_step
      AND (p.run = 'Forecast' OR p.step < horizon)
    GROUP BY p.run, p.step, m.to_state;
    SET current_step = current_step + 1;
END WHILE;

-- Forecast for the next four quarters, with revenue from the existing base
WITH revenue_per_state AS (
    SELECT state, AVG(revenue) AS avg_revenue
    FROM `sahyadri_b2b.customer_quarter_state`
    WHERE quarter_start > DATE_SUB(last_quarter, INTERVAL 12 MONTH)
    GROUP BY state
)
SELECT
    p.step                                                                    AS quarters_ahead,
    ROUND(SUM(IF(p.state = '1. High', p.customers, 0)), 1)                    AS high,
    ROUND(SUM(IF(p.state = '2. Low',  p.customers, 0)), 1)                    AS low,
    ROUND(SUM(IF(p.state LIKE '%Silent%', p.customers, 0)), 1)                AS silent_1_to_3_quarters,
    ROUND(SUM(IF(p.state = '6. Lost', p.customers, 0)), 1)                    AS lost,
    ROUND(SUM(p.customers * r.avg_revenue), 0)                                AS expected_revenue
FROM `sahyadri_b2b.markov_projection` AS p
JOIN revenue_per_state AS r ON r.state = p.state
WHERE p.run = 'Forecast' AND p.step <= horizon
GROUP BY p.step
ORDER BY p.step;

-- -----------------------------------------------------------------------------
-- Step 4 · Backtest: predicted vs actual state mix in 2026 Q3 for the base
--          that existed in 2025 Q3
-- -----------------------------------------------------------------------------
WITH base AS (
    SELECT customer_id FROM `sahyadri_b2b.customer_quarter_state` WHERE quarter_start = backtest_quarter
),
actual AS (
    SELECT s.state, COUNT(*) AS actual_customers
    FROM `sahyadri_b2b.customer_quarter_state` AS s
    JOIN base AS b ON b.customer_id = s.customer_id
    WHERE s.quarter_start = DATE_ADD(backtest_quarter, INTERVAL 12 MONTH)
    GROUP BY s.state
)
SELECT
    p.state,
    ROUND(p.customers, 1)                                         AS predicted_customers,
    a.actual_customers,
    ROUND(p.customers - a.actual_customers, 1)                    AS error,
    ROUND(100 * (p.customers - a.actual_customers) / a.actual_customers, 1) AS error_pct
FROM `sahyadri_b2b.markov_projection` AS p
JOIN actual AS a ON a.state = p.state
WHERE p.run = 'Backtest' AND p.step = horizon
ORDER BY p.state;

-- -----------------------------------------------------------------------------
-- Step 5 · Long run: where the existing base settles, and convergence check
-- -----------------------------------------------------------------------------
SELECT
    p.state,
    ROUND(p.customers, 1)                                                AS customers_after_long_run,
    ROUND(100 * p.customers / SUM(p.customers) OVER (), 1)               AS share_pct,
    ROUND(ABS(p.customers - q.customers), 4)                             AS change_in_last_quarter
FROM `sahyadri_b2b.markov_projection` AS p
JOIN `sahyadri_b2b.markov_projection` AS q
  ON q.run = p.run AND q.state = p.state AND q.step = p.step - 1
WHERE p.run = 'Forecast' AND p.step = long_run
ORDER BY p.state;

-- Value of the win-back scenario: revenue over the next four quarters
WITH revenue_per_state AS (
    SELECT state, AVG(revenue) AS avg_revenue
    FROM `sahyadri_b2b.customer_quarter_state`
    WHERE quarter_start > DATE_SUB(last_quarter, INTERVAL 12 MONTH)
    GROUP BY state
)
SELECT
    p.run,
    ROUND(SUM(p.customers * r.avg_revenue), 0)                                  AS revenue_next_4_quarters,
    ROUND(SUM(IF(p.step = horizon AND p.state IN ('1. High', '2. Low'), p.customers, 0)), 1) AS active_customers_in_4_quarters
FROM `sahyadri_b2b.markov_projection` AS p
JOIN revenue_per_state AS r ON r.state = p.state
WHERE p.run IN ('Forecast', 'Win-back') AND p.step BETWEEN 1 AND horizon
GROUP BY p.run
ORDER BY p.run;
