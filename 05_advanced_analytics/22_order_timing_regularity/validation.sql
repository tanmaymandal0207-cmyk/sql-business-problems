/* =============================================================================
   Case study · Order timing regularity — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE min_order_days  INT64 DEFAULT 7;
DECLARE simulations     INT64 DEFAULT 200;
DECLARE first_snapshot  DATE  DEFAULT DATE '2024-06-30';
DECLARE last_snapshot   DATE  DEFAULT DATE '2026-08-31';
DECLARE horizon_days    INT64 DEFAULT 30;
DECLARE min_history     INT64 DEFAULT 4;

WITH d AS (SELECT * FROM `sahyadri_b2b.ot_days`),
     c AS (SELECT * FROM `sahyadri_b2b.ot_customers`),
     sim AS (SELECT * FROM `sahyadri_b2b.ot_simulated_cv`),
     r AS (SELECT * FROM `sahyadri_b2b.ot_regularity`),
     sn AS (SELECT * FROM `sahyadri_b2b.ot_snapshots`),

src_days AS (
    SELECT customer_id, COUNT(DISTINCT order_date) AS n
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY customer_id
),
p_recount AS (
    SELECT r.customer_id, r.p_regular, r.p_bursty,
           (1 + COUNTIF(s.cv <= r.cv)) / (1 + COUNT(*)) AS p_reg, (1 + COUNTIF(s.cv >= r.cv)) / (1 + COUNT(*)) AS p_bur
    FROM r JOIN sim AS s USING (customer_id)
    GROUP BY r.customer_id, r.p_regular, r.p_bursty
),
next_recount AS (
    SELECT s.snapshot_date, s.customer_id, s.ordered_next,
           EXISTS (SELECT 1 FROM d WHERE d.customer_id = s.customer_id AND d.order_date > s.snapshot_date
                                     AND DATE_DIFF(d.order_date, s.snapshot_date, DAY) <= horizon_days) AS recount
    FROM sn AS s
),
history_recount AS (
    SELECT x.snapshot_date, COUNT(*) AS n
    FROM (SELECT DISTINCT snapshot_date FROM sn) AS x
    JOIN (SELECT customer_id, order_date FROM d) AS y ON y.order_date <= x.snapshot_date
    GROUP BY x.snapshot_date, y.customer_id
    HAVING COUNT(*) >= min_history
),

checks AS (
    SELECT '01. Order days = distinct valid order dates per customer, numbered 1..n' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM (SELECT customer_id, COUNT(*) AS n, MAX(seq) AS mx FROM d GROUP BY customer_id) AS x
              JOIN src_days AS s USING (customer_id) WHERE x.n != s.n OR x.mx != s.n)
         + ABS((SELECT COUNT(DISTINCT customer_id) FROM d) - (SELECT COUNT(*) FROM src_days)) AS actual
    UNION ALL
    SELECT '02. Gaps = days between consecutive order days, always positive', 0,
           (SELECT COUNTIF(gap IS NULL AND seq != 1) + COUNTIF(gap IS NOT NULL AND seq = 1) + COUNTIF(gap <= 0) FROM d)
    UNION ALL
    SELECT '03. Customers with 7+ order days, mean gap = span / (n - 1), CV recomputed', 0,
           ABS((SELECT COUNT(*) FROM c) - (SELECT COUNTIF(n >= min_order_days) FROM src_days))
         + (SELECT COUNTIF(ABS(c.mean_gap - DATE_DIFF(c.last_day, c.first_day, DAY) / (c.order_days - 1)) > 1e-9
                           OR ABS(c.cv - SQRT(x.m2 - POW(x.m1, 2)) / x.m1) > 1e-9)
              FROM c JOIN (SELECT customer_id, AVG(gap) AS m1, AVG(gap * gap) AS m2 FROM d WHERE gap IS NOT NULL GROUP BY customer_id) AS x
                USING (customer_id))
    UNION ALL
    SELECT '04. 200 random versions per customer, each with n - 1 gaps spanning first to last order', 0,
           (SELECT COUNTIF(k != simulations) FROM (SELECT customer_id, COUNT(*) AS k FROM sim GROUP BY customer_id))
         + (SELECT COUNT(*) FROM sim JOIN c USING (customer_id)
             WHERE sim.gaps != c.order_days - 1 OR ABS(sim.total_gap - DATE_DIFF(c.last_day, c.first_day, DAY)) > 1e-6)
         + ABS((SELECT COUNT(DISTINCT customer_id) FROM sim) - (SELECT COUNT(*) FROM c))
    UNION ALL
    SELECT '05. p-values recounted, and the pattern follows them', 0,
           (SELECT COUNTIF(ABS(p_regular - p_reg) > 1e-12 OR ABS(p_bursty - p_bur) > 1e-12) FROM p_recount)
         + (SELECT COUNTIF(pattern != CASE WHEN p_regular < 0.05 THEN 'More regular than random'
                                           WHEN p_bursty < 0.05 THEN 'Burstier than random' ELSE 'Random-like' END) FROM r)
    UNION ALL
    SELECT '06. Every qualifying customer has exactly one pattern', 0,
           ABS((SELECT COUNT(*) FROM r) - (SELECT COUNT(*) FROM c)) + (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM r)
    UNION ALL
    SELECT '07. Snapshots are month-ends in range, with 4+ order days and no negative silence', 0,
           (SELECT COUNTIF(snapshot_date != LAST_DAY(snapshot_date) OR snapshot_date < first_snapshot OR snapshot_date > last_snapshot
                           OR order_days < min_history OR days_since_last < 0 OR mean_gap_so_far <= 0) FROM sn)
    UNION ALL
    SELECT '08. "Ordered in the next 30 days" = direct recount', 0,
           (SELECT COUNTIF(ordered_next != recount) FROM next_recount)
    UNION ALL
    SELECT '09. Random-ordering expectation = 1 - EXP(-30 / average gap), between 0 and 1', 0,
           (SELECT COUNTIF(ABS(random_expectation - (1 - EXP(-horizon_days / mean_gap_so_far))) > 1e-12
                           OR random_expectation < 0 OR random_expectation > 1) FROM sn)
    UNION ALL
    SELECT '10. Customers per snapshot = recount of customers with 4+ order days to date', 0,
           (SELECT COUNT(*) FROM (SELECT snapshot_date, COUNT(*) AS n FROM sn GROUP BY snapshot_date) AS a
              FULL OUTER JOIN (SELECT snapshot_date, COUNT(*) AS n FROM history_recount GROUP BY snapshot_date) AS b USING (snapshot_date)
             WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
