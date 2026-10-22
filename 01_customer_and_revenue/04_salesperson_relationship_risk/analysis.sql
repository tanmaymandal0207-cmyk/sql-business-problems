/* =============================================================================
   Case study · Salesperson relationship risk
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   In B2B distribution, customers often buy from one salesperson, and the
   relationship leaves when that person leaves. The sales head has two new
   joiners starting in September 2026 and wants to plan account coverage
   before anyone resigns. The questions are:
     1. How much revenue depends on a single salesperson relationship?
     2. Which salespeople carry the most of that exposure?
     3. What has actually happened to customers whose salesperson changed?
     4. Which accounts need a second contact first?

   KEY RULES
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Current window: 1 Oct 2025 - 30 Sep 2026 (12 months).
     - Coverage window: 1 Oct 2024 - 30 Sep 2026 (24 months), used to count
       how many salespeople have served a customer.
     - Primary salesperson: the employee with the most attributed revenue in
       the window. Ties go to the lower employee_id.
     - Relationship type (active customers):
         Single-threaded : one salesperson in 24 months
         Dominant        : more than one, but the primary holds >= 80 % of
                           attributed 12-month revenue
         Shared          : everyone else
         Unassigned      : no order with a salesperson in the window
     - Orders without a salesperson stay in customer revenue but are not
       credited to anyone.
   ============================================================================= */

DECLARE window_start   DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end     DATE    DEFAULT DATE '2026-09-30';
DECLARE coverage_start DATE    DEFAULT DATE '2024-10-01';
DECLARE prior_start    DATE    DEFAULT DATE '2024-10-01';
DECLARE prior_end      DATE    DEFAULT DATE '2025-09-30';
DECLARE dominant_share FLOAT64 DEFAULT 0.80;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per active customer: primary salesperson and coverage
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_relationship_coverage` AS
WITH order_revenue AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.employee_id,
        o.order_date,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN coverage_start AND window_end
    GROUP BY o.order_id, o.customer_id, o.employee_id, o.order_date
),
customer_window AS (
    SELECT
        customer_id,
        SUM(revenue)                                    AS revenue_12m,
        SUM(IF(employee_id IS NULL, revenue, 0))        AS unattributed_revenue_12m
    FROM order_revenue
    WHERE order_date BETWEEN window_start AND window_end
    GROUP BY customer_id
),
employee_window AS (
    SELECT
        customer_id,
        employee_id,
        SUM(revenue) AS revenue_12m,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY SUM(revenue) DESC, employee_id) AS rank_in_customer
    FROM order_revenue
    WHERE order_date BETWEEN window_start AND window_end
      AND employee_id IS NOT NULL
    GROUP BY customer_id, employee_id
),
primary_rep AS (
    SELECT
        customer_id,
        MAX(IF(rank_in_customer = 1, employee_id, NULL))                 AS primary_employee_id,
        SAFE_DIVIDE(MAX(IF(rank_in_customer = 1, revenue_12m, NULL)),
                    SUM(revenue_12m))                                    AS primary_share
    FROM employee_window
    GROUP BY customer_id
),
coverage AS (
    SELECT customer_id, COUNT(DISTINCT employee_id) AS salespeople_24m
    FROM order_revenue
    WHERE employee_id IS NOT NULL
    GROUP BY customer_id
)
SELECT
    w.customer_id,
    c.customer_name,
    c.customer_segment,
    ROUND(w.revenue_12m, 2)                       AS revenue_12m,
    ROUND(w.unattributed_revenue_12m, 2)          AS unattributed_revenue_12m,
    p.primary_employee_id,
    ROUND(p.primary_share, 4)                     AS primary_share,
    IFNULL(cv.salespeople_24m, 0)                 AS salespeople_24m,
    CASE
        WHEN p.primary_employee_id IS NULL     THEN 'Unassigned'
        WHEN cv.salespeople_24m = 1            THEN 'Single-threaded'
        WHEN p.primary_share >= dominant_share THEN 'Dominant'
        ELSE 'Shared'
    END                                           AS relationship_type
FROM customer_window           AS w
JOIN `sahyadri_b2b.customers`  AS c  ON c.customer_id  = w.customer_id
LEFT JOIN primary_rep          AS p  ON p.customer_id  = w.customer_id
LEFT JOIN coverage             AS cv ON cv.customer_id = w.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · How much revenue depends on one relationship?
-- -----------------------------------------------------------------------------
SELECT
    relationship_type,
    COUNT(*)                                                         AS customers,
    ROUND(SUM(revenue_12m), 2)                                       AS revenue_12m,
    ROUND(100 * SUM(revenue_12m) / SUM(SUM(revenue_12m)) OVER (), 1) AS pct_of_revenue,
    ROUND(AVG(revenue_12m), 0)                                       AS avg_revenue_per_customer
FROM `sahyadri_b2b.customer_relationship_coverage`
GROUP BY relationship_type
ORDER BY revenue_12m DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · Exposure by salesperson: the revenue that would be at risk if they left
-- -----------------------------------------------------------------------------
WITH book AS (
    SELECT
        primary_employee_id,
        COUNT(*)                                                   AS primary_customers,
        SUM(revenue_12m)                                           AS book_revenue,
        COUNTIF(relationship_type = 'Single-threaded')             AS single_threaded_customers,
        SUM(IF(relationship_type = 'Single-threaded', revenue_12m, 0)) AS single_threaded_revenue,
        SUM(IF(relationship_type IN ('Single-threaded', 'Dominant'), revenue_12m, 0)) AS high_dependency_revenue,
        MAX(revenue_12m)                                           AS largest_account
    FROM `sahyadri_b2b.customer_relationship_coverage`
    WHERE primary_employee_id IS NOT NULL
    GROUP BY primary_employee_id
)
SELECT
    e.employee_id,
    e.employee_name,
    e.designation,
    e.hire_date,
    b.primary_customers,
    ROUND(b.book_revenue, 2)                                                AS book_revenue,
    ROUND(100 * b.book_revenue / SUM(b.book_revenue) OVER (), 1)            AS pct_of_attributed_book,
    b.single_threaded_customers,
    ROUND(b.single_threaded_revenue, 2)                                     AS single_threaded_revenue,
    ROUND(b.high_dependency_revenue, 2)                                     AS high_dependency_revenue,
    ROUND(100 * b.high_dependency_revenue / b.book_revenue, 1)              AS pct_of_book_high_dependency,
    ROUND(100 * b.largest_account / b.book_revenue, 1)                      AS largest_account_pct_of_book
FROM book                        AS b
JOIN `sahyadri_b2b.employees`    AS e ON e.employee_id = b.primary_employee_id
ORDER BY high_dependency_revenue DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Evidence: what happened when a customer's primary salesperson changed?
--          Customers with a primary in the prior 12 months, compared with the
--          current 12 months.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.salesperson_handover` AS
WITH order_revenue AS (
    SELECT
        o.customer_id,
        o.employee_id,
        IF(o.order_date BETWEEN prior_start AND prior_end, 'prior', 'current') AS period,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN prior_start AND window_end
    GROUP BY o.customer_id, o.employee_id, period
),
primary_by_period AS (
    SELECT customer_id, period, employee_id
    FROM (
        SELECT
            customer_id, period, employee_id,
            ROW_NUMBER() OVER (PARTITION BY customer_id, period
                               ORDER BY SUM(revenue) DESC, employee_id) AS rn
        FROM order_revenue
        WHERE employee_id IS NOT NULL
        GROUP BY customer_id, period, employee_id
    )
    WHERE rn = 1
),
revenue_by_period AS (
    SELECT
        customer_id,
        SUM(IF(period = 'prior',   revenue, 0)) AS prior_revenue,
        SUM(IF(period = 'current', revenue, 0)) AS current_revenue
    FROM order_revenue
    GROUP BY customer_id
)
SELECT
    p.customer_id,
    p.employee_id                     AS prior_primary,
    c.employee_id                     AS current_primary,
    ROUND(r.prior_revenue, 2)         AS prior_revenue,
    ROUND(r.current_revenue, 2)       AS current_revenue,
    CASE
        WHEN r.current_revenue = 0          THEN 'Stopped buying'
        WHEN c.employee_id IS NULL          THEN 'No salesperson recorded'
        WHEN c.employee_id = p.employee_id  THEN 'Same salesperson'
        ELSE 'Salesperson changed'
    END                               AS handover_outcome
