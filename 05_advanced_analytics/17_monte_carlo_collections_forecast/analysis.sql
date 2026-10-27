/* =============================================================================
   Case study · Monte Carlo forecast of collections from open receivables
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   Every month the finance manager tells the bank and the directors how
   much cash will come in from the receivables on the books. Today she
   applies standard percentages by age bucket and gives one number. The
   directors want a range ("how bad could it be?"), and the auditors want
   to know how much of the book will ever be collected:
     1. How does the chance of collection fall as a receivable ages?
     2. How much of today's open book will be collected in 30, 60 and 90
        days, as a range?
     3. Would the method have worked in the past (back-test), and is the
        range honest?
     4. How much of the book is unlikely ever to be collected?

   METHOD
     - Receivables: delivered orders with a delivery date on every shipment.
       Outstanding at a date = order value - payments up to that date
       (items over Rs 1 only). Age = days since final delivery.
       Age bands: 0-30, 31-60, 61-90, 91-180, 181-365, 365+ days.
     - Snapshots at every month-end from 30 Jun 2024. For each open item:
       the share of its outstanding balance collected in the next 30, 60
       and 90 days (capped at 100 %).
     - Forecast at an as-of date A and horizon h uses only snapshots s with
       s >= A - 365 days and s + h <= A (outcomes known by A).
     - Monte Carlo, 500 replicates, two levels:
         1. draw one historical month-end (collection conditions vary from
            month to month);
         2. for every open item, draw one item of the same age band from
            that month-end and apply its collected share.
       Replicate total = SUM outstanding x drawn share. P10 / P50 / P90 of
       the totals give the range.
     - For comparison, the usual item-independent model: mean = SUM
       outstanding x average share; variance = SUM outstanding^2 x variance
       of share; P10 / P90 = mean -/+ 1.2816 standard deviations.
     - Back-test at five quarter-ends (30 Jun 2025 - 30 Jun 2026), against
       actual collections from the open items; live forecast at 30 Sep 2026.
     - Random draws use a portable integer hash (identical in any engine).
   ============================================================================= */

DECLARE first_snapshot DATE  DEFAULT DATE '2024-06-30';
DECLARE as_of          DATE  DEFAULT DATE '2026-09-30';
DECLARE replicates     INT64 DEFAULT 500;
DECLARE prime          INT64 DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Month-end snapshots of open receivables and what happened next
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mc_snapshot_items` AS
WITH invoices AS (
    SELECT o.order_id, MAX(s.delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_id
    HAVING COUNT(s.delivery_date) = COUNT(*)
),
value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
snapshots AS (
    SELECT DATE_SUB(DATE_ADD(m, INTERVAL 1 MONTH), INTERVAL 1 DAY) AS snapshot_date
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(first_snapshot, MONTH), DATE_TRUNC(as_of, MONTH), INTERVAL 1 MONTH)) AS m
),
paid AS (
    SELECT s.snapshot_date, i.order_id,
           SUM(IF(p.payment_date <= s.snapshot_date, p.amount, 0))                                                  AS paid_to_date,
           SUM(IF(p.payment_date >  s.snapshot_date AND p.payment_date <= DATE_ADD(s.snapshot_date, INTERVAL 30 DAY), p.amount, 0)) AS paid_next_30,
           SUM(IF(p.payment_date >  s.snapshot_date AND p.payment_date <= DATE_ADD(s.snapshot_date, INTERVAL 60 DAY), p.amount, 0)) AS paid_next_60,
           SUM(IF(p.payment_date >  s.snapshot_date AND p.payment_date <= DATE_ADD(s.snapshot_date, INTERVAL 90 DAY), p.amount, 0)) AS paid_next_90
    FROM snapshots AS s
    JOIN invoices AS i ON i.final_delivery_date <= s.snapshot_date
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = i.order_id
    GROUP BY s.snapshot_date, i.order_id
),
open_items AS (
    SELECT p.snapshot_date, p.order_id, i.final_delivery_date,
           DATE_DIFF(p.snapshot_date, i.final_delivery_date, DAY)          AS age_days,
           v.order_value - p.paid_to_date                                  AS outstanding,
           p.paid_next_30, p.paid_next_60, p.paid_next_90
    FROM paid AS p
    JOIN invoices AS i ON i.order_id = p.order_id
    JOIN value AS v ON v.order_id = p.order_id
    WHERE v.order_value - p.paid_to_date > 1
)
SELECT
    o.*,
    CASE WHEN age_days <= 30  THEN 1 WHEN age_days <= 60  THEN 2 WHEN age_days <= 90 THEN 3
         WHEN age_days <= 180 THEN 4 WHEN age_days <= 365 THEN 5 ELSE 6 END   AS age_band,
    LEAST(paid_next_30 / outstanding, 1)                                     AS share_30,
    LEAST(paid_next_60 / outstanding, 1)                                     AS share_60,
    LEAST(paid_next_90 / outstanding, 1)                                     AS share_90
FROM open_items AS o;

-- How the chance of collection falls with age (outcomes fully observed)
SELECT
    age_band,
    CASE age_band WHEN 1 THEN '0-30 days' WHEN 2 THEN '31-60 days' WHEN 3 THEN '61-90 days'
                  WHEN 4 THEN '91-180 days' WHEN 5 THEN '181-365 days' ELSE '365+ days' END AS age,
    COUNT(*)                                                       AS item_snapshots,
    ROUND(100 * SUM(LEAST(paid_next_30, outstanding)) / SUM(outstanding), 1) AS collected_30d_pct,
    ROUND(100 * SUM(LEAST(paid_next_90, outstanding)) / SUM(outstanding), 1) AS collected_90d_pct,
    ROUND(100 * AVG(IF(share_90 = 0, 1, 0)), 1)                    AS nothing_paid_in_90d_pct
FROM `sahyadri_b2b.mc_snapshot_items`
WHERE snapshot_date <= DATE_SUB(as_of, INTERVAL 90 DAY)
GROUP BY age_band
ORDER BY age_band;

-- -----------------------------------------------------------------------------
-- Step 2 · Forecast settings: as-of dates x horizons, and the history pools
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mc_settings` AS
SELECT a AS forecast_date, h AS horizon_days, DATE_DIFF(a, DATE '1970-01-01', DAY) AS day_number
FROM UNNEST([DATE '2025-06-30', DATE '2025-09-30', DATE '2025-12-31', DATE '2026-03-31', DATE '2026-06-30', DATE '2026-09-30']) AS a
CROSS JOIN UNNEST([30, 60, 90]) AS h;

