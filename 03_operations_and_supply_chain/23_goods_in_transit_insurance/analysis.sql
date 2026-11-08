/* =============================================================================
   Case study · Goods in transit: how much is on the road, what limits the
   transit policy needs, and what sum insured to declare
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The company's goods travel to customers by road under an annual open
   (turnover) marine-inland transit policy. The policy is up for renewal
   and the insurer asks for three figures: the estimated annual dispatches
   to insure, the largest value that can travel on one vehicle (the
   per-conveyance or "per-bottom" limit), and the claims history. The
   finance controller has always sent last year's sales figure. She asks:
     1. How much value is on the road on a typical day, and at the peak?
     2. What per-conveyance limit is needed, and what is uninsured at
        lower limits?
     3. What sum insured should be declared for 2026-27, and what would
        happen if last year's figure is sent again?
     4. Which shipments are still on the road, and are any now claims?

   RULES APPLIED (as summarised in insurers' policy prospectuses; see the README)
     - Open policy: one year, a sum insured on estimated dispatches, cover
       for every dispatch until the sum insured is used up; it can be
       increased during the year, unused sum insured is refunded at expiry.
     - Liability is limited per sending / per conveyance ("per bottom").
     - Agreed value: invoice value plus 10 % for incidental expenses.
     - Missing goods: presumed a total loss 90 days after the expected
       delivery date; a claim against the carrier must be lodged within
       six months of the lorry receipt.

   METHOD AND ASSUMPTIONS
     - Shipments dispatched 1 January 2024 - 30 September 2026, all statuses
       (goods are at risk in transit whether or not they are later returned).
     - Shipment value = order value after discount / shipments of the order
       (as in the e-way bill study); invoice value = value x 1.18 (GST
       assumed at 18 %); insured value = invoice value x 1.10.
     - On the road at the end of day d: dispatched on or before d and not yet
       delivered (delivered after d, or no delivery date by 30 September
       2026).
     - Conveyance: shipments to the same city on the same day, assumed to
       travel on one vehicle (an upper bound on what one vehicle carries).
     - Financial year April - March. The 2026-27 projection scales each
       October - March month of 2025-26 by the April - September growth.
     - Expected delivery = dispatch + the 99th percentile of delivered
       transit times.
     - Ten shipments are marked Delivered but have no delivery date; they
       are taken as delivered after the median transit time (4 days) and
       reported separately.
   ============================================================================= */

DECLARE gst_rate        FLOAT64 DEFAULT 0.18;
DECLARE insured_margin  FLOAT64 DEFAULT 0.10;
DECLARE first_dispatch  DATE    DEFAULT DATE '2024-01-01';
DECLARE data_end        DATE    DEFAULT DATE '2026-09-30';
DECLARE median_transit  INT64   DEFAULT 4;   -- median transit days of delivered shipments

