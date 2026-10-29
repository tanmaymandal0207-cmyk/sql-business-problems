/* =============================================================================
   Case study · Cash application matching — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE tolerance FLOAT64 DEFAULT 0.05;

WITH r AS (SELECT * FROM `sahyadri_b2b.ca_receipts`),
     c AS (SELECT * FROM `sahyadri_b2b.ca_candidates`),
     m AS (SELECT * FROM `sahyadri_b2b.ca_matches`),

order_value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
-- open balance of the true order just before each receipt, from a running total
running AS (
    SELECT p.payment_id, p.order_id, o.order_date, p.payment_date, v.order_value,
           v.order_value - (SUM(p.amount) OVER (PARTITION BY p.order_id ORDER BY p.payment_date, p.payment_id
                                                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) - p.amount) AS open_before
    FROM `sahyadri_b2b.payments` AS p
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
    JOIN order_value AS v ON v.order_id = p.order_id
),
fit_counts AS (
    SELECT payment_id, COUNTIF(fits_invoice) AS inv, COUNTIF(fits_balance) AS bal
    FROM c
    GROUP BY payment_id
),
instalments AS (
    SELECT true_order_id, MAX(payments_on_order) AS n, MAX(instalment_no) AS max_no,
           COUNT(DISTINCT instalment_no) AS distinct_no, MIN(instalment_no) AS min_no
    FROM r
    GROUP BY true_order_id
),

checks AS (
    SELECT '01. One receipt per payment' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM r) - (SELECT COUNT(*) FROM `sahyadri_b2b.payments`))
         + (SELECT COUNT(*) - COUNT(DISTINCT payment_id) FROM r) AS actual
    UNION ALL
    SELECT '02. Instalments are numbered 1 to n on every order', 0,
           (SELECT COUNTIF(min_no != 1 OR max_no != n OR distinct_no != n) FROM instalments)
    UNION ALL
    SELECT '03. Round-sum flag = recount (whole multiple of Rs 1,000)', 0,
           (SELECT COUNTIF(is_round_sum != (ABS(amount / 1000 - ROUND(amount / 1000)) < 1e-9)) FROM r)
    UNION ALL
    SELECT '04. Receipt customer and order value = source', 0,
           (SELECT COUNTIF(r.customer_id != o.customer_id OR ABS(r.order_value - v.order_value) > 0.01)
              FROM r
              JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = r.true_order_id
              JOIN order_value AS v ON v.order_id = r.true_order_id)
    UNION ALL
    SELECT '05. Every candidate is the same customer''s order placed by the receipt date', 0,
           (SELECT COUNTIF(o.customer_id != r.customer_id OR o.order_date > r.payment_date)
              FROM c
              JOIN r ON r.payment_id = c.payment_id
              JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = c.order_id)
    UNION ALL
    SELECT '06. Open balance of the true order = running-total recount', 0,
           (SELECT COUNTIF(ABS(c.open_balance - x.open_before) > 0.01)
              FROM c JOIN running AS x ON x.payment_id = c.payment_id AND x.order_id = c.order_id)
    UNION ALL
    SELECT '07. True order is a candidate exactly when it is open and already placed', 0,
           (SELECT COUNTIF((x.order_date <= x.payment_date AND x.open_before > tolerance) != (c.payment_id IS NOT NULL))
              FROM running AS x
              LEFT JOIN c ON c.payment_id = x.payment_id AND c.order_id = x.order_id)
    UNION ALL
    SELECT '08. One match result per receipt, from the four categories', 0,
           ABS((SELECT COUNT(*) FROM m) - (SELECT COUNT(*) FROM r))
         + (SELECT COUNTIF(match_result IS NULL OR match_result NOT IN
                ('R1. Exact invoice amount', 'R2. Exact open balance', 'X1. Ambiguous', 'X2. No match')) FROM m)
    UNION ALL
    SELECT '09. R1 and R2 counts = recount from candidate fits', 0,
           ABS((SELECT COUNTIF(match_result LIKE 'R1%') FROM m) - (SELECT COUNTIF(inv = 1) FROM fit_counts))
         + ABS((SELECT COUNTIF(match_result LIKE 'R2%') FROM m) - (SELECT COUNTIF(inv = 0 AND bal = 1) FROM fit_counts))
    UNION ALL
    SELECT '10. Matched order is set only for R1/R2 and is one of the receipt''s candidates', 0,
           (SELECT COUNTIF((matched_order_id IS NOT NULL) != (match_result LIKE 'R%')) FROM m)
         + (SELECT COUNT(*) FROM m
             WHERE matched_order_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM c WHERE c.payment_id = m.payment_id AND c.order_id = m.matched_order_id))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