CREATE OR REPLACE TABLE `sahyadri_b2b.mc_pool` AS
SELECT
    t.forecast_date, t.horizon_days, s.snapshot_date, s.age_band, s.order_id,
    CASE t.horizon_days WHEN 30 THEN s.share_30 WHEN 60 THEN s.share_60 ELSE s.share_90 END        AS share,
    DENSE_RANK() OVER (PARTITION BY t.forecast_date, t.horizon_days ORDER BY s.snapshot_date)      AS snapshot_no,
    ROW_NUMBER() OVER (PARTITION BY t.forecast_date, t.horizon_days, s.snapshot_date, s.age_band ORDER BY s.order_id) AS member_no,
    COUNT(*) OVER (PARTITION BY t.forecast_date, t.horizon_days, s.snapshot_date, s.age_band)       AS members
FROM `sahyadri_b2b.mc_settings` AS t
JOIN `sahyadri_b2b.mc_snapshot_items` AS s
  ON s.snapshot_date >= DATE_SUB(t.forecast_date, INTERVAL 365 DAY)
 AND DATE_ADD(s.snapshot_date, INTERVAL t.horizon_days DAY) <= t.forecast_date;

-- -----------------------------------------------------------------------------
-- Step 3 · Monte Carlo simulation (two-level bootstrap)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mc_replicates` AS
WITH open_book AS (
    SELECT t.forecast_date, t.horizon_days, t.day_number, s.order_id, s.age_band, s.outstanding
    FROM `sahyadri_b2b.mc_settings` AS t
    JOIN `sahyadri_b2b.mc_snapshot_items` AS s ON s.snapshot_date = t.forecast_date
),
snapshot_counts AS (
    SELECT forecast_date, horizon_days, MAX(snapshot_no) AS snapshots FROM `sahyadri_b2b.mc_pool` GROUP BY forecast_date, horizon_days
),
-- level 1: one historical month-end per replicate
month_draw AS (
    SELECT t.forecast_date, t.horizon_days, b,
           MOD(b * 7919 + t.day_number * 1299709 + t.horizon_days * 15485863, prime) AS x0
    FROM `sahyadri_b2b.mc_settings` AS t
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, replicates)) AS b
),
month_hash AS (
    SELECT *, MOD(x0 * x0 + 12345, prime) AS x1 FROM month_draw
),
month_pick AS (
    SELECT m.forecast_date, m.horizon_days, m.b,
           1 + MOD(MOD(m.x1 * m.x1 + 54321, prime), c.snapshots) AS snapshot_no
    FROM month_hash AS m
    JOIN snapshot_counts AS c ON c.forecast_date = m.forecast_date AND c.horizon_days = m.horizon_days
),
pool_sizes AS (
    SELECT DISTINCT forecast_date, horizon_days, snapshot_no, age_band, members FROM `sahyadri_b2b.mc_pool`
),
-- level 2: one historical item of the same age band per open item
item_draw AS (
    SELECT o.forecast_date, o.horizon_days, m.b, o.order_id, o.outstanding, m.snapshot_no, o.age_band, ps.members,
           MOD(m.b * 7919 + o.order_id * 104729 + o.day_number * 1299709 + o.horizon_days * 15485863, prime) AS x0
    FROM open_book AS o
    JOIN month_pick AS m ON m.forecast_date = o.forecast_date AND m.horizon_days = o.horizon_days
    LEFT JOIN pool_sizes AS ps
      ON ps.forecast_date = o.forecast_date AND ps.horizon_days = o.horizon_days
     AND ps.snapshot_no = m.snapshot_no AND ps.age_band = o.age_band
),
hashed AS (
    SELECT *, MOD(x0 * x0 + 12345, prime) AS x1 FROM item_draw
),
picked AS (
    SELECT h.forecast_date, h.horizon_days, h.b, h.order_id, h.outstanding, h.snapshot_no, h.age_band,
           1 + MOD(MOD(h.x1 * h.x1 + 54321, prime), h.members) AS member_no
    FROM hashed AS h
    WHERE h.members IS NOT NULL
)
SELECT
    p.forecast_date, p.horizon_days, p.b,
    SUM(p.outstanding * q.share)                                       AS simulated_collections,
    COUNT(*)                                                           AS items_drawn
FROM picked AS p
JOIN `sahyadri_b2b.mc_pool` AS q
  ON q.forecast_date = p.forecast_date AND q.horizon_days = p.horizon_days
 AND q.snapshot_no = p.snapshot_no AND q.age_band = p.age_band AND q.member_no = p.member_no
GROUP BY p.forecast_date, p.horizon_days, p.b;

-- -----------------------------------------------------------------------------
-- Step 4 · Results: range, comparison model and back-test
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.mc_results` AS
WITH book AS (
    SELECT t.forecast_date, t.horizon_days,
           COUNT(*)                                                     AS open_items,
           SUM(s.outstanding)                                           AS open_book,
           SUM(LEAST(CASE t.horizon_days WHEN 30 THEN s.paid_next_30 WHEN 60 THEN s.paid_next_60 ELSE s.paid_next_90 END,
                     s.outstanding))                                    AS actual_collections
    FROM `sahyadri_b2b.mc_settings` AS t
    JOIN `sahyadri_b2b.mc_snapshot_items` AS s ON s.snapshot_date = t.forecast_date
    GROUP BY t.forecast_date, t.horizon_days
),
band_stats AS (
    SELECT forecast_date, horizon_days, age_band, AVG(share) AS mean_share, VAR_POP(share) AS var_share
    FROM `sahyadri_b2b.mc_pool`
    GROUP BY forecast_date, horizon_days, age_band
),
independent AS (
    SELECT t.forecast_date, t.horizon_days,
           SUM(s.outstanding * b.mean_share)                           AS ind_mean,
           SQRT(SUM(POW(s.outstanding, 2) * b.var_share))              AS ind_sd
    FROM `sahyadri_b2b.mc_settings` AS t
    JOIN `sahyadri_b2b.mc_snapshot_items` AS s ON s.snapshot_date = t.forecast_date
    JOIN band_stats AS b ON b.forecast_date = t.forecast_date AND b.horizon_days = t.horizon_days AND b.age_band = s.age_band
    GROUP BY t.forecast_date, t.horizon_days
),
mc AS (
    SELECT forecast_date, horizon_days,
           AVG(simulated_collections)                                  AS mc_mean,
           APPROX_QUANTILES(simulated_collections, 10)[OFFSET(1)]      AS mc_p10,
           APPROX_QUANTILES(simulated_collections, 10)[OFFSET(5)]      AS mc_p50,
           APPROX_QUANTILES(simulated_collections, 10)[OFFSET(9)]      AS mc_p90
    FROM `sahyadri_b2b.mc_replicates`
    GROUP BY forecast_date, horizon_days
)
SELECT
    b.forecast_date, b.horizon_days, b.open_items, b.open_book,
    m.mc_mean, m.mc_p10, m.mc_p50, m.mc_p90,
    i.ind_mean, i.ind_mean - 1.2816 * i.ind_sd AS ind_p10, i.ind_mean + 1.2816 * i.ind_sd AS ind_p90,
    IF(b.forecast_date < as_of, b.actual_collections, NULL)                          AS actual_collections,
    IF(b.forecast_date < as_of, b.actual_collections BETWEEN m.mc_p10 AND m.mc_p90, NULL) AS in_mc_range,
    IF(b.forecast_date < as_of, b.actual_collections BETWEEN i.ind_mean - 1.2816 * i.ind_sd
                                                        AND i.ind_mean + 1.2816 * i.ind_sd, NULL) AS in_independent_range
