/* =============================================================================
   Case study · Sales commission plan simulation
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The company is introducing commission for its 15 salespeople and has a
   budget equal to 2 % of their net revenue. HR has drafted four plan
   designs. Before choosing, the sales director wants each one run on the
   last 12 months of actual orders, so everyone can see who would have
   earned what and what behaviour each plan rewards:
     1. How much would each salesperson have earned under each plan?
     2. Which plan pays most for gross profit rather than for volume?
     3. How strongly does each plan discourage discounting?
     4. Which plan should be chosen, and with what safeguards?

   METHOD
     - Period: orders dated 1 Oct 2025 - 30 Sep 2026, not Cancelled or
       Returned. Salespeople: everyone with orders in the period except the
       Head of Sales (who would be paid on team results) and unassigned orders.
     - Gross profit (GP) = net revenue - quantity x unit cost, on lines with a
       known unit cost.
     - Budget = 2 % of the team's net revenue. Plans B-D are scaled so that
       they cost exactly the same in total, so only the distribution differs.
         A. Revenue:       2 % of net revenue.
         B. Gross profit:  rate x GP.
         C. Quota tiers:   k x (1 x revenue up to quota + 3 x revenue above
                           quota). Quota = prior-12-month revenue (annualised
                           for people hired during that year) x 1.10.
         D. GP on cash:    rate x GP of orders fully paid by 30 Sep 2026.
     - Discount sensitivity: commission lost for each extra rupee of
       discount on a line = A: 2 %, B and D: their GP rate (a rupee of
       discount is a rupee of GP), C: k x 1 or k x 3 depending on quota.
   ============================================================================= */

DECLARE period_start DATE    DEFAULT DATE '2025-10-01';
DECLARE period_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE prior_start  DATE    DEFAULT DATE '2024-10-01';
DECLARE budget_rate  FLOAT64 DEFAULT 0.02;
DECLARE quota_uplift FLOAT64 DEFAULT 1.10;
DECLARE above_quota_multiple FLOAT64 DEFAULT 3.0;

-- -----------------------------------------------------------------------------
-- Step 1 · Salesperson base: revenue, GP, discount, collected GP, quota
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cp_base` AS
WITH lines AS (
    SELECT o.order_id, o.employee_id, o.order_date,
           i.quantity * i.unit_price                                             AS gross_value,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS net_revenue,
           IF(p.unit_cost IS NULL, NULL,
              i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) - i.quantity * p.unit_cost) AS gross_profit
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.employee_id IS NOT NULL
      AND o.order_date BETWEEN prior_start AND period_end
),
order_totals AS (
    SELECT order_id, SUM(net_revenue) AS order_value FROM lines GROUP BY order_id
),
paid AS (
    SELECT p.order_id, SUM(p.amount) AS paid
    FROM `sahyadri_b2b.payments` AS p
    WHERE p.payment_date <= period_end
    GROUP BY p.order_id
),
cur AS (
    SELECT l.employee_id,
           COUNT(DISTINCT l.order_id)                                         AS orders,
           SUM(l.gross_value)                                                 AS gross_value,
           SUM(l.net_revenue)                                                 AS net_revenue,
           SUM(IFNULL(l.gross_profit, 0))                                     AS gross_profit,
           SUM(IF(IFNULL(pd.paid, 0) >= t.order_value - 0.05, IFNULL(l.gross_profit, 0), 0)) AS gp_collected
    FROM lines AS l
    JOIN order_totals AS t ON t.order_id = l.order_id
    LEFT JOIN paid AS pd ON pd.order_id = l.order_id
    WHERE l.order_date >= period_start
    GROUP BY l.employee_id
),
prior AS (
    SELECT employee_id, SUM(net_revenue) AS prior_revenue
    FROM lines WHERE order_date < period_start
    GROUP BY employee_id
)
SELECT
    c.employee_id, e.employee_name, e.designation, e.hire_date, e.salary,
    c.orders, c.gross_value, c.net_revenue, c.gross_profit, c.gp_collected,
    IFNULL(p.prior_revenue, 0)                                                  AS prior_revenue,
    -- months of the prior year the person was employed (1-12)
    LEAST(12, GREATEST(1, DATE_DIFF(period_start, GREATEST(e.hire_date, prior_start), MONTH))) AS prior_months,
    quota_uplift * IFNULL(p.prior_revenue, 0) * 12
      / LEAST(12, GREATEST(1, DATE_DIFF(period_start, GREATEST(e.hire_date, prior_start), MONTH))) AS quota
FROM cur AS c
JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = c.employee_id
LEFT JOIN prior AS p ON p.employee_id = c.employee_id
WHERE e.designation != 'Head of Sales';

-- -----------------------------------------------------------------------------
-- Step 2 · Calibrate the plans to the same budget and compute payouts
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.cp_plans` AS
WITH t AS (
    SELECT
        budget_rate * SUM(net_revenue)                                          AS budget,
        SUM(gross_profit)                                                       AS team_gp,
        SUM(gp_collected)                                                       AS team_gp_collected,
        SUM(LEAST(net_revenue, quota) + above_quota_multiple * GREATEST(net_revenue - quota, 0)) AS tier_units
    FROM `sahyadri_b2b.cp_base`
),
rates AS (
    SELECT budget, budget / team_gp AS rate_b, budget / tier_units AS rate_c, budget / team_gp_collected AS rate_d
    FROM t
)
SELECT
    b.*, r.rate_b, r.rate_c, r.rate_d,
    budget_rate * b.net_revenue                                                                   AS pay_a_revenue,
    r.rate_b * b.gross_profit                                                                     AS pay_b_gross_profit,
    r.rate_c * (LEAST(b.net_revenue, b.quota) + above_quota_multiple * GREATEST(b.net_revenue - b.quota, 0)) AS pay_c_quota_tiers,
    r.rate_d * b.gp_collected                                                                     AS pay_d_gp_on_cash
