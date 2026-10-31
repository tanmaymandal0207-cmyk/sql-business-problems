/* =============================================================================
   Case study · Dispatch capacity simulation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE sim_start   DATE    DEFAULT DATE '2025-10-01';
DECLARE sim_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE hold_days   INT64   DEFAULT 7;

WITH a AS (SELECT * FROM `sahyadri_b2b.cs_arrivals`),
     dd AS (SELECT * FROM `sahyadri_b2b.cs_days`),
     w AS (SELECT * FROM `sahyadri_b2b.cs_waits`),

ship AS (SELECT order_id, MIN(shipment_date) AS first_ship FROM `sahyadri_b2b.shipments` GROUP BY order_id),
src AS (
    SELECT o.order_id, o.order_date, DATE_DIFF(s.first_ship, o.order_date, DAY) AS wait
    FROM `sahyadri_b2b.sales_orders` AS o
    LEFT JOIN ship AS s ON s.order_id = o.order_id
    WHERE (s.first_ship >= o.order_date OR (s.first_ship IS NULL AND o.order_status IN ('Pending', 'Processing')))
),
recursion AS (
    SELECT scenario, c, t, a_t, d_t, LAG(d_t) OVER (PARTITION BY scenario, c ORDER BY t) AS d_prev FROM dd
),
fifo AS (
    SELECT scenario, c, k, order_date, sim_dispatch_date,
           LAG(sim_dispatch_date) OVER (PARTITION BY scenario, c ORDER BY k) AS prev_dispatch
    FROM w
),
per_day AS (
    SELECT scenario, c, sim_dispatch_date AS d, COUNT(*) AS n FROM w GROUP BY scenario, c, sim_dispatch_date
),

checks AS (
    SELECT '01. Today = every queue order placed in the 12 months, 2027 = today + copies' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM a WHERE scenario = 'Today') - (SELECT COUNT(*) FROM src WHERE order_date BETWEEN sim_start AND sim_end))
         + ABS((SELECT COUNT(*) FROM a WHERE scenario = '2027' AND copy_no = 0) - (SELECT COUNT(*) FROM a WHERE scenario = 'Today'))
         + (SELECT COUNTIF(copy_no NOT IN (0, 1)) FROM a) AS actual
    UNION ALL
    SELECT '02. Arrival numbers k run 1..n in date order', 0,
           (SELECT COUNTIF(n != mx OR n != nd) FROM (SELECT scenario, COUNT(*) AS n, MAX(k) AS mx, COUNT(DISTINCT k) AS nd FROM a GROUP BY scenario))
         + (SELECT COUNTIF(order_date < prev_date) FROM (SELECT order_date, LAG(order_date) OVER (PARTITION BY scenario ORDER BY k) AS prev_date FROM a))
    UNION ALL
    SELECT '03. Arrivals by the last day = all arrivals', 0,
           (SELECT COUNT(*) FROM (SELECT scenario, MAX(a_t) AS m FROM dd GROUP BY scenario) AS x
              JOIN (SELECT scenario, COUNT(*) AS n FROM a GROUP BY scenario) AS y USING (scenario) WHERE x.m != y.n)
    UNION ALL
    SELECT '04. Departures follow D(t) = MIN(A(t), D(t-1) + c), starting from D(1) = MIN(A(1), c)', 0,
           (SELECT COUNTIF(d_t != LEAST(a_t, IFNULL(d_prev, 0) + c)) FROM recursion)
    UNION ALL
    SELECT '05. Every arrival leaves exactly once at every capacity', 0,
           (SELECT COUNT(*) FROM (SELECT scenario, c, COUNT(*) AS n, COUNT(DISTINCT k) AS nd FROM w GROUP BY scenario, c) AS x
              JOIN (SELECT scenario, COUNT(*) AS n FROM a GROUP BY scenario) AS y USING (scenario) WHERE x.n != y.n OR x.nd != y.n)
         + ABS(16 - (SELECT COUNT(DISTINCT CONCAT(scenario, CAST(c AS STRING))) FROM w))
    UNION ALL
    SELECT '06. First in, first out, and never before the order date', 0,
           (SELECT COUNTIF(sim_dispatch_date < prev_dispatch OR sim_dispatch_date < order_date) FROM fifo)
    UNION ALL
    SELECT '07. No day ships more than the capacity', 0,
           (SELECT COUNTIF(n > c) FROM per_day)
    UNION ALL
    SELECT '08. Orders leaving each day = D(t) - D(t-1)', 0,
           (SELECT COUNT(*) FROM recursion AS r
              LEFT JOIN per_day AS p ON p.scenario = r.scenario AND p.c = r.c AND p.d = DATE_ADD(sim_start, INTERVAL r.t - 1 DAY)
             WHERE IFNULL(p.n, 0) != r.d_t - IFNULL(r.d_prev, 0))
    UNION ALL
    SELECT '09. Actual waits = first shipment - order date', 0,
           (SELECT COUNT(*) FROM a JOIN src AS s USING (order_id)
             WHERE a.copy_no = 0 AND IFNULL(a.actual_wait, -1) != IFNULL(s.wait, -1))
    UNION ALL
    SELECT '10. 2027 copies = the growth share of today''s orders (within 1 %)', 0,
           IF(ABS((SELECT COUNTIF(copy_no = 1) FROM a) / (SELECT COUNT(*) FROM a WHERE scenario = 'Today')
                  - (SELECT MAX(growth) FROM a)) > 0.01, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
