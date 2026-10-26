/* =============================================================================
   Case study · Sales force cost efficiency
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The sales team costs about Rs 2 crore a year in salaries. The CEO is
   preparing next year's budget and asks: what does the company get back for
   that money, and is pay aligned with what each person and role delivers?
     1. How much gross profit does each salesperson generate per rupee of
        salary, and what is the cost of sales as a share of revenue?
     2. Which roles (managers, key account managers, executives) are the most
        cost-efficient?
     3. Does higher pay go with higher gross profit?
     4. How much gross profit comes from orders with no salesperson?
     5. Who is below a break-even level of gross profit for their cost?

   KEY RULES
     - Period: 1 Oct 2025 - 30 Sep 2026 (12 months).
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Gross profit (GP): revenue - quantity x unit_cost on lines with a known
       cost; GP on uncosted lines is estimated at the salesperson's own
       margin % on costed lines (reported separately).
     - Salary cost: annual salary x share of the period employed (from hire
       date). Salary is treated as the full employment cost; benefits, travel
       and incentives are not in the data.
     - GP return = GP / salary cost. Cost of sales = salary cost / revenue.
     - Break-even: GP return of 3.0, i.e. GP covers salary three times, a
       common rule of thumb for direct sales roles (salary, overheads and a
       contribution to profit). It is a parameter, not a finding.
     - Head of Sales is shown separately: the role is management, not quota.
   ============================================================================= */

DECLARE period_start  DATE    DEFAULT DATE '2025-10-01';
DECLARE period_end    DATE    DEFAULT DATE '2026-09-30';
DECLARE breakeven_roi FLOAT64 DEFAULT 3.0;

