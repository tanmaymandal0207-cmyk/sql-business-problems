/* =============================================================================
   Case study · Salesperson workload balancing with the fewest account moves
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The Head of Sales hears two complaints: some salespeople say they are
   drowning in orders, while others have time on their hands. Before the
   new financial year he wants to rebalance account ownership, but without
   breaking customer relationships or reshuffling the whole book. He asks:
     1. How uneven is the workload, and does a heavy load hurt order
        outcomes?
     2. Which accounts could move, to whom, so that every salesperson ends
        within 15 % of the average?
     3. How few moves does it take, and can every move go to someone the
        customer already knows?
     4. What does the rebalanced book look like?

   METHOD
     - Window: orders placed 1 Oct 2025 - 30 Sep 2026 by the 15 field
       salespeople (the Head of Sales and unassigned orders are left out).
     - Account owner: the salesperson with the most orders on the account
       in the window (ties: latest order, then lowest ID).
     - Workload: all orders on the accounts a salesperson owns (one owner
       per account). Band: average +/- 15 %.
     - Load and outcomes: month by month, each salesperson's orders against
       their cancellation and return rate, measured against their own
       average (so that differences between people do not count).
     - Rebalancing (greedy, one pass):
         Candidates  accounts of salespeople above the band, small enough
                     (orders <= band width) that one move cannot jump the
                     band, going to a salesperson below the average who
                     has booked at least one order for that customer since
                     1 Oct 2024 (a known contact). Best receiver = highest
                     share of the customer's orders, then lightest load.
         Sender      largest accounts first, until the excess is covered.
         Receiver    takes moves, largest first, while it stays within
                     the band.
   ============================================================================= */

DECLARE window_start   DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE history_start  DATE    DEFAULT DATE '2024-10-01';
DECLARE tolerance      FLOAT64 DEFAULT 0.15;

-- -----------------------------------------------------------------------------
-- Step 1 · Accounts and their owners
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.wb_accounts` AS
WITH field_orders AS (
    SELECT o.order_id, o.customer_id, o.employee_id, o.order_date, o.order_status
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = o.employee_id
    WHERE e.department_id = 1 AND e.designation != 'Head of Sales'
      AND o.order_date BETWEEN window_start AND window_end
),
order_value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS value
    FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id
),
by_rep AS (
    SELECT f.customer_id, f.employee_id, COUNT(*) AS orders, MAX(f.order_date) AS last_order,
           SUM(IF(f.order_status NOT IN ('Cancelled', 'Returned'), IFNULL(v.value, 0), 0)) AS revenue
    FROM field_orders AS f LEFT JOIN order_value AS v ON v.order_id = f.order_id
    GROUP BY f.customer_id, f.employee_id
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY orders DESC, last_order DESC, employee_id) AS rk,
           SUM(orders)  OVER (PARTITION BY customer_id) AS account_orders,
           SUM(revenue) OVER (PARTITION BY customer_id) AS account_revenue,
           COUNT(*)     OVER (PARTITION BY customer_id) AS salespeople_on_account
    FROM by_rep
)
SELECT
    r.customer_id, c.customer_segment, c.state,
    r.employee_id                                                                    AS owner_id,
    r.orders                                                                         AS owner_orders,
    r.account_orders, r.account_revenue, r.salespeople_on_account
FROM ranked AS r
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = r.customer_id
WHERE r.rk = 1;

-- -----------------------------------------------------------------------------
-- Step 2 · Workload by salesperson, and does load hurt outcomes?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.wb_reps` AS
WITH loads AS (
    SELECT owner_id AS employee_id, COUNT(*) AS accounts, SUM(account_orders) AS workload, SUM(account_revenue) AS revenue
    FROM `sahyadri_b2b.wb_accounts` GROUP BY owner_id
)
SELECT
    l.*, e.employee_name, e.designation,
    AVG(l.workload) OVER ()                                                          AS average_workload,
    AVG(l.workload) OVER () * (1 - tolerance)                                             AS lower_band,
    AVG(l.workload) OVER () * (1 + tolerance)                                             AS upper_band,
    CASE WHEN l.workload > AVG(l.workload) OVER () * (1 + tolerance) THEN 'Over'
         WHEN l.workload < AVG(l.workload) OVER () * (1 - tolerance) THEN 'Under' ELSE 'In band' END AS status