FROM `sahyadri_b2b.cp_base` AS b
CROSS JOIN rates AS r;

SELECT
    ROUND(ANY_VALUE(rate_b) * 100, 2)                 AS plan_b_pct_of_gp,
    ROUND(ANY_VALUE(rate_c) * 100, 3)                 AS plan_c_pct_below_quota,
    ROUND(ANY_VALUE(rate_c) * above_quota_multiple * 100, 3) AS plan_c_pct_above_quota,
    ROUND(ANY_VALUE(rate_d) * 100, 2)                 AS plan_d_pct_of_collected_gp,
    ROUND(SUM(pay_a_revenue) / 1e5, 2)                AS budget_lakh
FROM `sahyadri_b2b.cp_plans`;

-- Payout per salesperson under each plan (Rs lakh a year)
SELECT
    employee_id, employee_name, designation,
    ROUND(net_revenue / 1e5, 1)                                         AS revenue_lakh,
    ROUND(100 * gross_profit / net_revenue, 1)                          AS gp_margin_pct,
    ROUND(100 * (gross_value - net_revenue) / gross_value, 1)           AS discount_pct,
    ROUND(100 * net_revenue / quota, 0)                                 AS pct_of_quota,
    ROUND(pay_a_revenue / 1e5, 2)                                       AS a_revenue,
    ROUND(pay_b_gross_profit / 1e5, 2)                                  AS b_gross_profit,
    ROUND(pay_c_quota_tiers / 1e5, 2)                                   AS c_quota_tiers,
    ROUND(pay_d_gp_on_cash / 1e5, 2)                                    AS d_gp_on_cash,
    ROUND(100 * (pay_b_gross_profit / pay_a_revenue - 1), 1)            AS b_vs_a_pct
FROM `sahyadri_b2b.cp_plans`
ORDER BY net_revenue DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · What each plan rewards
-- -----------------------------------------------------------------------------
WITH long AS (
              SELECT 'A. Revenue' AS plan, employee_id, pay_a_revenue AS pay, gross_profit, net_revenue, salary FROM `sahyadri_b2b.cp_plans`
    UNION ALL SELECT 'B. Gross profit',     employee_id, pay_b_gross_profit,      gross_profit, net_revenue, salary FROM `sahyadri_b2b.cp_plans`
    UNION ALL SELECT 'C. Quota tiers',      employee_id, pay_c_quota_tiers,       gross_profit, net_revenue, salary FROM `sahyadri_b2b.cp_plans`
    UNION ALL SELECT 'D. GP on cash',       employee_id, pay_d_gp_on_cash,        gross_profit, net_revenue, salary FROM `sahyadri_b2b.cp_plans`
)
SELECT
    plan,
    ROUND(SUM(pay) / 1e5, 2)                                            AS total_lakh,
    ROUND(MIN(pay) / 1e5, 2)                                            AS lowest_lakh,
    ROUND(MAX(pay) / 1e5, 2)                                            AS highest_lakh,
    ROUND(CORR(pay, gross_profit), 3)                                   AS corr_with_gross_profit,
    ROUND(CORR(pay / net_revenue, gross_profit / net_revenue), 3)       AS corr_pay_rate_with_margin,
    ROUND(AVG(pay / salary) * 100, 1)                                   AS avg_pay_as_pct_of_salary,
    ROUND(MAX(pay / salary) * 100, 1)                                   AS max_pay_as_pct_of_salary
FROM long
GROUP BY plan
ORDER BY plan;

-- Commission lost per Rs 100 of extra discount on a line
SELECT
    ROUND(100 * budget_rate, 2)                                         AS a_revenue,
    ROUND(100 * ANY_VALUE(rate_b), 2)                                   AS b_gross_profit,
    ROUND(100 * ANY_VALUE(rate_c), 2)                                   AS c_below_quota,
    ROUND(100 * ANY_VALUE(rate_c) * above_quota_multiple, 2)            AS c_above_quota,
    ROUND(100 * ANY_VALUE(rate_d), 2)                                   AS d_gp_on_cash_if_paid
FROM `sahyadri_b2b.cp_plans`;

-- Who gains and loses when moving from revenue to gross profit commission
SELECT
    IF(pay_b_gross_profit >= pay_a_revenue, 'Gains under GP plan', 'Loses under GP plan') AS outcome,
    COUNT(*)                                                            AS salespeople,
    ROUND(100 * SUM(gross_profit) / SUM(net_revenue), 1)                AS gp_margin_pct,
    ROUND(100 * SUM(gross_value - net_revenue) / SUM(gross_value), 1)   AS discount_pct,
    ROUND(SUM(pay_b_gross_profit - pay_a_revenue) / 1e5, 2)             AS net_change_lakh
FROM `sahyadri_b2b.cp_plans`
GROUP BY outcome
ORDER BY outcome DESC;

-- Quota plan: who earns the above-quota rate, and why
SELECT
    employee_id, employee_name, hire_date, prior_months,
    ROUND(prior_revenue / 1e5, 1)                                       AS prior_revenue_lakh,
    ROUND(quota / 1e5, 1)                                               AS quota_lakh,
    ROUND(net_revenue / 1e5, 1)                                         AS revenue_lakh,
    ROUND(100 * net_revenue / quota, 0)                                 AS pct_of_quota,
    ROUND(pay_c_quota_tiers / 1e5, 2)                                   AS c_quota_tiers_lakh,
    ROUND(pay_a_revenue / 1e5, 2)                                       AS a_revenue_lakh
FROM `sahyadri_b2b.cp_plans`
ORDER BY net_revenue / quota DESC;