-- -----------------------------------------------------------------------------
-- Step 1 · Shipments with insured value, and the value on the road every day
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.gt_shipments` AS
WITH order_value AS (
    SELECT o.order_id, o.customer_id, SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    GROUP BY o.order_id, o.customer_id
),
split AS (
    SELECT order_id, COUNT(*) AS shipments_of_order FROM `sahyadri_b2b.shipments` GROUP BY order_id
)
SELECT s.shipment_id, s.order_id, v.customer_id, s.shipment_date, s.delivery_date, s.shipping_city, s.shipment_status,
       -- the date the goods left the company's risk; a Delivered shipment without a date is assumed delivered after the median transit
       IF(s.delivery_date IS NULL AND s.shipment_status = 'Delivered', DATE_ADD(s.shipment_date, INTERVAL median_transit DAY), s.delivery_date) AS off_road_date,
       v.order_value / sp.shipments_of_order * (1 + gst_rate)                        AS invoice_value,
       v.order_value / sp.shipments_of_order * (1 + gst_rate) * (1 + insured_margin) AS insured_value,
       DATE_DIFF(s.delivery_date, s.shipment_date, DAY)                              AS transit_days,
       EXTRACT(YEAR FROM DATE_SUB(s.shipment_date, INTERVAL 3 MONTH))                AS financial_year
FROM `sahyadri_b2b.shipments` AS s
JOIN order_value AS v ON v.order_id = s.order_id
JOIN split AS sp ON sp.order_id = s.order_id
WHERE s.shipment_date BETWEEN first_dispatch AND data_end;

CREATE OR REPLACE TABLE `sahyadri_b2b.gt_daily` AS
WITH days AS (
    SELECT d AS on_date FROM UNNEST(GENERATE_DATE_ARRAY(first_dispatch, data_end, INTERVAL 1 DAY)) AS d
),
on_road AS (
    SELECT dy.on_date,
           COUNT(*)                                                                  AS shipments_on_road,
           SUM(s.insured_value)                                                      AS insured_value_on_road,
           MAX(s.insured_value)                                                      AS largest_shipment_on_road
    FROM days AS dy
    JOIN `sahyadri_b2b.gt_shipments` AS s
      ON s.shipment_date <= dy.on_date AND (s.off_road_date > dy.on_date OR s.off_road_date IS NULL)
    GROUP BY dy.on_date
)
SELECT dy.on_date,
       IFNULL(r.shipments_on_road, 0)                                                AS shipments_on_road,
       IFNULL(r.insured_value_on_road, 0)                                            AS insured_value_on_road,
       IFNULL(r.largest_shipment_on_road, 0)                                         AS largest_shipment_on_road
FROM days AS dy
LEFT JOIN on_road AS r USING (on_date);

CREATE OR REPLACE TABLE `sahyadri_b2b.gt_conveyances` AS
SELECT shipment_date, shipping_city,
       COUNT(*)                                                                      AS shipments,
       SUM(insured_value)                                                            AS insured_value,
       MAX(insured_value)                                                            AS largest_shipment
FROM `sahyadri_b2b.gt_shipments`
GROUP BY shipment_date, shipping_city;

-- -----------------------------------------------------------------------------
-- Step 2 · How much is on the road on a typical day, and at the peak?
-- -----------------------------------------------------------------------------
SELECT
    CONCAT(CAST(EXTRACT(YEAR FROM DATE_SUB(on_date, INTERVAL 3 MONTH)) AS STRING), '-',
           CAST(MOD(EXTRACT(YEAR FROM DATE_SUB(on_date, INTERVAL 3 MONTH)) + 1, 100) AS STRING)) AS financial_year,
    COUNT(*)                                                                         AS days,
    ROUND(AVG(shipments_on_road), 1)                                                 AS average_shipments_on_road,
    ROUND(AVG(insured_value_on_road) / 1e5, 1)                                       AS average_value_on_road_lakh,
    ROUND(APPROX_QUANTILES(insured_value_on_road, 100)[OFFSET(95)] / 1e5, 1)         AS p95_value_on_road_lakh,
    ROUND(MAX(insured_value_on_road) / 1e5, 1)                                       AS peak_value_on_road_lakh
FROM `sahyadri_b2b.gt_daily`
GROUP BY financial_year
ORDER BY financial_year;

-- The peak days, and how much of each is one shipment
SELECT
    on_date,
    shipments_on_road,
    ROUND(insured_value_on_road / 1e5, 1)                                            AS value_on_road_lakh,
    ROUND(largest_shipment_on_road / 1e5, 1)                                         AS largest_shipment_lakh,
    ROUND(100 * largest_shipment_on_road / insured_value_on_road, 1)                 AS largest_share_pct
FROM `sahyadri_b2b.gt_daily`
ORDER BY insured_value_on_road DESC
LIMIT 8;

-- -----------------------------------------------------------------------------
-- Step 3 · What per-conveyance limit is needed?
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                                         AS conveyances,
    ROUND(APPROX_QUANTILES(insured_value, 100)[OFFSET(50)] / 1e5, 2)                 AS median_lakh,
    ROUND(APPROX_QUANTILES(insured_value, 100)[OFFSET(90)] / 1e5, 2)                 AS p90_lakh,
    ROUND(APPROX_QUANTILES(insured_value, 100)[OFFSET(99)] / 1e5, 2)                 AS p99_lakh,
    ROUND(MAX(insured_value) / 1e5, 1)                                               AS largest_lakh,
    COUNTIF(shipments > 1)                                                           AS with_more_than_one_shipment
FROM `sahyadri_b2b.gt_conveyances`;

SELECT
    limit_lakh,
    COUNTIF(c.insured_value > limit_lakh * 1e5)                                      AS conveyances_above_limit,
    ROUND(SUM(GREATEST(0, c.insured_value - limit_lakh * 1e5)) / 1e5, 1)             AS value_above_limit_lakh,
    ROUND(100 * SUM(LEAST(c.insured_value, limit_lakh * 1e5)) / SUM(c.insured_value), 2) AS value_covered_pct
FROM `sahyadri_b2b.gt_conveyances` AS c
CROSS JOIN (SELECT 10 AS limit_lakh UNION ALL SELECT 25 UNION ALL SELECT 50 UNION ALL SELECT 100 UNION ALL SELECT 160) AS l
GROUP BY limit_lakh
ORDER BY limit_lakh;

SELECT
    shipment_date, shipping_city, shipments,
    ROUND(insured_value / 1e5, 1)                                                    AS insured_value_lakh,
    ROUND(largest_shipment / 1e5, 1)                                                 AS largest_shipment_lakh
FROM `sahyadri_b2b.gt_conveyances`
ORDER BY insured_value DESC
LIMIT 8;

-- -----------------------------------------------------------------------------
-- Step 4 · What sum insured to declare
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.gt_declaration` AS
WITH monthly AS (
    SELECT financial_year, DATE_TRUNC(shipment_date, MONTH) AS month_start,
           MOD(EXTRACT(MONTH FROM shipment_date) + 8, 12) + 1                        AS month_of_year,
           SUM(insured_value)                                                        AS insured_value
    FROM `sahyadri_b2b.gt_shipments`
    GROUP BY financial_year, month_start, month_of_year
),
growth AS (
    SELECT SUM(IF(financial_year = 2026, insured_value, 0)) / SUM(IF(financial_year = 2025 AND month_of_year <= 6, insured_value, 0)) AS h1_growth
    FROM monthly
),
fy_2026 AS (
    -- actual April - September 2026, projected October 2026 - March 2027
    SELECT 2026 AS financial_year, m.month_of_year,
           IFNULL(a.insured_value, m.insured_value * g.h1_growth)                    AS insured_value,
           a.insured_value IS NULL                                                   AS projected
    FROM monthly AS m
    CROSS JOIN growth AS g
    LEFT JOIN monthly AS a ON a.financial_year = 2026 AND a.month_of_year = m.month_of_year
    WHERE m.financial_year = 2025
)
SELECT financial_year, month_of_year, insured_value, FALSE AS projected
FROM monthly WHERE financial_year IN (2024, 2025)
UNION ALL
SELECT financial_year, month_of_year, insured_value, projected FROM fy_2026;

