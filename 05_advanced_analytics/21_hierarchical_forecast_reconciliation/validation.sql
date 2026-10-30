/* =============================================================================
   Case study · Hierarchical forecast reconciliation — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE start_month  DATE  DEFAULT DATE '2024-01-01';
DECLARE end_month    DATE  DEFAULT DATE '2026-09-01';
DECLARE fit_last_t   INT64 DEFAULT 12;
DECLARE share_months INT64 DEFAULT 12;

WITH s AS (SELECT * FROM `sahyadri_b2b.hf_series`),
     e AS (SELECT * FROM `sahyadri_b2b.hf_ses`),
     a AS (SELECT * FROM `sahyadri_b2b.hf_alpha`),
     f AS (SELECT * FROM `sahyadri_b2b.hf_forecasts`),

src AS (
    SELECT SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date >= start_month AND o.order_date < DATE_ADD(end_month, INTERVAL 1 MONTH)
),
month_sums AS (
    SELECT t, SUM(IF(is_total, revenue, 0)) AS total, SUM(IF(is_total, 0, revenue)) AS cats FROM s GROUP BY t
),
recursion AS (
    SELECT cur.series, cur.alpha, cur.t, cur.forecast,
           cur.alpha * prev_y.revenue + (1 - cur.alpha) * prev.forecast AS by_recursion
    FROM e AS cur
    JOIN e AS prev ON prev.series = cur.series AND prev.alpha = cur.alpha AND prev.t = cur.t - 1
    JOIN s AS prev_y ON prev_y.series = cur.series AND prev_y.t = cur.t - 1
),
mae AS (
    SELECT series, alpha, AVG(ABS(forecast - actual)) AS m FROM e WHERE t <= fit_last_t GROUP BY series, alpha
),
coherence AS (
    SELECT t,
           SUM(IF(is_total, 0, top_down))  AS td_cats, SUM(IF(is_total, 0, bottom_up)) AS bu_cats,
           SUM(IF(is_total, 0, combined))  AS cb_cats, SUM(IF(is_total, 0, actual))    AS act_cats,
           SUM(IF(is_total, 0, share))     AS shares,
           MAX(IF(is_total, top_down, NULL))  AS td_total, MAX(IF(is_total, bottom_up, NULL)) AS bu_total,
           MAX(IF(is_total, combined, NULL))  AS cb_total, MAX(IF(is_total, actual, NULL))    AS act_total
    FROM f GROUP BY t
),
share_recount AS (
    SELECT c.series, c.t,
           (SELECT SUM(revenue) FROM s AS x WHERE x.series = c.series AND x.t BETWEEN c.t - share_months AND c.t - 1)
         / (SELECT SUM(revenue) FROM s AS x WHERE x.is_total AND x.t BETWEEN c.t - share_months AND c.t - 1) AS share
    FROM f AS c WHERE NOT c.is_total
),

checks AS (
    SELECT '01. 11 series x 33 months, categories add up to the total every month' AS check_name, 0 AS expected,
           ABS(11 * 33 - (SELECT COUNT(*) FROM s)) + (SELECT COUNTIF(ABS(total - cats) > 0.01) FROM month_sums) AS actual
    UNION ALL
    SELECT '02. Total revenue = source recount', 0,
           IF(ABS((SELECT SUM(revenue) FROM s WHERE is_total) - (SELECT v FROM src)) > 1, 1, 0)
    UNION ALL
    SELECT '03. Closed-form smoothing = the recursion F(t) = a y(t-1) + (1 - a) F(t-1), F(2) = y(1)', 0,
           (SELECT COUNTIF(ABS(forecast - by_recursion) > 1e-6 * (1 + ABS(by_recursion))) FROM recursion)
         + (SELECT COUNT(*) FROM e JOIN s AS y1 ON y1.series = e.series AND y1.t = 1 WHERE e.t = 2 AND ABS(e.forecast - y1.revenue) > 1e-6)
    UNION ALL
    SELECT '04. Chosen alpha has the lowest 2024 error for its series', 0,
           (SELECT COUNT(*) FROM a JOIN mae AS m ON m.series = a.series AND m.m < a.mae_2024 - 1e-9)
         + ABS(11 - (SELECT COUNT(*) FROM a))
    UNION ALL
    SELECT '05. Category shares = previous 12 months only, and add up to 1', 0,
           (SELECT COUNTIF(ABS(f.share - r.share) > 1e-12) FROM f JOIN share_recount AS r USING (series, t))
         + (SELECT COUNTIF(ABS(shares - 1) > 1e-9) FROM coherence)
    UNION ALL
    SELECT '06. Coherence: category forecasts add up to the total for every method', 0,
           (SELECT COUNTIF(ABS(td_cats - td_total) > 0.01 OR ABS(bu_cats - bu_total) > 0.01 OR ABS(cb_cats - cb_total) > 0.01
                           OR ABS(act_cats - act_total) > 0.01) FROM coherence)
    UNION ALL
    SELECT '07. Top-down total = the total''s own forecast, combined = average of the two', 0,
           (SELECT COUNT(*) FROM f JOIN e ON e.series = 'Total' AND e.t = f.t
                               JOIN a ON a.series = 'Total' AND a.alpha = e.alpha
             WHERE f.is_total AND ABS(f.top_down - e.forecast) > 0.01)
         + (SELECT COUNTIF(ABS(combined - (top_down + bottom_up) / 2) > 0.01) FROM f)
    UNION ALL
    SELECT '08. Bottom-up category forecast = own smoothing at the chosen alpha', 0,
           (SELECT COUNT(*) FROM f JOIN a ON a.series = f.series JOIN e ON e.series = f.series AND e.alpha = a.alpha AND e.t = f.t
             WHERE NOT f.is_total AND ABS(f.bottom_up - e.forecast) > 0.01)
    UNION ALL
    SELECT '09. Naive forecast = the previous month''s actual', 0,
           (SELECT COUNT(*) FROM f JOIN s AS p ON p.series = f.series AND p.t = f.t - 1 WHERE ABS(f.naive - p.revenue) > 0.01)
    UNION ALL
    SELECT '10. 21 evaluation months x 11 series, none in the fitting year', 0,
           ABS(21 * 11 - (SELECT COUNT(*) FROM f)) + (SELECT COUNTIF(t <= fit_last_t) FROM f)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
