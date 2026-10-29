/* =============================================================================
   Case study · Dispatch queue discipline — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE max_gap INT64 DEFAULT 7;

WITH o AS (SELECT * FROM `sahyadri_b2b.fq_orders`),
     p AS (SELECT * FROM `sahyadri_b2b.fq_pairs`),
     e AS (SELECT * FROM `sahyadri_b2b.fq_expected`),
     f AS (SELECT * FROM `sahyadri_b2b.fq_fifo`),

src AS (
    SELECT s.order_id
    FROM `sahyadri_b2b.shipments` AS s
    JOIN `sahyadri_b2b.sales_orders` AS x ON x.order_id = s.order_id
    GROUP BY s.order_id, x.order_date
    HAVING MIN(s.shipment_date) >= x.order_date
),
daily AS (
    SELECT order_date, COUNT(*) AS n FROM o GROUP BY order_date
),
pair_recount AS (
    SELECT SUM(a.n * b.n) AS pairs
    FROM daily AS a
    JOIN daily AS b ON b.order_date > a.order_date AND DATE_DIFF(b.order_date, a.order_date, DAY) <= max_gap
),
dispatch_actual AS (SELECT dispatch_date AS d, COUNT(*) AS n FROM f GROUP BY dispatch_date),
dispatch_fifo   AS (SELECT fifo_dispatch_date AS d, COUNT(*) AS n FROM f GROUP BY fifo_dispatch_date),
fifo_seq AS (
    SELECT fifo_dispatch_date,
           LAG(fifo_dispatch_date) OVER (ORDER BY order_date, order_id) AS prev_dispatch
    FROM f
),

checks AS (
    SELECT '01. One row per order dispatched on or after its order date' AS check_name, 0 AS expected,
           (SELECT COUNT(*) FROM o) - (SELECT COUNT(*) FROM src) + (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM o) AS actual
    UNION ALL
    SELECT '02. Lag = dispatch date - order date, never negative', 0,
           (SELECT COUNTIF(lag_days != DATE_DIFF(dispatch_date, order_date, DAY) OR lag_days < 0) FROM o)
    UNION ALL
    SELECT '03. Pairs = recount from daily order counts', 0,
           (SELECT COUNT(*) FROM p) - (SELECT pairs FROM pair_recount)
    UNION ALL
    SELECT '04. Overtaken exactly when earlier lag - later lag > gap', 0,
           (SELECT COUNTIF(overtaken != (earlier_lag - later_lag > gap_days) OR same_day != (earlier_lag - later_lag = gap_days)) FROM p)
    UNION ALL
    SELECT '05. Expected probabilities lie in 0-1 and fall as the gap grows', 0,
           (SELECT COUNTIF(expected_overtaken < 0 OR expected_overtaken + expected_same_day > 1) FROM e)
         + (SELECT COUNTIF(expected_overtaken > prev + 1e-12) FROM (SELECT expected_overtaken, LAG(expected_overtaken) OVER (ORDER BY gap_days) AS prev FROM e) WHERE prev IS NOT NULL)
    UNION ALL
    SELECT '06. FIFO keeps the number of dispatches on every day', 0,
           (SELECT COUNT(*) FROM dispatch_actual AS a FULL OUTER JOIN dispatch_fifo AS b ON b.d = a.d WHERE IFNULL(a.n, 0) != IFNULL(b.n, 0))
    UNION ALL
    SELECT '07. Under FIFO no earlier order leaves after a later one', 0,
           (SELECT COUNTIF(fifo_dispatch_date < prev_dispatch) FROM fifo_seq)
    UNION ALL
    SELECT '08. FIFO never dispatches before the order date', 0,
           (SELECT COUNTIF(fifo_dispatch_date < order_date) FROM f)
    UNION ALL
    SELECT '09. FIFO delivery = FIFO dispatch + actual transit', 0,
           (SELECT COUNTIF(DATE_DIFF(fifo_delivery_date, fifo_dispatch_date, DAY) != DATE_DIFF(final_delivery_date, dispatch_date, DAY))
              FROM f WHERE final_delivery_date IS NOT NULL)
    UNION ALL
    SELECT '10. Total waiting days are the same under both policies', 0,
           (SELECT SUM(lag_days) - SUM(fifo_lag_days) FROM f)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
