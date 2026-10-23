/* =============================================================================
   Case study · Replenishment reorder reminders
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Many customers rebuy the same consumables (bearings, fasteners, gloves,
   seals) on a rough cycle. If a customer's usual reorder date passes without
   an order, they may have bought from a competitor. The inside-sales team
   wants a weekly reminder list: "these customers usually buy this product
   about now". Before building it, the sales head wants to know:
     1. How many customer-product pairs buy on a regular cycle?
     2. Which pairs are due or overdue today, and what are they worth?
     3. Would the reminders have worked? Backtest: of the pairs the method
        said were due, how many actually reordered, compared with pairs that
        were not due?

   KEY RULES
     - Purchase event: a customer buying a product on an order date (orders
       not Cancelled or Returned). Several lines of the same product on the
       same day count as one event.
     - Gap: days between consecutive events for the same customer-product.
     - Cycle statistics use events up to the evaluation date only:
         median gap, coefficient of variation (CV = stddev / mean of gaps),
         last purchase date, typical event value (median).
     - Regularity (pairs with at least min_events events):
         Regular CV < 0.5 · Semi-regular 0.5-1.0 · Irregular >= 1.0
       Fewer events: "Insufficient history".
     - Status at the evaluation date, by days since the last purchase
       relative to the median gap:
         Not yet due < 0.8x · Due now 0.8-1.5x · Overdue 1.5-3x · Lapsed > 3x
     - Backtest: evaluate at 31 Mar 2026; a pair is "predicted due" if its
       expected next date (last purchase + median gap) falls on or before the
       end of the next 90 days and it is not already lapsed. Check who
       actually bought in those 90 days.
   ============================================================================= */

DECLARE as_of_date     DATE  DEFAULT DATE '2026-09-30';
DECLARE backtest_date  DATE  DEFAULT DATE '2026-03-31';
DECLARE horizon_days   INT64 DEFAULT 90;
DECLARE min_events     INT64 DEFAULT 4;

-- -----------------------------------------------------------------------------
-- Step 1 · Purchase events with the gap since the previous event
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_product_purchases` AS
WITH events AS (
    SELECT
        o.customer_id,
        i.product_id,
        o.order_date                                                                   AS purchase_date,
        SUM(i.quantity)                                                                AS quantity,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))     AS value
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date <= as_of_date
    GROUP BY o.customer_id, i.product_id, o.order_date
)
SELECT
    *,
    DATE_DIFF(purchase_date,
              LAG(purchase_date) OVER (PARTITION BY customer_id, product_id ORDER BY purchase_date),
              DAY)                                                                     AS gap_days
FROM events;

-- -----------------------------------------------------------------------------
-- Step 2 · Cycle statistics and reorder status as of 30 Sep 2026
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.reorder_status` AS
WITH medians AS (
    SELECT DISTINCT
        customer_id,
        product_id,
        PERCENTILE_CONT(gap_days, 0.5) OVER (PARTITION BY customer_id, product_id) AS median_gap,
        PERCENTILE_CONT(value,    0.5) OVER (PARTITION BY customer_id, product_id) AS typical_value
    FROM `sahyadri_b2b.customer_product_purchases`
),
stats AS (
    SELECT
        customer_id,
        product_id,
        COUNT(*)                                   AS events,
        MAX(purchase_date)                         AS last_purchase,
        SAFE_DIVIDE(STDDEV_SAMP(gap_days), AVG(gap_days)) AS gap_cv
    FROM `sahyadri_b2b.customer_product_purchases`
    GROUP BY customer_id, product_id
)
SELECT
    s.customer_id,
    s.product_id,
    s.events,
    s.last_purchase,
    m.median_gap,
    ROUND(s.gap_cv, 3)                                                  AS gap_cv,
    ROUND(m.typical_value, 2)                                           AS typical_value,
    DATE_DIFF(as_of_date, s.last_purchase, DAY)                         AS days_since_last,
    ROUND(SAFE_DIVIDE(DATE_DIFF(as_of_date, s.last_purchase, DAY), m.median_gap), 2) AS cycle_ratio,
    CASE
        WHEN s.events < min_events OR m.median_gap IS NULL OR m.median_gap = 0 THEN 'Insufficient history'
        WHEN s.gap_cv < 0.5 THEN 'Regular'
        WHEN s.gap_cv < 1.0 THEN 'Semi-regular'
        ELSE 'Irregular'
    END                                                                 AS regularity,
    CASE
        WHEN s.events < min_events OR m.median_gap IS NULL OR m.median_gap = 0 THEN NULL
        WHEN DATE_DIFF(as_of_date, s.last_purchase, DAY) < 0.8 * m.median_gap THEN '1. Not yet due'
        WHEN DATE_DIFF(as_of_date, s.last_purchase, DAY) <= 1.5 * m.median_gap THEN '2. Due now'
        WHEN DATE_DIFF(as_of_date, s.last_purchase, DAY) <= 3.0 * m.median_gap THEN '3. Overdue'
        ELSE '4. Lapsed'
    END                                                                 AS reorder_status
FROM stats        AS s
JOIN medians      AS m ON m.customer_id = s.customer_id AND m.product_id = s.product_id;

-- How many pairs buy on a cycle?
SELECT
    regularity,
    COUNT(*)                                                         AS pairs,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                 AS pct_of_pairs,
    ROUND(AVG(median_gap), 0)                                        AS avg_median_gap_days,
    SUM(events)                                                      AS purchase_events
FROM `sahyadri_b2b.reorder_status`
GROUP BY regularity
ORDER BY CASE regularity WHEN 'Regular' THEN 1 WHEN 'Semi-regular' THEN 2 WHEN 'Irregular' THEN 3 ELSE 4 END;

