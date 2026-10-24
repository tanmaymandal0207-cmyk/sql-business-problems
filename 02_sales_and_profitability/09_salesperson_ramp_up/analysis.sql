/* =============================================================================
   Case study · Salesperson ramp-up
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Four salespeople joined between November 2024 and June 2025, and two more
   joined in September 2026. The sales head has to set first-year targets for
   the new joiners and decide how much support they need, but has no view of
   how long a new salesperson takes to become productive. The questions:
     1. How long does a new salesperson take to win a first order, and to
        reach the productivity of an established colleague?
     2. What does the typical ramp-up curve look like over the first year?
     3. Is a new joiner's revenue built on customers handed over to them, or
        on customers they win themselves?
     4. When a new joiner lags, is it fewer orders or smaller orders?
     5. What revenue should be planned for the September 2026 joiners in
        their first six months?

   KEY RULES
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - New joiner: Sales department, hired on or after 1 Jan 2024 (the start of
       the order data), so the whole ramp-up is visible.
     - Benchmark: the average of established Sales Executives and Senior Sales
       Executives (hired before 2024) in the SAME calendar month, so
       seasonality cancels out. Managers and key account managers are excluded
       because they hold the largest accounts.
     - Tenure month 1 = the first full calendar month after the hire month.
     - Productive = 3-month rolling revenue at 80 % or more of the benchmark.
     - Orders with no salesperson are excluded.
   ============================================================================= */

DECLARE as_of        DATE    DEFAULT DATE '2026-09-30';
DECLARE productive   FLOAT64 DEFAULT 0.8;

-- -----------------------------------------------------------------------------
-- Step 1 · Monthly activity per salesperson, zero-filled for every month
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rep_monthly` AS
WITH orders AS (
    SELECT
        o.order_id,
        o.employee_id,
        o.customer_id,
        DATE_TRUNC(o.order_date, MONTH)                                            AS month_start,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.employee_id IS NOT NULL
    GROUP BY o.order_id, o.employee_id, o.customer_id, month_start
),
reps AS (
    SELECT
        e.employee_id,
        e.employee_name,
        e.designation,
        e.hire_date,
        CASE WHEN e.hire_date >= DATE '2024-01-01' THEN 'New joiner'
             WHEN e.designation IN ('Sales Executive', 'Senior Sales Executive') THEN 'Benchmark peer'
             ELSE 'Other established' END                                          AS rep_group
    FROM `sahyadri_b2b.employees`   AS e
    JOIN `sahyadri_b2b.departments` AS d ON d.department_id = e.department_id
    WHERE d.department_name = 'Sales'
),
months AS (
    SELECT month_start
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2024-01-01', DATE_TRUNC(as_of, MONTH), INTERVAL 1 MONTH)) AS month_start
)
SELECT
    r.employee_id,
    r.employee_name,
    r.designation,
    r.hire_date,
    r.rep_group,
    m.month_start,
    DATE_DIFF(m.month_start, DATE_TRUNC(r.hire_date, MONTH), MONTH)  AS tenure_month,
    COUNT(o.order_id)                                                AS orders,
    COUNT(DISTINCT o.customer_id)                                    AS customers,
    IFNULL(SUM(o.revenue), 0)                                        AS revenue
FROM reps AS r
CROSS JOIN months AS m
LEFT JOIN orders AS o
  ON o.employee_id = r.employee_id AND o.month_start = m.month_start
WHERE m.month_start > DATE_TRUNC(r.hire_date, MONTH)
GROUP BY r.employee_id, r.employee_name, r.designation, r.hire_date, r.rep_group, m.month_start;

-- -----------------------------------------------------------------------------
-- Step 2 · Ramp table: each new joiner's month against the benchmark month
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rep_ramp` AS
WITH benchmark AS (
    SELECT
        month_start,
        COUNT(*)          AS peers,
        AVG(revenue)      AS benchmark_revenue,
        AVG(orders)       AS benchmark_orders,
        SAFE_DIVIDE(SUM(revenue), SUM(orders)) AS benchmark_order_value
    FROM `sahyadri_b2b.rep_monthly`
    WHERE rep_group = 'Benchmark peer'
    GROUP BY month_start
),
joined AS (
    SELECT
        r.*,
        b.peers,
        b.benchmark_revenue,
        b.benchmark_orders,
        b.benchmark_order_value,
        r.revenue / b.benchmark_revenue                                AS revenue_index,
        r.orders  / b.benchmark_orders                                 AS orders_index
    FROM `sahyadri_b2b.rep_monthly` AS r
    JOIN benchmark AS b ON b.month_start = r.month_start
    WHERE r.rep_group = 'New joiner'
)
SELECT
    *,
    SUM(revenue) OVER w3 / SUM(benchmark_revenue) OVER w3              AS revenue_index_3m,
    SUM(orders)  OVER w3 / SUM(benchmark_orders)  OVER w3              AS orders_index_3m,
    COUNT(*)     OVER w3                                               AS months_in_window