SELECT
    CONCAT(CAST(financial_year AS STRING), '-', CAST(MOD(financial_year + 1, 100) AS STRING)) AS financial_year,
    ROUND(SUM(insured_value) / 1e7, 2)                                               AS insured_dispatches_crore,
    ROUND(SUM(IF(month_of_year <= 6, insured_value, 0)) / 1e7, 2)                    AS april_september_crore,
    ROUND(100 * SUM(IF(month_of_year <= 6, insured_value, 0)) / SUM(insured_value), 1) AS april_september_share_pct,
    LOGICAL_OR(projected)                                                            AS includes_projection
FROM `sahyadri_b2b.gt_declaration`
GROUP BY financial_year
ORDER BY financial_year;

-- If the previous year's dispatches are declared: when is the sum insured used up?
WITH declared AS (
    SELECT financial_year + 1 AS financial_year, SUM(insured_value) AS sum_insured
    FROM `sahyadri_b2b.gt_declaration`
    GROUP BY financial_year
),
cumulative AS (
    SELECT d.financial_year, d.month_of_year, d.projected,
           SUM(d.insured_value) OVER (PARTITION BY d.financial_year ORDER BY d.month_of_year) AS cumulative_value,
           s.sum_insured
    FROM `sahyadri_b2b.gt_declaration` AS d
    JOIN declared AS s ON s.financial_year = d.financial_year
)
SELECT
    CONCAT(CAST(financial_year AS STRING), '-', CAST(MOD(financial_year + 1, 100) AS STRING)) AS financial_year,
    ROUND(MAX(sum_insured) / 1e7, 2)                                                 AS declared_at_previous_year_crore,
    ROUND(MAX(cumulative_value) / 1e7, 2)                                            AS dispatches_crore,
    MIN(IF(cumulative_value > sum_insured, month_of_year, NULL))                     AS month_used_up_1_april,
    ROUND(GREATEST(0, MAX(cumulative_value) - MAX(sum_insured)) / 1e7, 2)            AS uninsured_unless_increased_crore
FROM cumulative
GROUP BY financial_year
ORDER BY financial_year;

-- Three figures the controller could declare for 2026-27, and the month each runs out on the projection
WITH options AS (
    SELECT '1. Dispatches of 2025-26' AS declaration,
           (SELECT SUM(insured_value) FROM `sahyadri_b2b.gt_shipments` WHERE financial_year = 2025) AS sum_insured
    UNION ALL
    SELECT '2. Dispatches of the last 12 months (October 2025 - September 2026)',
           (SELECT SUM(insured_value) FROM `sahyadri_b2b.gt_shipments` WHERE shipment_date > DATE '2025-09-30')
    UNION ALL
    SELECT '3. Projection for 2026-27',
           (SELECT SUM(insured_value) FROM `sahyadri_b2b.gt_declaration` WHERE financial_year = 2026)
),
cumulative AS (
    SELECT month_of_year, SUM(insured_value) OVER (ORDER BY month_of_year) AS cumulative_value
    FROM `sahyadri_b2b.gt_declaration`
    WHERE financial_year = 2026
)
SELECT
    o.declaration,
    ROUND(o.sum_insured / 1e7, 2)                                                    AS sum_insured_crore,
    -- month of the financial year (1 = April) in which projected dispatches pass the sum insured
    MIN(IF(c.cumulative_value > o.sum_insured + 1, c.month_of_year, NULL))           AS month_used_up_1_april
