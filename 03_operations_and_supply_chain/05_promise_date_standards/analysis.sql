/* =============================================================================
   Case study · City-wise delivery promise standards
   Category : Operations and supply chain
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b
   Depends  : sahyadri_b2b.delivery_performance, created by
              03_operations_and_supply_chain/01_late_delivery_root_cause/analysis.sql

   BUSINESS PROBLEM
   Salespeople choose delivery promise dates by judgement. The late delivery
   study showed promises do not account for destination: a salesperson
   serving distant cities promises the same as one serving nearby cities. The
   operations and sales heads want a standard promise table by city:
     1. How long do deliveries actually take to each city?
     2. If promises had followed a city standard, what on-time rate would
        that give, and would promises be longer or shorter than today?
     3. Which service level (80 %, 85 % or 90 % of orders on time) gives the
        best balance between on-time delivery and a competitive promise?

   METHOD — out-of-sample test
     - Standards are set from 2024-2025 deliveries ("training" period).
     - They are tested on January-September 2026 deliveries the standards
       have never seen ("test" period), and compared with what actually
       happened in 2026.
     - City standard at service level s = actual lead time (days from order
       to final delivery) that s of the city's training orders met, rounded
       up to whole days. Cities with fewer than `min_city_orders` training
       orders use the company-wide standard.
   ============================================================================= */

DECLARE train_end       DATE  DEFAULT DATE '2025-12-31';
DECLARE min_city_orders INT64 DEFAULT 20;

