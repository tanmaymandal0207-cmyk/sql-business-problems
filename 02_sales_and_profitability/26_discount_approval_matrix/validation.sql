/* =============================================================================
   Case study · A discount approval matrix — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_order       DATE    DEFAULT DATE '2024-01-01';
DECLARE last_order        DATE    DEFAULT DATE '2026-09-30';
DECLARE calibration_end   DATE    DEFAULT DATE '2025-12-31';

WITH l AS (SELECT * FROM `sahyadri_b2b.da_lines`),
     o AS (SELECT * FROM `sahyadri_b2b.da_orders`),
     c AS (SELECT * FROM `sahyadri_b2b.da_segment_caps`),

src AS (
    SELECT COUNT(*) AS n, COUNT(DISTINCT o.order_id) AS orders,
           SUM(i.quantity * i.unit_price) AS gross,
           SUM(i.quantity * i.unit_price * IFNULL(i.discount_percent, 0) / 100) AS disc
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_date BETWEEN first_order AND last_order
),
recount AS (
    SELECT order_id, SUM(gross_value) AS g, SUM(gross_value * discount_pct / 100) AS d, MAX(discount_pct) AS m, COUNT(*) AS n
    FROM l GROUP BY order_id
),
segment_ss AS (
    SELECT
        (SELECT SUM(POW(max_discount_pct - (SELECT AVG(max_discount_pct) FROM o), 2)) FROM o) AS total_ss,
        (SELECT SUM(POW(o.max_discount_pct - g.m, 2)) FROM o
           JOIN (SELECT customer_segment, AVG(max_discount_pct) AS m FROM o GROUP BY customer_segment) AS g USING (customer_segment)) AS within_ss,
        (SELECT SUM(n * POW(m - (SELECT AVG(max_discount_pct) FROM o), 2))
           FROM (SELECT customer_segment, COUNT(*) AS n, AVG(max_discount_pct) AS m FROM o GROUP BY customer_segment)) AS between_ss
),

checks AS (
    SELECT '01. Lines = order items of orders dated January 2024 - September 2026, gross and discount = source' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM l) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(gross_value) FROM l) - (SELECT gross FROM src)) > 1, 1, 0)
         + IF(ABS((SELECT SUM(gross_value * discount_pct / 100) FROM l) - (SELECT disc FROM src)) > 1, 1, 0)
         + (SELECT COUNTIF(discount_pct IS NULL) FROM l) AS actual
    UNION ALL
    SELECT '02. Order gross value, discount given, maximum line discount and line count = recount from lines', 0,
           (SELECT COUNTIF(ABS(o.gross_value - r.g) > 1e-6 OR ABS(o.discount_given - r.d) > 1e-6 OR o.max_discount_pct != r.m OR o.lines != r.n)
              FROM o JOIN recount AS r USING (order_id))
    UNION ALL
    SELECT '03. Every order kept, title limit missing only when no salesperson is recorded', 0,
           ABS((SELECT COUNT(*) FROM o) - (SELECT orders FROM src))
         + (SELECT COUNTIF((title_limit_pct IS NULL) != (employee_id IS NULL)) FROM o)
         + (SELECT COUNTIF((title_approver = 'No salesperson recorded') != (employee_id IS NULL)) FROM o)
    UNION ALL
    SELECT '04. Approver = own authority up to the title limit, else the lowest title whose limit covers the discount', 0,
           (SELECT COUNTIF(title_approver != CASE
                        WHEN title_limit_pct IS NULL THEN 'No salesperson recorded'
                        WHEN max_discount_pct <= title_limit_pct THEN 'Own authority'
                        WHEN max_discount_pct <= (SELECT limit_pct FROM `sahyadri_b2b.da_title_limits` WHERE approval_level = 2) THEN 'Senior Sales Executive'
                        WHEN max_discount_pct <= (SELECT MAX(limit_pct) FROM `sahyadri_b2b.da_title_limits` WHERE approval_level = 3) THEN 'Manager (KAM or RSM)'
                        WHEN max_discount_pct <= (SELECT limit_pct FROM `sahyadri_b2b.da_title_limits` WHERE approval_level = 4) THEN 'Head of Sales'
                        ELSE 'Managing Director' END) FROM o)
    UNION ALL
    SELECT '05. Size bands: under Rs 25,000, Rs 25,000 - 1 lakh, Rs 1 - 5 lakh, Rs 5 lakh and above', 0,
           (SELECT COUNTIF((size_band LIKE '1.%' AND gross_value >= 25000)
                        OR (size_band LIKE '2.%' AND (gross_value < 25000 OR gross_value >= 100000))
                        OR (size_band LIKE '3.%' AND (gross_value < 100000 OR gross_value >= 500000))
                        OR (size_band LIKE '4.%' AND gross_value < 500000)) FROM o)
    UNION ALL
    SELECT '06. Segment cap = the highest order discount the segment received in 2024 - 2025 (recount)', 0,
           (SELECT COUNT(*) FROM c FULL OUTER JOIN
               (SELECT customer_segment, MAX(max_discount_pct) AS m, COUNT(*) AS n FROM o WHERE order_date <= calibration_end
                GROUP BY customer_segment) AS r USING (customer_segment)
             WHERE c.segment_cap_pct IS NULL OR r.m IS NULL OR c.segment_cap_pct != r.m OR c.calibration_orders != r.n)
    UNION ALL
    SELECT '07. Four segments, every order has a cap, and a line-level recount finds no line above its segment cap', 0,
           ABS((SELECT COUNT(*) FROM c) - 4)
         + (SELECT COUNT(*) FROM o LEFT JOIN c USING (customer_segment) WHERE c.segment_cap_pct IS NULL)
         + (SELECT COUNT(*) FROM l
              JOIN `sahyadri_b2b.sales_orders` AS so ON so.order_id = l.order_id
              JOIN `sahyadri_b2b.customers` AS cu ON cu.customer_id = so.customer_id
              JOIN c ON c.customer_segment = cu.customer_segment
             WHERE l.discount_pct > c.segment_cap_pct AND l.order_date <= calibration_end)
    UNION ALL
    SELECT '08. Calibration period = orders dated to 31 December 2025', 0,
           (SELECT COUNTIF(calibration_period != (order_date <= calibration_end)) FROM o)
    UNION ALL
    SELECT '09. Discount above the title limit never exceeds the discount given, line by line', 0,
           (SELECT COUNTIF(l.gross_value * GREATEST(0, l.discount_pct - o.title_limit_pct) > l.gross_value * l.discount_pct + 1e-9)
              FROM l JOIN o USING (order_id) WHERE o.title_limit_pct IS NOT NULL)
    UNION ALL
    SELECT '10. Variance by segment: between + within = total sum of squares', 0,
           IF(ABS((SELECT between_ss + within_ss - total_ss FROM segment_ss)) > 1e-3, 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
