/* =============================================================================
   Case study · Late payment scorecard
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   About four delivered orders in ten are still not fully paid 60 days
   after delivery. The credit controller has two people to chase overdue
   accounts and wants to know at the moment of delivery which orders are
   likely to be paid late, so reminders and calls start early on the right
   ones. She asks for a simple, explainable points scorecard, the kind
   banks use, built and tested on the company's own history:
     1. Which order and customer characteristics predict late payment, and
        how strongly (information value)?
     2. How well does a points scorecard rank orders on data it has not
        seen (time-based hold-out)?
     3. How much better is it than the simplest rule (segment only)?
     4. Where should the collection effort go?

   METHOD
     - Population: Delivered orders whose final delivery was on or before
       31 Jul 2026, so 60 days after delivery can be observed.
     - Target: LATE = not fully paid within 60 days of final delivery
       (payments dated up to delivery + 60 days).
     - Characteristics, each in bins, all known at delivery:
         segment; customer's prior late rate (orders whose 60-day window had
         closed before this order date); order value; average discount;
         delivered late or on time.
     - Train: deliveries before 1 Oct 2025. Test: 1 Oct 2025 - 31 Jul 2026.
     - Weight of evidence per bin (train): WoE = LN(share of on-time payers
       in the bin / share of late payers in the bin), with 0.5 added to
       counts. Information value IV = SUM (share good - share bad) x WoE.
     - Points = ROUND(28.85 x WoE) per bin (20 points double the odds of
       paying on time); score = 600 + sum of points. Higher = safer.
     - Performance on the test period: AUC and Gini (= 2 AUC - 1), and late
       rate by score band.
   ============================================================================= */

DECLARE train_end     DATE    DEFAULT DATE '2025-10-01';
DECLARE last_delivery DATE    DEFAULT DATE '2026-07-31';
DECLARE window_days   INT64   DEFAULT 60;
DECLARE pdo_factor    FLOAT64 DEFAULT 28.85;