FROM options AS o
CROSS JOIN cumulative AS c
GROUP BY o.declaration, o.sum_insured
ORDER BY o.declaration;

-- The exact day in 2025-26
SELECT
    MIN(shipment_date)                                                               AS sum_insured_used_up_on,
    ROUND((SELECT SUM(insured_value) FROM `sahyadri_b2b.gt_shipments` WHERE financial_year = 2025)
          - (SELECT SUM(insured_value) FROM `sahyadri_b2b.gt_shipments` WHERE financial_year = 2024), 0) AS uninsured_rupees
FROM (
    SELECT shipment_date,
           SUM(SUM(insured_value)) OVER (ORDER BY shipment_date)                     AS cumulative_value
    FROM `sahyadri_b2b.gt_shipments`
    WHERE financial_year = 2025
    GROUP BY shipment_date
)
WHERE cumulative_value > (SELECT SUM(insured_value) FROM `sahyadri_b2b.gt_shipments` WHERE financial_year = 2024);

-- -----------------------------------------------------------------------------
-- Step 5 · Shipments still on the road on 30 September 2026
-- -----------------------------------------------------------------------------
WITH limit_days AS (
    SELECT APPROX_QUANTILES(transit_days, 100)[OFFSET(99)] AS p99_transit_days
    FROM `sahyadri_b2b.gt_shipments`
    WHERE delivery_date IS NOT NULL
)
SELECT
    s.shipment_id, s.order_id, c.customer_name, s.shipping_city, s.shipment_date,
    DATE_DIFF(data_end, s.shipment_date, DAY)                                        AS days_on_road,
    DATE_ADD(s.shipment_date, INTERVAL l.p99_transit_days DAY)                       AS expected_delivery,
    ROUND(s.insured_value / 1e5, 2)                                                  AS insured_value_lakh,
    CASE WHEN DATE_DIFF(data_end, s.shipment_date, DAY) > 182 AND DATE_DIFF(data_end, s.shipment_date, DAY) - l.p99_transit_days > 90
              THEN '1. Presumed lost, carrier claim window passed'
         WHEN DATE_DIFF(data_end, s.shipment_date, DAY) - l.p99_transit_days > 90 THEN '2. Presumed lost, claim the carrier now'
         WHEN DATE_DIFF(data_end, s.shipment_date, DAY) > l.p99_transit_days THEN '3. Overdue'
         ELSE '4. Normal transit' END                                                AS status
FROM `sahyadri_b2b.gt_shipments` AS s
CROSS JOIN limit_days AS l
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = s.customer_id
WHERE s.shipment_status = 'In Transit'
  AND DATE_DIFF(data_end, s.shipment_date, DAY) > l.p99_transit_days
ORDER BY s.shipment_date;

WITH limit_days AS (
    SELECT APPROX_QUANTILES(transit_days, 100)[OFFSET(99)] AS p99_transit_days
    FROM `sahyadri_b2b.gt_shipments`
    WHERE delivery_date IS NOT NULL
)
SELECT
    l.p99_transit_days,
    COUNTIF(s.shipment_status = 'In Transit')                                        AS in_transit,
    COUNTIF(s.shipment_status = 'In Transit' AND DATE_DIFF(data_end, s.shipment_date, DAY) <= l.p99_transit_days) AS within_normal_transit,
    COUNTIF(s.shipment_status = 'In Transit' AND DATE_DIFF(data_end, s.shipment_date, DAY) > l.p99_transit_days)  AS overdue,
    ROUND(SUM(IF(s.shipment_status = 'In Transit' AND DATE_DIFF(data_end, s.shipment_date, DAY) > l.p99_transit_days, s.insured_value, 0)) / 1e5, 2) AS overdue_value_lakh,
    COUNTIF(s.shipment_status = 'Delivered' AND s.delivery_date IS NULL)             AS delivered_without_a_date,
    ROUND(SUM(IF(s.shipment_status = 'Delivered' AND s.delivery_date IS NULL, s.insured_value, 0)) / 1e5, 2) AS delivered_without_a_date_value_lakh,
    COUNTIF(s.shipment_status = 'Returned')                                          AS returned_shipments,
    ROUND(SUM(IF(s.shipment_status = 'Returned', s.insured_value, 0)) / 1e5, 1)      AS returned_value_lakh
FROM `sahyadri_b2b.gt_shipments` AS s
CROSS JOIN limit_days AS l
GROUP BY l.p99_transit_days;