FROM primary_by_period      AS p
JOIN revenue_by_period      AS r ON r.customer_id = p.customer_id
LEFT JOIN primary_by_period AS c ON c.customer_id = p.customer_id AND c.period = 'current'
WHERE p.period = 'prior';

SELECT
    handover_outcome,
    COUNT(*)                                                   AS customers,
    ROUND(SUM(prior_revenue), 2)                               AS prior_revenue,
    ROUND(SUM(current_revenue), 2)                             AS current_revenue,
    ROUND(100 * (SUM(current_revenue) / SUM(prior_revenue) - 1), 1) AS revenue_change_pct,
    COUNTIF(current_revenue < prior_revenue)                   AS customers_declining,
    ROUND(100 * COUNTIF(current_revenue < prior_revenue) / COUNT(*), 1) AS pct_declining
FROM `sahyadri_b2b.salesperson_handover`
GROUP BY handover_outcome
ORDER BY customers DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Succession list: the 10 largest single-threaded accounts
-- -----------------------------------------------------------------------------
SELECT
    r.customer_id,
    r.customer_name,
    r.customer_segment,
    e.employee_name                                     AS only_salesperson,
    e.designation,
    ROUND(r.revenue_12m, 2)                             AS revenue_12m,
    ROUND(100 * r.revenue_12m / SUM(r.revenue_12m) OVER (), 2) AS pct_of_single_threaded_revenue
FROM `sahyadri_b2b.customer_relationship_coverage` AS r
JOIN `sahyadri_b2b.employees`                      AS e ON e.employee_id = r.primary_employee_id
WHERE r.relationship_type = 'Single-threaded'
QUALIFY ROW_NUMBER() OVER (ORDER BY r.revenue_12m DESC) <= 10
ORDER BY r.revenue_12m DESC;
