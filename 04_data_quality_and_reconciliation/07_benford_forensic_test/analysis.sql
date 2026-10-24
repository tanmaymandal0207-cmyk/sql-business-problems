/* =============================================================================
   Case study · Benford's law forensic test
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Internal audit wants a quick, data-wide screen for invented or manipulated
   amounts before the year-end audit. Naturally occurring financial amounts
   follow Benford's law: about 30 % start with the digit 1 and fewer than 5 %
   with 9. Made-up numbers, systematic rounding or keyed-in thresholds usually
   break that pattern. Audit wants to know:
     1. Do payment amounts, order values and order line values conform to
        Benford's law, overall and by payment method?
     2. Which leading digits (or digit pairs) are over-represented?
     3. Are there unusual round amounts, and can they be explained by normal
        business behaviour?

   METHOD
     Expected share of first digit d (1-9)       = LOG10(1 + 1/d)
     Expected share of first two digits dd (10-99) = LOG10(1 + 1/dd)
     Digit z-statistic (with continuity correction):
         z = (|p_obs - p_exp| - 1 / (2n)) / SQRT(p_exp (1 - p_exp) / n)
     MAD (mean absolute deviation) = average over digits of |p_obs - p_exp|
     Conformity (Nigrini's thresholds):
         First digit : <= 0.006 close, <= 0.012 acceptable, <= 0.015 marginal, else non-conforming
         First two   : <= 0.0012 close, <= 0.0018 acceptable, <= 0.0022 marginal, else non-conforming
     Chi-square = sum over digits of n (p_obs - p_exp)^2 / p_exp, reported
     for information (with thousands of records it flags trivial deviations,
     which is why MAD is the main measure).

   KEY RULES
     - Amounts of at least ₹10 (so that every amount has two leading digits).
     - Payments: every payment row. Order values: every order's value after
       discount. Order lines: every line's gross value (quantity * unit_price).
     - Round amount: an exact multiple of ₹1,000.
   ============================================================================= */

DECLARE min_amount FLOAT64 DEFAULT 10;

-- -----------------------------------------------------------------------------
-- Step 1 · Leading digits for every amount in the three populations
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.benford_values` AS
WITH amounts AS (
    SELECT 'Payments' AS population, CAST(payment_id AS STRING) AS record_id,
           IFNULL(payment_method, 'Not recorded') AS subgroup, amount
    FROM `sahyadri_b2b.payments`
    UNION ALL
    SELECT 'Order values', CAST(order_id AS STRING), 'All',
           SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
    UNION ALL
    SELECT 'Order lines', CAST(order_item_id AS STRING), 'All', quantity * unit_price
    FROM `sahyadri_b2b.sales_order_items`
)
SELECT
    population,
    record_id,
    subgroup,
    amount,
    -- leading digits from the whole-rupee part as text (avoids floating-point LOG10 edge cases)
    CAST(SUBSTR(CAST(CAST(FLOOR(amount) AS INT64) AS STRING), 1, 2) AS INT64) AS first_two_digits,
    CAST(SUBSTR(CAST(CAST(FLOOR(amount) AS INT64) AS STRING), 1, 1) AS INT64) AS first_digit
FROM amounts
WHERE amount >= min_amount;

-- -----------------------------------------------------------------------------
-- Step 2 · First-digit test for each population
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.benford_first_digit` AS
WITH digits AS (SELECT d FROM UNNEST(GENERATE_ARRAY(1, 9)) AS d),
pops AS (SELECT population, COUNT(*) AS n FROM `sahyadri_b2b.benford_values` GROUP BY population),
observed AS (
    SELECT population, first_digit AS d, COUNT(*) AS cnt
    FROM `sahyadri_b2b.benford_values`
    GROUP BY population, first_digit
)
SELECT
    p.population,
    g.d                                                                        AS digit,
    p.n,
    IFNULL(o.cnt, 0)                                                           AS observed_count,
    IFNULL(o.cnt, 0) / p.n                                                     AS observed_share,
    LOG10(1 + 1 / g.d)                                                         AS expected_share,
    (ABS(IFNULL(o.cnt, 0) / p.n - LOG10(1 + 1 / g.d)) - 1 / (2 * p.n))
        / SQRT(LOG10(1 + 1 / g.d) * (1 - LOG10(1 + 1 / g.d)) / p.n)            AS z