-- -----------------------------------------------------------------------------
-- Step 1 · City standards from the training period (80 %, 85 %, 90 % levels)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.city_promise_standards` AS
WITH training AS (
    SELECT * FROM `sahyadri_b2b.delivery_performance`
    WHERE order_date <= train_end
),
city_levels AS (
    SELECT DISTINCT
        delivery_city,
        COUNT(*) OVER (PARTITION BY delivery_city)                                        AS training_orders,
        CEIL(PERCENTILE_DISC(actual_lead_days, 0.50) OVER (PARTITION BY delivery_city))   AS lead_p50,
        CEIL(PERCENTILE_DISC(actual_lead_days, 0.80) OVER (PARTITION BY delivery_city))   AS standard_p80,
        CEIL(PERCENTILE_DISC(actual_lead_days, 0.85) OVER (PARTITION BY delivery_city))   AS standard_p85,
        CEIL(PERCENTILE_DISC(actual_lead_days, 0.90) OVER (PARTITION BY delivery_city))   AS standard_p90
    FROM training
),
company_levels AS (
    SELECT DISTINCT
        CEIL(PERCENTILE_DISC(actual_lead_days, 0.50) OVER ()) AS lead_p50,
        CEIL(PERCENTILE_DISC(actual_lead_days, 0.80) OVER ()) AS standard_p80,
        CEIL(PERCENTILE_DISC(actual_lead_days, 0.85) OVER ()) AS standard_p85,
        CEIL(PERCENTILE_DISC(actual_lead_days, 0.90) OVER ()) AS standard_p90
    FROM training
)
SELECT
    c.delivery_city,
    c.training_orders,
    c.training_orders >= min_city_orders                                  AS uses_city_standard,
    IF(c.training_orders >= min_city_orders, c.lead_p50,     k.lead_p50)     AS lead_p50,
    IF(c.training_orders >= min_city_orders, c.standard_p80, k.standard_p80) AS standard_p80,
    IF(c.training_orders >= min_city_orders, c.standard_p85, k.standard_p85) AS standard_p85,
    IF(c.training_orders >= min_city_orders, c.standard_p90, k.standard_p90) AS standard_p90
FROM city_levels         AS c
CROSS JOIN company_levels AS k;

-- -----------------------------------------------------------------------------
-- Step 2 · Out-of-sample test on 2026 orders: standards vs what actually happened
-- -----------------------------------------------------------------------------
WITH test AS (
    SELECT t.*, s.standard_p80, s.standard_p85, s.standard_p90
    FROM `sahyadri_b2b.delivery_performance` AS t
    JOIN `sahyadri_b2b.city_promise_standards` AS s
        ON s.delivery_city = t.delivery_city
    WHERE t.order_date > train_end
)
SELECT 'Actual 2026 promises' AS promise_rule,
       COUNT(*) AS orders,
       ROUND(100 * COUNTIF(NOT is_late) / COUNT(*), 1)                      AS on_time_pct,
       ROUND(AVG(promised_lead_days), 1)                                    AS avg_promise_days
FROM test
UNION ALL
SELECT 'City standard at 80 %', COUNT(*),
       ROUND(100 * COUNTIF(actual_lead_days <= standard_p80) / COUNT(*), 1),
       ROUND(AVG(standard_p80), 1)
FROM test
UNION ALL
SELECT 'City standard at 85 %', COUNT(*),
       ROUND(100 * COUNTIF(actual_lead_days <= standard_p85) / COUNT(*), 1),
       ROUND(AVG(standard_p85), 1)
FROM test
UNION ALL
SELECT 'City standard at 90 %', COUNT(*),
       ROUND(100 * COUNTIF(actual_lead_days <= standard_p90) / COUNT(*), 1),
       ROUND(AVG(standard_p90), 1)
FROM test
ORDER BY avg_promise_days;

-- -----------------------------------------------------------------------------
-- Step 3 · Promise table by city (85 % standard) vs current practice in 2026
-- -----------------------------------------------------------------------------
SELECT
    s.delivery_city,
    s.training_orders,
    s.uses_city_standard,
    s.lead_p50                                                   AS typical_lead_days,
    s.standard_p85                                               AS recommended_promise_days,
    COUNT(t.order_id)                                            AS orders_2026,
    ROUND(AVG(t.promised_lead_days), 1)                          AS current_avg_promise_days,
    ROUND(100 * COUNTIF(NOT t.is_late) / NULLIF(COUNT(t.order_id), 0), 1) AS current_on_time_pct,
    ROUND(AVG(t.promised_lead_days) - s.standard_p85, 1)          AS promise_gap_days
FROM `sahyadri_b2b.city_promise_standards`  AS s
LEFT JOIN `sahyadri_b2b.delivery_performance` AS t
    ON  t.delivery_city = s.delivery_city
    AND t.order_date > train_end
GROUP BY s.delivery_city, s.training_orders, s.uses_city_standard, s.lead_p50, s.standard_p85
ORDER BY recommended_promise_days DESC, s.delivery_city;

-- -----------------------------------------------------------------------------
-- Step 4 · Where current promises are furthest from the standard (2026)
--          negative gap = promising faster than the city standard (lateness risk)
--          positive gap = promising slower than needed (less competitive)
-- -----------------------------------------------------------------------------
WITH city_gap AS (
    SELECT
        s.delivery_city,
        s.standard_p85,
        COUNT(*)                                        AS orders_2026,
        AVG(t.promised_lead_days)                       AS current_avg_promise_days,
        100 * COUNTIF(NOT t.is_late) / COUNT(*)         AS current_on_time_pct
    FROM `sahyadri_b2b.city_promise_standards`  AS s
    JOIN `sahyadri_b2b.delivery_performance`    AS t
        ON t.delivery_city = s.delivery_city AND t.order_date > train_end
    WHERE s.uses_city_standard
    GROUP BY s.delivery_city, s.standard_p85
)
SELECT
    IF(current_avg_promise_days < standard_p85, 'Promising too fast', 'Promising slower than needed') AS gap_type,
    COUNT(*)                                                  AS cities,
    SUM(orders_2026)                                          AS orders_2026,
    ROUND(SUM(current_on_time_pct * orders_2026) / SUM(orders_2026), 1) AS current_on_time_pct
FROM city_gap
GROUP BY gap_type
ORDER BY gap_type;
