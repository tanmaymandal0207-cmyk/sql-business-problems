/* =============================================================================
   Case study · Monetary unit sampling for the receivables audit
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The statutory auditors will test whether each delivered order's payment
   status (Paid / Partially Paid / Unpaid) correctly reflects the cash
   received, because receivables are built from it. They will not test
   every order: they will draw a monetary unit sample (MUS), where every
   rupee of value has the same chance of selection, so large orders are
   more likely to be picked. Finance wants to:
     1. Design the sample the auditors are likely to draw (size, interval).
     2. Run it, and evaluate the result the way the auditors will
        (projected misstatement and upper misstatement limit).
     3. Check the method against the truth: because finance holds all the
        data, the actual misstatement of the whole population is known.
        How often does a sample reach the right conclusion?

   METHOD
     - Population: Delivered orders whose final delivery fell in FY 2025-26
       (1 Apr 2025 - 31 Mar 2026). Book value = order value.
     - Misstatement of an order: |outstanding implied by its status -
       actual outstanding|, where Paid implies 0, Unpaid implies the full
       value, Partially Paid implies the actual balance (only the status
       is tested), and actual outstanding = value - all payments (min 0).
       Differences of Rs 10 or less are treated as rounding, not errors.
       Tainting = misstatement / book value, capped at 1.
     - Design: 95 % confidence, no expected misstatement (reliability
       factor 3.0), tolerable misstatement 1 % of book value.
       Sample size n = CEIL(book value x 3.0 / tolerable); interval J =
       book value / n. Systematic selection with a random start r: the
       sampled rupees are r, r + J, r + 2J ... over the cumulative book
       value in order_id sequence.
     - Evaluation (Poisson / cell-free method): items with book value >= J
       form a top stratum and their misstatement counts in full.
       Projected misstatement = SUM(tainting) x J + top-stratum misstatement.
       Upper limit = J x (3.0 + SUM over ranked taintings of the incremental
       Poisson factor) + top-stratum misstatement.
       Conclusion: acceptable if the upper limit <= tolerable misstatement
       (compared to the nearest rupee).
     - Replicates: 20 random starts (golden-ratio sequence) show how often
       the method reaches the right conclusion.
   ============================================================================= */

DECLARE fy_start        DATE    DEFAULT DATE '2025-04-01';
DECLARE fy_end          DATE    DEFAULT DATE '2026-03-31';
DECLARE tolerable_pct   FLOAT64 DEFAULT 0.01;
DECLARE reliability     FLOAT64 DEFAULT 3.0;
DECLARE replicates      INT64   DEFAULT 20;
DECLARE trivial_amount  FLOAT64 DEFAULT 10;

-- -----------------------------------------------------------------------------
-- Step 1 · Population with book value, misstatement and cumulative value
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mus_population` AS
WITH value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS book_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
delivered AS (
    SELECT order_id, MAX(delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
    HAVING COUNT(delivery_date) = COUNT(*)
),
paid AS (
    SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` GROUP BY order_id
),
base AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.payment_status,
        v.book_value,
        IFNULL(p.paid, 0)                                                          AS paid,
        GREATEST(v.book_value - IFNULL(p.paid, 0), 0)                              AS actual_outstanding,
        CASE o.payment_status
            WHEN 'Paid'   THEN 0
            WHEN 'Unpaid' THEN v.book_value
            ELSE GREATEST(v.book_value - IFNULL(p.paid, 0), 0) END                 AS implied_outstanding
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN value     AS v ON v.order_id = o.order_id
    JOIN delivered AS d ON d.order_id = o.order_id
    LEFT JOIN paid AS p ON p.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
      AND d.final_delivery_date BETWEEN fy_start AND fy_end
)
SELECT
    *,
    IF(ABS(implied_outstanding - actual_outstanding) > trivial_amount,
       ABS(implied_outstanding - actual_outstanding), 0)                           AS misstatement,
    LEAST(IF(ABS(implied_outstanding - actual_outstanding) > trivial_amount,
             ABS(implied_outstanding - actual_outstanding), 0) / book_value, 1)    AS tainting,
    SUM(book_value) OVER (ORDER BY order_id) - book_value                          AS cum_before,
    SUM(book_value) OVER (ORDER BY order_id)                                       AS cum_after
FROM base;