-- -----------------------------------------------------------------------------
-- Step 1 · Modelling table: one row per delivered order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.lps_orders` AS
WITH value AS (
    SELECT order_id,
           SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))                       AS order_value,
           100 * (1 - SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100))
                      / SUM(quantity * unit_price))                                                   AS discount_pct
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
delivery AS (
    SELECT order_id, MAX(delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
    HAVING COUNT(delivery_date) = COUNT(*)
),
base AS (
    SELECT o.order_id, o.customer_id, o.order_date, o.promised_delivery_date, c.customer_segment,
           v.order_value, v.discount_pct, d.final_delivery_date
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN value    AS v ON v.order_id = o.order_id
    JOIN delivery AS d ON d.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'Delivered'
      AND d.final_delivery_date <= last_delivery
),
paid_in_window AS (
    SELECT b.order_id, SUM(p.amount) AS paid
    FROM base AS b
    JOIN `sahyadri_b2b.payments` AS p
      ON p.order_id = b.order_id
     AND p.payment_date <= DATE_ADD(b.final_delivery_date, INTERVAL window_days DAY)
    GROUP BY b.order_id
),
labelled AS (
    SELECT b.*, IFNULL(w.paid, 0) < b.order_value - 0.05 AS is_late
    FROM base AS b
    LEFT JOIN paid_in_window AS w ON w.order_id = b.order_id
),
history AS (
    -- the customer's earlier orders whose 60-day window had closed before this order was placed
    SELECT a.order_id, COUNT(h.order_id) AS prior_orders, AVG(IF(h.is_late, 1, 0)) AS prior_late_rate
    FROM labelled AS a
    LEFT JOIN labelled AS h
      ON h.customer_id = a.customer_id
     AND DATE_ADD(h.final_delivery_date, INTERVAL window_days DAY) < a.order_date
    GROUP BY a.order_id
)
SELECT
    l.*,
    IF(l.final_delivery_date < train_end, 'Train', 'Test')                       AS sample,
    l.customer_segment                                                           AS bin_segment,
    CASE WHEN h.prior_orders = 0          THEN '1. No history'
         WHEN h.prior_late_rate = 0       THEN '2. Never late'
         WHEN h.prior_late_rate < 0.25    THEN '3. Under 25 % late'
         WHEN h.prior_late_rate < 0.50    THEN '4. 25-50 % late'
         ELSE                                  '5. 50 %+ late' END               AS bin_history,
    CASE WHEN l.order_value < 25000  THEN '1. Under Rs 25k'
         WHEN l.order_value < 100000 THEN '2. Rs 25k-1 lakh'
         WHEN l.order_value < 300000 THEN '3. Rs 1-3 lakh'
         ELSE                             '4. Rs 3 lakh+' END                    AS bin_value,
    CASE WHEN l.discount_pct = 0  THEN '1. None'
         WHEN l.discount_pct < 5  THEN '2. Under 5 %'
         WHEN l.discount_pct < 10 THEN '3. 5-10 %'
         ELSE                          '4. 10 %+' END                            AS bin_discount,
    CASE WHEN l.promised_delivery_date IS NULL                   THEN '3. No promise date'
         WHEN l.final_delivery_date > l.promised_delivery_date   THEN '2. Delivered late'
         ELSE                                                         '1. On time' END AS bin_delivery
FROM labelled AS l
JOIN history  AS h ON h.order_id = l.order_id;

SELECT sample, COUNT(*) AS orders, COUNTIF(is_late) AS late, ROUND(100 * AVG(IF(is_late, 1, 0)), 1) AS late_pct
FROM `sahyadri_b2b.lps_orders`
GROUP BY sample
ORDER BY sample DESC;

-- -----------------------------------------------------------------------------
-- Step 2 · Weight of evidence and information value (train sample)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.lps_woe` AS
WITH long AS (
              SELECT is_late, '1. Segment'         AS characteristic, bin_segment  AS bin FROM `sahyadri_b2b.lps_orders` WHERE sample = 'Train'
    UNION ALL SELECT is_late, '2. Payment history',                   bin_history         FROM `sahyadri_b2b.lps_orders` WHERE sample = 'Train'
    UNION ALL SELECT is_late, '3. Order value',                       bin_value           FROM `sahyadri_b2b.lps_orders` WHERE sample = 'Train'
    UNION ALL SELECT is_late, '4. Discount',                          bin_discount        FROM `sahyadri_b2b.lps_orders` WHERE sample = 'Train'
    UNION ALL SELECT is_late, '5. Delivery',                          bin_delivery        FROM `sahyadri_b2b.lps_orders` WHERE sample = 'Train'
    -- interaction: payment history measured within each segment
    UNION ALL SELECT is_late, '6. Segment x history', CONCAT(bin_segment, ' | ', bin_history) FROM `sahyadri_b2b.lps_orders` WHERE sample = 'Train'
),
counts AS (
    SELECT characteristic, bin,
           COUNTIF(NOT is_late) + 0.5 AS good,
           COUNTIF(is_late) + 0.5     AS bad
    FROM long
    GROUP BY characteristic, bin
),
shares AS (
    SELECT *,
           good / SUM(good) OVER (PARTITION BY characteristic) AS good_share,
           bad  / SUM(bad)  OVER (PARTITION BY characteristic) AS bad_share
    FROM counts
)
SELECT
    characteristic, bin, good - 0.5 AS on_time_orders, bad - 0.5 AS late_orders,
    (bad - 0.5) / (good + bad - 1)                                 AS late_rate,
    LN(good_share / bad_share)                                     AS woe,
    (good_share - bad_share) * LN(good_share / bad_share)          AS iv_part,
    CAST(ROUND(pdo_factor * LN(good_share / bad_share)) AS INT64)  AS points
FROM shares;

SELECT characteristic,
       ROUND(SUM(iv_part), 3)                                       AS information_value,
       CASE WHEN SUM(iv_part) < 0.02 THEN 'Not useful'
            WHEN SUM(iv_part) < 0.10 THEN 'Weak'
            WHEN SUM(iv_part) < 0.30 THEN 'Medium'
            ELSE 'Strong' END                                       AS strength
FROM `sahyadri_b2b.lps_woe`
GROUP BY characteristic
ORDER BY information_value DESC;

SELECT characteristic, bin, on_time_orders, late_orders, ROUND(100 * late_rate, 1) AS late_pct,
       ROUND(woe, 3) AS woe, points
FROM `sahyadri_b2b.lps_woe`
WHERE characteristic NOT LIKE '6.%'
ORDER BY characteristic, bin;

-- Does payment history matter within a segment? Late rate by segment and history (train)
SELECT
    bin_segment,
    ROUND(100 * AVG(IF(bin_history = '1. No history', IF(is_late, 1, 0), NULL)), 1)      AS no_history_pct,
    ROUND(100 * AVG(IF(bin_history IN ('2. Never late', '3. Under 25 % late'), IF(is_late, 1, 0), NULL)), 1) AS rarely_late_pct,
    ROUND(100 * AVG(IF(bin_history = '4. 25-50 % late', IF(is_late, 1, 0), NULL)), 1)    AS sometimes_late_pct,
    ROUND(100 * AVG(IF(bin_history = '5. 50 %+ late', IF(is_late, 1, 0), NULL)), 1)      AS mostly_late_pct,
    COUNT(*)                                                                             AS orders
