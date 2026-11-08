/* =============================================================================
   Case study · Goods in transit — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE gst_rate        FLOAT64 DEFAULT 0.18;
DECLARE insured_margin  FLOAT64 DEFAULT 0.10;
DECLARE first_dispatch  DATE    DEFAULT DATE '2024-01-01';
DECLARE data_end        DATE    DEFAULT DATE '2026-09-30';
DECLARE median_transit  INT64   DEFAULT 4;

WITH s AS (SELECT * FROM `sahyadri_b2b.gt_shipments`),
     d AS (SELECT * FROM `sahyadri_b2b.gt_daily`),
     c AS (SELECT * FROM `sahyadri_b2b.gt_conveyances`),
     y AS (SELECT * FROM `sahyadri_b2b.gt_declaration`),

order_value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS v
    FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id
),
by_order AS (
    SELECT order_id, SUM(insured_value) AS insured FROM s GROUP BY order_id
),
on_31_mar AS (
    SELECT SUM(insured_value) AS v FROM s
    WHERE shipment_date <= DATE '2026-03-31' AND (off_road_date > DATE '2026-03-31' OR off_road_date IS NULL)
),
fy_months AS (
    SELECT financial_year, MOD(EXTRACT(MONTH FROM shipment_date) + 8, 12) + 1 AS month_of_year, SUM(insured_value) AS v
    FROM s GROUP BY financial_year, month_of_year
),
growth AS (
    SELECT SUM(IF(financial_year = 2026, v, 0)) / SUM(IF(financial_year = 2025 AND month_of_year <= 6, v, 0)) AS g FROM fy_months
),
fy25_days AS (
    SELECT shipment_date, SUM(SUM(insured_value)) OVER (ORDER BY shipment_date) AS cum
    FROM s WHERE financial_year = 2025 GROUP BY shipment_date
),

checks AS (
    SELECT '01. Shipments = all dispatched January 2024 - September 2026, insured value = order value / shipments x 1.18 x 1.10' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM s)
             - (SELECT COUNT(*) FROM `sahyadri_b2b.shipments` WHERE shipment_date BETWEEN first_dispatch AND data_end))
         + (SELECT COUNTIF(ABS(b.insured - ov.v * (1 + gst_rate) * (1 + insured_margin)) > 1e-3)
              FROM by_order AS b JOIN order_value AS ov USING (order_id))
         + (SELECT COUNTIF(ABS(insured_value - invoice_value * (1 + insured_margin)) > 1e-6) FROM s) AS actual
    UNION ALL
    SELECT '02. Off-road date = delivery date, or dispatch + 4 days for Delivered without a date, open only when In Transit', 0,
           (SELECT COUNTIF((delivery_date IS NOT NULL AND off_road_date != delivery_date)
                        OR (delivery_date IS NULL AND shipment_status = 'Delivered' AND DATE_DIFF(off_road_date, shipment_date, DAY) != median_transit)
                        OR (off_road_date IS NULL AND shipment_status != 'In Transit')
                        OR (shipment_status = 'In Transit' AND off_road_date IS NOT NULL)) FROM s)
    UNION ALL
    SELECT '03. Median transit of delivered shipments = 4 days', 0,
           (SELECT ABS(APPROX_QUANTILES(transit_days, 2)[OFFSET(1)] - median_transit) FROM s WHERE delivery_date IS NOT NULL)
    UNION ALL
    SELECT '04. One daily row for every day, 1 January 2024 - 30 September 2026', 0,
           ABS((SELECT COUNT(*) FROM d) - (DATE_DIFF(data_end, first_dispatch, DAY) + 1))
         + ABS((SELECT COUNT(DISTINCT on_date) FROM d) - (SELECT COUNT(*) FROM d))
         + IF((SELECT MIN(on_date) FROM d) != first_dispatch OR (SELECT MAX(on_date) FROM d) != data_end, 1, 0)
    UNION ALL
    SELECT '05. Value on the road on 31 March 2026 = recount from shipments', 0,
           IF(ABS((SELECT insured_value_on_road FROM d WHERE on_date = DATE '2026-03-31') - (SELECT v FROM on_31_mar)) > 1e-3, 1, 0)
    UNION ALL
    SELECT '06. Largest shipment on the road never exceeds the value on the road, zero only when nothing is on it', 0,
           (SELECT COUNTIF(largest_shipment_on_road > insured_value_on_road + 1e-6
                        OR ((shipments_on_road = 0) != (insured_value_on_road = 0))) FROM d)
    UNION ALL
    SELECT '07. Conveyances add up to all shipments, one per dispatch day and city', 0,
           ABS((SELECT SUM(shipments) FROM c) - (SELECT COUNT(*) FROM s))
         + IF(ABS((SELECT SUM(insured_value) FROM c) - (SELECT SUM(insured_value) FROM s)) > 1e-3, 1, 0)
         + ABS((SELECT COUNT(*) FROM c) - (SELECT COUNT(DISTINCT CONCAT(CAST(shipment_date AS STRING), shipping_city)) FROM s))
    UNION ALL
    SELECT '08. Declaration months for 2024-25 and 2025-26 = dispatches by month, 12 months each', 0,
           (SELECT COUNT(*)
              FROM (SELECT * FROM y WHERE financial_year IN (2024, 2025)) AS yy
              FULL OUTER JOIN (SELECT * FROM fy_months WHERE financial_year IN (2024, 2025)) AS f
                USING (financial_year, month_of_year)
             WHERE yy.insured_value IS NULL OR f.v IS NULL OR ABS(yy.insured_value - f.v) > 1e-3)
         + ABS((SELECT COUNT(*) FROM y WHERE financial_year IN (2024, 2025)) - 24)
    UNION ALL
    SELECT '09. 2026-27 = actual April - September, then 2025-26 months x the April - September growth', 0,
           (SELECT COUNT(*) FROM y
              JOIN fy_months AS last_year ON last_year.financial_year = 2025 AND last_year.month_of_year = y.month_of_year
              LEFT JOIN fy_months AS actual ON actual.financial_year = 2026 AND actual.month_of_year = y.month_of_year
              CROSS JOIN growth AS g
             WHERE y.financial_year = 2026
               AND ((y.projected AND (actual.v IS NOT NULL OR ABS(y.insured_value - last_year.v * g.g) > 1e-3))
                 OR (NOT y.projected AND ABS(y.insured_value - actual.v) > 1e-3)))
         + ABS((SELECT COUNT(*) FROM y WHERE financial_year = 2026) - 12)
    UNION ALL
    SELECT '10. 2025-26 at last year''s sum insured: used up on 19 March 2026, not before', 0,
           IF((SELECT MAX(cum) FROM fy25_days WHERE shipment_date < DATE '2026-03-19')
                > (SELECT SUM(insured_value) FROM s WHERE financial_year = 2024)
           OR (SELECT MAX(cum) FROM fy25_days WHERE shipment_date <= DATE '2026-03-19')
                <= (SELECT SUM(insured_value) FROM s WHERE financial_year = 2024), 1, 0)
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