FROM loads AS l
JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = l.employee_id;

SELECT
    employee_id, employee_name, designation, accounts, workload,
    ROUND(revenue / 1e5, 1)                                                          AS revenue_lakh,
    ROUND(workload / average_workload, 2)                                            AS workload_index,
    status
FROM `sahyadri_b2b.wb_reps`
ORDER BY workload DESC;

SELECT
    COUNT(*)                                                                         AS salespeople,
    ROUND(AVG(workload), 1)                                                          AS average_workload,
    MIN(workload)                                                                    AS lightest,
    MAX(workload)                                                                    AS heaviest,
    ROUND(STDDEV_POP(workload) / AVG(workload), 3)                                   AS coefficient_of_variation,
    COUNTIF(status = 'Over')                                                         AS over_band,
    COUNTIF(status = 'Under')                                                        AS under_band,
    ROUND(SUM(IF(status = 'Over', workload - upper_band, 0)), 1)                     AS excess_orders_over_band
FROM `sahyadri_b2b.wb_reps`;

-- Load and outcomes: busy months against each salesperson's own average
WITH monthly AS (
    SELECT o.employee_id, DATE_TRUNC(o.order_date, MONTH) AS month, COUNT(*) AS orders,
           COUNTIF(o.order_status IN ('Cancelled', 'Returned')) / COUNT(*) AS bad_rate
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.wb_reps` AS r ON r.employee_id = o.employee_id
    WHERE o.order_date BETWEEN history_start AND window_end
    GROUP BY o.employee_id, month
),
deviations AS (
    SELECT *, orders - AVG(orders) OVER (PARTITION BY employee_id) AS orders_dev,
              bad_rate - AVG(bad_rate) OVER (PARTITION BY employee_id) AS bad_dev
    FROM monthly
),
centred AS (
    SELECT *, NTILE(4) OVER (ORDER BY orders_dev, employee_id, month) AS busy_quartile FROM deviations
)
SELECT
    busy_quartile,
    COUNT(*)                                                                         AS salesperson_months,
    SUM(orders)                                                                      AS orders,
    ROUND(AVG(orders_dev), 1)                                                        AS orders_vs_own_average,
    ROUND(100 * SUM(bad_rate * orders) / SUM(orders), 1)                             AS cancelled_or_returned_pct,
    ROUND(ANY_VALUE(r), 3)                                                           AS within_person_correlation
FROM centred
CROSS JOIN (SELECT CORR(orders_dev, bad_dev) AS r FROM centred)
GROUP BY busy_quartile
ORDER BY busy_quartile;

-- -----------------------------------------------------------------------------
-- Step 3 · Candidate moves to a known contact
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.wb_candidates` AS
WITH history AS (
    SELECT o.customer_id, o.employee_id, COUNT(*) AS orders
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.wb_reps` AS r ON r.employee_id = o.employee_id
    WHERE o.order_date BETWEEN history_start AND window_end
    GROUP BY o.customer_id, o.employee_id
),
history_total AS (
    SELECT customer_id, SUM(orders) AS orders FROM history GROUP BY customer_id
),
pairs AS (
    SELECT
        a.customer_id, a.owner_id AS sender_id, a.account_orders, a.account_revenue,
        s.workload AS sender_workload, s.upper_band, s.lower_band, s.average_workload,
        h.employee_id AS receiver_id, rv.workload AS receiver_workload,
        h.orders AS receiver_history_orders,
        h.orders / t.orders AS relationship_share
    FROM `sahyadri_b2b.wb_accounts` AS a
    JOIN `sahyadri_b2b.wb_reps` AS s ON s.employee_id = a.owner_id AND s.status = 'Over'
    JOIN history AS h ON h.customer_id = a.customer_id AND h.employee_id != a.owner_id
    JOIN `sahyadri_b2b.wb_reps` AS rv ON rv.employee_id = h.employee_id AND rv.workload < rv.average_workload
    JOIN history_total AS t ON t.customer_id = a.customer_id
    WHERE a.account_orders <= s.upper_band - s.lower_band
      AND rv.workload + a.account_orders <= s.upper_band
)
SELECT * EXCEPT (rk)
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY receiver_workload, relationship_share DESC, receiver_id) AS rk
    FROM pairs
)
WHERE rk = 1;

-- -----------------------------------------------------------------------------
-- Step 4 · Greedy selection: senders shed their largest accounts, receivers stay in band
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.wb_moves` AS
WITH sender_pick AS (
    SELECT *,
           SUM(account_orders) OVER (PARTITION BY sender_id ORDER BY account_orders DESC, customer_id
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS shed_before
    FROM `sahyadri_b2b.wb_candidates`
),
picked AS (
    SELECT * FROM sender_pick WHERE IFNULL(shed_before, 0) < sender_workload - upper_band
),
receiver_check AS (
    SELECT *,
           SUM(account_orders) OVER (PARTITION BY receiver_id ORDER BY account_orders DESC, customer_id
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS received_so_far
    FROM picked
)
SELECT customer_id, sender_id, receiver_id, account_orders, account_revenue, relationship_share, receiver_history_orders
FROM receiver_check
WHERE receiver_workload + received_so_far <= upper_band;

-- -----------------------------------------------------------------------------
-- Step 5 · The rebalanced book
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.wb_after` AS
SELECT
    r.employee_id, r.employee_name, r.designation, r.lower_band, r.upper_band, r.average_workload,
    r.workload                                                                       AS before_workload,
    r.accounts                                                                       AS before_accounts,
    IFNULL(o.accounts_out, 0)                                                        AS accounts_out,
    IFNULL(i.accounts_in, 0)                                                         AS accounts_in,
    r.workload - IFNULL(o.orders_out, 0) + IFNULL(i.orders_in, 0)                    AS after_workload,
    r.accounts - IFNULL(o.accounts_out, 0) + IFNULL(i.accounts_in, 0)                AS after_accounts
FROM `sahyadri_b2b.wb_reps` AS r
LEFT JOIN (SELECT sender_id, COUNT(*) AS accounts_out, SUM(account_orders) AS orders_out FROM `sahyadri_b2b.wb_moves` GROUP BY sender_id) AS o
  ON o.sender_id = r.employee_id
LEFT JOIN (SELECT receiver_id, COUNT(*) AS accounts_in, SUM(account_orders) AS orders_in FROM `sahyadri_b2b.wb_moves` GROUP BY receiver_id) AS i
  ON i.receiver_id = r.employee_id;

SELECT employee_id, employee_name, designation, before_workload, accounts_out, accounts_in, after_workload,
       CASE WHEN after_workload > upper_band THEN 'Over' WHEN after_workload < lower_band THEN 'Under' ELSE 'In band' END AS after_status
FROM `sahyadri_b2b.wb_after`
ORDER BY before_workload DESC;

SELECT
    (SELECT COUNT(*) FROM `sahyadri_b2b.wb_accounts`)                                AS accounts,
    (SELECT COUNT(*) FROM `sahyadri_b2b.wb_candidates`)                              AS candidate_accounts,
    (SELECT COUNT(*) FROM `sahyadri_b2b.wb_moves`)                                   AS accounts_moved,
    (SELECT SUM(account_orders) FROM `sahyadri_b2b.wb_moves`)                        AS orders_moved,
    (SELECT ROUND(SUM(account_revenue) / 1e5, 1) FROM `sahyadri_b2b.wb_moves`)       AS revenue_moved_lakh,
    (SELECT ROUND(100 * AVG(relationship_share), 1) FROM `sahyadri_b2b.wb_moves`)    AS avg_receiver_share_of_history_pct,
    (SELECT MIN(receiver_history_orders) FROM `sahyadri_b2b.wb_moves`)               AS min_receiver_history_orders,
    ROUND(STDDEV_POP(before_workload) / AVG(before_workload), 3)                     AS cv_before,
    ROUND(STDDEV_POP(after_workload) / AVG(after_workload), 3)                       AS cv_after,
    MIN(before_workload)                                                             AS lightest_before,
    MAX(before_workload)                                                             AS heaviest_before,
    MIN(after_workload)                                                              AS lightest_after,
    MAX(after_workload)                                                              AS heaviest_after,
    COUNTIF(before_workload BETWEEN lower_band AND upper_band)                       AS in_band_before,
    COUNTIF(after_workload BETWEEN lower_band AND upper_band)                        AS in_band_after
FROM `sahyadri_b2b.wb_after`;

-- The moves
SELECT m.customer_id, c.customer_name, a.customer_segment, a.state, m.sender_id, m.receiver_id, m.account_orders,
       ROUND(m.account_revenue / 1e5, 1) AS revenue_lakh, m.receiver_history_orders, ROUND(100 * m.relationship_share, 1) AS receiver_share_pct
FROM `sahyadri_b2b.wb_moves` AS m
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = m.customer_id
JOIN `sahyadri_b2b.wb_accounts` AS a ON a.customer_id = m.customer_id
ORDER BY m.sender_id, m.account_orders DESC;

-- What is left: for each salesperson still outside the band, the smallest known-contact
-- move that would bring them in without pushing the other side out
WITH owners_after AS (
    SELECT a.customer_id, a.account_orders, IFNULL(m.receiver_id, a.owner_id) AS owner_id
    FROM `sahyadri_b2b.wb_accounts` AS a LEFT JOIN `sahyadri_b2b.wb_moves` AS m ON m.customer_id = a.customer_id
),
contacts AS (
    SELECT DISTINCT o.customer_id, o.employee_id
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.wb_reps` AS r ON r.employee_id = o.employee_id
    WHERE o.order_date BETWEEN history_start AND window_end
),
options AS (
    -- give away: the salesperson is over the band
    SELECT x.employee_id, 'Over' AS status, x.after_workload - x.upper_band AS gap, oa.customer_id, oa.account_orders, y.employee_id AS other_id
    FROM `sahyadri_b2b.wb_after` AS x
    JOIN owners_after AS oa ON oa.owner_id = x.employee_id
    JOIN contacts AS ct ON ct.customer_id = oa.customer_id AND ct.employee_id != x.employee_id
    JOIN `sahyadri_b2b.wb_after` AS y ON y.employee_id = ct.employee_id
    WHERE x.after_workload > x.upper_band
      AND x.after_workload - oa.account_orders BETWEEN x.lower_band AND x.upper_band
      AND y.after_workload + oa.account_orders <= y.upper_band
    UNION ALL
    -- take over: the salesperson is under the band
    SELECT x.employee_id, 'Under', x.lower_band - x.after_workload, oa.customer_id, oa.account_orders, y.employee_id
    FROM `sahyadri_b2b.wb_after` AS x
    JOIN contacts AS ct ON ct.employee_id = x.employee_id
    JOIN owners_after AS oa ON oa.customer_id = ct.customer_id AND oa.owner_id != x.employee_id
    JOIN `sahyadri_b2b.wb_after` AS y ON y.employee_id = oa.owner_id
    WHERE x.after_workload < x.lower_band
      AND x.after_workload + oa.account_orders BETWEEN x.lower_band AND x.upper_band
      AND y.after_workload - oa.account_orders >= y.lower_band
)
SELECT
    x.employee_id, x.employee_name,
    CASE WHEN x.after_workload > x.upper_band THEN 'Over' ELSE 'Under' END           AS status,
    ROUND(ABS(IF(x.after_workload > x.upper_band, x.after_workload - x.upper_band, x.lower_band - x.after_workload)), 1) AS orders_outside_band,
    COUNT(DISTINCT op.customer_id)                                                   AS closing_accounts_available,
    MIN(op.account_orders)                                                           AS smallest_closing_account_orders
FROM `sahyadri_b2b.wb_after` AS x
LEFT JOIN options AS op ON op.employee_id = x.employee_id
WHERE x.after_workload NOT BETWEEN x.lower_band AND x.upper_band
GROUP BY x.employee_id, x.employee_name, x.after_workload, x.upper_band, x.lower_band
ORDER BY x.employee_id;
