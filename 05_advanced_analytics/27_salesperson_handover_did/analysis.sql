/* =============================================================================
   Case study · Does a salesperson handover cost revenue? A difference-in-
   differences test
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The salesperson relationship study found that customers whose main
   salesperson changed lost 7.1 % of revenue while others grew, but warned
   that this was an association: accounts may change hands because they
   were already declining. The workload balancing study now proposes 17
   account moves. Before approving them, the Head of Sales asks:
     1. Comparing like with like, does a handover cost revenue in the year
        after it?
     2. Were the accounts that changed hands already declining before?
     3. Is the result driven by a few large accounts?
     4. Do handovers to newly hired salespeople fare worse?

   METHOD
     - Quarters 2024 Q1 - 2026 Q3. Main salesperson in a window = the
       field salesperson with the most orders (ties: lowest ID).
     - Event quarters 2025 Q1 - 2025 Q4. For each, the year before
       (4 quarters) and the year from the event quarter (4 quarters).
       Treated: the main salesperson of the year after differs from the
       year before (first such event per customer). Control: same main
       salesperson in both years, never treated.
     - Outcome: log growth = ln((revenue after + Rs 10,000) / (revenue
       before + Rs 10,000)), valid orders only.
     - Matching: treated and control customers are compared within cells
       of event quarter x segment x third of revenue in the year before;
       the effect is the treated-weighted average of cell differences
       (difference in differences).
     - Pre-trend test: the same comparison on growth from the first half of
       the year before to its second half.
     - Permutation test: 500 shuffles of the treated label within cells.
   ============================================================================= */

DECLARE offset_value FLOAT64 DEFAULT 10000;
DECLARE shuffles     INT64   DEFAULT 500;
DECLARE prime        INT64   DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Orders by quarter, and windows around each event quarter
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ho_windows` AS
WITH orders AS (
    SELECT o.order_id, o.customer_id, o.order_status,
           IF(e.department_id = 1 AND e.designation != 'Head of Sales', o.employee_id, NULL)   AS salesperson,
           (EXTRACT(YEAR FROM o.order_date) - 2024) * 4 + EXTRACT(QUARTER FROM o.order_date) - 1 AS qi,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))          AS value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    LEFT JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = o.employee_id
    GROUP BY o.order_id, o.customer_id, o.order_status, salesperson, qi
),
events AS (
    SELECT ev FROM UNNEST([4, 5, 6, 7]) AS ev
),
tagged AS (
    SELECT ev.ev, o.*,
           CASE WHEN o.qi BETWEEN ev.ev - 4 AND ev.ev - 3 THEN 'before_1'
                WHEN o.qi BETWEEN ev.ev - 2 AND ev.ev - 1 THEN 'before_2'
                WHEN o.qi BETWEEN ev.ev AND ev.ev + 3 THEN 'after' END                      AS part
    FROM orders AS o CROSS JOIN events AS ev
    WHERE o.qi BETWEEN ev.ev - 4 AND ev.ev + 3
),
rep_counts AS (
    SELECT ev, customer_id, IF(part = 'after', 'after', 'before') AS side, salesperson, COUNT(*) AS n
    FROM tagged WHERE salesperson IS NOT NULL
    GROUP BY ev, customer_id, side, salesperson
),
main_rep AS (
    SELECT ev, customer_id, side, salesperson
    FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY ev, customer_id, side ORDER BY n DESC, salesperson) AS rk FROM rep_counts)
    WHERE rk = 1
),
revenue AS (
    SELECT ev, customer_id,
           SUM(IF(part != 'after' AND order_status NOT IN ('Cancelled', 'Returned'), value, 0))   AS rev_before,
           SUM(IF(part = 'before_1' AND order_status NOT IN ('Cancelled', 'Returned'), value, 0)) AS rev_before_1,
           SUM(IF(part = 'before_2' AND order_status NOT IN ('Cancelled', 'Returned'), value, 0)) AS rev_before_2,
           SUM(IF(part = 'after' AND order_status NOT IN ('Cancelled', 'Returned'), value, 0))    AS rev_after
    FROM tagged GROUP BY ev, customer_id
)
SELECT r.*, b.salesperson AS rep_before, a.salesperson AS rep_after, c.customer_segment
FROM revenue AS r
JOIN main_rep AS b ON b.ev = r.ev AND b.customer_id = r.customer_id AND b.side = 'before'
JOIN main_rep AS a ON a.ev = r.ev AND a.customer_id = r.customer_id AND a.side = 'after'
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = r.customer_id
WHERE r.rev_before > 0;

-- -----------------------------------------------------------------------------
-- Step 2 · Treated and control customers, cells and outcomes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ho_panel` AS
WITH first_change AS (
    SELECT customer_id, MIN(ev) AS ev FROM `sahyadri_b2b.ho_windows` WHERE rep_before != rep_after GROUP BY customer_id
),
units AS (
    SELECT w.*, TRUE AS treated
    FROM `sahyadri_b2b.ho_windows` AS w JOIN first_change AS f USING (customer_id, ev)
    UNION ALL
    SELECT w.*, FALSE
    FROM `sahyadri_b2b.ho_windows` AS w
    WHERE w.rep_before = w.rep_after AND w.customer_id NOT IN (SELECT customer_id FROM first_change)
),
sized AS (
    SELECT *, NTILE(3) OVER (PARTITION BY ev ORDER BY rev_before, customer_id) AS size_third FROM units
),
with_cells AS (
    SELECT *, CONCAT(CAST(ev AS STRING), '|', customer_segment, '|', CAST(size_third AS STRING)) AS cell,
           LN((rev_after + offset_value) / (rev_before + offset_value))              AS growth,
           LN((rev_before_2 + offset_value) / (rev_before_1 + offset_value))         AS pre_growth
    FROM sized
),
usable AS (
    SELECT cell FROM with_cells GROUP BY cell HAVING COUNTIF(treated) > 0 AND COUNTIF(NOT treated) > 0
)
SELECT w.*, h.hire_date AS receiver_hire_date,
       DATE_DIFF(DATE_ADD(DATE '2024-01-01', INTERVAL w.ev * 3 MONTH), h.hire_date, DAY) < 365 AS receiver_new_hire,
       ROW_NUMBER() OVER (PARTITION BY w.cell ORDER BY w.customer_id)                AS cell_no