-- -----------------------------------------------------------------------------
-- Step 1 · Revenue, gross profit and salary cost per salesperson
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.sales_cost_efficiency` AS
WITH lines AS (
    SELECT
        o.employee_id,
        o.order_id,
        o.customer_id,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)            AS revenue,
        IF(p.unit_cost IS NULL, NULL,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) - i.quantity * p.unit_cost) AS gp
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN period_start AND period_end
),
by_rep AS (
    SELECT
        employee_id,
        COUNT(DISTINCT order_id)                                  AS orders,
        COUNT(DISTINCT customer_id)                               AS customers,
        SUM(revenue)                                              AS revenue,
        SUM(IF(gp IS NOT NULL, revenue, 0))                       AS costed_revenue,
        SUM(gp)                                                   AS costed_gp
    FROM lines
    GROUP BY employee_id
),
sales_team AS (
    SELECT e.employee_id, e.employee_name, e.designation, e.hire_date, e.salary
    FROM `sahyadri_b2b.employees`   AS e
    JOIN `sahyadri_b2b.departments` AS d ON d.department_id = e.department_id
    WHERE d.department_name = 'Sales'
)
SELECT
    IFNULL(t.employee_id, r.employee_id)                                         AS employee_id,
    IFNULL(t.employee_name, 'No salesperson recorded')                           AS employee_name,
    IFNULL(t.designation, 'No salesperson recorded')                             AS designation,
    CASE WHEN t.designation = 'Head of Sales' THEN 'Management'
         WHEN t.designation IN ('Regional Sales Manager', 'Key Account Manager') THEN 'Managers and key accounts'
         WHEN t.designation IN ('Senior Sales Executive', 'Sales Executive')    THEN 'Executives'
         ELSE 'Unassigned' END                                                   AS role_group,
    t.hire_date,
    t.salary                                                                     AS annual_salary,
    -- share of the period employed
    IF(t.employee_id IS NULL, 0,
       GREATEST(0, DATE_DIFF(period_end, GREATEST(t.hire_date, period_start), DAY) + 1)
         / (DATE_DIFF(period_end, period_start, DAY) + 1))                       AS months_employed_share,
    IF(t.employee_id IS NULL, 0,
       t.salary * GREATEST(0, DATE_DIFF(period_end, GREATEST(t.hire_date, period_start), DAY) + 1)
         / (DATE_DIFF(period_end, period_start, DAY) + 1))                       AS salary_cost,
    IFNULL(r.orders, 0)                                                          AS orders,
    IFNULL(r.customers, 0)                                                       AS customers,
    IFNULL(r.revenue, 0)                                                         AS revenue,
    IFNULL(r.costed_revenue, 0)                                                  AS costed_revenue,
    IFNULL(r.costed_gp, 0)                                                       AS costed_gp,
    SAFE_DIVIDE(r.costed_gp, r.costed_revenue)                                   AS gp_margin_pct,
    -- costed GP plus uncosted revenue at the person's own margin
    IFNULL(r.costed_gp + (r.revenue - r.costed_revenue) * SAFE_DIVIDE(r.costed_gp, r.costed_revenue), 0) AS gross_profit
FROM sales_team AS t
FULL OUTER JOIN by_rep AS r ON r.employee_id = t.employee_id;

SELECT
    employee_id,
    employee_name,
    designation,
    ROUND(annual_salary / 1e5, 2)                                  AS annual_salary_lakh,
    ROUND(salary_cost / 1e5, 2)                                    AS salary_cost_lakh,
    orders,
    customers,
    ROUND(revenue / 1e5, 1)                                        AS revenue_lakh,
    ROUND(gross_profit / 1e5, 1)                                   AS gross_profit_lakh,
    ROUND(100 * gp_margin_pct, 1)                                  AS gp_margin_pct,
    ROUND(SAFE_DIVIDE(gross_profit, salary_cost), 1)               AS gp_return,
    ROUND(100 * SAFE_DIVIDE(salary_cost, revenue), 2)              AS cost_of_sales_pct,
    CASE WHEN salary_cost = 0 THEN NULL
         WHEN months_employed_share < 0.25 THEN 'Too new to judge'
         WHEN role_group = 'Management' THEN 'Management (not judged)'
         WHEN SAFE_DIVIDE(gross_profit, salary_cost) < breakeven_roi THEN 'Below break-even'
         ELSE 'Above break-even' END                               AS breakeven_status
FROM `sahyadri_b2b.sales_cost_efficiency`
ORDER BY role_group, SAFE_DIVIDE(gross_profit, salary_cost) DESC;

-- -----------------------------------------------------------------------------
-- Step 2 · By role group, and the team total
-- -----------------------------------------------------------------------------
SELECT
    role_group,
    COUNT(*)                                                       AS people,
    ROUND(SUM(salary_cost) / 1e5, 1)                               AS salary_cost_lakh,
    ROUND(SUM(revenue) / 1e7, 2)                                   AS revenue_crore,
    ROUND(SUM(gross_profit) / 1e7, 2)                              AS gross_profit_crore,
    ROUND(SAFE_DIVIDE(SUM(gross_profit), SUM(salary_cost)), 1)     AS gp_return,
    ROUND(100 * SAFE_DIVIDE(SUM(salary_cost), SUM(revenue)), 2)    AS cost_of_sales_pct,
    ROUND(SAFE_DIVIDE(SUM(revenue), SUM(months_employed_share)) / 1e7, 2) AS revenue_per_person_year_crore
FROM `sahyadri_b2b.sales_cost_efficiency`
GROUP BY role_group
UNION ALL
SELECT
    'All',
    COUNT(*),
    ROUND(SUM(salary_cost) / 1e5, 1),
    ROUND(SUM(revenue) / 1e7, 2),
    ROUND(SUM(gross_profit) / 1e7, 2),
    ROUND(SUM(gross_profit) / SUM(salary_cost), 1),
    ROUND(100 * SUM(salary_cost) / SUM(revenue), 2),
    NULL
FROM `sahyadri_b2b.sales_cost_efficiency`
ORDER BY role_group;

-- -----------------------------------------------------------------------------
-- Step 3 · Does pay follow gross profit? (salespeople employed all period)
-- -----------------------------------------------------------------------------
WITH full_period AS (
    SELECT *
    FROM `sahyadri_b2b.sales_cost_efficiency`
    WHERE role_group IN ('Managers and key accounts', 'Executives')
      AND months_employed_share = 1
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY annual_salary)  AS salary_rank,
        RANK() OVER (ORDER BY gross_profit)   AS gp_rank
    FROM full_period
)
SELECT
    COUNT(*)                                                       AS salespeople,
    ROUND(CORR(annual_salary, gross_profit), 3)                    AS pearson_salary_vs_gp,
    ROUND(CORR(salary_rank, gp_rank), 3)                           AS spearman_salary_vs_gp,
    ROUND(MAX(gross_profit) / MIN(gross_profit), 1)                AS gp_highest_to_lowest,
    ROUND(MAX(annual_salary) / MIN(annual_salary), 1)              AS salary_highest_to_lowest
FROM ranked;

-- -----------------------------------------------------------------------------
-- Step 4 · Break-even view: GP needed to cover salary at the target return
-- -----------------------------------------------------------------------------
SELECT
    employee_name,
    designation,
    ROUND(salary_cost / 1e5, 2)                                    AS salary_cost_lakh,
    ROUND(gross_profit / 1e5, 1)                                   AS gross_profit_lakh,
    ROUND(breakeven_roi * salary_cost / 1e5, 1)                    AS gp_needed_lakh,
    ROUND((gross_profit - breakeven_roi * salary_cost) / 1e5, 1)   AS surplus_or_gap_lakh,
    ROUND(IF(gross_profit < breakeven_roi * salary_cost,
             SAFE_DIVIDE(breakeven_roi * salary_cost - gross_profit, gp_margin_pct), NULL) / 1e5, 1) AS extra_revenue_needed_lakh
FROM `sahyadri_b2b.sales_cost_efficiency`
WHERE role_group IN ('Managers and key accounts', 'Executives')
  AND months_employed_share >= 0.25
ORDER BY surplus_or_gap_lakh;