FROM book AS b
JOIN mc AS m USING (forecast_date, horizon_days)
JOIN independent AS i USING (forecast_date, horizon_days);

-- Back-test, in Rs lakh
SELECT
    forecast_date, horizon_days,
    ROUND(open_book / 1e5, 1)                                          AS open_book_lakh,
    ROUND(mc_p10 / 1e5, 1) AS mc_p10_lakh, ROUND(mc_p50 / 1e5, 1) AS mc_p50_lakh, ROUND(mc_p90 / 1e5, 1) AS mc_p90_lakh,
    ROUND(actual_collections / 1e5, 1)                                 AS actual_lakh,
    ROUND(100 * (mc_mean - actual_collections) / actual_collections, 1) AS mc_mean_error_pct,
    in_mc_range,
    ROUND(ind_p10 / 1e5, 1) AS independent_p10_lakh, ROUND(ind_p90 / 1e5, 1) AS independent_p90_lakh,
    in_independent_range
FROM `sahyadri_b2b.mc_results`
WHERE forecast_date < as_of
ORDER BY forecast_date, horizon_days;

SELECT
    COUNT(*)                                                           AS forecasts_tested,
    COUNTIF(in_mc_range)                                               AS within_mc_p10_p90,
    COUNTIF(in_independent_range)                                      AS within_independent_p10_p90,
    ROUND(AVG(ABS(mc_mean - actual_collections) / actual_collections) * 100, 1) AS mean_abs_error_pct,
    ROUND(AVG((mc_p90 - mc_p10) / mc_mean) * 100, 1)                   AS mc_range_width_pct,
    ROUND(AVG((ind_p90 - ind_p10) / ind_mean) * 100, 1)                AS independent_range_width_pct