FROM joined
WINDOW w3 AS (PARTITION BY employee_id ORDER BY tenure_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW);

-- -----------------------------------------------------------------------------
-- Step 3 · Time to first order and time to productivity
-- -----------------------------------------------------------------------------
WITH first_orders AS (
    SELECT o.employee_id, MIN(o.order_date) AS first_order_date
    FROM `sahyadri_b2b.sales_orders` AS o
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.employee_id
),
productive_month AS (
    SELECT employee_id, MIN(tenure_month) AS first_productive_month
    FROM `sahyadri_b2b.rep_ramp`
    WHERE months_in_window = 3 AND revenue_index_3m >= productive
    GROUP BY employee_id
),
summary AS (
    SELECT
        employee_id,
        ANY_VALUE(employee_name)                                         AS employee_name,
        ANY_VALUE(designation)                                           AS designation,
        ANY_VALUE(hire_date)                                             AS hire_date,
        MAX(tenure_month)                                                AS months_observed,
        MAX(IF(tenure_month = 3,  revenue_index_3m, NULL))               AS revenue_index_m1_3,
        MAX(IF(tenure_month = 6,  revenue_index_3m, NULL))               AS revenue_index_m4_6,
        MAX(IF(tenure_month = 12, revenue_index_3m, NULL))               AS revenue_index_m10_12,
        SUM(IF(tenure_month BETWEEN 1 AND 12, revenue, 0))
          / SUM(IF(tenure_month BETWEEN 1 AND 12, benchmark_revenue, 0)) AS revenue_index_year1,
        SUM(IF(tenure_month BETWEEN 1 AND 12, orders, 0))
          / SUM(IF(tenure_month BETWEEN 1 AND 12, benchmark_orders, 0))  AS orders_index_year1,
        COUNTIF(revenue_index >= productive)                             AS months_at_or_above_80pct
    FROM `sahyadri_b2b.rep_ramp`
    GROUP BY employee_id
)
SELECT
    s.employee_id,
    s.employee_name,
    s.designation,
    s.hire_date,
    f.first_order_date,
    DATE_DIFF(f.first_order_date, s.hire_date, DAY)                      AS days_to_first_order,
    p.first_productive_month,
    s.months_observed,
    ROUND(s.revenue_index_m1_3, 2)                                       AS revenue_index_m1_3,
    ROUND(s.revenue_index_m4_6, 2)                                       AS revenue_index_m4_6,
    ROUND(s.revenue_index_m10_12, 2)                                     AS revenue_index_m10_12,
    ROUND(s.revenue_index_year1, 2)                                      AS revenue_index_year1,
    ROUND(s.orders_index_year1, 2)                                       AS orders_index_year1,
    s.months_at_or_above_80pct
FROM summary AS s
LEFT JOIN first_orders     AS f ON f.employee_id = s.employee_id
LEFT JOIN productive_month AS p ON p.employee_id = s.employee_id
ORDER BY s.hire_date;

-- Context: average monthly revenue and orders per salesperson, last 12 months
SELECT
    IF(rep_group = 'New joiner', employee_name, rep_group)               AS salesperson_or_group,
    COUNT(DISTINCT employee_id)                                          AS salespeople,
    ROUND(AVG(revenue), 0)                                               AS avg_monthly_revenue,
    ROUND(AVG(orders), 1)                                                AS avg_monthly_orders,
    ROUND(SAFE_DIVIDE(SUM(revenue), SUM(orders)), 0)                     AS avg_order_value
FROM `sahyadri_b2b.rep_monthly`
WHERE month_start > DATE_SUB(DATE_TRUNC(as_of, MONTH), INTERVAL 12 MONTH)
  AND employee_id IN (SELECT employee_id FROM `sahyadri_b2b.rep_monthly` GROUP BY employee_id HAVING SUM(orders) > 0)
GROUP BY salesperson_or_group
ORDER BY avg_monthly_revenue DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Average ramp-up curve, by quarter of tenure (all new joiners)
-- -----------------------------------------------------------------------------
SELECT
    CAST(CEIL(tenure_month / 3) AS INT64)                                AS tenure_quarter,
    COUNT(DISTINCT employee_id)                                          AS joiners,
    ROUND(SUM(revenue) / SUM(benchmark_revenue), 2)                      AS revenue_index,
    ROUND(SUM(orders)  / SUM(benchmark_orders), 2)                       AS orders_index,
    ROUND(SAFE_DIVIDE(SUM(revenue), SUM(orders))
          / (SUM(benchmark_revenue) / SUM(benchmark_orders)), 2)         AS order_value_index
FROM `sahyadri_b2b.rep_ramp`
WHERE tenure_month BETWEEN 1 AND 18
GROUP BY tenure_quarter
ORDER BY tenure_quarter;

