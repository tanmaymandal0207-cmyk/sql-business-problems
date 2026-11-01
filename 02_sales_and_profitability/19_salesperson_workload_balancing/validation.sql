/* =============================================================================
   Case study · Salesperson workload balancing — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE window_start   DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE history_start  DATE    DEFAULT DATE '2024-10-01';
DECLARE tolerance      FLOAT64 DEFAULT 0.15;

WITH a AS (SELECT * FROM `sahyadri_b2b.wb_accounts`),
     r AS (SELECT * FROM `sahyadri_b2b.wb_reps`),
     c AS (SELECT * FROM `sahyadri_b2b.wb_candidates`),
     m AS (SELECT * FROM `sahyadri_b2b.wb_moves`),
     af AS (SELECT * FROM `sahyadri_b2b.wb_after`),

field AS (
    SELECT o.customer_id, o.employee_id, o.order_date
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = o.employee_id
    WHERE e.department_id = 1 AND e.designation != 'Head of Sales'
),
in_window AS (
    SELECT customer_id, employee_id, COUNT(*) AS n
    FROM field WHERE order_date BETWEEN window_start AND window_end
    GROUP BY customer_id, employee_id
),
contacts AS (
    SELECT DISTINCT customer_id, employee_id FROM field WHERE order_date BETWEEN history_start AND window_end
),

checks AS (
    SELECT '01. One owner per account, accounts = customers with field orders in the window' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM a) - (SELECT COUNT(DISTINCT customer_id) FROM a))
         + ABS((SELECT COUNT(*) FROM a) - (SELECT COUNT(DISTINCT customer_id) FROM in_window)) AS actual
    UNION ALL
    SELECT '02. Account orders add up to all field orders in the window', 0,
           ABS((SELECT SUM(account_orders) FROM a) - (SELECT SUM(n) FROM in_window))
    UNION ALL
    SELECT '03. No salesperson has more orders on an account than its owner', 0,
           (SELECT COUNT(*) FROM a JOIN in_window AS w ON w.customer_id = a.customer_id AND w.employee_id != a.owner_id
             WHERE w.n > a.owner_orders)
    UNION ALL
    SELECT '04. Workloads add up to all account orders, band = average +/- 15 %', 0,
           ABS((SELECT SUM(workload) FROM r) - (SELECT SUM(account_orders) FROM a))
         + (SELECT COUNTIF(ABS(lower_band - average_workload * (1 - tolerance)) > 1e-9
                        OR ABS(upper_band - average_workload * (1 + tolerance)) > 1e-9
                        OR ABS(average_workload - (SELECT AVG(workload) FROM r)) > 1e-9) FROM r)
    UNION ALL
    SELECT '05. Status labels follow the band', 0,
           (SELECT COUNTIF(status != CASE WHEN workload > upper_band THEN 'Over' WHEN workload < lower_band THEN 'Under' ELSE 'In band' END) FROM r)
    UNION ALL
    SELECT '06. Candidates: sender over, receiver below average and a known contact, account fits', 0,
           (SELECT COUNT(*) FROM c
              JOIN r AS s ON s.employee_id = c.sender_id
              JOIN r AS v ON v.employee_id = c.receiver_id
              LEFT JOIN contacts AS k ON k.customer_id = c.customer_id AND k.employee_id = c.receiver_id
             WHERE s.status != 'Over' OR v.workload >= v.average_workload OR k.customer_id IS NULL
                OR c.account_orders > s.upper_band - s.lower_band OR v.workload + c.account_orders > v.upper_band)
    UNION ALL
    SELECT '07. Each account moves at most once, and only as a candidate', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM m)
         + (SELECT COUNT(*) FROM m LEFT JOIN c ON c.customer_id = m.customer_id AND c.receiver_id = m.receiver_id WHERE c.customer_id IS NULL)
    UNION ALL
    SELECT '08. No receiver ends above the band, no sender below it', 0,
           (SELECT COUNTIF((accounts_in > 0 AND after_workload > upper_band) OR (accounts_out > 0 AND after_workload < lower_band)) FROM af)
    UNION ALL
    SELECT '09. Orders and accounts are conserved by the moves', 0,
           ABS((SELECT SUM(after_workload) FROM af) - (SELECT SUM(before_workload) FROM af))
         + ABS((SELECT SUM(after_accounts) FROM af) - (SELECT COUNT(*) FROM a))
         + (SELECT COUNTIF(accounts_in > 0 AND accounts_out > 0) FROM af)
    UNION ALL
    SELECT '10. 15 salespeople, Head of Sales and unassigned orders left out', 0,
           ABS((SELECT COUNT(*) FROM r) - 15)
         + (SELECT COUNT(*) FROM r JOIN `sahyadri_b2b.employees` AS e USING (employee_id) WHERE e.designation = 'Head of Sales' OR e.department_id != 1)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