-- -----------------------------------------------------------------------------
-- Step 2 · Sample design
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mus_design` AS
SELECT
    COUNT(*)                                                                       AS population_items,
    SUM(book_value)                                                                AS book_value,
    tolerable_pct * SUM(book_value)                                                AS tolerable_misstatement,
    CAST(CEIL(SUM(book_value) * reliability / (tolerable_pct * SUM(book_value))) AS INT64) AS sample_size,
    SUM(book_value) / CEIL(SUM(book_value) * reliability / (tolerable_pct * SUM(book_value))) AS sampling_interval,
    SUM(misstatement)                                                              AS true_misstatement,
    COUNTIF(misstatement > 0)                                                      AS true_errors
FROM `sahyadri_b2b.mus_population`;

SELECT
    population_items,
    ROUND(book_value / 1e7, 2)                                                     AS book_value_crore,
    ROUND(tolerable_misstatement / 1e5, 2)                                         AS tolerable_lakh,
    sample_size,
    ROUND(sampling_interval / 1e5, 2)                                              AS interval_lakh,
    true_errors,
    ROUND(true_misstatement / 1e5, 2)                                              AS true_misstatement_lakh
FROM `sahyadri_b2b.mus_design`;

-- The errors in the population (known to finance, not to the auditor)
SELECT order_id, customer_id, payment_status, ROUND(book_value, 0) AS book_value,
       ROUND(paid, 0) AS paid, ROUND(misstatement, 0) AS misstatement, ROUND(tainting, 3) AS tainting
FROM `sahyadri_b2b.mus_population`
WHERE misstatement > 0
ORDER BY misstatement DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · Selection for 20 random starts (replicate 1 is the audit sample)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mus_selection` AS
WITH starts AS (
    SELECT k AS replicate,
           MOD(k * 0.6180339887498949, 1) * d.sampling_interval                    AS random_start
    FROM UNNEST(GENERATE_ARRAY(1, replicates)) AS k
    CROSS JOIN `sahyadri_b2b.mus_design` AS d
)
SELECT
    s.replicate,
    s.random_start,
    p.order_id,
    p.book_value,
    p.misstatement,
    p.tainting,
    p.book_value >= d.sampling_interval                                            AS top_stratum,
    CAST(FLOOR((p.cum_after  - s.random_start) / d.sampling_interval)
       - FLOOR((p.cum_before - s.random_start) / d.sampling_interval) AS INT64)    AS hits
FROM starts AS s
CROSS JOIN `sahyadri_b2b.mus_design` AS d
JOIN `sahyadri_b2b.mus_population` AS p
  ON FLOOR((p.cum_after  - s.random_start) / d.sampling_interval)
   > FLOOR((p.cum_before - s.random_start) / d.sampling_interval);

