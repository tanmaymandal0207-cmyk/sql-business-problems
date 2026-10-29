/* =============================================================================
   Case study · KPI change-point detection — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE start_month   DATE   DEFAULT DATE '2024-01-01';
DECLARE end_month     DATE   DEFAULT DATE '2026-09-01';
DECLARE min_segment   INT64  DEFAULT 3;
DECLARE permutations  INT64  DEFAULT 500;

WITH c  AS (SELECT * FROM `sahyadri_b2b.chp_series`),
     sg AS (SELECT * FROM `sahyadri_b2b.chp_segments`),
     md AS (SELECT * FROM `sahyadri_b2b.chp_models`),
     pr AS (SELECT * FROM `sahyadri_b2b.chp_prefix`),
     ps AS (SELECT * FROM `sahyadri_b2b.chp_permutation_stats`),

-- check 02 and 03: source recounts by month
src_orders AS (
    SELECT DATE_TRUNC(order_date, MONTH) AS month,
           COUNT(*) AS orders,
           SUM(IF(order_status = 'Cancelled', 1, 0)) AS cancelled,
           SUM(IF(order_status = 'Returned', 1, 0))  AS returned
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_date >= start_month AND order_date < DATE_ADD(end_month, INTERVAL 1 MONTH)
    GROUP BY month
),
src_revenue AS (
    SELECT DATE_TRUNC(o.order_date, MONTH) AS month,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue,
           SUM(i.quantity * i.unit_price) / SUM(i.quantity * p.selling_price)           AS price_factor
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date >= start_month AND o.order_date < DATE_ADD(end_month, INTERVAL 1 MONTH)
    GROUP BY month
),
-- check 04: segment SSE computed directly from the series
seg_direct AS (
    SELECT g.kpi_no, g.first_t, g.last_t, g.sse, g.mean_y,
           SUM(POW(c.y - g.mean_y, 2)) AS sse_direct, AVG(c.y) AS mean_direct
    FROM sg AS g
    JOIN c ON c.kpi_no = g.kpi_no AND c.t BETWEEN g.first_t AND g.last_t
    GROUP BY g.kpi_no, g.first_t, g.last_t, g.sse, g.mean_y
),
-- check 05: no-change and trend SSE from population variance and correlation
moments AS (
    SELECT kpi_no, COUNT(*) * VAR_POP(y) AS sst, COUNT(*) * VAR_POP(y) * (1 - POW(CORR(t, y), 2)) AS sse_trend
    FROM c
    GROUP BY kpi_no
),
-- check 06: brute-force best single break without prefix sums
break_candidates AS (
    SELECT DISTINCT kpi_no, t AS break_t FROM c
),
break_sides AS (
    SELECT b.kpi_no, b.break_t, c.t, c.y,
           AVG(c.y) OVER (PARTITION BY b.kpi_no, b.break_t, c.t >= b.break_t) AS side_mean,
           COUNT(*) OVER (PARTITION BY b.kpi_no, b.break_t, c.t >= b.break_t) AS side_n
    FROM break_candidates AS b
    JOIN c ON c.kpi_no = b.kpi_no
),
break_sse AS (
    SELECT kpi_no, break_t, SUM(POW(y - side_mean, 2)) AS sse,
           ROW_NUMBER() OVER (PARTITION BY kpi_no ORDER BY SUM(POW(y - side_mean, 2)), break_t) AS rk
    FROM break_sides
    GROUP BY kpi_no, break_t
    HAVING MIN(side_n) >= min_segment AND COUNT(DISTINCT IF(t >= break_t, 1, 0)) = 2
),
-- check 07: models side by side
wide AS (
    SELECT kpi_no, ANY_VALUE(n) AS n,
           MAX(IF(model LIKE 'M0%', sse, NULL)) AS sse0, MAX(IF(model LIKE 'T%', sse, NULL)) AS sse_t,
           MAX(IF(model LIKE 'M1%', sse, NULL)) AS sse1, MAX(IF(model LIKE 'M2%', sse, NULL)) AS sse2,
           MAX(IF(model LIKE 'M1%', break_1, NULL)) AS m1_break,
           MAX(IF(model LIKE 'M2%', break_1, NULL)) AS m2_break_1, MAX(IF(model LIKE 'M2%', break_2, NULL)) AS m2_break_2
    FROM md
    GROUP BY kpi_no
),

checks AS (
    SELECT '01. 33 consecutive months per KPI, one row each' AS check_name, 0 AS expected,
           (SELECT COUNTIF(n != DATE_DIFF(end_month, start_month, MONTH) + 1 OR min_t != 1 OR max_t != n OR distinct_t != n)
              FROM (SELECT kpi_no, COUNT(*) AS n, MIN(t) AS min_t, MAX(t) AS max_t, COUNT(DISTINCT t) AS distinct_t FROM c GROUP BY kpi_no))
         + ABS(10 - (SELECT COUNT(DISTINCT kpi_no) FROM c)) AS actual
    UNION ALL
    SELECT '02. Orders, cancellations and returns = source recount', 0,
           (SELECT COUNTIF(ABS(o.value - s.orders) > 1e-9
                        OR ABS(k.value - s.cancelled / s.orders) > 1e-9
                        OR ABS(r.value - s.returned / s.orders) > 1e-9)
              FROM src_orders AS s
              JOIN c AS o ON o.month = s.month AND o.kpi_no = 2
              JOIN c AS k ON k.month = s.month AND k.kpi_no = 7
              JOIN c AS r ON r.month = s.month AND r.kpi_no = 8)
         + ABS(33 - (SELECT COUNT(*) FROM src_orders))
    UNION ALL
    SELECT '03. Net revenue and price factor = source recount', 0,
           (SELECT COUNTIF(ABS(v.value - s.revenue) > 0.01 OR ABS(f.value - s.price_factor) > 1e-12)
              FROM src_revenue AS s
              JOIN c AS v ON v.month = s.month AND v.kpi_no = 4
              JOIN c AS f ON f.month = s.month AND f.kpi_no = 1)
    UNION ALL
    SELECT '04. Every segment mean and SSE = direct recount', 0,
           (SELECT COUNTIF(ABS(sse - sse_direct) > 1e-9 * (1 + sse_direct) OR ABS(mean_y - mean_direct) > 1e-9 * (1 + ABS(mean_direct))) FROM seg_direct)
         + (SELECT COUNTIF(months < min_segment) FROM sg)
    UNION ALL
    SELECT '05. No-change and trend SSE = recount from VAR_POP and CORR', 0,
           (SELECT COUNTIF(ABS(w.sse0 - m.sst) > 1e-9 * (1 + m.sst) OR ABS(w.sse_t - m.sse_trend) > 1e-9 * (1 + m.sse_trend))
              FROM wide AS w JOIN moments AS m ON m.kpi_no = w.kpi_no)
    UNION ALL
    SELECT '06. One-shift model = brute-force best break', 0,
           (SELECT COUNTIF(ABS(w.sse1 - b.sse) > 1e-9 * (1 + b.sse) OR w.m1_break != b.break_t)
              FROM wide AS w JOIN break_sse AS b ON b.kpi_no = w.kpi_no AND b.rk = 1)
    UNION ALL
    SELECT '07. SSE: two shifts <= one shift <= no change, trend <= no change, every level 3+ months', 0,
           (SELECT COUNTIF(sse2 > sse1 + 1e-12 OR sse1 > sse0 + 1e-12 OR sse_t > sse0 + 1e-12
                           OR m1_break - 1 < min_segment OR n - m1_break + 1 < min_segment
                           OR m2_break_1 - 1 < min_segment OR m2_break_2 - m2_break_1 < min_segment
                           OR n - m2_break_2 + 1 < min_segment) FROM wide)
    UNION ALL
    SELECT '08. BIC recomputed, and one chosen model per KPI', 0,
           (SELECT COUNTIF(ABS(bic - (n * LN(sse / n) + params * LN(n))) > 1e-9) FROM md)
         + (SELECT COUNTIF(chosen != 1) FROM (SELECT kpi_no, COUNTIF(bic_rank = 1) AS chosen FROM md GROUP BY kpi_no))
         + ABS(40 - (SELECT COUNT(*) FROM md))
    UNION ALL
    SELECT '09. 500 permutations per KPI, explained variance between 0 and 1', 0,
           (SELECT COUNTIF(reps != permutations) FROM (SELECT kpi_no, COUNT(*) AS reps FROM ps GROUP BY kpi_no))
         + (SELECT COUNTIF(r2_best_shift < -1e-12 OR r2_best_shift > 1 + 1e-12) FROM ps)
         + ABS(10 - (SELECT COUNT(DISTINCT kpi_no) FROM ps))
    UNION ALL
    SELECT '10. Known truth: price factor shifts in January 2025 and January 2026 only', 0,
           (SELECT COUNTIF(NOT (m.model LIKE 'M2%' AND b1.month = DATE '2025-01-01' AND b2.month = DATE '2026-01-01'))
              FROM md AS m
              JOIN c AS b1 ON b1.kpi_no = m.kpi_no AND b1.t = m.break_1
              JOIN c AS b2 ON b2.kpi_no = m.kpi_no AND b2.t = m.break_2
             WHERE m.kpi_no = 1 AND m.bic_rank = 1)
         + ABS(1 - (SELECT COUNT(*) FROM md WHERE kpi_no = 1 AND bic_rank = 1 AND model LIKE 'M2%'))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
