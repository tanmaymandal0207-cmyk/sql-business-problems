/* =============================================================================
   Case study · Revenue cut-off reconciliation (order date vs delivery date)
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Management reports book revenue on the order date, because that is the
   date the order system records first. Under Ind AS 115, revenue on these
   sales is recognised when control of the goods passes to the customer,
   which for delivered sales is the delivery date. Orders placed near a
   month-end, and especially near the 31 March financial year-end, are often
   delivered in the next period. Before the half-year close, finance wants to
   know how large the cut-off difference is:
     1. How different is monthly revenue on an order-date basis from revenue
        on a delivery-date basis?
     2. At each month-end, how much has been ordered but not yet delivered
        (the cut-off exposure)?
     3. What is the effect on financial-year revenue (April-March)?
     4. What is open at 30 Sep 2026, the current half-year end?

   KEY RULES
     - Revenue: SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)).
     - Scope: orders not Cancelled or Returned.
     - Order basis: revenue in the month of the order date.
     - Delivery basis: revenue in the month of the final delivery date.
       Orders not yet delivered at 30 Sep 2026 (Pending, Processing, Shipped)
       have no delivery-basis revenue yet.
     - Delivered orders with no delivery date cannot be placed on a delivery
       basis; they are counted and excluded from the comparison.
     - Financial year: 1 April - 31 March (FY2025-26 = Apr 2025 - Mar 2026).
     - This analysis measures the timing difference only; it is not an
       accounting opinion on contract terms.
   ============================================================================= */

DECLARE period_start DATE DEFAULT DATE '2024-01-01';
DECLARE as_of_date   DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · One row per in-scope order with order date and recognition date
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.revenue_recognition_basis` AS
WITH order_value AS (
    SELECT order_id,
           SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
final_delivery AS (
    SELECT order_id, MAX(delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.order_status,
    o.order_date,
    IF(o.order_status = 'Delivered', d.final_delivery_date, NULL)          AS delivery_date,
    v.revenue,
    CASE
        WHEN o.order_status = 'Delivered' AND d.final_delivery_date IS NOT NULL THEN 'Delivered'
        WHEN o.order_status = 'Delivered'                                      THEN 'Delivered - no delivery date'
        ELSE                                                                        'Not yet delivered'
    END                                                                    AS recognition_status
FROM `sahyadri_b2b.sales_orders` AS o
JOIN order_value                 AS v ON v.order_id = o.order_id
LEFT JOIN final_delivery         AS d ON d.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned');

-- -----------------------------------------------------------------------------
-- Step 2 · Monthly revenue: order basis vs delivery basis, and month-end exposure
-- -----------------------------------------------------------------------------
WITH months AS (
    SELECT month_start, LAST_DAY(month_start) AS month_end
    FROM UNNEST(GENERATE_DATE_ARRAY(period_start, as_of_date, INTERVAL 1 MONTH)) AS month_start
),
basis AS (
    SELECT * FROM `sahyadri_b2b.revenue_recognition_basis`
    WHERE recognition_status <> 'Delivered - no delivery date'
)
SELECT
    m.month_start,
    ROUND(SUM(IF(b.order_date    BETWEEN m.month_start AND m.month_end, b.revenue, 0)), 2) AS revenue_order_basis,
    ROUND(SUM(IF(b.delivery_date BETWEEN m.month_start AND m.month_end, b.revenue, 0)), 2) AS revenue_delivery_basis,
    ROUND(SUM(IF(b.order_date    BETWEEN m.month_start AND m.month_end, b.revenue, 0))
        - SUM(IF(b.delivery_date BETWEEN m.month_start AND m.month_end, b.revenue, 0)), 2) AS cutoff_difference,
    -- ordered on or before month-end but delivered after it (or not yet)
    ROUND(SUM(IF(b.order_date <= m.month_end
                 AND (b.delivery_date > m.month_end OR b.delivery_date IS NULL), b.revenue, 0)), 2)
                                                                                           AS month_end_exposure
FROM months AS m
CROSS JOIN basis AS b
GROUP BY m.month_start
ORDER BY m.month_start;

-- -----------------------------------------------------------------------------
-- Step 3 · Financial-year revenue (April-March) on both bases
-- -----------------------------------------------------------------------------
WITH basis AS (
    SELECT
        *,
        CASE WHEN EXTRACT(MONTH FROM order_date) >= 4
             THEN EXTRACT(YEAR FROM order_date) ELSE EXTRACT(YEAR FROM order_date) - 1 END    AS fy_start_order,
        CASE WHEN EXTRACT(MONTH FROM delivery_date) >= 4
             THEN EXTRACT(YEAR FROM delivery_date) ELSE EXTRACT(YEAR FROM delivery_date) - 1 END AS fy_start_delivery
    FROM `sahyadri_b2b.revenue_recognition_basis`
    WHERE recognition_status <> 'Delivered - no delivery date'
),
fy_list AS (
    SELECT DISTINCT fy_start_order AS fy_start FROM basis
)
SELECT
    CONCAT('FY', CAST(f.fy_start AS STRING), '-', SUBSTR(CAST(f.fy_start + 1 AS STRING), 3, 2)) AS financial_year,
    ROUND(SUM(IF(b.fy_start_order    = f.fy_start, b.revenue, 0)), 2)                         AS revenue_order_basis,
    ROUND(SUM(IF(b.fy_start_delivery = f.fy_start, b.revenue, 0)), 2)                         AS revenue_delivery_basis,
    ROUND(SUM(IF(b.fy_start_order    = f.fy_start, b.revenue, 0))
        - SUM(IF(b.fy_start_delivery = f.fy_start, b.revenue, 0)), 2)                         AS cutoff_difference
FROM fy_list AS f
CROSS JOIN basis AS b
GROUP BY f.fy_start
ORDER BY f.fy_start;

-- -----------------------------------------------------------------------------
-- Step 4 · Year-end (31 March) exposure: orders placed in the last 10 days of
--          March and delivered in April or later
-- -----------------------------------------------------------------------------
SELECT
    EXTRACT(YEAR FROM order_date)                                   AS march_of_year,
    COUNT(*)                                                        AS orders_last_10_days,
    ROUND(SUM(revenue), 2)                                          AS revenue_last_10_days,
    COUNTIF(delivery_date > LAST_DAY(order_date))                   AS delivered_after_year_end,
    ROUND(SUM(IF(delivery_date > LAST_DAY(order_date), revenue, 0)), 2) AS revenue_delivered_after_year_end
FROM `sahyadri_b2b.revenue_recognition_basis`
WHERE EXTRACT(MONTH FROM order_date) = 3
  AND EXTRACT(DAY FROM order_date) >= 22
  AND recognition_status = 'Delivered'
GROUP BY march_of_year
ORDER BY march_of_year;

-- -----------------------------------------------------------------------------
-- Step 5 · Open at the half-year end (30 Sep 2026) and excluded records
-- -----------------------------------------------------------------------------
SELECT
    recognition_status,
    order_status,
    COUNT(*)                     AS orders,
    ROUND(SUM(revenue), 2)       AS revenue
FROM `sahyadri_b2b.revenue_recognition_basis`
WHERE recognition_status <> 'Delivered'
GROUP BY recognition_status, order_status
ORDER BY recognition_status, order_status;