FROM pops        AS p
CROSS JOIN digits AS g
LEFT JOIN observed AS o ON o.population = p.population AND o.d = g.d;

SELECT
    population,
    ANY_VALUE(n)                                                               AS records,
    ROUND(AVG(ABS(observed_share - expected_share)), 4)                        AS mad,
    CASE
        WHEN AVG(ABS(observed_share - expected_share)) <= 0.006 THEN 'Close conformity'
        WHEN AVG(ABS(observed_share - expected_share)) <= 0.012 THEN 'Acceptable conformity'
        WHEN AVG(ABS(observed_share - expected_share)) <= 0.015 THEN 'Marginal conformity'
        ELSE 'Non-conformity'
    END                                                                        AS conformity,
    ROUND(SUM(n * POW(observed_share - expected_share, 2) / expected_share), 1) AS chi_square_8_df,
    COUNTIF(z > 1.96)                                                          AS digits_with_z_above_1_96,
    ROUND(100 * MAX(IF(digit = 1, observed_share, NULL)), 1)                    AS digit_1_pct,
    ROUND(100 * MAX(IF(digit = 9, observed_share, NULL)), 1)                    AS digit_9_pct
FROM `sahyadri_b2b.benford_first_digit`
GROUP BY population
ORDER BY population;

-- -----------------------------------------------------------------------------
-- Step 3 · First-two-digit test: conformity and the largest spikes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.benford_first_two` AS
WITH digits AS (SELECT d FROM UNNEST(GENERATE_ARRAY(10, 99)) AS d),
pops AS (SELECT population, COUNT(*) AS n FROM `sahyadri_b2b.benford_values` GROUP BY population),
observed AS (
    SELECT population, first_two_digits AS d, COUNT(*) AS cnt
    FROM `sahyadri_b2b.benford_values`
    GROUP BY population, first_two_digits
)
SELECT
    p.population,
    g.d                                                                        AS digits,
    p.n,
    IFNULL(o.cnt, 0)                                                           AS observed_count,
    IFNULL(o.cnt, 0) / p.n                                                     AS observed_share,
    LOG10(1 + 1 / g.d)                                                         AS expected_share,
    (ABS(IFNULL(o.cnt, 0) / p.n - LOG10(1 + 1 / g.d)) - 1 / (2 * p.n))
        / SQRT(LOG10(1 + 1 / g.d) * (1 - LOG10(1 + 1 / g.d)) / p.n)            AS z
FROM pops        AS p
CROSS JOIN digits AS g
LEFT JOIN observed AS o ON o.population = p.population AND o.d = g.d;

SELECT
    population,
    ROUND(AVG(ABS(observed_share - expected_share)), 5)                        AS mad,
    CASE
        WHEN AVG(ABS(observed_share - expected_share)) <= 0.0012 THEN 'Close conformity'
        WHEN AVG(ABS(observed_share - expected_share)) <= 0.0018 THEN 'Acceptable conformity'
        WHEN AVG(ABS(observed_share - expected_share)) <= 0.0022 THEN 'Marginal conformity'
        ELSE 'Non-conformity'
    END                                                                        AS conformity,
    COUNTIF(z > 3 AND observed_share > expected_share)                         AS spikes_z_above_3
FROM `sahyadri_b2b.benford_first_two`
GROUP BY population
ORDER BY population;

-- The over-represented digit pairs (z > 3, above expectation)
SELECT
    population,
    digits,
    observed_count,
    ROUND(n * expected_share, 1)                    AS expected_count,
    ROUND(100 * observed_share, 2)                  AS observed_pct,
    ROUND(100 * expected_share, 2)                  AS expected_pct,
    ROUND(z, 2)                                     AS z
FROM `sahyadri_b2b.benford_first_two`
WHERE z > 3 AND observed_share > expected_share
ORDER BY population, z DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Round-amount test on payments: are round amounts explained?
--          A round payment that is one of several payments on the order is an
--          instalment; a single round payment that does not settle the order
--          is unexplained.
-- -----------------------------------------------------------------------------
WITH pay AS (
    SELECT
        p.payment_id,
        p.order_id,
        p.amount,
        MOD(CAST(ROUND(p.amount * 100) AS INT64), 100000) = 0   AS is_round_thousand,
        COUNT(*) OVER (PARTITION BY p.order_id)                AS payments_on_order,
        SUM(p.amount) OVER (PARTITION BY p.order_id)           AS paid_on_order
    FROM `sahyadri_b2b.payments` AS p
),
order_value AS (
    SELECT order_id, ROUND(SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)), 2) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
)
SELECT
    CASE
        WHEN NOT p.is_round_thousand                                   THEN '0. Not a round amount'
        WHEN p.payments_on_order > 1                                   THEN '1. Round instalment (order has several payments)'
        WHEN ABS(p.paid_on_order - v.order_value) <= 0.05              THEN '2. Round single payment that settles the order'
        ELSE '3. Round single payment that does not settle the order'
    END                                                                 AS payment_type,
    COUNT(*)                                                            AS payments,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                    AS pct_of_payments,
    ROUND(SUM(p.amount), 2)                                             AS amount
FROM pay              AS p
JOIN order_value      AS v ON v.order_id = p.order_id
GROUP BY payment_type
ORDER BY payment_type;

-- -----------------------------------------------------------------------------
-- Step 5 · Payments by method: first-digit MAD per subgroup
-- -----------------------------------------------------------------------------
WITH digits AS (SELECT d FROM UNNEST(GENERATE_ARRAY(1, 9)) AS d),
groups AS (
    SELECT subgroup, COUNT(*) AS n FROM `sahyadri_b2b.benford_values`
    WHERE population = 'Payments' GROUP BY subgroup
),
observed AS (
    SELECT subgroup, first_digit AS d, COUNT(*) AS cnt
    FROM `sahyadri_b2b.benford_values`
    WHERE population = 'Payments'
    GROUP BY subgroup, first_digit
)
SELECT
    g.subgroup                                                                       AS payment_method,
    g.n                                                                              AS payments,
    ROUND(AVG(ABS(IFNULL(o.cnt, 0) / g.n - LOG10(1 + 1 / d.d))), 4)                  AS mad,
    CASE
        WHEN AVG(ABS(IFNULL(o.cnt, 0) / g.n - LOG10(1 + 1 / d.d))) <= 0.006 THEN 'Close conformity'
        WHEN AVG(ABS(IFNULL(o.cnt, 0) / g.n - LOG10(1 + 1 / d.d))) <= 0.012 THEN 'Acceptable conformity'
        WHEN AVG(ABS(IFNULL(o.cnt, 0) / g.n - LOG10(1 + 1 / d.d))) <= 0.015 THEN 'Marginal conformity'
        ELSE 'Non-conformity'
    END                                                                              AS conformity
FROM groups AS g
CROSS JOIN digits AS d
LEFT JOIN observed AS o ON o.subgroup = g.subgroup AND o.d = d.d
GROUP BY g.subgroup, g.n
ORDER BY mad DESC;

-- Payment-rail limits: amounts that break the rules of the payment method recorded
--   RTGS is for amounts of ₹2 lakh and above; UPI's general per-transaction
--   limit is ₹1 lakh. A breach usually means the method was recorded wrongly.
SELECT
    IFNULL(payment_method, 'Not recorded')                                  AS payment_method,
    COUNT(*)                                                                AS payments,
    COUNTIF(payment_method = 'RTGS' AND amount < 200000)                    AS rtgs_below_2_lakh,
    ROUND(SUM(IF(payment_method = 'RTGS' AND amount < 200000, amount, 0)), 2) AS rtgs_below_2_lakh_amount,
    COUNTIF(payment_method = 'UPI' AND amount > 100000)                     AS upi_above_1_lakh,
    MIN(amount)                                                             AS smallest_amount,
    MAX(amount)                                                             AS largest_amount
FROM `sahyadri_b2b.payments`
GROUP BY payment_method
ORDER BY payments DESC;
