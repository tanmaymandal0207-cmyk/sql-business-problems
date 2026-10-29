/* =============================================================================
   Case study · Expected credit loss: a roll-rate provision matrix
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The auditors have asked for an expected credit loss (ECL) provision on
   trade receivables under the simplified approach of Ind AS 109 / IFRS 9:
   a provision matrix of loss rates by age, built from the company's own
   payment history. Today the company provides nothing until a customer is
   written off. The CFO wants:
     1. How fast do receivables roll from one age bucket to the next, and
        when is an unpaid balance effectively lost?
     2. What loss rate applies to each age bucket, and what is the
        provision on today's book?
     3. Does one matrix fit all customers, or does each segment need its
        own?
     4. Would the matrix have predicted the losses that actually happened?

   METHOD
     - Receivable: a delivered order (delivery date on every shipment) with
       more than Rs 1 outstanding at a month-end (order value - payments to
       date).
     - Age bucket: calendar months since the delivery month (0 = delivered
       this month, 1, 2, ... 6+). Every open item moves exactly one bucket
       per month-end.
     - Default: still unpaid at bucket 6 (the end of the sixth month after
       delivery, 153-184 days). The data shows that almost nothing is ever
       collected after that point.
     - Roll rate of bucket k: balance still open one month later
       / balance in bucket k, over the transitions completed by the
       reporting date. Three designs are compared:
         A. pooled, trailing 12 months of transitions
         B. one matrix per customer segment, all history to date
         C. pooled, all history to date
     - Loss rate of bucket k: the product of the roll rates from k to 5;
       bucket 6+ = 100 %. Provision = outstanding x loss rate.
     - Back-test: at each month-end from January 2025 to March 2026, the
       provision on buckets 0-5 against the balance of the same items still
       unpaid when they reached bucket 6.
   ============================================================================= */

DECLARE first_snapshot  DATE   DEFAULT DATE '2024-01-31';
DECLARE first_reporting DATE   DEFAULT DATE '2025-01-31';
DECLARE as_of           DATE   DEFAULT DATE '2026-09-30';
DECLARE default_bucket  INT64  DEFAULT 6;
DECLARE window_months   INT64  DEFAULT 12;

