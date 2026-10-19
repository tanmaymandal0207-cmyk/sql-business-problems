/* =============================================================================
   Case study · Salesperson performance scorecard
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Sales incentives are paid on revenue alone. The sales head suspects this
   rewards people who win volume through deep discounts, orders that later
   cancel, and customers who pay late. Before redesigning the incentive plan,
   they want a balanced scorecard for each salesperson:
     1. How does each salesperson perform on revenue, margin, discount,
        cancellations, on-time delivery and cash collection?
     2. Does ranking on revenue alone tell the same story as a balanced view?
     3. Who sells a lot at low margin, and who sells less but more profitably?

   KEY RULES
     - Period: all orders, Jan 2024 - Sep 2026. As-of date 30 Sep 2026.
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Gross margin %: lines whose product has a unit cost.
     - Discount %: discount given / gross value.
     - Cancellation rate: cancelled orders / all orders placed.
     - On-time delivery %: Delivered orders with a promised date and a
       delivery date, delivered on or before the promised date.
     - Overdue receivable %: balance unpaid on Delivered orders delivered more
       than 90 days before the as-of date, as a share of those orders' value.
     - Balanced rank: average of the six metric ranks (1 = best). Orders with
       no salesperson are shown as 'Unassigned' and are not ranked.
   ============================================================================= */

DECLARE as_of_date DATE DEFAULT DATE '2026-09-30';

