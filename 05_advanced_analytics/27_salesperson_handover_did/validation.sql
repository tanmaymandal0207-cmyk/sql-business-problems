/* =============================================================================
   Case study · Salesperson handover difference in differences — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE offset_value FLOAT64 DEFAULT 10000;

WITH w AS (SELECT * FROM `sahyadri_b2b.ho_windows`),
     p AS (SELECT * FROM `sahyadri_b2b.ho_panel`),
     pm AS (SELECT * FROM `sahyadri_b2b.ho_permutations`),
     e AS (SELECT * FROM `sahyadri_b2b.ho_effects`),

-- independent recount for event quarter 5 (2025 Q2): before = 2024 Q2 - 2025 Q1, after = 2025 Q2 - 2026 Q1
src AS (
    SELECT o.customer_id,
           SUM(IF(o.order_date BETWEEN DATE '2024-04-01' AND DATE '2025-03-31', i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100), 0)) AS before_v,
           SUM(IF(o.order_date BETWEEN DATE '2025-04-01' AND DATE '2026-03-31', i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100), 0)) AS after_v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.customer_id
),
before_counts AS (
    SELECT o.customer_id, o.employee_id, COUNT(*) AS n
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.employees` AS em ON em.employee_id = o.employee_id
    WHERE o.order_date BETWEEN DATE '2024-04-01' AND DATE '2025-03-31' AND em.department_id = 1 AND em.designation != 'Head of Sales'
    GROUP BY o.customer_id, o.employee_id
),
cell_means AS (
    SELECT cell, AVG(IF(NOT treated, growth, NULL)) AS control_mean FROM p GROUP BY cell
),

checks AS (
    SELECT '01. One window row per customer and event quarter, all with revenue before' AS check_name, 0 AS expected,
           (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(ev AS STRING))) FROM w)
         + (SELECT COUNTIF(rev_before <= 0) FROM w) AS actual
    UNION ALL
    SELECT '02. Event quarter 2025 Q2: revenue before and after = recount from orders', 0,
           (SELECT COUNTIF(ABS(w.rev_before - s.before_v) > 0.01 OR ABS(w.rev_after - s.after_v) > 0.01)
              FROM w JOIN src AS s USING (customer_id) WHERE w.ev = 5)
    UNION ALL
    SELECT '03. Event quarter 2025 Q2: nobody has more orders than the main salesperson before', 0,
           (SELECT COUNT(*) FROM w
              JOIN before_counts AS m ON m.customer_id = w.customer_id AND m.employee_id = w.rep_before
              JOIN before_counts AS x ON x.customer_id = w.customer_id AND x.employee_id != w.rep_before
             WHERE w.ev = 5 AND (x.n > m.n OR (x.n = m.n AND x.employee_id < m.employee_id)))
    UNION ALL
    SELECT '04. Treated once at their first change, controls never change, once per event quarter', 0,
           -- treated customers appear once; controls once per event quarter (stacked design)
           (SELECT COUNTIF(treated) - COUNT(DISTINCT IF(treated, customer_id, NULL)) FROM p)
         + (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', CAST(ev AS STRING))) FROM p)
         + (SELECT COUNTIF(treated AND (rep_before = rep_after OR ev != (SELECT MIN(ev) FROM w AS x WHERE x.customer_id = p.customer_id AND x.rep_before != x.rep_after))) FROM p)
         + (SELECT COUNTIF(NOT treated AND customer_id IN (SELECT customer_id FROM w WHERE rep_before != rep_after)) FROM p)
    UNION ALL
    SELECT '05. Every cell has treated and control customers', 0,
           (SELECT COUNTIF(t = 0 OR c = 0) FROM (SELECT cell, COUNTIF(treated) AS t, COUNTIF(NOT treated) AS c FROM p GROUP BY cell))
    UNION ALL
    SELECT '06. Growth and pre-trend growth = log formulas', 0,
           (SELECT COUNTIF(ABS(growth - LN((rev_after + offset_value) / (rev_before + offset_value))) > 1e-12
                           OR ABS(pre_growth - LN((rev_before_2 + offset_value) / (rev_before_1 + offset_value))) > 1e-12
                           OR ABS(rev_before - rev_before_1 - rev_before_2) > 0.01) FROM p)
    UNION ALL
    SELECT '07. Size thirds are ordered by revenue before within each event quarter', 0,
           (SELECT COUNT(*) FROM (SELECT ev, size_third, MIN(rev_before) AS lo, MAX(rev_before) AS hi FROM p GROUP BY ev, size_third) AS a
              JOIN (SELECT ev, size_third, MIN(rev_before) AS lo FROM p GROUP BY ev, size_third) AS b
                ON b.ev = a.ev AND b.size_third = a.size_third + 1
             WHERE a.hi > b.lo)
    UNION ALL
    SELECT '08. 500 relabellings, centred near zero', 0,
           ABS((SELECT COUNT(*) FROM pm) - 500) + IF(ABS((SELECT AVG(effect) FROM pm)) > 0.05, 1, 0)
    UNION ALL
    SELECT '09. Effect = average of treated growth minus its cell control mean', 0,
           IF(ABS((SELECT effect FROM e) - (SELECT AVG(p.growth - c.control_mean) FROM p JOIN cell_means AS c USING (cell) WHERE p.treated)) > 1e-12, 1, 0)
    UNION ALL
    SELECT '10. New-hire flag = receiver hired less than a year before the event quarter', 0,
           (SELECT COUNTIF(receiver_new_hire != (DATE_DIFF(DATE_ADD(DATE '2024-01-01', INTERVAL ev * 3 MONTH), receiver_hire_date, DAY) < 365)) FROM p WHERE treated)
         + ABS((SELECT to_new_hires + to_existing FROM e) - (SELECT treated_customers FROM e))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
