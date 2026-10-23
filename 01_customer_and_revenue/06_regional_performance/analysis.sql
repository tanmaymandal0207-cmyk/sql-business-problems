/* =============================================================================
   Case study · Regional performance and market coverage
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The company sells to customers in 22 states from one sales team. The
   managing director is deciding where to add the next regional salesperson
   and where to set up a stocking point. That needs a state-by-state view of:
     1. Where revenue comes from, and where it is growing or shrinking.
     2. How well each state's registered customers are converted into active
        buyers, and how much each active customer is worth.
     3. Which states depend on one or two customers.
     4. Whether delivery service is worse in some regions.

   KEY RULES
     - Location: the customer's registered state (bill-to), grouped into
       regions with a mapping table (Step 0).
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - 12-month window: 1 Oct 2025 - 30 Sep 2026.
     - Growth: January-September 2026 vs January-September 2025, the same
       like-for-like basis as the revenue growth bridge.
     - Active customer: at least one in-scope order in the 12-month window.
     - Activation rate: active customers / registered customers.
     - Concentration: the largest customer's share of the state's 12-month
       revenue.
     - On-time: delivered orders in the window with both dates, final delivery
       on or before the promised date.
     - Portfolio quadrant (states with at least ₹50 lakh 12-month revenue):
         Invest  : above-median revenue and above-company growth
         Defend  : above-median revenue, growth at or below company
         Develop : below-median revenue, above-company growth
         Review  : below-median revenue, growth at or below company
       States below ₹50 lakh are "Too small to classify".
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE py_start     DATE    DEFAULT DATE '2025-01-01';
DECLARE py_end       DATE    DEFAULT DATE '2025-09-30';
DECLARE cy_start     DATE    DEFAULT DATE '2026-01-01';
DECLARE cy_end       DATE    DEFAULT DATE '2026-09-30';
DECLARE min_revenue  FLOAT64 DEFAULT 5000000;

-- -----------------------------------------------------------------------------
-- Step 0 · State-to-region mapping table
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.state_region_map` AS
SELECT 'Maharashtra' AS state, 'West' AS region UNION ALL
SELECT 'Gujarat',          'West'    UNION ALL
SELECT 'Goa',              'West'    UNION ALL
SELECT 'Tamil Nadu',       'South'   UNION ALL
SELECT 'Karnataka',        'South'   UNION ALL
SELECT 'Telangana',        'South'   UNION ALL
SELECT 'Kerala',           'South'   UNION ALL
SELECT 'Andhra Pradesh',   'South'   UNION ALL
SELECT 'Delhi',            'North'   UNION ALL
SELECT 'Haryana',          'North'   UNION ALL
SELECT 'Punjab',           'North'   UNION ALL
SELECT 'Himachal Pradesh', 'North'   UNION ALL
SELECT 'Uttarakhand',      'North'   UNION ALL
SELECT 'Uttar Pradesh',    'North'   UNION ALL
SELECT 'Rajasthan',        'North'   UNION ALL
SELECT 'West Bengal',      'East'    UNION ALL
SELECT 'Jharkhand',        'East'    UNION ALL
SELECT 'Bihar',            'East'    UNION ALL
SELECT 'Odisha',           'East'    UNION ALL
SELECT 'Assam',            'East'    UNION ALL
SELECT 'Madhya Pradesh',   'Central' UNION ALL
SELECT 'Chhattisgarh',     'Central';

-- -----------------------------------------------------------------------------
-- Step 1 · One row per state: revenue, growth, activation, concentration, service
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.state_performance` AS
WITH lines AS (
    SELECT
        c.state,
        o.customer_id,
        o.order_date,
        i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id    = i.order_id
    JOIN `sahyadri_b2b.customers`         AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
),
customer_12m AS (
    SELECT state, customer_id, SUM(revenue) AS revenue_12m
    FROM lines
    WHERE order_date BETWEEN window_start AND window_end
    GROUP BY state, customer_id
),
state_revenue AS (
    SELECT
        state,
        SUM(IF(order_date BETWEEN window_start AND window_end, revenue, 0)) AS revenue_12m,
        SUM(IF(order_date BETWEEN py_start     AND py_end,     revenue, 0)) AS revenue_py_ytd,
        SUM(IF(order_date BETWEEN cy_start     AND cy_end,     revenue, 0)) AS revenue_cy_ytd
    FROM lines
    GROUP BY state
),
registered AS (
    SELECT state, COUNT(*) AS registered_customers
    FROM `sahyadri_b2b.customers`
    GROUP BY state
),
concentration AS (
    SELECT state, COUNT(*) AS active_customers, MAX(revenue_12m) AS largest_customer_revenue
    FROM customer_12m
    GROUP BY state
),
delivery AS (
    SELECT
        c.state,
        COUNT(*)                                          AS measured_deliveries,
        COUNTIF(d.final_delivery_date <= o.promised_delivery_date) AS on_time_deliveries
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.customers`    AS c ON c.customer_id = o.customer_id
    JOIN (SELECT order_id, MAX(delivery_date) AS final_delivery_date
            FROM `sahyadri_b2b.shipments` GROUP BY order_id) AS d ON d.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date BETWEEN window_start AND window_end
      AND o.promised_delivery_date IS NOT NULL
      AND d.final_delivery_date IS NOT NULL
    GROUP BY c.state
)
SELECT
    g.state,
    IFNULL(m.region, 'Unmapped')                                        AS region,
    g.registered_customers,
    IFNULL(k.active_customers, 0)                                       AS active_customers,
    ROUND(SAFE_DIVIDE(IFNULL(k.active_customers, 0), g.registered_customers), 4) AS activation_rate,
    ROUND(IFNULL(r.revenue_12m, 0), 2)                                  AS revenue_12m,
    ROUND(SAFE_DIVIDE(r.revenue_12m, k.active_customers), 2)            AS revenue_per_active_customer,
    ROUND(IFNULL(r.revenue_py_ytd, 0), 2)                               AS revenue_py_ytd,
    ROUND(IFNULL(r.revenue_cy_ytd, 0), 2)                               AS revenue_cy_ytd,
    ROUND(SAFE_DIVIDE(r.revenue_cy_ytd, r.revenue_py_ytd) - 1, 4)       AS ytd_growth,
    ROUND(SAFE_DIVIDE(k.largest_customer_revenue, r.revenue_12m), 4)    AS largest_customer_share,
    IFNULL(d.measured_deliveries, 0)                                    AS measured_deliveries,
    ROUND(SAFE_DIVIDE(d.on_time_deliveries, d.measured_deliveries), 4)  AS on_time_rate
FROM registered                       AS g
LEFT JOIN `sahyadri_b2b.state_region_map` AS m ON m.state = g.state
LEFT JOIN state_revenue               AS r ON r.state = g.state
LEFT JOIN concentration               AS k ON k.state = g.state
LEFT JOIN delivery                    AS d ON d.state = g.state;

-- -----------------------------------------------------------------------------
-- Step 2 · Region summary
-- -----------------------------------------------------------------------------
SELECT
    region,
    COUNT(*)                                                             AS states,
    SUM(registered_customers)                                            AS registered,
    SUM(active_customers)                                                AS active,
    ROUND(100 * SUM(active_customers) / SUM(registered_customers), 1)    AS activation_pct,
    ROUND(SUM(revenue_12m), 2)                                           AS revenue_12m,
    ROUND(100 * SUM(revenue_12m) / SUM(SUM(revenue_12m)) OVER (), 1)     AS pct_of_revenue,
    ROUND(100 * (SUM(revenue_cy_ytd) / SUM(revenue_py_ytd) - 1), 1)      AS ytd_growth_pct,
    ROUND(SUM(revenue_12m) / SUM(active_customers), 0)                   AS revenue_per_active_customer,
    ROUND(100 * SUM(on_time_rate * measured_deliveries) / SUM(measured_deliveries), 1) AS on_time_pct
FROM `sahyadri_b2b.state_performance`
GROUP BY region
ORDER BY revenue_12m DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · State portfolio: size vs growth quadrant
-- -----------------------------------------------------------------------------
WITH company AS (
    SELECT SUM(revenue_cy_ytd) / SUM(revenue_py_ytd) - 1 AS company_growth
    FROM `sahyadri_b2b.state_performance`
),
median_size AS (
    SELECT DISTINCT PERCENTILE_CONT(revenue_12m, 0.5) OVER () AS median_revenue
    FROM `sahyadri_b2b.state_performance`
    WHERE revenue_12m >= min_revenue
),
benchmarks AS (
    SELECT c.company_growth, m.median_revenue
    FROM company AS c CROSS JOIN median_size AS m
)
SELECT
    s.state,
    s.region,
    s.revenue_12m,
    ROUND(100 * s.ytd_growth, 1)                  AS ytd_growth_pct,
    s.active_customers,
    ROUND(100 * s.activation_rate, 1)             AS activation_pct,
    ROUND(100 * s.largest_customer_share, 1)      AS largest_customer_pct,
    ROUND(100 * s.on_time_rate, 1)                AS on_time_pct,
    CASE
        WHEN s.revenue_12m < min_revenue                                          THEN 'Too small to classify'
        WHEN s.revenue_12m >= b.median_revenue AND s.ytd_growth >  b.company_growth THEN 'Invest'
        WHEN s.revenue_12m >= b.median_revenue                                      THEN 'Defend'
        WHEN s.ytd_growth > b.company_growth                                        THEN 'Develop'
        ELSE 'Review'
    END                                           AS quadrant
FROM `sahyadri_b2b.state_performance` AS s
CROSS JOIN benchmarks                 AS b
ORDER BY s.revenue_12m DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Concentration risk: states where one customer is over 40 % of revenue
-- -----------------------------------------------------------------------------
WITH ranked AS (
    SELECT
        c.state,
        c.customer_id,
        c.customer_name,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue_12m,
        ROW_NUMBER() OVER (PARTITION BY c.state
                           ORDER BY SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) DESC) AS rank_in_state
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id    = i.order_id
    JOIN `sahyadri_b2b.customers`         AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN window_start AND window_end
    GROUP BY c.state, c.customer_id, c.customer_name
)
SELECT
    s.state,
    s.revenue_12m                                 AS state_revenue_12m,
    s.active_customers,
    r.customer_id                                 AS largest_customer_id,
    r.customer_name                               AS largest_customer,
    ROUND(r.revenue_12m, 2)                       AS largest_customer_revenue,
    ROUND(100 * s.largest_customer_share, 1)      AS largest_customer_pct
FROM `sahyadri_b2b.state_performance` AS s
JOIN ranked                           AS r ON r.state = s.state AND r.rank_in_state = 1
WHERE s.largest_customer_share > 0.40
ORDER BY s.revenue_12m DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Dormant registered base by state: registered but not active
-- -----------------------------------------------------------------------------
SELECT
    state,
    region,
    registered_customers,
    active_customers,
    registered_customers - active_customers       AS inactive_customers,
    ROUND(100 * activation_rate, 1)               AS activation_pct,
    ROUND(revenue_per_active_customer, 0)         AS revenue_per_active_customer
FROM `sahyadri_b2b.state_performance`
WHERE registered_customers >= 10
ORDER BY activation_rate;
