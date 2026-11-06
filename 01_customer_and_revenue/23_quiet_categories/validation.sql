/* =============================================================================
   Case study · Quiet categories — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_day  DATE  DEFAULT DATE '2024-01-01';
DECLARE last_day   DATE  DEFAULT DATE '2026-09-30';
DECLARE n_quarters INT64 DEFAULT 11;

WITH p AS (SELECT * FROM `sahyadri_b2b.qc_panel`),
     e AS (SELECT * FROM `sahyadri_b2b.qc_events`),

src AS (
    SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN first_day AND last_day
),
src_quarter AS (
    -- customer revenue by calendar quarter, straight from the source
    SELECT o.customer_id, DATE_TRUNC(o.order_date, QUARTER) AS qd,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN first_day AND last_day
    GROUP BY o.customer_id, qd
),
panel_quarter AS (
    SELECT customer_id, DATE_ADD(first_day, INTERVAL 3 * q MONTH) AS qd, SUM(value) AS v, LOGICAL_OR(customer_active) AS active
    FROM p GROUP BY customer_id, q
),
recount AS (
    -- each event recounted from the panel with self-joins
    SELECT e.customer_id, e.category_id, e.start_q,
           ANY_VALUE(e.prior_quarters) AS prior_quarters, ANY_VALUE(e.quiet) AS quiet, ANY_VALUE(e.next_purchase_q) AS next_purchase_q,
           ANY_VALUE(e.prior_value) AS prior_value,
           COUNTIF(x.q BETWEEN e.start_q - 4 AND e.start_q - 1 AND x.value > 0)          AS prior_q2,
           SUM(IF(x.q BETWEEN e.start_q - 4 AND e.start_q - 1, x.value, 0))              AS prior_v2,
           COUNTIF(x.q = e.start_q - 1 AND x.value > 0)                                  AS bought_last_quarter,
           COUNTIF(x.q BETWEEN e.start_q AND e.start_q + 2 AND x.value > 0)              AS bought_spell,
           COUNTIF(x.q BETWEEN e.start_q AND e.start_q + 2 AND x.customer_active)        AS active_spell,
           MIN(IF(x.q > e.start_q + 2 AND x.value > 0, x.q, NULL))                       AS next_q2
    FROM e JOIN p AS x ON x.customer_id = e.customer_id AND x.category_id = e.category_id
    GROUP BY e.customer_id, e.category_id, e.start_q
),
rate AS (
    SELECT customer_id, category_id, COUNTIF(value > 0) / COUNTIF(customer_active) AS r FROM p GROUP BY customer_id, category_id
),

checks AS (
    SELECT '01. Panel revenue = source revenue' AS check_name, 0 AS expected,
           IF(ABS((SELECT SUM(value) FROM p) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Every pair has one row for each of the 11 quarters', 0,
           (SELECT COUNT(*) FROM (SELECT customer_id, category_id, COUNT(*) AS n, COUNT(DISTINCT q) AS dq, MIN(q) AS lo, MAX(q) AS hi
                                  FROM p GROUP BY customer_id, category_id)
             WHERE n != n_quarters OR dq != n_quarters OR lo != 0 OR hi != n_quarters - 1)
    UNION ALL
    SELECT '03. Quarter index and customer activity match the calendar quarters of the source', 0,
           (SELECT COUNT(*) FROM panel_quarter AS pq LEFT JOIN src_quarter AS sq USING (customer_id, qd)
             WHERE pq.active != (sq.customer_id IS NOT NULL) OR ABS(pq.v - IFNULL(sq.v, 0)) > 1e-6)
    UNION ALL
    SELECT '04. Events are established pairs: 3+ of the prior 4 quarters, bought in the last one (recount)', 0,
           (SELECT COUNTIF(prior_q2 != prior_quarters OR prior_q2 < 3 OR bought_last_quarter != 1 OR ABS(prior_v2 - prior_value) > 1e-6) FROM recount)
    UNION ALL
    SELECT '05. The customer ordered in all three quarters of every window', 0,
           (SELECT COUNTIF(active_spell != 3) FROM recount)
    UNION ALL
    SELECT '06. Quiet = no purchase of the category in the three quarters (recount)', 0,
           (SELECT COUNTIF(quiet != (bought_spell = 0)) FROM recount)
    UNION ALL
    SELECT '07. Return quarter = first purchase after the spell (recount)', 0,
           (SELECT COUNTIF(IFNULL(next_q2, -1) != IFNULL(next_purchase_q, -1)) FROM recount)
         + (SELECT COUNTIF(came_back != (quiet AND next_purchase_q IS NOT NULL)) FROM e)
    UNION ALL
    SELECT '08. Chance of a quiet spell = (1 - pair buy rate) cubed', 0,
           (SELECT COUNTIF(ABS(e.pair_buy_rate - r.r) > 1e-12 OR ABS(e.chance_quiet - POW(1 - r.r, 3)) > 1e-12)
              FROM e JOIN rate AS r USING (customer_id, category_id))
    UNION ALL
    SELECT '09. Spell starts lie in 2025 Q1 - 2026 Q1 (quarters 4-8)', 0,
           (SELECT COUNTIF(start_q NOT BETWEEN 4 AND n_quarters - 3) FROM e)
         + ABS((SELECT COUNT(DISTINCT start_q) FROM e) - 5)
    UNION ALL
    SELECT '10. Quiet spells of the same pair never overlap', 0,
           (SELECT COUNT(*) FROM e AS a JOIN e AS b
               ON a.customer_id = b.customer_id AND a.category_id = b.category_id AND a.start_q < b.start_q AND b.start_q <= a.start_q + 2
             WHERE a.quiet AND b.quiet)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