FROM `sahyadri_b2b.lps_orders`
WHERE sample = 'Train'
GROUP BY bin_segment
ORDER BY bin_segment;

-- -----------------------------------------------------------------------------
-- Step 3 · Score every order and test on the hold-out period
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.lps_scores` AS
SELECT
    o.order_id, o.customer_id, o.sample, o.is_late, o.order_value, o.customer_segment,
    600 + s.points + h.points + v.points + d.points + y.points                    AS score,
    600 + s.points                                                               AS score_segment_only,
    600 + x.points                                                               AS score_segment_history
FROM `sahyadri_b2b.lps_orders` AS o
JOIN `sahyadri_b2b.lps_woe` AS s ON s.characteristic = '1. Segment'         AND s.bin = o.bin_segment
JOIN `sahyadri_b2b.lps_woe` AS h ON h.characteristic = '2. Payment history' AND h.bin = o.bin_history
JOIN `sahyadri_b2b.lps_woe` AS v ON v.characteristic = '3. Order value'     AND v.bin = o.bin_value
JOIN `sahyadri_b2b.lps_woe` AS d ON d.characteristic = '4. Discount'        AND d.bin = o.bin_discount
JOIN `sahyadri_b2b.lps_woe` AS y ON y.characteristic = '5. Delivery'        AND y.bin = o.bin_delivery
JOIN `sahyadri_b2b.lps_woe` AS x ON x.characteristic = '6. Segment x history' AND x.bin = CONCAT(o.bin_segment, ' | ', o.bin_history);

CREATE OR REPLACE TABLE `sahyadri_b2b.lps_auc` AS
WITH long AS (
              SELECT sample, is_late, 'Scorecard (5 characteristics)' AS model, score              AS value FROM `sahyadri_b2b.lps_scores`
    UNION ALL SELECT sample, is_late, 'Segment only',                           score_segment_only          FROM `sahyadri_b2b.lps_scores`
    UNION ALL SELECT sample, is_late, 'Segment x history (combined bins)',      score_segment_history       FROM `sahyadri_b2b.lps_scores`
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY sample, model ORDER BY value)
             + (COUNT(*) OVER (PARTITION BY sample, model, value) - 1) / 2       AS avg_rank
    FROM long
)
SELECT
    sample, model,
    COUNTIF(NOT is_late) AS on_time, COUNTIF(is_late) AS late,
    -- probability that an on-time order scores higher than a late one
    (SUM(IF(NOT is_late, avg_rank, 0)) - COUNTIF(NOT is_late) * (COUNTIF(NOT is_late) + 1) / 2)
      / (COUNTIF(NOT is_late) * COUNTIF(is_late))                                AS auc
FROM ranked
GROUP BY sample, model;

SELECT sample, model, on_time, late, ROUND(auc, 3) AS auc, ROUND(2 * auc - 1, 3) AS gini
FROM `sahyadri_b2b.lps_auc`
ORDER BY sample DESC, model;

-- Late rate by score band on the test period
WITH banded AS (
    SELECT *, NTILE(5) OVER (ORDER BY score, order_id) AS score_band
    FROM `sahyadri_b2b.lps_scores`
    WHERE sample = 'Test'
)
SELECT
    score_band                                                                   AS band_1_is_riskiest,
    MIN(score)                                                                   AS min_score,
    MAX(score)                                                                   AS max_score,
    COUNT(*)                                                                     AS orders,
    ROUND(100 * AVG(IF(is_late, 1, 0)), 1)                                       AS late_pct,
    ROUND(100 * COUNTIF(is_late) / SUM(COUNTIF(is_late)) OVER (), 1)             AS share_of_late_orders_pct,
    ROUND(100 * SUM(IF(is_late, order_value, 0)) / SUM(SUM(IF(is_late, order_value, 0))) OVER (), 1) AS share_of_late_value_pct
FROM banded
GROUP BY score_band
ORDER BY score_band;

-- The recommended rule: segment only, on the test period
SELECT
    customer_segment,
    COUNT(*)                                                                     AS orders,
    ROUND(100 * AVG(IF(is_late, 1, 0)), 1)                                       AS late_pct,
    ROUND(100 * COUNTIF(is_late) / SUM(COUNTIF(is_late)) OVER (), 1)             AS share_of_late_orders_pct,
    ROUND(SUM(IF(is_late, order_value, 0)) / 1e5, 1)                             AS late_order_value_lakh
FROM `sahyadri_b2b.lps_scores`
WHERE sample = 'Test'
GROUP BY customer_segment
ORDER BY late_pct DESC;