-- -----------------------------------------------------------------------------
-- Step 1 · Scorecard table: one row per salesperson
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.salesperson_scorecard` AS
WITH line_values AS (
    SELECT
        o.order_id,
        o.employee_id,
        o.order_status,
        i.quantity * i.unit_price                                             AS gross_value,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS net_revenue,
        i.quantity * p.unit_cost                                              AS line_cost
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id   = i.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
),

sales_metrics AS (
    SELECT
        employee_id,
        SUM(net_revenue)                                              AS net_revenue,
        COUNT(DISTINCT order_id)                                      AS orders,
        100 * SUM(gross_value - net_revenue) / SUM(gross_value)       AS discount_pct,
        100 * SUM(IF(line_cost IS NOT NULL, net_revenue - line_cost, 0))
            / SUM(IF(line_cost IS NOT NULL, net_revenue, 0))          AS gross_margin_pct
    FROM line_values
    WHERE order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY employee_id
),

order_value AS (
    SELECT order_id, employee_id, order_status, SUM(net_revenue) AS order_value
    FROM line_values
    GROUP BY order_id, employee_id, order_status
),

cancellations AS (
    SELECT
        employee_id,
        COUNT(*)                                             AS orders_placed,
        COUNTIF(order_status = 'Cancelled')                  AS cancelled_orders,
        100 * COUNTIF(order_status = 'Cancelled') / COUNT(*) AS cancellation_rate_pct
    FROM order_value
    GROUP BY employee_id
),

delivery AS (
    SELECT
        o.employee_id,
        COUNT(*)                                                                   AS delivered_measured,
        COUNTIF(s.final_delivery_date <= o.promised_delivery_date)                AS on_time_orders,
        100 * COUNTIF(s.final_delivery_date <= o.promised_delivery_date) / COUNT(*) AS on_time_pct
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN (SELECT order_id, MAX(delivery_date) AS final_delivery_date
          FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS s
        ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
      AND o.promised_delivery_date IS NOT NULL
      AND s.final_delivery_date IS NOT NULL
    GROUP BY o.employee_id
),

collections AS (
    -- delivered more than 90 days ago: how much of the value is still unpaid?
    SELECT
        v.employee_id,
        SUM(v.order_value)                                              AS aged_order_value,
        SUM(GREATEST(v.order_value - IFNULL(p.paid, 0), 0))            AS overdue_balance,
        100 * SUM(GREATEST(v.order_value - IFNULL(p.paid, 0), 0)) / SUM(v.order_value)
            AS overdue_receivable_pct
    FROM order_value AS v
    JOIN (SELECT order_id, MAX(delivery_date) AS final_delivery_date
          FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS s
        ON s.order_id = v.order_id
    LEFT JOIN (SELECT order_id, SUM(amount) AS paid
               FROM `sahyadri_b2b.payments` GROUP BY order_id) AS p
        ON p.order_id = v.order_id
    WHERE v.order_status = 'Delivered'
      AND DATE_DIFF(as_of_date, s.final_delivery_date, DAY) > 90
    GROUP BY v.employee_id
)

SELECT
    m.employee_id,
    IFNULL(e.employee_name, 'Unassigned')             AS salesperson,
    e.designation,
    ROUND(m.net_revenue, 2)                           AS net_revenue,
    m.orders,
    ROUND(m.gross_margin_pct, 2)                      AS gross_margin_pct,
    ROUND(m.discount_pct, 2)                          AS discount_pct,
    ROUND(c.cancellation_rate_pct, 2)                 AS cancellation_rate_pct,
    ROUND(d.on_time_pct, 2)                           AS on_time_pct,
    ROUND(k.overdue_receivable_pct, 2)                AS overdue_receivable_pct,
    c.orders_placed,
    c.cancelled_orders,
    d.delivered_measured,
    d.on_time_orders,
    ROUND(k.aged_order_value, 2)                      AS aged_order_value,
    ROUND(k.overdue_balance, 2)                       AS overdue_balance
FROM sales_metrics                AS m
LEFT JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = m.employee_id
LEFT JOIN cancellations           AS c ON c.employee_id IS NOT DISTINCT FROM m.employee_id
LEFT JOIN delivery                AS d ON d.employee_id IS NOT DISTINCT FROM m.employee_id
LEFT JOIN collections             AS k ON k.employee_id IS NOT DISTINCT FROM m.employee_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Balanced ranking (1 = best on each metric)
-- -----------------------------------------------------------------------------
WITH ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY net_revenue DESC)            AS rank_revenue,
        RANK() OVER (ORDER BY gross_margin_pct DESC)       AS rank_margin,
        RANK() OVER (ORDER BY discount_pct ASC)            AS rank_discount,
        RANK() OVER (ORDER BY cancellation_rate_pct ASC)   AS rank_cancellation,
        RANK() OVER (ORDER BY on_time_pct DESC)            AS rank_on_time,
        RANK() OVER (ORDER BY overdue_receivable_pct ASC)  AS rank_collection
    FROM `sahyadri_b2b.salesperson_scorecard`
    WHERE employee_id IS NOT NULL
)
SELECT
    employee_id,
    salesperson,
    rank_revenue,
    rank_margin,
    rank_discount,
    rank_cancellation,
    rank_on_time,
    rank_collection,
    ROUND((rank_revenue + rank_margin + rank_discount
         + rank_cancellation + rank_on_time + rank_collection) / 6, 1) AS avg_rank,
    RANK() OVER (ORDER BY (rank_revenue + rank_margin + rank_discount
                         + rank_cancellation + rank_on_time + rank_collection)) AS balanced_rank,
    rank_revenue - RANK() OVER (ORDER BY (rank_revenue + rank_margin + rank_discount
                         + rank_cancellation + rank_on_time + rank_collection)) AS rank_shift
FROM ranked
ORDER BY balanced_rank, rank_revenue;

-- -----------------------------------------------------------------------------
-- Step 3 · Full scorecard values, including unassigned orders
-- -----------------------------------------------------------------------------
SELECT
    employee_id, salesperson, designation, net_revenue, orders,
    gross_margin_pct, discount_pct, cancellation_rate_pct, on_time_pct,
    overdue_receivable_pct
FROM `sahyadri_b2b.salesperson_scorecard`
ORDER BY net_revenue DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Revenue vs margin quadrant (split at the median of ranked staff)
-- -----------------------------------------------------------------------------
WITH medians AS (
    SELECT DISTINCT
        PERCENTILE_CONT(net_revenue, 0.5)      OVER () AS median_revenue,
        PERCENTILE_CONT(gross_margin_pct, 0.5) OVER () AS median_margin
    FROM `sahyadri_b2b.salesperson_scorecard`
    WHERE employee_id IS NOT NULL
)
SELECT
    CASE
        WHEN s.net_revenue >= m.median_revenue AND s.gross_margin_pct >= m.median_margin THEN '1. High revenue, high margin'
        WHEN s.net_revenue >= m.median_revenue                                          THEN '2. High revenue, low margin'
        WHEN s.gross_margin_pct >= m.median_margin                                      THEN '3. Low revenue, high margin'
        ELSE                                                                                 '4. Low revenue, low margin'
    END                                              AS quadrant,
    COUNT(*)                                         AS salespeople,
    STRING_AGG(s.salesperson, ', ' ORDER BY s.net_revenue DESC) AS names,
    ROUND(SUM(s.net_revenue), 2)                     AS net_revenue
FROM `sahyadri_b2b.salesperson_scorecard` AS s
CROSS JOIN medians AS m
WHERE s.employee_id IS NOT NULL
GROUP BY quadrant
ORDER BY quadrant;
