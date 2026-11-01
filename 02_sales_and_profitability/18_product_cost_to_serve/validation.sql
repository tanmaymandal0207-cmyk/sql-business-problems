/* =============================================================================
   Case study · Product profitability after cost to serve — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE fy_start       DATE    DEFAULT DATE '2025-04-01';
DECLARE fy_end         DATE    DEFAULT DATE '2026-03-31';
DECLARE as_of          DATE    DEFAULT DATE '2026-09-30';
DECLARE cost_of_money  FLOAT64 DEFAULT 0.12;
DECLARE loss_days      INT64   DEFAULT 180;

WITH l AS (SELECT * FROM `sahyadri_b2b.pc_lines`),
     pr AS (SELECT * FROM `sahyadri_b2b.pc_products`),
     rt AS (SELECT * FROM `sahyadri_b2b.pc_rates`),

src AS (
    SELECT COUNT(*) AS n, COUNT(DISTINCT o.order_id) AS orders,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN fy_start AND fy_end
),
-- handling pool recomputed from the employee table
pool AS (
    SELECT SUM(IFNULL(salary, 0) * GREATEST(DATE_DIFF(fy_end, GREATEST(hire_date, fy_start), DAY) + 1, 0)) / 365 AS handling_pool
    FROM `sahyadri_b2b.employees` WHERE department_id IN (4, 5)
),
all_fy_orders AS (
    SELECT COUNT(*) AS n FROM `sahyadri_b2b.sales_orders` WHERE order_date BETWEEN fy_start AND fy_end
),
order_level AS (
    SELECT order_id, ANY_VALUE(order_date) AS order_date, SUM(revenue) AS revenue, SUM(freight_cost) AS freight,
           SUM(handling_cost) AS handling, SUM(value_share) AS shares, SUM(credit_loss) AS loss, SUM(credit_cost) AS credit_cost
    FROM l GROUP BY order_id
),
ship AS (
    SELECT order_id, SUM(IFNULL(shipping_cost, 0)) AS freight,
           IF(COUNT(delivery_date) = COUNT(*), MAX(delivery_date), NULL) AS delivered
    FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
-- payments within the loss window, one row each, with days outstanding
pay AS (
    SELECT p.order_id, p.amount,
           GREATEST(DATE_DIFF(p.payment_date, IFNULL(s.delivered, ol.order_date), DAY), 0) AS days
    FROM `sahyadri_b2b.payments` AS p
    JOIN order_level AS ol ON ol.order_id = p.order_id
    LEFT JOIN ship AS s ON s.order_id = p.order_id
    WHERE p.payment_date <= DATE_ADD(ol.order_date, INTERVAL loss_days DAY)
),
bounds AS (
    SELECT ol.order_id, ol.revenue, ol.loss, ol.credit_cost,
           IFNULL(s.delivered, ol.order_date)                    AS credit_start,
           DATE_ADD(ol.order_date, INTERVAL loss_days DAY)        AS window_end
    FROM order_level AS ol LEFT JOIN ship AS s ON s.order_id = ol.order_id
),
recount AS (
    SELECT b.order_id, b.loss, b.credit_cost,
           GREATEST(b.revenue - IFNULL(SUM(pay.amount), 0), 0) AS loss_recount,
           (IFNULL(SUM(pay.amount * pay.days), 0)
             + GREATEST(b.revenue - IFNULL(SUM(pay.amount), 0), 0) * GREATEST(DATE_DIFF(b.window_end, b.credit_start, DAY), 0))
             * cost_of_money / 365 AS credit_cost_recount
    FROM bounds AS b
    LEFT JOIN pay ON pay.order_id = b.order_id
    GROUP BY b.order_id, b.loss, b.credit_cost, b.revenue, b.window_end, b.credit_start
),
salespeople AS (
    SELECT e.employee_id, e.designation,
           IFNULL(e.salary, 0) * GREATEST(DATE_DIFF(fy_end, GREATEST(e.hire_date, fy_start), DAY) + 1, 0) / 365 AS pay_fy,
           COUNT(o.order_id) AS fy_orders,
           COUNTIF(o.order_status NOT IN ('Cancelled', 'Returned')) AS valid_orders
    FROM `sahyadri_b2b.employees` AS e
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.employee_id = e.employee_id AND o.order_date BETWEEN fy_start AND fy_end
    WHERE e.department_id = 1
    GROUP BY e.employee_id, e.designation, e.salary, e.hire_date
),
curve AS (
    SELECT contribution,
           ROW_NUMBER() OVER (ORDER BY contribution DESC, product_id) AS rk,
           SUM(contribution) OVER (ORDER BY contribution DESC, product_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_c
    FROM pr
),

checks AS (
    SELECT '01. Lines = valid order lines of the financial year, revenue = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM l) - (SELECT n FROM src)) + IF(ABS((SELECT SUM(revenue) FROM l) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. Handling rate = Operations and Supply Chain pay / all orders, charged once per valid order', 0,
           IF(ABS((SELECT per_order FROM rt WHERE rate = 'Handling per order') - (SELECT handling_pool FROM pool) / (SELECT n FROM all_fy_orders)) > 0.01, 1, 0)
         + (SELECT COUNTIF(ABS(handling - (SELECT per_order FROM rt WHERE rate = 'Handling per order')) > 1e-6) FROM order_level)
    UNION ALL
    SELECT '03. Sales effort = each salesperson''s pay x valid / all orders booked, Head of Sales not charged', 0,
           (SELECT COUNTIF(ABS(IFNULL(c.charged, 0) - IF(s.designation = 'Head of Sales', 0, s.pay_fy * s.valid_orders / s.fy_orders)) > 1)
              FROM salespeople AS s
              LEFT JOIN (SELECT employee_id, SUM(sales_effort_cost) AS charged FROM l GROUP BY employee_id) AS c ON c.employee_id = s.employee_id)
    UNION ALL
    SELECT '04. Freight charged = shipping cost of these orders', 0,
           (SELECT COUNTIF(ABS(ol.freight - IFNULL(s.freight, 0)) > 0.01) FROM order_level AS ol LEFT JOIN ship AS s ON s.order_id = ol.order_id)
    UNION ALL
    SELECT '05. Value shares add up to 1 on every order', 0,
           (SELECT COUNTIF(ABS(shares - 1) > 1e-9) FROM order_level)
    UNION ALL
    SELECT '06. Credit loss = order value - payments within 180 days (recount)', 0,
           (SELECT COUNTIF(ABS(loss - loss_recount) > 0.01) FROM recount)
    UNION ALL
    SELECT '07. Cost of credit = rupee-days x 12 % / 365 (recount from single payments)', 0,
           (SELECT COUNTIF(ABS(credit_cost - credit_cost_recount) > 0.01) FROM recount)
         + (SELECT COUNTIF(credit_cost < 0 OR credit_loss < 0) FROM l)
    UNION ALL
    SELECT '08. Every order''s 180-day window closes by the as-of date', 0,
           (SELECT COUNTIF(DATE_ADD(order_date, INTERVAL loss_days DAY) > as_of) FROM order_level)
    UNION ALL
    SELECT '09. Product rows = sum of their lines, contribution = GP - all costs', 0,
           (SELECT COUNTIF(ABS(p.revenue - x.revenue) > 0.01 OR p.lines != x.lines
                           OR ABS(p.contribution - (p.gross_profit - p.freight_cost - p.handling_cost - p.sales_effort_cost - p.credit_cost - p.credit_loss)) > 0.01
                           OR ABS(p.operating_contribution - p.contribution - p.credit_loss) > 0.01)
              FROM pr AS p JOIN (SELECT product_id, SUM(revenue) AS revenue, COUNT(*) AS lines FROM l GROUP BY product_id) AS x USING (product_id))
         + ABS((SELECT COUNT(*) FROM pr) - (SELECT COUNT(DISTINCT product_id) FROM l WHERE unit_cost IS NOT NULL))
    UNION ALL
    SELECT '10. Whale curve ranks run 1 to n and end at total contribution', 0,
           IF((SELECT MAX(rk) FROM curve) != (SELECT COUNT(*) FROM pr), 1, 0)
         + IF(ABS((SELECT cum_c FROM curve WHERE rk = (SELECT MAX(rk) FROM curve)) - (SELECT SUM(contribution) FROM pr)) > 0.01, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
