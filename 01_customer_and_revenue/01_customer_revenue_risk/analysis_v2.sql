/* =============================================================================
   Case study 01 · Customer revenue risk — VERSION 2
   Dialect : Google BigQuery Standard SQL
   Supersedes analysis.sql (version 1, kept unchanged for reference).
   Changes from version 1:
     - NULL discount_percent treated as 0 % (version 1 dropped those lines)
     - Cancelled and Returned orders excluded from revenue and order counts
     - Cumulative revenue share and Pareto band added (business question 3)
     - Table names in lower case; SAFE_DIVIDE; thresholds in a params CTE
   Dataset : sahyadri_b2b

   BUSINESS PROBLEM
   Management suspects that headline revenue hides three risks:
     1. Some customers look valuable because of one unusually large order.
     2. Some customers order frequently but contribute very little revenue.
     3. A small number of customers account for a disproportionate share of sales.

   OUTPUT GRAIN
   One row per customer with at least `min_orders` in-scope orders.

   KEY RULES (see README for rationale)
     - Revenue  = quantity * unit_price * (1 - discount_percent / 100)
     - NULL discount_percent is treated as 0 % (no discount). Without this,
       the whole line becomes NULL and is silently dropped by SUM().
     - Cancelled and Returned orders are excluded from revenue and order counts.
     - Company share and cumulative share use ALL in-scope customers as the
       denominator, before the `min_orders` filter.
   ============================================================================= */

WITH params AS (
    SELECT
        5         AS min_orders,           -- minimum orders for concentration to be meaningful
        50.0      AS critical_conc_pct,    -- largest order >= 50 % of customer sales
        30.0      AS moderate_conc_pct,    -- largest order >= 30 % of customer sales
        1000000.0 AS high_value_sales,     -- customer net sales threshold
        20        AS high_freq_orders      -- customer order-count threshold
),

-- 1. One row per in-scope order
order_revenue AS (
    SELECT
        o.customer_id,
        o.order_id,
        SUM(
            i.quantity * i.unit_price
            * (1 - IFNULL(i.discount_percent, 0) / 100)
        ) AS net_sales
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o
        ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY
        o.customer_id,
        o.order_id
),

-- 2. One row per customer
customer_metrics AS (
    SELECT
        customer_id,
        COUNT(*)                         AS total_orders,
        SUM(net_sales)                   AS net_sales,
        MAX(net_sales)                   AS largest_order,
        SAFE_DIVIDE(SUM(net_sales), COUNT(*))       AS avg_order_value,
        SAFE_DIVIDE(MAX(net_sales), SUM(net_sales)) * 100
                                         AS largest_order_pct
    FROM order_revenue
    GROUP BY customer_id
),

-- 3. Company-wide position of every customer (before any filter)
customer_position AS (
    SELECT
        m.*,
        SAFE_DIVIDE(m.net_sales, SUM(m.net_sales) OVER ()) * 100
            AS company_sales_pct,
        SAFE_DIVIDE(
            SUM(m.net_sales) OVER (
                ORDER BY m.net_sales DESC, m.customer_id
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ),
            SUM(m.net_sales) OVER ()
        ) * 100                                     AS cumulative_sales_pct,
        RANK() OVER (ORDER BY m.net_sales DESC)     AS sales_rank
    FROM customer_metrics AS m
)

-- 4. Classification
SELECT
    c.customer_id,
    c.total_orders,
    ROUND(c.net_sales, 2)            AS net_sales,
    ROUND(c.avg_order_value, 2)      AS avg_order_value,
    ROUND(c.largest_order, 2)        AS largest_order,
    ROUND(c.largest_order_pct, 2)    AS largest_order_pct,
    ROUND(c.company_sales_pct, 3)    AS company_sales_pct,
    ROUND(c.cumulative_sales_pct, 2) AS cumulative_sales_pct,
    c.sales_rank,
    RANK() OVER (ORDER BY c.largest_order_pct DESC) AS concentration_rank,

    -- Risk 1: dependence on a single order
    CASE
        WHEN c.largest_order_pct >= p.critical_conc_pct THEN 'Critical Concentration'
        WHEN c.largest_order_pct >= p.moderate_conc_pct THEN 'Moderate Concentration'
        ELSE 'Diversified'
    END AS order_concentration_flag,

    -- Risk 2: value vs. frequency
    CASE
        WHEN c.net_sales >= p.high_value_sales AND c.total_orders >= p.high_freq_orders THEN 'Strategic'
        WHEN c.net_sales >= p.high_value_sales                                          THEN 'High Value'
        WHEN c.total_orders >= p.high_freq_orders                                       THEN 'High Frequency'
        ELSE 'Standard'
    END AS value_frequency_segment,

    -- Risk 3: position in company revenue (Pareto band)
    CASE
        WHEN c.cumulative_sales_pct - c.company_sales_pct < 50 THEN 'Top 50% of revenue'
        WHEN c.cumulative_sales_pct - c.company_sales_pct < 80 THEN 'Next 30% of revenue'
        ELSE 'Remaining 20% of revenue'
    END AS revenue_band

FROM customer_position AS c
CROSS JOIN params AS p
WHERE c.total_orders >= p.min_orders
ORDER BY
    c.sales_rank,
    c.customer_id;