FROM `sahyadri_b2b.mc_results`
WHERE forecast_date < as_of;

-- Live forecast at the latest month-end
SELECT
    horizon_days,
    open_items,
    ROUND(open_book / 1e5, 1)                                          AS open_book_lakh,
    ROUND(mc_p10 / 1e5, 1)                                             AS p10_lakh,
    ROUND(mc_p50 / 1e5, 1)                                             AS p50_lakh,
    ROUND(mc_p90 / 1e5, 1)                                             AS p90_lakh,
    ROUND(100 * mc_p50 / open_book, 1)                                 AS p50_share_of_book_pct
FROM `sahyadri_b2b.mc_results`
WHERE forecast_date = as_of
ORDER BY horizon_days;

-- -----------------------------------------------------------------------------
-- Step 5 · How much of today's book is unlikely ever to be collected?
-- -----------------------------------------------------------------------------
SELECT
    age_band,
    CASE age_band WHEN 1 THEN '0-30 days' WHEN 2 THEN '31-60 days' WHEN 3 THEN '61-90 days'
                  WHEN 4 THEN '91-180 days' WHEN 5 THEN '181-365 days' ELSE '365+ days' END AS age,
    COUNT(*)                                                           AS open_items,
    ROUND(SUM(outstanding) / 1e5, 1)                                   AS outstanding_lakh,
    ROUND(100 * SUM(outstanding) / SUM(SUM(outstanding)) OVER (), 1)   AS share_of_book_pct
FROM `sahyadri_b2b.mc_snapshot_items`
WHERE snapshot_date = as_of
GROUP BY age_band
ORDER BY age_band;