-- -----------------------------------------------------------------------------
-- Step 5 · Handed-over or self-won? Customer source of each joiner's revenue
-- -----------------------------------------------------------------------------
WITH valid AS (
    SELECT
        o.order_id, o.customer_id, o.employee_id, o.order_date,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, o.employee_id, o.order_date
),
customer_first AS (
    SELECT customer_id, MIN(order_date) AS first_order_date FROM valid GROUP BY customer_id
),
rep_customer AS (
    SELECT v.employee_id, v.customer_id, MIN(v.order_date) AS first_with_rep, SUM(v.revenue) AS revenue
    FROM valid AS v
    JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = v.employee_id
    WHERE e.hire_date >= DATE '2024-01-01'
    GROUP BY v.employee_id, v.customer_id
)
SELECT
    e.employee_name,
    IF(c.first_order_date < r.first_with_rep, 'Existing customer (handed over)',
                                              'New customer (won by the joiner)') AS customer_source,
    COUNT(*)                                                              AS customers,
    ROUND(SUM(r.revenue), 0)                                              AS revenue,
    ROUND(100 * SUM(r.revenue) / SUM(SUM(r.revenue)) OVER (PARTITION BY e.employee_name), 1) AS revenue_pct
FROM rep_customer AS r
JOIN customer_first           AS c ON c.customer_id = r.customer_id
JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = r.employee_id
GROUP BY e.employee_name, customer_source
ORDER BY e.employee_name, customer_source;

-- New customers won since the first joiner started: joiners against everyone else
WITH labelled AS (
    SELECT
        o.order_id, o.customer_id, o.order_date,
        CASE WHEN o.employee_id IS NULL THEN 'No salesperson recorded'
             WHEN e.hire_date >= DATE '2024-01-01' THEN 'New joiners'
             ELSE 'Established salespeople' END                           AS rep_type
    FROM `sahyadri_b2b.sales_orders` AS o
    LEFT JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = o.employee_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
first_order AS (
    SELECT * FROM labelled
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) = 1
),
won AS (
    SELECT rep_type, COUNT(*) AS new_customers
    FROM first_order WHERE order_date >= DATE '2024-12-01'
    GROUP BY rep_type
),
activity AS (
    SELECT rep_type, COUNT(*) AS orders
    FROM labelled WHERE order_date >= DATE '2024-12-01'
    GROUP BY rep_type
)
SELECT
    a.rep_type,
    a.orders                                                              AS orders_since_dec_2024,
    ROUND(100 * a.orders / SUM(a.orders) OVER (), 1)                      AS orders_pct,
    IFNULL(w.new_customers, 0)                                            AS new_customers_won,
    ROUND(100 * IFNULL(w.new_customers, 0) / SUM(IFNULL(w.new_customers, 0)) OVER (), 1) AS new_customers_pct
FROM activity AS a
LEFT JOIN won AS w ON w.rep_type = a.rep_type
ORDER BY a.rep_type;

-- -----------------------------------------------------------------------------
-- Step 6 · Planning: expected first-six-month revenue for the September 2026
--          joiners, from the observed ramp and the latest benchmark
-- -----------------------------------------------------------------------------
WITH joiner_index AS (
    -- each joiner's first six months against the benchmark for the same months
    SELECT
        employee_id,
        SUM(revenue)           AS revenue_m1_6,
        SUM(benchmark_revenue) AS benchmark_m1_6
    FROM `sahyadri_b2b.rep_ramp`
    WHERE tenure_month BETWEEN 1 AND 6
    GROUP BY employee_id
),
curve AS (
    SELECT
        SUM(revenue_m1_6) / SUM(benchmark_m1_6)                           AS pooled_index,
        MIN(revenue_m1_6 / benchmark_m1_6)                                AS lowest_index,
        MAX(revenue_m1_6 / benchmark_m1_6)                                AS highest_index
    FROM joiner_index
),
latest_benchmark AS (
    SELECT AVG(revenue) AS monthly_benchmark
    FROM `sahyadri_b2b.rep_monthly`
    WHERE rep_group = 'Benchmark peer'
      AND month_start > DATE_SUB(DATE_TRUNC(as_of, MONTH), INTERVAL 12 MONTH)
),
planned_joiners AS (
    SELECT e.employee_id, e.employee_name, e.hire_date
    FROM `sahyadri_b2b.employees`   AS e
    JOIN `sahyadri_b2b.departments` AS d ON d.department_id = e.department_id
    WHERE d.department_name = 'Sales'
      AND e.hire_date > DATE_SUB(as_of, INTERVAL 3 MONTH)
)
SELECT
    j.employee_name,
    j.hire_date,
    ROUND(b.monthly_benchmark, 0)                                         AS benchmark_monthly_revenue,
    ROUND(c.pooled_index, 2)                                              AS planned_index_m1_6,
    ROUND(6 * c.pooled_index  * b.monthly_benchmark, 0)                   AS planned_revenue_m1_6,
    ROUND(6 * c.lowest_index  * b.monthly_benchmark, 0)                   AS low_case_m1_6,
    ROUND(6 * c.highest_index * b.monthly_benchmark, 0)                   AS high_case_m1_6
FROM planned_joiners AS j
CROSS JOIN curve AS c
CROSS JOIN latest_benchmark AS b
ORDER BY j.hire_date;