-- -----------------------------------------------------------------------------
-- Step 4 · Evaluation of every replicate
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mus_evaluation` AS
WITH poisson_95 AS (
    -- cumulative upper limits for 0..10 errors at 95 % confidence
    SELECT 0 AS k, 3.00 AS ul UNION ALL SELECT 1, 4.74 UNION ALL SELECT 2, 6.30 UNION ALL
    SELECT 3, 7.75 UNION ALL SELECT 4, 9.15 UNION ALL SELECT 5, 10.51 UNION ALL SELECT 6, 11.84 UNION ALL
    SELECT 7, 13.15 UNION ALL SELECT 8, 14.43 UNION ALL SELECT 9, 15.71 UNION ALL SELECT 10, 16.96
),
increments AS (
    SELECT k AS error_rank, ul - LAG(ul) OVER (ORDER BY k) AS increment
    FROM poisson_95
),
errors AS (
    -- lower-stratum errors ranked by tainting, largest first
    SELECT replicate, tainting,
           ROW_NUMBER() OVER (PARTITION BY replicate ORDER BY tainting DESC, order_id) AS error_rank
    FROM `sahyadri_b2b.mus_selection`
    WHERE misstatement > 0 AND NOT top_stratum
),
lower AS (
    SELECT e.replicate,
           COUNT(*)                                              AS lower_errors,
           SUM(e.tainting)                                       AS sum_tainting,
           SUM(e.tainting * IFNULL(i.increment, 1.25))           AS factor_tainting
    FROM errors AS e
    LEFT JOIN increments AS i ON i.error_rank = e.error_rank
    GROUP BY e.replicate
),
per_replicate AS (
    SELECT
        replicate,
        ANY_VALUE(random_start)                                  AS random_start,
        COUNT(*)                                                 AS items_selected,
        SUM(hits)                                                AS hits,
        COUNTIF(top_stratum)                                     AS top_stratum_items,
        COUNTIF(misstatement > 0)                                AS errors_found,
        SUM(IF(top_stratum, misstatement, 0))                    AS top_stratum_misstatement
    FROM `sahyadri_b2b.mus_selection`
    GROUP BY replicate
)
SELECT
    r.*,
    IFNULL(l.lower_errors, 0)                                                      AS lower_errors,
    IFNULL(l.sum_tainting, 0) * d.sampling_interval + r.top_stratum_misstatement   AS projected_misstatement,
    d.sampling_interval * (reliability + IFNULL(l.factor_tainting, 0))
      + r.top_stratum_misstatement                                                 AS upper_limit,
    d.tolerable_misstatement,
    d.true_misstatement,
    ROUND(d.sampling_interval * (reliability + IFNULL(l.factor_tainting, 0))
      + r.top_stratum_misstatement) <= ROUND(d.tolerable_misstatement)             AS sample_accepts,
    d.true_misstatement <= d.tolerable_misstatement                                AS truth_acceptable,
    d.sampling_interval * (reliability + IFNULL(l.factor_tainting, 0))
      + r.top_stratum_misstatement >= d.true_misstatement                          AS upper_limit_covers_truth
FROM per_replicate AS r
CROSS JOIN `sahyadri_b2b.mus_design` AS d
LEFT JOIN lower AS l ON l.replicate = r.replicate;

-- The audit sample (replicate 1)
SELECT
    items_selected,
    hits,
    top_stratum_items,
    errors_found,
    ROUND(projected_misstatement / 1e5, 2)                                         AS projected_lakh,
    ROUND(upper_limit / 1e5, 2)                                                    AS upper_limit_lakh,
    ROUND(tolerable_misstatement / 1e5, 2)                                         AS tolerable_lakh,
    sample_accepts
FROM `sahyadri_b2b.mus_evaluation`
WHERE replicate = 1;

-- How the method performs across 20 random starts
SELECT
    COUNT(*)                                                                       AS replicate_count,
    ROUND(AVG(items_selected), 1)                                                  AS avg_items_selected,
    COUNTIF(errors_found > 0)                                                      AS samples_finding_an_error,
    MAX(errors_found)                                                              AS most_errors_found,
    COUNTIF(sample_accepts = truth_acceptable)                                     AS correct_conclusions,
    COUNTIF(upper_limit_covers_truth)                                              AS upper_limit_covered_truth,
    ROUND(MIN(upper_limit) / 1e5, 2)                                               AS min_upper_limit_lakh,
    ROUND(MAX(upper_limit) / 1e5, 2)                                               AS max_upper_limit_lakh
FROM `sahyadri_b2b.mus_evaluation`;

-- Chance that each erroneous order is selected (book value / interval, max 1)
WITH times_selected AS (
    SELECT order_id, COUNT(DISTINCT replicate) AS replicates_selecting_it
    FROM `sahyadri_b2b.mus_selection`
    GROUP BY order_id
)
SELECT
    p.order_id,
    ROUND(p.book_value, 0)                                                         AS book_value,
    ROUND(p.misstatement, 0)                                                       AS misstatement,
    ROUND(100 * LEAST(p.book_value / d.sampling_interval, 1), 1)                   AS selection_probability_pct,
    IFNULL(t.replicates_selecting_it, 0)                                           AS replicates_selecting_it
FROM `sahyadri_b2b.mus_population` AS p
CROSS JOIN `sahyadri_b2b.mus_design` AS d
LEFT JOIN times_selected AS t ON t.order_id = p.order_id
WHERE p.misstatement > 0
ORDER BY p.misstatement DESC;

-- Probability that a systematic MUS sample contains at least one of the errors
-- (each error is selected independently with probability book value / interval)
SELECT
    ROUND(100 * (1 - EXP(SUM(LN(1 - LEAST(p.book_value / d.sampling_interval, 0.999999))))), 1) AS chance_sample_finds_an_error_pct
FROM `sahyadri_b2b.mus_population` AS p
CROSS JOIN `sahyadri_b2b.mus_design` AS d
WHERE p.misstatement > 0;