-- Status today for the pairs worth reminding (regular and semi-regular)
SELECT
    regularity,
    reorder_status,
    COUNT(*)                                     AS pairs,
    COUNT(DISTINCT customer_id)                  AS customers,
    ROUND(SUM(typical_value), 2)                 AS value_of_one_reorder
FROM `sahyadri_b2b.reorder_status`
WHERE regularity IN ('Regular', 'Semi-regular')
GROUP BY regularity, reorder_status
ORDER BY regularity, reorder_status;

-- -----------------------------------------------------------------------------
-- Step 3 · Backtest at 31 Mar 2026: did "due" pairs actually reorder?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.reorder_backtest` AS
WITH history AS (
    SELECT * FROM `sahyadri_b2b.customer_product_purchases` WHERE purchase_date <= backtest_date
),
medians AS (
    SELECT DISTINCT
        customer_id,
        product_id,
        PERCENTILE_CONT(gap_days, 0.5) OVER (PARTITION BY customer_id, product_id) AS median_gap
    FROM history
),
stats AS (
    SELECT
        customer_id, product_id,
        COUNT(*)                                          AS events,
        MAX(purchase_date)                                AS last_purchase,
        SAFE_DIVIDE(STDDEV_SAMP(gap_days), AVG(gap_days)) AS gap_cv
    FROM history
    GROUP BY customer_id, product_id
),
actual AS (
    SELECT DISTINCT customer_id, product_id
    FROM `sahyadri_b2b.customer_product_purchases`
    WHERE purchase_date >  backtest_date
      AND purchase_date <= DATE_ADD(backtest_date, INTERVAL horizon_days DAY)
)
SELECT
    s.customer_id,
    s.product_id,
    s.last_purchase,
    m.median_gap,
    CASE WHEN s.gap_cv < 0.5 THEN 'Regular' WHEN s.gap_cv < 1.0 THEN 'Semi-regular' ELSE 'Irregular' END AS regularity,
    DATE_ADD(s.last_purchase, INTERVAL CAST(ROUND(m.median_gap) AS INT64) DAY)  AS expected_next,
    -- due within the horizon, and not already lapsed (more than 3 cycles overdue)
    DATE_ADD(s.last_purchase, INTERVAL CAST(ROUND(m.median_gap) AS INT64) DAY)
        <= DATE_ADD(backtest_date, INTERVAL horizon_days DAY)
    AND DATE_DIFF(backtest_date, s.last_purchase, DAY) <= 3 * m.median_gap      AS predicted_due,
    a.customer_id IS NOT NULL                                                    AS actually_reordered
FROM stats        AS s
JOIN medians      AS m ON m.customer_id = s.customer_id AND m.product_id = s.product_id
LEFT JOIN actual  AS a ON a.customer_id = s.customer_id AND a.product_id = s.product_id
WHERE s.events >= min_events AND m.median_gap > 0;

SELECT
    regularity,
    COUNTIF(predicted_due)                                                         AS predicted_due,
    COUNTIF(predicted_due AND actually_reordered)                                  AS due_and_reordered,
    ROUND(100 * COUNTIF(predicted_due AND actually_reordered) / NULLIF(COUNTIF(predicted_due), 0), 1)         AS reorder_rate_if_due_pct,
    ROUND(100 * COUNTIF(NOT predicted_due AND actually_reordered) / NULLIF(COUNTIF(NOT predicted_due), 0), 1) AS reorder_rate_if_not_due_pct,
    ROUND(SAFE_DIVIDE(COUNTIF(predicted_due AND actually_reordered) / NULLIF(COUNTIF(predicted_due), 0),
                      COUNTIF(NOT predicted_due AND actually_reordered) / NULLIF(COUNTIF(NOT predicted_due), 0)), 2) AS lift,
    ROUND(100 * COUNTIF(predicted_due AND actually_reordered) / NULLIF(COUNTIF(actually_reordered), 0), 1)    AS pct_of_reorders_anticipated
FROM `sahyadri_b2b.reorder_backtest`
GROUP BY regularity
ORDER BY CASE regularity WHEN 'Regular' THEN 1 WHEN 'Semi-regular' THEN 2 ELSE 3 END;

-- -----------------------------------------------------------------------------
-- Step 4 · Reminder list: overdue regular and semi-regular pairs by value
-- -----------------------------------------------------------------------------
SELECT
    r.customer_id,
    c.customer_name,
    r.product_id,
    p.product_name,
    r.regularity,
    r.events,
    r.median_gap                    AS usual_gap_days,
    r.last_purchase,
    r.days_since_last,
    r.typical_value
FROM `sahyadri_b2b.reorder_status` AS r
JOIN `sahyadri_b2b.customers`      AS c ON c.customer_id = r.customer_id
JOIN `sahyadri_b2b.products`       AS p ON p.product_id  = r.product_id
WHERE r.regularity IN ('Regular', 'Semi-regular')
  AND r.reorder_status = '3. Overdue'
ORDER BY r.typical_value DESC
LIMIT 15;

-- Customers with the most overdue reorders (a call list)
SELECT
    r.customer_id,
    c.customer_name,
    c.customer_segment,
    COUNT(*)                          AS overdue_products,
    ROUND(SUM(r.typical_value), 2)    AS value_of_one_reorder_each
FROM `sahyadri_b2b.reorder_status` AS r
JOIN `sahyadri_b2b.customers`      AS c ON c.customer_id = r.customer_id
WHERE r.regularity IN ('Regular', 'Semi-regular')
  AND r.reorder_status = '3. Overdue'
GROUP BY r.customer_id, c.customer_name, c.customer_segment
ORDER BY value_of_one_reorder_each DESC
LIMIT 10;
