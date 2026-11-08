/* =============================================================================
   Case study · Would trade credit insurance have paid our bad debts? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE credit_days        INT64   DEFAULT 45;
DECLARE default_after_days INT64   DEFAULT 180;
DECLARE max_extension_days INT64   DEFAULT 60;
DECLARE insured_pct        FLOAT64 DEFAULT 0.90;
DECLARE data_end           DATE    DEFAULT DATE '2026-09-30';

WITH t AS (SELECT * FROM `sahyadri_b2b.ti_tests`),

src AS (
    SELECT o.order_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS amount,
           MAX(d.last_delivery) AS invoice_date
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN (SELECT order_id, MAX(delivery_date) AS last_delivery FROM `sahyadri_b2b.shipments`
          GROUP BY order_id HAVING COUNTIF(delivery_date IS NULL) = 0) AS d ON d.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_id
),
in_scope AS (
    SELECT * FROM src WHERE DATE_ADD(invoice_date, INTERVAL 225 DAY) <= data_end
),
paid AS (
    SELECT order_id, SUM(amount) AS paid FROM `sahyadri_b2b.payments` WHERE payment_date <= data_end GROUP BY order_id
),
-- the date each invoice's unpaid balance first fell to Rs 1 or less (NULL if never)
running AS (
    SELECT p.order_id, p.payment_date,
           SUM(p.amount) OVER (PARTITION BY p.order_id ORDER BY p.payment_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_paid
    FROM `sahyadri_b2b.payments` AS p
),
cleared AS (
    SELECT t.order_id, MIN(IF(r.cum_paid >= t.amount - 1, r.payment_date, NULL)) AS cleared_on
    FROM t LEFT JOIN running AS r ON r.order_id = t.order_id
    GROUP BY t.order_id
),
overdue_recount AS (
    SELECT a.order_id,
           COUNTIF(b.order_id IS NOT NULL) > 0 AS delivered_while_overdue
    FROM t AS a
    LEFT JOIN (SELECT t.*, c.cleared_on FROM t JOIN cleared AS c USING (order_id)) AS b
      ON b.customer_id = a.customer_id
     AND DATE_ADD(b.due_date, INTERVAL 60 DAY) < a.invoice_date
     AND (b.cleared_on IS NULL OR b.cleared_on >= a.invoice_date)
    GROUP BY a.order_id
),
last_payment AS (
    SELECT o.customer_id, MAX(p.payment_date) AS last_payment_date
    FROM `sahyadri_b2b.payments` AS p JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
    WHERE p.payment_date <= data_end
    GROUP BY o.customer_id
),

checks AS (
    SELECT '01. Invoices = fully delivered orders with a default date by 30 September 2026, amount = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM t) - (SELECT COUNT(*) FROM in_scope))
         + IF(ABS((SELECT SUM(amount) FROM t) - (SELECT SUM(amount) FROM in_scope)) > 1, 1, 0)
         + (SELECT COUNT(*) FROM t JOIN in_scope AS s USING (order_id) WHERE t.invoice_date != s.invoice_date) AS actual
    UNION ALL
    SELECT '02. Due date = invoice + 45 days, default date = due date + 180 days', 0,
           (SELECT COUNTIF(DATE_DIFF(due_date, invoice_date, DAY) != credit_days
                        OR DATE_DIFF(default_date, due_date, DAY) != default_after_days) FROM t)
    UNION ALL
    SELECT '03. Loss = MAX(0, amount - payments to 30 September 2026), recount', 0,
           (SELECT COUNTIF(ABS(t.loss - GREATEST(0, t.amount - IFNULL(p.paid, 0))) > 1e-6) FROM t LEFT JOIN paid AS p USING (order_id))
    UNION ALL
    SELECT '04. Paid by the default date never exceeds paid by 30 September 2026', 0,
           (SELECT COUNTIF(paid_by_default_date > paid_by_data_end + 1e-6) FROM t)
    UNION ALL
    SELECT '05. Delivered while overdue = recount from the date each earlier invoice was cleared', 0,
           (SELECT COUNTIF(t.delivered_while_overdue != r.delivered_while_overdue) FROM t JOIN overdue_recount AS r USING (order_id))
    UNION ALL
    SELECT '06. Customer kept paying = the customer''s last payment is after the default date', 0,
           (SELECT COUNTIF((t.customer_paid_after_default > 0) != (lp.last_payment_date > t.default_date))
              FROM t JOIN last_payment AS lp USING (customer_id) WHERE t.loss > 1)
    UNION ALL
    SELECT '07. Every invoice has one class, paid only when nothing is lost, classes add up to the total loss', 0,
           (SELECT COUNTIF(loss_class IS NULL OR ((loss_class = '0. Paid') != (loss <= 1))) FROM t)
         + IF(ABS((SELECT SUM(s) FROM (SELECT loss_class, SUM(loss) AS s FROM t GROUP BY loss_class)) - (SELECT SUM(loss) FROM t)) > 1e-3, 1, 0)
    UNION ALL
    SELECT '08. Insurable = lost, not delivered while overdue, no customer payment after the default date', 0,
           (SELECT COUNTIF((loss_class LIKE '3.%')
                        != (loss > 1 AND NOT delivered_while_overdue AND customer_paid_after_default = 0)) FROM t)
    UNION ALL
    SELECT '09. Claims = 90 % of losses recounted from the two independent tests (cleared dates, last payment)', 0,
           IF(ABS((SELECT insured_pct * SUM(IF(loss_class LIKE '3.%', loss, 0)) FROM t)
                  - (SELECT 0.9 * SUM(t.loss) FROM t
                       JOIN overdue_recount AS r USING (order_id)
                       LEFT JOIN last_payment AS lp USING (customer_id)
                      WHERE t.loss > 1 AND NOT r.delivered_while_overdue
                        AND (lp.last_payment_date IS NULL OR lp.last_payment_date <= t.default_date))) > 1e-3, 1, 0)
    UNION ALL
    SELECT '10. Turnover delivered while overdue + insurable turnover = all turnover', 0,
           IF(ABS((SELECT SUM(IF(delivered_while_overdue, amount, 0)) + SUM(IF(NOT delivered_while_overdue, amount, 0)) FROM t)
                  - (SELECT SUM(amount) FROM t)) > 1e-3, 1, 0)
         + (SELECT COUNTIF(delivered_while_overdue IS NULL) FROM t)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
