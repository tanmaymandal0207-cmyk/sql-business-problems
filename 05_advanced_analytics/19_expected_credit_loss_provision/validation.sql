/* =============================================================================
   Case study · Expected credit loss provision matrix — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_snapshot  DATE   DEFAULT DATE '2024-01-31';
DECLARE first_reporting DATE   DEFAULT DATE '2025-01-31';
DECLARE as_of           DATE   DEFAULT DATE '2026-09-30';
DECLARE default_bucket  INT64  DEFAULT 6;
DECLARE window_months   INT64  DEFAULT 12;

WITH s AS (SELECT * FROM `sahyadri_b2b.ecl_snapshots`),
     t AS (SELECT * FROM `sahyadri_b2b.ecl_transitions`),
     x AS (SELECT * FROM `sahyadri_b2b.ecl_matrix`),
     p AS (SELECT * FROM `sahyadri_b2b.ecl_provision`),

value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
delivered AS (
    SELECT o.order_id, MAX(sh.delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments` AS sh ON sh.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_id
    HAVING COUNT(sh.delivery_date) = COUNT(*)
),
-- check 01: today's open book rebuilt from source
book_rebuild AS (
    SELECT d.order_id, v.order_value - IFNULL(SUM(pm.amount), 0) AS outstanding
    FROM delivered AS d
    JOIN value AS v ON v.order_id = d.order_id
    LEFT JOIN `sahyadri_b2b.payments` AS pm ON pm.order_id = d.order_id AND pm.payment_date <= as_of
    WHERE d.final_delivery_date <= as_of
    GROUP BY d.order_id, v.order_value
    HAVING v.order_value - IFNULL(SUM(pm.amount), 0) > 1
),
-- check 04: consecutive month-ends of the same item
moves AS (
    SELECT a.bucket AS bucket_now, b.bucket AS bucket_next, a.outstanding AS bal_now, b.outstanding AS bal_next
    FROM s AS a
    JOIN s AS b ON b.order_id = a.order_id AND b.month_idx = a.month_idx + 1
),
-- check 06: roll rates at the reporting date recounted from the snapshots
roll_recount AS (
    SELECT a.bucket, SUM(IFNULL(b.outstanding, 0)) / SUM(a.outstanding) AS roll_rate
    FROM s AS a
    LEFT JOIN s AS b ON b.order_id = a.order_id AND b.month_idx = a.month_idx + 1
    WHERE a.bucket < default_bucket
      AND a.month_idx + 1 BETWEEN EXTRACT(YEAR FROM as_of) * 12 + EXTRACT(MONTH FROM as_of) - window_months + 1
                              AND EXTRACT(YEAR FROM as_of) * 12 + EXTRACT(MONTH FROM as_of)
    GROUP BY a.bucket
),
-- check 07: loss rate = explicit product of later roll rates (no window function)
loss_recount AS (
    SELECT a.reporting_date, a.history, a.scope, a.bucket, a.loss_rate, EXP(SUM(LN(GREATEST(b.roll_rate, 1e-12)))) AS product
    FROM x AS a
    JOIN x AS b ON b.reporting_date = a.reporting_date AND b.history = a.history AND b.scope = a.scope
               AND b.bucket >= a.bucket AND b.bucket < default_bucket
    WHERE a.bucket < default_bucket
    GROUP BY a.reporting_date, a.history, a.scope, a.bucket, a.loss_rate
),
-- check 08: loss rates by bucket in order
loss_seq AS (
    SELECT loss_rate, LAG(loss_rate) OVER (PARTITION BY reporting_date, history, scope ORDER BY bucket) AS prev_loss, bucket
    FROM x
),
-- check 10: the loss that followed, rebuilt from payments
calendar AS (SELECT DISTINCT snapshot_date, month_idx FROM s),
outcome_rebuild AS (
    SELECT b.snapshot_date AS reporting_date,
           SUM(IF(v.order_value - IFNULL(pm.paid, 0) > 1, v.order_value - IFNULL(pm.paid, 0), 0)) AS actual_loss
    FROM s AS b
    JOIN calendar AS c ON c.month_idx = b.month_idx + (default_bucket - b.bucket)
    JOIN value AS v ON v.order_id = b.order_id
    LEFT JOIN (
        SELECT q.order_id, c2.snapshot_date, SUM(q.amount) AS paid
        FROM `sahyadri_b2b.payments` AS q
        JOIN calendar AS c2 ON q.payment_date <= c2.snapshot_date
        GROUP BY q.order_id, c2.snapshot_date
    ) AS pm ON pm.order_id = b.order_id AND pm.snapshot_date = c.snapshot_date
    WHERE b.bucket < default_bucket
      AND b.snapshot_date BETWEEN first_reporting AND LAST_DAY(DATE_SUB(as_of, INTERVAL default_bucket MONTH))
    GROUP BY b.snapshot_date
),
outcome_table AS (
    SELECT reporting_date, SUM(actual_loss) AS actual_loss
    FROM p
    WHERE method LIKE 'C%' AND bucket < default_bucket
      AND reporting_date BETWEEN first_reporting AND LAST_DAY(DATE_SUB(as_of, INTERVAL default_bucket MONTH))
    GROUP BY reporting_date
),

checks AS (
    SELECT '01. Open book at the reporting date = rebuild from source (items and rupees)' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM s WHERE snapshot_date = as_of) - (SELECT COUNT(*) FROM book_rebuild))
         + IF(ABS((SELECT SUM(outstanding) FROM s WHERE snapshot_date = as_of) - (SELECT SUM(outstanding) FROM book_rebuild)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Bucket = calendar months since delivery, capped at 6', 0,
           (SELECT COUNTIF(bucket != LEAST(DATE_DIFF(snapshot_date, final_delivery_date, MONTH), default_bucket)
                           OR months_since_delivery < 0) FROM s)
    UNION ALL
    SELECT '03. One snapshot per month-end, each the last day of a month', 0,
           ABS((SELECT COUNT(DISTINCT snapshot_date) FROM s) - (DATE_DIFF(as_of, first_snapshot, MONTH) + 1))
         + (SELECT COUNTIF(snapshot_date != LAST_DAY(snapshot_date)) FROM s)
         + (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(order_id AS STRING), '|', CAST(snapshot_date AS STRING))) FROM s)
    UNION ALL
    SELECT '04. Items move one bucket a month and balances never rise', 0,
           (SELECT COUNTIF(bucket_next != LEAST(bucket_now + 1, default_bucket) OR bal_next > bal_now + 0.01) FROM moves)
    UNION ALL
    SELECT '05. One transition per open item in buckets 0-5, next balance between 0 and today''s', 0,
           ABS((SELECT COUNT(*) FROM t) - (SELECT COUNT(*) FROM s WHERE bucket < default_bucket AND snapshot_date < as_of))
         + (SELECT COUNTIF(outstanding_next_month < 0 OR outstanding_next_month > outstanding + 0.01) FROM t)
    UNION ALL
    SELECT '06. Trailing-12-month roll rates at the reporting date = recount from snapshots', 0,
           (SELECT COUNTIF(ABS(m.roll_rate - r.roll_rate) > 1e-9)
              FROM x AS m JOIN roll_recount AS r ON r.bucket = m.bucket
             WHERE m.reporting_date = as_of AND m.history = 'Trailing 12 months' AND m.scope = 'All')
         + ABS(6 - (SELECT COUNT(*) FROM roll_recount))
    UNION ALL
    SELECT '07. Loss rate = product of the roll rates from the bucket to bucket 5', 0,
           (SELECT COUNTIF(ABS(loss_rate - product) > 1e-9) FROM loss_recount)
    UNION ALL
    SELECT '08. Loss rates lie in 0-1, rise with age, and bucket 6 = 100 %', 0,
           (SELECT COUNTIF(loss_rate < 0 OR loss_rate > 1 + 1e-12 OR loss_rate < prev_loss - 1e-12
                           OR (bucket = default_bucket AND loss_rate != 1)) FROM loss_seq)
    UNION ALL
    SELECT '09. Three provisions per open item and date, each = balance x loss rate', 0,
           ABS((SELECT COUNT(*) FROM p) - 3 * (SELECT COUNT(*) FROM s WHERE snapshot_date BETWEEN first_reporting AND as_of))
         + (SELECT COUNTIF(ABS(provision - outstanding * loss_rate) > 0.01) FROM p)
    UNION ALL
    SELECT '10. Loss that followed = rebuild from payments, every back-test date', 0,
           (SELECT COUNTIF(ABS(a.actual_loss - b.actual_loss) > 1) FROM outcome_table AS a JOIN outcome_rebuild AS b USING (reporting_date))
         + ABS((SELECT COUNT(*) FROM outcome_table) - (SELECT COUNT(*) FROM outcome_rebuild))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
