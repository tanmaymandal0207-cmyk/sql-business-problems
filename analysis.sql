/* =============================================================================
   Case study · Next order due: whose ordering rhythm has slipped
   Category : Advanced analytics
   Every reordering customer has a rhythm (median gap between orders).
   Field wants a due-list: who is overdue against their own rhythm, and
   does the rule actually predict reorders? Back-tested, no look-ahead.
     1. What is each customer's typical gap and spread?
     2. Who is overdue today, and by how much?
     3. Does overdue-against-own-rhythm predict who reorders next month?
   METHOD: customers with >=3 orders to Sep 2026; gaps = date_diff of
   consecutive orders; rhythm = median gap (p50), spread = p90-p50;
   due = last order + median gap; as-of 2026-09-30; back-test as-of
   2026-06-30 predicting July 2026 reorders; AUC from Mann-Whitney rank.
   ============================================================================= */
DECLARE data_end DATE DEFAULT DATE '2026-09-30';
DECLARE backtest_asof DATE DEFAULT DATE '2026-06-30';

CREATE OR REPLACE TABLE `sahyadri_b2b.no_gaps` AS
WITH ords AS (
  SELECT customer_id, order_date, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS rn
  FROM `sahyadri_b2b.sales_orders` WHERE order_status NOT IN ('Cancelled') AND order_date <= data_end
),
g AS (
  SELECT a.customer_id, DATE_DIFF(b.order_date, a.order_date, DAY) AS gap
  FROM ords AS a JOIN ords AS b ON b.customer_id = a.customer_id AND b.rn = a.rn + 1
)
SELECT customer_id, COUNT(*) + 1 AS orders,
  APPROX_QUANTILES(gap, 100)[OFFSET(50)] AS median_gap,
  APPROX_QUANTILES(gap, 100)[OFFSET(90)] AS p90_gap,
  AVG(gap) AS mean_gap FROM g GROUP BY customer_id HAVING COUNT(*) >= 2;

CREATE OR REPLACE TABLE `sahyadri_b2b.no_due` AS
WITH lastord AS (SELECT customer_id, MAX(order_date) AS last_date FROM `sahyadri_b2b.sales_orders`
  WHERE order_status NOT IN ('Cancelled') AND order_date <= data_end GROUP BY customer_id)
SELECT g.customer_id, c.customer_name, c.customer_segment, g.orders, g.median_gap, g.p90_gap,
  l.last_date, DATE_ADD(l.last_date, INTERVAL g.median_gap DAY) AS due_date,
  DATE_DIFF(data_end, l.last_date, DAY) AS days_since_last,
  DATE_DIFF(data_end, DATE_ADD(l.last_date, INTERVAL g.median_gap DAY), DAY) AS days_overdue,
  DATE_DIFF(data_end, l.last_date, DAY) > g.median_gap AS is_overdue,
  DATE_DIFF(data_end, l.last_date, DAY) > g.p90_gap AS is_far_overdue
FROM `sahyadri_b2b.no_gaps` AS g JOIN lastord AS l USING (customer_id)
JOIN `sahyadri_b2b.customers` AS c USING (customer_id);

SELECT COUNT(*) AS scored_customers, COUNTIF(is_overdue) AS overdue, COUNTIF(is_far_overdue) AS far_overdue,
  ROUND(100*COUNTIF(is_overdue)/COUNT(*),1) AS overdue_pct FROM `sahyadri_b2b.no_due`;
SELECT customer_name, customer_segment, orders, median_gap, last_date, due_date, days_overdue
FROM `sahyadri_b2b.no_due` WHERE is_overdue ORDER BY days_overdue DESC LIMIT 25;

-- Back-test: as-of 2026-06-30, does days-overdue rank July reorderers above the rest (AUC)?
WITH hist AS (
  SELECT customer_id, order_date FROM `sahyadri_b2b.sales_orders`
  WHERE order_status NOT IN ('Cancelled') AND order_date <= backtest_asof
),
gaps AS (
  SELECT customer_id, DATE_DIFF(order_date, LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date), DAY) AS gap
  FROM hist
),
rhythm AS (
  SELECT customer_id, APPROX_QUANTILES(gap, 100)[OFFSET(50)] AS med FROM gaps WHERE gap IS NOT NULL
  GROUP BY customer_id HAVING COUNT(gap) >= 2
),
scored AS (
  SELECT r.customer_id, DATE_DIFF(backtest_asof, MAX(h.order_date), DAY) - r.med AS overdue_days,
         MAX(IF(o.order_date BETWEEN DATE_ADD(backtest_asof, INTERVAL 1 DAY) AND DATE_ADD(backtest_asof, INTERVAL 31 DAY), 1, 0)) AS reordered
  FROM rhythm AS r JOIN hist AS h USING (customer_id)
  LEFT JOIN `sahyadri_b2b.sales_orders` AS o ON o.customer_id = r.customer_id
    AND o.order_status NOT IN ('Cancelled') AND o.order_date BETWEEN DATE_ADD(backtest_asof, INTERVAL 1 DAY) AND DATE_ADD(backtest_asof, INTERVAL 31 DAY)
  GROUP BY r.customer_id, r.med
),
ranked AS (SELECT *, RANK() OVER (ORDER BY overdue_days) AS rk FROM scored)
SELECT COUNT(*) AS n, SUM(reordered) AS reordered,
  ROUND((SUM(IF(reordered=1, rk, 0)) - SUM(reordered)*(SUM(reordered)+1)/2) / (SUM(reordered)*(COUNT(*)-SUM(reordered))), 3) AS auc
FROM ranked;
