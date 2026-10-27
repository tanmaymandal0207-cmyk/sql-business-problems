/* =============================================================================
   Case study · Sales commission plan simulation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE period_start DATE    DEFAULT DATE '2025-10-01';
DECLARE period_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE prior_start  DATE    DEFAULT DATE '2024-10-01';
DECLARE budget_rate  FLOAT64 DEFAULT 0.02;
DECLARE quota_uplift FLOAT64 DEFAULT 1.10;
DECLARE above_quota_multiple FLOAT64 DEFAULT 3.0;

WITH p AS (SELECT * FROM `sahyadri_b2b.cp_plans`),

src AS (
    SELECT o.employee_id,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))                       AS rev,
           SUM(IF(pr.unit_cost IS NULL, 0, i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)
                                           - i.quantity * pr.unit_cost))                                   AS gp
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS pr ON pr.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN period_start AND period_end
    GROUP BY o.employee_id
),
-- GP of fully paid orders, rebuilt order by order
order_gp AS (
    SELECT o.order_id, o.employee_id,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))                       AS v,
           SUM(IF(pr.unit_cost IS NULL, 0, i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)
                                           - i.quantity * pr.unit_cost))                                   AS gp
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS pr ON pr.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN period_start AND period_end
    GROUP BY o.order_id, o.employee_id
),
collected AS (
    SELECT g.employee_id, SUM(g.gp) AS gp
    FROM order_gp AS g
    JOIN (SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date <= period_end GROUP BY order_id) AS x
      ON x.order_id = g.order_id
    WHERE x.paid >= g.v - 0.05
    GROUP BY g.employee_id
),

checks AS (
    SELECT '01. Revenue and GP per salesperson = source (rupees)' AS check_name, 0 AS expected,
           (SELECT COUNTIF(ABS(p.net_revenue - s.rev) > 0.5 OR ABS(p.gross_profit - s.gp) > 0.5)
              FROM p JOIN src AS s USING (employee_id)) AS actual
    UNION ALL
    SELECT '02. 15 salespeople, no Head of Sales, no unassigned orders', 0,
           ABS((SELECT COUNT(*) FROM p) - 15) + (SELECT COUNTIF(designation = 'Head of Sales' OR employee_id IS NULL) FROM p)
    UNION ALL
    SELECT '03. Every plan costs exactly the budget (paise)', 0,
           (SELECT CAST(ROUND(100 * (ABS(SUM(pay_b_gross_profit) - SUM(pay_a_revenue)) + ABS(SUM(pay_c_quota_tiers) - SUM(pay_a_revenue))
                                   + ABS(SUM(pay_d_gp_on_cash) - SUM(pay_a_revenue)))) AS INT64) FROM p)
    UNION ALL
    SELECT '04. Plan A = 2 % of net revenue for everyone', 0,
           (SELECT COUNTIF(ABS(pay_a_revenue - budget_rate * net_revenue) > 1e-6) FROM p)
    UNION ALL
    SELECT '05. Plan B pays the same share of GP to everyone', 0,
           (SELECT COUNTIF(ABS(pay_b_gross_profit / gross_profit - rate_b) > 1e-12) FROM p)
    UNION ALL
    SELECT '06. Quota = 1.10 x prior revenue annualised for months employed (1-12)', 0,
           (SELECT COUNTIF(prior_months < 1 OR prior_months > 12
                        OR ABS(quota - quota_uplift * prior_revenue * 12 / prior_months) > 1e-6) FROM p)
    UNION ALL
    SELECT '07. Plan C = k x (revenue to quota + 3 x revenue above quota)', 0,
           (SELECT COUNTIF(ABS(pay_c_quota_tiers - rate_c * (LEAST(net_revenue, quota) + above_quota_multiple * GREATEST(net_revenue - quota, 0))) > 1e-6) FROM p)
    UNION ALL
    SELECT '08. Collected GP = rebuild from fully paid orders (rupees)', 0,
           (SELECT COUNTIF(ABS(p.gp_collected - IFNULL(c.gp, 0)) > 0.5) FROM p LEFT JOIN collected AS c USING (employee_id))
    UNION ALL
    SELECT '09. Plan D pays the same share of collected GP to everyone', 0,
           (SELECT COUNTIF(ABS(pay_d_gp_on_cash - rate_d * gp_collected) > 1e-6) FROM p)
    UNION ALL
    SELECT '10. Prior revenue = source for the prior 12 months (rupees)', 0,
           (SELECT COUNTIF(ABS(p.prior_revenue - IFNULL(x.rev, 0)) > 0.5) FROM p LEFT JOIN (
                SELECT o.employee_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS rev
                FROM `sahyadri_b2b.sales_orders` AS o JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
                WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date >= prior_start AND o.order_date < period_start
                GROUP BY o.employee_id) AS x USING (employee_id))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