FROM with_cells AS w
JOIN usable USING (cell)
LEFT JOIN `sahyadri_b2b.employees` AS h ON h.employee_id = w.rep_after;

SELECT
    IF(treated, 'Salesperson changed', 'Same salesperson')                            AS customer_group,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    COUNT(*)                                                                          AS customer_windows,
    ROUND(SUM(rev_before) / 1e7, 2)                                                   AS revenue_before_crore,
    ROUND(SUM(rev_after) / 1e7, 2)                                                    AS revenue_after_crore,
    ROUND(100 * (SUM(rev_after) / SUM(rev_before) - 1), 1)                            AS aggregate_change_pct,
    ROUND(100 * (EXP(AVG(growth)) - 1), 1)                                            AS typical_customer_change_pct
FROM `sahyadri_b2b.ho_panel`
GROUP BY customer_group
ORDER BY customer_group;

-- -----------------------------------------------------------------------------
-- Step 3 · Difference in differences, pre-trend and permutation test
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ho_permutations` AS
WITH cell_sizes AS (
    SELECT cell, COUNTIF(treated) AS n_treated FROM `sahyadri_b2b.ho_panel` GROUP BY cell
),
draws AS (
    SELECT p.cell, p.growth, b,
           ROW_NUMBER() OVER (PARTITION BY b, p.cell
                              ORDER BY MOD(MOD(b * 7919 + p.customer_id * 104729 + p.ev * 1299709, prime)
                                         * MOD(b * 7919 + p.customer_id * 104729 + p.ev * 1299709, prime) + 12345, prime)) AS rk
    FROM `sahyadri_b2b.ho_panel` AS p
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, shuffles)) AS b
),
relabelled AS (
    SELECT d.b, d.cell, d.growth, d.rk <= s.n_treated AS fake_treated, s.n_treated
    FROM draws AS d JOIN cell_sizes AS s USING (cell)
),
cell_diffs AS (
    SELECT b, cell, ANY_VALUE(n_treated) AS n_treated,
           AVG(IF(fake_treated, growth, NULL)) - AVG(IF(NOT fake_treated, growth, NULL)) AS diff
    FROM relabelled GROUP BY b, cell
)
SELECT b, SUM(n_treated * diff) / SUM(n_treated) AS effect
FROM cell_diffs GROUP BY b;

CREATE OR REPLACE TABLE `sahyadri_b2b.ho_effects` AS
WITH cell_diffs AS (
    SELECT cell, COUNTIF(treated) AS n_treated,
           AVG(IF(treated, growth, NULL)) - AVG(IF(NOT treated, growth, NULL))         AS diff,
           AVG(IF(treated, pre_growth, NULL)) - AVG(IF(NOT treated, pre_growth, NULL)) AS pre_diff,
           AVG(IF(treated AND receiver_new_hire, growth, NULL)) - AVG(IF(NOT treated, growth, NULL))     AS diff_new_hire,
           AVG(IF(treated AND NOT receiver_new_hire, growth, NULL)) - AVG(IF(NOT treated, growth, NULL)) AS diff_existing,
           COUNTIF(treated AND receiver_new_hire) AS n_new_hire,
           COUNTIF(treated AND NOT receiver_new_hire) AS n_existing
    FROM `sahyadri_b2b.ho_panel` GROUP BY cell
)
SELECT
    SUM(n_treated)                                                                    AS treated_customers,
    SUM(n_treated * diff) / SUM(n_treated)                                            AS effect,
    SUM(n_treated * pre_diff) / SUM(n_treated)                                        AS pre_trend_effect,
    SUM(IF(n_new_hire > 0, n_new_hire * diff_new_hire, 0)) / NULLIF(SUM(n_new_hire), 0) AS effect_new_hire,
    SUM(IF(n_existing > 0, n_existing * diff_existing, 0)) / NULLIF(SUM(n_existing), 0) AS effect_existing,
    SUM(n_new_hire)                                                                   AS to_new_hires,
    SUM(n_existing)                                                                   AS to_existing
FROM cell_diffs;

SELECT
    e.treated_customers,
    (SELECT COUNTIF(NOT treated) FROM `sahyadri_b2b.ho_panel`)                        AS control_customers,
    ROUND(100 * (EXP(e.effect) - 1), 1)                                               AS handover_effect_pct,
    ROUND(100 * (EXP(APPROX_QUANTILES(p.effect, 40)[OFFSET(1)]) - 1), 1)              AS shuffle_p2_5_pct,
    ROUND(100 * (EXP(APPROX_QUANTILES(p.effect, 40)[OFFSET(39)]) - 1), 1)             AS shuffle_p97_5_pct,
    ROUND(AVG(IF(ABS(p.effect) >= ABS(e.effect), 1, 0)), 3)                           AS p_value_two_sided,
    ROUND(100 * (EXP(e.pre_trend_effect) - 1), 1)                                     AS pre_trend_pct,
    ROUND(100 * (EXP(e.effect_new_hire) - 1), 1)                                      AS effect_to_new_hire_pct,
    e.to_new_hires,
    ROUND(100 * (EXP(e.effect_existing) - 1), 1)                                      AS effect_to_existing_rep_pct,
    e.to_existing
FROM `sahyadri_b2b.ho_effects` AS e
CROSS JOIN `sahyadri_b2b.ho_permutations` AS p
GROUP BY e.treated_customers, e.effect, e.pre_trend_effect, e.effect_new_hire, e.to_new_hires, e.effect_existing, e.to_existing;

-- -----------------------------------------------------------------------------
-- Step 4 · Large accounts and event quarters
-- -----------------------------------------------------------------------------
-- The aggregate gap with and without the five largest treated accounts
WITH ranked AS (
    SELECT *, IF(treated, ROW_NUMBER() OVER (PARTITION BY treated ORDER BY rev_before DESC), NULL) AS size_rank
    FROM `sahyadri_b2b.ho_panel`
)
SELECT
    'All treated customers'                                                           AS view,
    ROUND(100 * (SUM(IF(treated, rev_after, 0)) / SUM(IF(treated, rev_before, 0)) - 1), 1)            AS treated_change_pct,
    ROUND(100 * (SUM(IF(NOT treated, rev_after, 0)) / SUM(IF(NOT treated, rev_before, 0)) - 1), 1)    AS control_change_pct
FROM ranked
UNION ALL
SELECT
    'Without the 5 largest treated',
    ROUND(100 * (SUM(IF(treated AND size_rank > 5, rev_after, 0)) / SUM(IF(treated AND size_rank > 5, rev_before, 0)) - 1), 1),
    ROUND(100 * (SUM(IF(NOT treated, rev_after, 0)) / SUM(IF(NOT treated, rev_before, 0)) - 1), 1)
FROM ranked;

SELECT
    customer_id, customer_segment, ev AS event_quarter_index, rep_before, rep_after,
    ROUND(rev_before / 1e5, 1) AS revenue_before_lakh, ROUND(rev_after / 1e5, 1) AS revenue_after_lakh
FROM `sahyadri_b2b.ho_panel`
WHERE treated
ORDER BY rev_before DESC
LIMIT 5;

SELECT
    ev                                                                                AS event_quarter_index,
    COUNTIF(treated)                                                                  AS treated,
    COUNTIF(NOT treated)                                                              AS controls,
    ROUND(100 * (EXP(AVG(IF(treated, growth, NULL)) - AVG(IF(NOT treated, growth, NULL))) - 1), 1) AS raw_gap_pct
FROM `sahyadri_b2b.ho_panel`
GROUP BY ev
ORDER BY ev;
