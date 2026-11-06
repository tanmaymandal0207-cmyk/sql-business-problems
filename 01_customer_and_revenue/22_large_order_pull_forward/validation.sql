/* =============================================================================
   Case study · Do large orders steal next quarter's demand? — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE first_day    DATE    DEFAULT DATE '2024-01-01';
DECLARE last_day     DATE    DEFAULT DATE '2026-09-30';
DECLARE large_order  FLOAT64 DEFAULT 500000;
DECLARE placebo_sets INT64   DEFAULT 400;

WITH o AS (SELECT * FROM `sahyadri_b2b.po_orders`),
     dy AS (SELECT * FROM `sahyadri_b2b.po_days`),
     sc AS (SELECT * FROM `sahyadri_b2b.po_scores`),
     st AS (SELECT * FROM `sahyadri_b2b.po_sets`),

src AS (
    SELECT COUNT(DISTINCT x.order_id) AS n,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS x
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = x.order_id
    WHERE x.order_status NOT IN ('Cancelled', 'Returned') AND x.order_date BETWEEN first_day AND last_day
),
n AS (SELECT COUNT(*) AS days FROM dy),
expected_events AS (
    SELECT w, COUNTIF(o.value >= large_order AND o.t >= w + 1 AND o.t <= n.days - 1 - w) AS events
    FROM o CROSS JOIN n CROSS JOIN UNNEST([30, 60, 90, 180]) AS w
    GROUP BY w
),
own_recount AS (
    -- the customer's own windows, recounted from orders, for the actual events and five placebo sets
    SELECT sc.w, sc.e, sc.k,
           ANY_VALUE(sc.before_base) AS before_base, ANY_VALUE(sc.after_base) AS after_base,
           ANY_VALUE(sc.before_large) AS before_large, ANY_VALUE(sc.after_large) AS after_large,
           SUM(IF(x.t BETWEEN sc.t - sc.w AND sc.t - 1, x.value, 0))                  AS before_all,
           SUM(IF(x.t BETWEEN sc.t + 1 AND sc.t + sc.w, x.value, 0))                  AS after_all,
           SUM(IF(x.t BETWEEN sc.t - sc.w AND sc.t - 1 AND x.value < large_order, x.value, 0)) AS before_b,
           SUM(IF(x.t BETWEEN sc.t + 1 AND sc.t + sc.w AND x.value < large_order, x.value, 0)) AS after_b
    FROM sc LEFT JOIN o AS x ON x.customer_id = sc.customer_id
    WHERE sc.k <= 5
    GROUP BY sc.w, sc.e, sc.k
),
market_recount AS (
    -- everyone else's base revenue over the same days, recounted from orders (90-day window, actual events)
    SELECT sc.e, ANY_VALUE(sc.market_before) AS market_before, ANY_VALUE(sc.market_after) AS market_after,
           SUM(IF(x.t BETWEEN sc.t - 90 AND sc.t - 1, x.value, 0))                    AS mb,
           SUM(IF(x.t BETWEEN sc.t + 1 AND sc.t + 90, x.value, 0))                    AS ma
    FROM sc JOIN o AS x ON x.customer_id != sc.customer_id AND x.value < large_order AND x.t BETWEEN sc.t - 90 AND sc.t + 90
    WHERE sc.w = 90 AND sc.k = 0
    GROUP BY sc.e
),
sets_recount AS (
    SELECT w, k, COUNT(*) AS events,
           (SUM(after_base) / SUM(before_base)) / (SUM(market_after) / SUM(market_before)) AS rel
    FROM sc GROUP BY w, k
),

checks AS (
    SELECT '01. Orders and revenue = source (valid orders, January 2024 - September 2026)' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM o) - (SELECT n FROM src))
         + IF(ABS((SELECT SUM(value) FROM o) - (SELECT v FROM src)) > 1, 1, 0) AS actual
    UNION ALL
    SELECT '02. One row per day, cumulative base = all orders below Rs 5 lakh', 0,
           ABS((SELECT COUNT(*) FROM dy) - (DATE_DIFF(last_day, first_day, DAY) + 1))
         + IF(ABS((SELECT MAX(cum_base) FROM dy) - (SELECT SUM(value) FROM o WHERE value < large_order)) > 1, 1, 0)
         + IF(ABS((SELECT SUM(base) FROM dy) - (SELECT MAX(cum_base) FROM dy)) > 1, 1, 0)
    UNION ALL
    SELECT '03. Events = large orders with a full window on both sides, by window', 0,
           (SELECT COUNT(*) FROM expected_events AS x
              LEFT JOIN (SELECT w, COUNT(*) AS events FROM sc WHERE k = 0 GROUP BY w) AS y USING (w)
             WHERE IFNULL(y.events, 0) != x.events)
         + (SELECT COUNTIF(event_value < large_order) FROM sc WHERE k = 0)
    UNION ALL
    SELECT '04. Every event has 400 placebo dates, all inside the valid range', 0,
           (SELECT COUNT(*) FROM (SELECT w, e, COUNT(*) AS c FROM sc GROUP BY w, e) WHERE c != placebo_sets + 1)
         + (SELECT COUNTIF(t < w + 1 OR t > (SELECT days FROM n) - 1 - w) FROM sc)
    UNION ALL
    SELECT '05. Placebo dates belong to the event''s customer and order', 0,
           (SELECT COUNT(*) FROM (SELECT w, e, COUNT(DISTINCT customer_id) AS c, COUNT(DISTINCT order_id) AS oi FROM sc GROUP BY w, e) WHERE c != 1 OR oi != 1)
    UNION ALL
    SELECT '06. Own base revenue before and after = recount from orders (actual and 5 placebo sets)', 0,
           (SELECT COUNTIF(ABS(before_base - before_b) > 1e-6 OR ABS(after_base - after_b) > 1e-6) FROM own_recount)
    UNION ALL
    SELECT '07. Base + large = every order in the window, the date itself left out', 0,
           (SELECT COUNTIF(ABS(before_base + before_large - before_all) > 1e-6 OR ABS(after_base + after_large - after_all) > 1e-6) FROM own_recount)
    UNION ALL
    SELECT '08. Market base before and after = recount of other customers (90-day window)', 0,
           (SELECT COUNTIF(ABS(market_before - mb) > 1e-3 OR ABS(market_after - ma) > 1e-3) FROM market_recount)
         + ABS((SELECT COUNT(*) FROM market_recount) - (SELECT COUNT(*) FROM sc WHERE w = 90 AND k = 0))
    UNION ALL
    SELECT '09. Relative change per set = recount from the event scores', 0,
           (SELECT COUNT(*) FROM st JOIN sets_recount AS r USING (w, k)
             WHERE st.events != r.events OR ABS(st.relative_change - r.rel) > 1e-9)
         + ABS((SELECT COUNT(*) FROM st) - 4 * (placebo_sets + 1))
    UNION ALL
    SELECT '10. Placebo dates spread over the range (average within 3 % of the midpoint)', 0,
           (SELECT COUNTIF(ABS(avg_t - mid) > 0.03 * mid) FROM (
               SELECT w, AVG(t) AS avg_t, (w + 1 + ((SELECT days FROM n) - 1 - w)) / 2 AS mid
               FROM sc WHERE k > 0 GROUP BY w))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