-- -----------------------------------------------------------------------------
-- Step 1 · Month-end ageing of every open receivable, and roll rates
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ecl_snapshots` AS
WITH invoices AS (
    SELECT o.order_id, o.customer_id, MAX(s.delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_id, o.customer_id
    HAVING COUNT(s.delivery_date) = COUNT(*)
),
value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
snapshots AS (
    SELECT LAST_DAY(m) AS snapshot_date
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(first_snapshot, MONTH), DATE_TRUNC(as_of, MONTH), INTERVAL 1 MONTH)) AS m
),
paid AS (
    SELECT s.snapshot_date, i.order_id, SUM(IF(p.payment_date <= s.snapshot_date, p.amount, 0)) AS paid_to_date
    FROM snapshots AS s
    JOIN invoices AS i ON i.final_delivery_date <= s.snapshot_date
    LEFT JOIN `sahyadri_b2b.payments` AS p ON p.order_id = i.order_id
    GROUP BY s.snapshot_date, i.order_id
)
SELECT
    p.snapshot_date,
    EXTRACT(YEAR FROM p.snapshot_date) * 12 + EXTRACT(MONTH FROM p.snapshot_date)                     AS month_idx,
    p.order_id, i.customer_id, c.customer_segment, i.final_delivery_date,
    (EXTRACT(YEAR FROM p.snapshot_date) * 12 + EXTRACT(MONTH FROM p.snapshot_date))
      - (EXTRACT(YEAR FROM i.final_delivery_date) * 12 + EXTRACT(MONTH FROM i.final_delivery_date))   AS months_since_delivery,
    LEAST((EXTRACT(YEAR FROM p.snapshot_date) * 12 + EXTRACT(MONTH FROM p.snapshot_date))
      - (EXTRACT(YEAR FROM i.final_delivery_date) * 12 + EXTRACT(MONTH FROM i.final_delivery_date)), default_bucket) AS bucket,
    v.order_value - p.paid_to_date                                                                    AS outstanding
FROM paid AS p
JOIN invoices AS i ON i.order_id = p.order_id
JOIN value AS v ON v.order_id = p.order_id
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = i.customer_id
WHERE v.order_value - p.paid_to_date > 1;

-- One row per open item in buckets 0-5 with its balance one month later
CREATE OR REPLACE TABLE `sahyadri_b2b.ecl_transitions` AS
SELECT
    a.snapshot_date, a.month_idx, a.order_id, a.customer_segment, a.bucket,
    a.outstanding,
    IFNULL(b.outstanding, 0)                                       AS outstanding_next_month
FROM `sahyadri_b2b.ecl_snapshots` AS a
LEFT JOIN `sahyadri_b2b.ecl_snapshots` AS b
  ON b.order_id = a.order_id AND b.month_idx = a.month_idx + 1
WHERE a.bucket < default_bucket
  AND a.snapshot_date < as_of;

-- Roll rates over the whole history, pooled and by segment
SELECT
    bucket,
    COUNT(*)                                                                              AS item_months,
    ROUND(SUM(outstanding) / 1e5, 1)                                                      AS balance_lakh,
    ROUND(100 * SUM(outstanding_next_month) / SUM(outstanding), 1)                        AS roll_rate_all_pct,
    ROUND(100 * SUM(IF(customer_segment = 'Distributor', outstanding_next_month, 0))
              / SUM(IF(customer_segment = 'Distributor', outstanding, 0)), 1)             AS distributor_pct,
    ROUND(100 * SUM(IF(customer_segment = 'Enterprise', outstanding_next_month, 0))
              / SUM(IF(customer_segment = 'Enterprise', outstanding, 0)), 1)              AS enterprise_pct,
    ROUND(100 * SUM(IF(customer_segment = 'Mid-Market', outstanding_next_month, 0))
              / SUM(IF(customer_segment = 'Mid-Market', outstanding, 0)), 1)              AS mid_market_pct,
    ROUND(100 * SUM(IF(customer_segment = 'SMB', outstanding_next_month, 0))
              / SUM(IF(customer_segment = 'SMB', outstanding, 0)), 1)                     AS smb_pct
FROM `sahyadri_b2b.ecl_transitions`
GROUP BY bucket
ORDER BY bucket;

-- Is anything collected after default? Payments received after an item first reached bucket 6
WITH first_default AS (
    SELECT order_id, MIN(snapshot_date) AS default_date, ANY_VALUE(outstanding) AS balance_at_default
    FROM `sahyadri_b2b.ecl_snapshots`
    WHERE months_since_delivery = default_bucket
    GROUP BY order_id
)
SELECT
    COUNT(*)                                                                    AS items_reaching_default,
    ROUND(SUM(d.balance_at_default) / 1e5, 1)                                   AS balance_at_default_lakh,
    ROUND(IFNULL(SUM(p.amount), 0) / 1e5, 2)                                    AS collected_afterwards_lakh,
    ROUND(100 * IFNULL(SUM(p.amount), 0) / SUM(d.balance_at_default), 2)        AS collected_afterwards_pct
FROM first_default AS d
LEFT JOIN (
    SELECT q.order_id, SUM(q.amount) AS amount
    FROM `sahyadri_b2b.payments` AS q
    JOIN first_default AS f ON f.order_id = q.order_id AND q.payment_date > f.default_date
    GROUP BY q.order_id
) AS p ON p.order_id = d.order_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Provision matrices at every month-end
--   history = 'Trailing 12 months' or 'All history to date'
--   scope   = 'All' (pooled) or a customer segment
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ecl_matrix` AS
WITH reporting_dates AS (
    SELECT LAST_DAY(m) AS reporting_date,
           EXTRACT(YEAR FROM m) * 12 + EXTRACT(MONTH FROM m) AS reporting_idx
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(first_reporting, MONTH), DATE_TRUNC(as_of, MONTH), INTERVAL 1 MONTH)) AS m
),
histories AS (
    SELECT 'Trailing 12 months' AS history UNION ALL SELECT 'All history to date'
),
scoped AS (
    SELECT 'All' AS scope, t.* FROM `sahyadri_b2b.ecl_transitions` AS t
    UNION ALL
    SELECT t.customer_segment, t.* FROM `sahyadri_b2b.ecl_transitions` AS t
),
rolls AS (
    -- only transitions completed by the reporting date
    SELECT r.reporting_date, h.history, s.scope, s.bucket,
           SUM(s.outstanding)              AS balance_from,
           SUM(s.outstanding_next_month)   AS balance_rolled
    FROM reporting_dates AS r
    CROSS JOIN histories AS h
    JOIN scoped AS s
      ON s.month_idx + 1 <= r.reporting_idx
     AND (h.history = 'All history to date' OR s.month_idx + 1 >= r.reporting_idx - window_months + 1)
    GROUP BY r.reporting_date, h.history, s.scope, s.bucket
),
rates AS (
    SELECT *, balance_rolled / balance_from AS roll_rate FROM rolls
)
SELECT
    reporting_date, history, scope, bucket, balance_from, balance_rolled, roll_rate,
    -- loss rate = product of the roll rates from this bucket to bucket 5
    EXP(SUM(LN(GREATEST(roll_rate, 1e-12))) OVER (PARTITION BY reporting_date, history, scope ORDER BY bucket DESC
                                                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS loss_rate
FROM rates
UNION ALL
SELECT DISTINCT reporting_date, history, scope, default_bucket, NULL, NULL, NULL, 1.0
FROM rates;

-- -----------------------------------------------------------------------------
-- Step 3 · Provision on every open item under three matrix designs, with the
--          loss that actually followed
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ecl_provision` AS
WITH book AS (
    SELECT s.*
    FROM `sahyadri_b2b.ecl_snapshots` AS s
    WHERE s.snapshot_date BETWEEN first_reporting AND as_of
),
methods AS (
    SELECT 'A. Pooled, trailing 12 months' AS method, 'Trailing 12 months' AS history, FALSE AS by_segment
    UNION ALL SELECT 'B. By segment, all history to date', 'All history to date', TRUE
    UNION ALL SELECT 'C. Pooled, all history to date',    'All history to date', FALSE
)
SELECT
    b.snapshot_date AS reporting_date, m.method, b.order_id, b.customer_segment, b.bucket, b.outstanding,
    x.loss_rate,
    b.outstanding * x.loss_rate                                                       AS provision,
    -- outcome: the balance still unpaid when the item reaches bucket 6
    b.month_idx + (default_bucket - b.bucket)
        <= EXTRACT(YEAR FROM as_of) * 12 + EXTRACT(MONTH FROM as_of)                  AS outcome_known,
    IF(b.bucket = default_bucket, b.outstanding, IFNULL(f.outstanding, 0))            AS actual_loss
FROM book AS b
CROSS JOIN methods AS m
JOIN `sahyadri_b2b.ecl_matrix` AS x
  ON x.reporting_date = b.snapshot_date AND x.bucket = b.bucket AND x.history = m.history
 AND x.scope = IF(m.by_segment, b.customer_segment, 'All')
LEFT JOIN `sahyadri_b2b.ecl_snapshots` AS f
  ON f.order_id = b.order_id AND f.month_idx = b.month_idx + (default_bucket - b.bucket) AND b.bucket < default_bucket;

-- -----------------------------------------------------------------------------
-- Step 4 · Back-test: provision on buckets 0-5 against the loss that followed
-- -----------------------------------------------------------------------------
WITH bt AS (
    SELECT reporting_date, method, SUM(outstanding) AS balance, SUM(provision) AS provision, SUM(actual_loss) AS actual_loss
    FROM `sahyadri_b2b.ecl_provision`
    WHERE bucket < default_bucket
      AND reporting_date <= LAST_DAY(DATE_SUB(as_of, INTERVAL default_bucket MONTH))   -- every bucket's outcome known
    GROUP BY reporting_date, method
)
SELECT
    reporting_date,
    ROUND(MAX(balance) / 1e5, 1)                                                                      AS buckets_0_5_lakh,
    ROUND(MAX(actual_loss) / 1e5, 1)                                                                  AS actual_loss_lakh,
    ROUND(MAX(IF(method LIKE 'A%', provision, NULL)) / 1e5, 1)                                        AS a_provision_lakh,
    ROUND(100 * (MAX(IF(method LIKE 'A%', provision, NULL)) / MAX(actual_loss) - 1), 1)               AS a_error_pct,
    ROUND(100 * (MAX(IF(method LIKE 'B%', provision, NULL)) / MAX(actual_loss) - 1), 1)               AS b_error_pct,
    ROUND(MAX(IF(method LIKE 'C%', provision, NULL)) / 1e5, 1)                                        AS c_provision_lakh,
    ROUND(100 * (MAX(IF(method LIKE 'C%', provision, NULL)) / MAX(actual_loss) - 1), 1)               AS c_error_pct
FROM bt
GROUP BY reporting_date
ORDER BY reporting_date;

WITH bt AS (
    SELECT reporting_date, method, SUM(provision) AS provision, SUM(actual_loss) AS actual_loss
    FROM `sahyadri_b2b.ecl_provision`
    WHERE bucket < default_bucket
      AND reporting_date <= LAST_DAY(DATE_SUB(as_of, INTERVAL default_bucket MONTH))
    GROUP BY reporting_date, method
)
SELECT
    method,
    COUNT(*)                                                                      AS reporting_dates,
    ROUND(SUM(provision) / 1e5, 1)                                                AS total_provision_lakh,
    ROUND(SUM(actual_loss) / 1e5, 1)                                              AS total_actual_loss_lakh,
    ROUND(100 * AVG(ABS(provision / actual_loss - 1)), 1)                         AS mean_abs_error_pct,
    ROUND(100 * AVG(IF(reporting_date <  LAST_DAY(DATE_ADD(first_reporting, INTERVAL 6 MONTH)),
                       ABS(provision / actual_loss - 1), NULL)), 1)               AS mean_abs_error_first_6_months_pct,
    ROUND(100 * AVG(IF(reporting_date >= LAST_DAY(DATE_ADD(first_reporting, INTERVAL 6 MONTH)),
                       ABS(provision / actual_loss - 1), NULL)), 1)               AS mean_abs_error_after_pct,
    COUNTIF(provision < actual_loss)                                              AS months_under_provided,
    ROUND(100 * MIN(provision / actual_loss - 1), 1)                              AS worst_under_pct,
    ROUND(100 * MAX(provision / actual_loss - 1), 1)                              AS worst_over_pct
FROM bt
GROUP BY method
ORDER BY method;

-- Why a trailing window misleads: losses by delivery quarter
WITH invoiced AS (
    SELECT o.order_id, MAX(s.delivery_date) AS final_delivery_date, ANY_VALUE(v.order_value) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    JOIN (SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
          FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id) AS v ON v.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_id
    HAVING COUNT(s.delivery_date) = COUNT(*)
)
SELECT
    DATE_TRUNC(i.final_delivery_date, QUARTER)                                             AS delivery_quarter,
    COUNT(*)                                                                               AS invoices,
    ROUND(SUM(i.order_value) / 1e5, 1)                                                     AS invoiced_lakh,
    ROUND(SUM(IFNULL(d.outstanding, 0)) / 1e5, 1)                                          AS unpaid_at_default_lakh,
    ROUND(100 * SUM(IFNULL(d.outstanding, 0)) / SUM(i.order_value), 2)                     AS loss_rate_pct
FROM invoiced AS i
LEFT JOIN `sahyadri_b2b.ecl_snapshots` AS d
  ON d.order_id = i.order_id AND d.months_since_delivery = default_bucket
WHERE LAST_DAY(DATE_ADD(i.final_delivery_date, INTERVAL 6 MONTH)) <= as_of
GROUP BY delivery_quarter
ORDER BY delivery_quarter;

-- -----------------------------------------------------------------------------
-- Step 5 · The provision on today's book
-- -----------------------------------------------------------------------------
-- The recommended matrix (C. pooled, all history to date) at the reporting date
SELECT
    p.bucket,
    CASE p.bucket WHEN 0 THEN 'Delivered this month' WHEN 6 THEN '6+ months (in default)'
                  ELSE CONCAT(CAST(p.bucket AS STRING), ' month(s) after delivery month') END  AS age,
    ROUND(100 * ANY_VALUE(x.roll_rate), 1)                                             AS roll_rate_pct,
    ROUND(100 * ANY_VALUE(x.loss_rate), 2)                                             AS loss_rate_pct,
    COUNT(*)                                                                            AS open_items,
    ROUND(SUM(p.outstanding) / 1e5, 1)                                                  AS outstanding_lakh,
    ROUND(SUM(p.provision) / 1e5, 1)                                                    AS provision_lakh
FROM `sahyadri_b2b.ecl_provision` AS p
JOIN `sahyadri_b2b.ecl_matrix` AS x
  ON x.reporting_date = p.reporting_date AND x.history = 'All history to date' AND x.scope = 'All' AND x.bucket = p.bucket
WHERE p.reporting_date = as_of AND p.method LIKE 'C%'
GROUP BY p.bucket
ORDER BY p.bucket;

-- Segment loss rates at the reporting date (all history to date)
SELECT
    scope,
    ROUND(100 * MAX(IF(bucket = 0, loss_rate, NULL)), 2)  AS loss_rate_b0_pct,
    ROUND(100 * MAX(IF(bucket = 1, loss_rate, NULL)), 2)  AS loss_rate_b1_pct,
    ROUND(100 * MAX(IF(bucket = 2, loss_rate, NULL)), 2)  AS loss_rate_b2_pct,
    ROUND(100 * MAX(IF(bucket = 3, loss_rate, NULL)), 2)  AS loss_rate_b3_pct,
    ROUND(100 * MAX(IF(bucket = 4, loss_rate, NULL)), 2)  AS loss_rate_b4_pct,
    ROUND(100 * MAX(IF(bucket = 5, loss_rate, NULL)), 2)  AS loss_rate_b5_pct
FROM `sahyadri_b2b.ecl_matrix`
WHERE reporting_date = as_of AND history = 'All history to date'
GROUP BY scope
ORDER BY scope;

-- Total provision under each design, against providing only for items in default
SELECT
    method,
    ROUND(SUM(outstanding) / 1e7, 2)                                                   AS book_crore,
    ROUND(SUM(IF(bucket = default_bucket, outstanding, 0)) / 1e7, 2)                   AS in_default_crore,
    ROUND(SUM(IF(bucket < default_bucket, outstanding, 0)) / 1e5, 1)                   AS buckets_0_5_lakh,
    ROUND(SUM(IF(bucket < default_bucket, provision, 0)) / 1e5, 1)                     AS ecl_on_buckets_0_5_lakh,
    ROUND(SUM(provision) / 1e7, 2)                                                     AS total_provision_crore,
    ROUND(100 * SUM(provision) / SUM(outstanding), 1)                                  AS coverage_pct
FROM `sahyadri_b2b.ecl_provision`
WHERE reporting_date = as_of
GROUP BY method
ORDER BY method;

-- Provision on buckets 0-5 by segment
SELECT
    customer_segment,
    ROUND(SUM(IF(method LIKE 'C%' AND bucket < default_bucket, outstanding, 0)) / 1e5, 1)    AS buckets_0_5_lakh,
    ROUND(SUM(IF(method LIKE 'C%' AND bucket < default_bucket, provision, 0)) / 1e5, 1)      AS ecl_pooled_lakh,
    ROUND(SUM(IF(method LIKE 'B%' AND bucket < default_bucket, provision, 0)) / 1e5, 1)      AS ecl_by_segment_lakh,
    ROUND(SUM(IF(method LIKE 'C%' AND bucket = default_bucket, outstanding, 0)) / 1e5, 1)    AS in_default_lakh
FROM `sahyadri_b2b.ecl_provision`
WHERE reporting_date = as_of
GROUP BY customer_segment
ORDER BY customer_segment;
