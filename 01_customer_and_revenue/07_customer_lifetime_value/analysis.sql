/* =============================================================================
   Case study · Customer lifetime value
   Category : Customer and revenue
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Sales and marketing spend is allocated on last year's revenue. A customer
   that buys once and never returns looks the same as one that will buy for
   years. The CFO wants a forward-looking value for every customer:
     1. What is the expected future margin of each customer over five years,
        allowing for the chance that they leave?
     2. What drives retention, and how certain are the retention rates?
     3. How concentrated is future value, and how does it differ by segment?
     4. What is it worth to turn a one-order customer into a repeat buyer,
        and how much can the company afford to spend doing it?

   METHOD — retention-based CLV
     CLV = m * sum over t = 1..H of (r / (1 + d))^t
         = m * q * (1 - q^H) / (1 - q),   q = r / (1 + d)
       m = the customer's annual margin (gross profit - freight) in the last
           12 months
       r = annual retention rate for the customer's purchase-frequency band
       d = discount rate (cost of capital, 12 %)
       H = horizon (5 years)
     The current year's margin is not included: CLV is future value only.

   RETENTION
     - Measured as the share of customers active in Oct 2024 - Sep 2025 who
       bought again in Oct 2025 - Sep 2026, by the number of orders they
       placed in the first year: 1, 2-5, 6 or more.
     - Laplace-smoothed: r = (retained + 1) / (customers + 2), so a band with
       100 % observed retention is not treated as certain.
     - 95 % interval: r +/- 1.96 * SQRT(r (1 - r) / n), capped to 0-1.

   KEY RULES
     - Orders not Cancelled or Returned; NULL discount = 0 %; product cost =
       quantity * unit_cost (NULL cost = 0); freight = shipping_cost on the
       orders (NULL = 0).
   ============================================================================= */

DECLARE p1_start      DATE    DEFAULT DATE '2024-10-01';
DECLARE p1_end        DATE    DEFAULT DATE '2025-09-30';
DECLARE p2_start      DATE    DEFAULT DATE '2025-10-01';
DECLARE p2_end        DATE    DEFAULT DATE '2026-09-30';
DECLARE discount_rate FLOAT64 DEFAULT 0.12;
DECLARE horizon_years INT64   DEFAULT 5;

-- -----------------------------------------------------------------------------
-- Step 1 · Retention by purchase-frequency band, with intervals
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.clv_retention_bands` AS
WITH p1 AS (
    SELECT customer_id, COUNT(DISTINCT order_id) AS orders
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
      AND order_date BETWEEN p1_start AND p1_end
    GROUP BY customer_id
),
p2 AS (
    SELECT DISTINCT customer_id
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
      AND order_date BETWEEN p2_start AND p2_end
),
banded AS (
    SELECT
        CASE WHEN p1.orders = 1 THEN '1 order' WHEN p1.orders <= 5 THEN '2-5 orders' ELSE '6+ orders' END AS frequency_band,
        p2.customer_id IS NOT NULL AS retained
    FROM p1
    LEFT JOIN p2 ON p2.customer_id = p1.customer_id
),
rates AS (
    SELECT
        frequency_band,
        COUNT(*)                                   AS customers,
        COUNTIF(retained)                          AS retained,
        COUNTIF(retained) / COUNT(*)               AS observed_rate,
        (COUNTIF(retained) + 1) / (COUNT(*) + 2)   AS retention_rate
    FROM banded
    GROUP BY frequency_band
)
SELECT
    *,
    GREATEST(retention_rate - 1.96 * SQRT(retention_rate * (1 - retention_rate) / customers), 0) AS retention_low,
    LEAST(retention_rate + 1.96 * SQRT(retention_rate * (1 - retention_rate) / customers), 1)    AS retention_high
FROM rates;

SELECT
    frequency_band,
    customers,
    retained,
    ROUND(100 * observed_rate, 1)   AS observed_pct,
    ROUND(100 * retention_rate, 1)  AS smoothed_pct,
    ROUND(100 * retention_low, 1)   AS low_95_pct,
    ROUND(100 * retention_high, 1)  AS high_95_pct
FROM `sahyadri_b2b.clv_retention_bands`
ORDER BY frequency_band;

-- -----------------------------------------------------------------------------
-- Step 2 · One row per current customer: annual margin, band and CLV
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_lifetime_value` AS
WITH orders_p2 AS (
    SELECT order_id, customer_id
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status NOT IN ('Cancelled', 'Returned')
      AND order_date BETWEEN p2_start AND p2_end
),
line_margin AS (
    SELECT
        o.customer_id,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100))      AS revenue,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)
            - i.quantity * IFNULL(p.unit_cost, 0))                                      AS gross_profit
    FROM orders_p2                        AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id   = o.order_id
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    GROUP BY o.customer_id
),
freight AS (
    SELECT o.customer_id, SUM(IFNULL(s.shipping_cost, 0)) AS freight
    FROM orders_p2                AS o
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    GROUP BY o.customer_id
),
order_counts AS (
    SELECT customer_id, COUNT(*) AS orders FROM orders_p2 GROUP BY customer_id
),
base AS (
    SELECT
        m.customer_id,
        c.customer_name,
        c.customer_segment,
        k.orders                                                   AS orders_12m,
        CASE WHEN k.orders = 1 THEN '1 order' WHEN k.orders <= 5 THEN '2-5 orders' ELSE '6+ orders' END AS frequency_band,
        m.revenue,
        m.gross_profit,
        IFNULL(f.freight, 0)                                       AS freight,
        m.gross_profit - IFNULL(f.freight, 0)                      AS annual_margin
    FROM line_margin              AS m
    JOIN order_counts             AS k ON k.customer_id = m.customer_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = m.customer_id
    LEFT JOIN freight             AS f ON f.customer_id = m.customer_id
),
factors AS (
    -- annuity factor sum_{t=1..H} q^t with q = r / (1 + d), for the central, low and high rates
    SELECT
        frequency_band,
        retention_rate,
        (retention_rate / (1 + discount_rate)) * (1 - POW(retention_rate / (1 + discount_rate), horizon_years))
            / (1 - retention_rate / (1 + discount_rate))                                   AS factor,
        (retention_low  / (1 + discount_rate)) * (1 - POW(retention_low  / (1 + discount_rate), horizon_years))
            / (1 - retention_low  / (1 + discount_rate))                                   AS factor_low,
        (retention_high / (1 + discount_rate)) * (1 - POW(retention_high / (1 + discount_rate), horizon_years))
            / (1 - retention_high / (1 + discount_rate))                                   AS factor_high
    FROM `sahyadri_b2b.clv_retention_bands`
)
SELECT
    b.*,
    ROUND(f.retention_rate, 4)                          AS retention_rate,
    ROUND(f.factor, 4)                                  AS clv_multiple,
    ROUND(b.annual_margin * f.factor, 2)                AS clv,
    ROUND(b.annual_margin * f.factor_low, 2)            AS clv_low,
    ROUND(b.annual_margin * f.factor_high, 2)           AS clv_high,
    ROW_NUMBER() OVER (ORDER BY b.annual_margin * f.factor DESC, b.customer_id) AS clv_rank
FROM base         AS b
JOIN factors      AS f ON f.frequency_band = b.frequency_band;

-- -----------------------------------------------------------------------------
-- Step 3 · CLV by segment and by frequency band
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                                      AS customers,
    ROUND(SUM(annual_margin), 0)                                  AS annual_margin,
    ROUND(SUM(clv), 0)                                            AS clv_5_years,
    ROUND(SUM(clv_low), 0)                                        AS clv_low,
    ROUND(SUM(clv_high), 0)                                       AS clv_high,
    ROUND(100 * SUM(clv) / SUM(SUM(clv)) OVER (), 1)              AS pct_of_total_clv,
    ROUND(AVG(clv), 0)                                            AS average_clv
FROM `sahyadri_b2b.customer_lifetime_value`
GROUP BY customer_segment
ORDER BY clv_5_years DESC;

SELECT
    frequency_band,
    COUNT(*)                                                      AS customers,
    ROUND(AVG(retention_rate) * 100, 1)                           AS retention_pct,
    ROUND(AVG(clv_multiple), 2)                                   AS clv_multiple_of_annual_margin,
    ROUND(SUM(clv), 0)                                            AS clv_5_years,
    ROUND(100 * SUM(clv) / SUM(SUM(clv)) OVER (), 1)              AS pct_of_total_clv
FROM `sahyadri_b2b.customer_lifetime_value`
GROUP BY frequency_band
ORDER BY frequency_band;

-- -----------------------------------------------------------------------------
-- Step 4 · How concentrated is future value?
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN clv_rank <= 10  THEN '1. Top 10'
        WHEN clv_rank <= 50  THEN '2. Next 40'
        WHEN clv <= 0        THEN '4. Zero or negative margin'
        ELSE '3. All other customers'
    END                                                            AS customer_group,
    COUNT(*)                                                       AS customers,
    ROUND(SUM(clv), 0)                                             AS clv_5_years,
    ROUND(100 * SUM(clv) / SUM(SUM(clv)) OVER (), 1)               AS pct_of_total_clv
FROM `sahyadri_b2b.customer_lifetime_value`
GROUP BY customer_group
ORDER BY customer_group;

-- -----------------------------------------------------------------------------
-- Step 5 · Value of a second order: one-order customers moved to the 2-5 band
-- -----------------------------------------------------------------------------
WITH multiples AS (
    SELECT frequency_band, ANY_VALUE(clv_multiple) AS multiple
    FROM `sahyadri_b2b.customer_lifetime_value`
    GROUP BY frequency_band
),
one_order AS (
    SELECT annual_margin FROM `sahyadri_b2b.customer_lifetime_value` WHERE frequency_band = '1 order'
),
typical AS (
    SELECT DISTINCT PERCENTILE_CONT(annual_margin, 0.5) OVER () AS median_margin FROM one_order
)
SELECT
    (SELECT COUNT(*) FROM one_order)                                              AS one_order_customers,
    ROUND(t.median_margin, 0)                                                     AS median_annual_margin,
    ROUND(m1.multiple, 2)                                                         AS multiple_if_one_order,
    ROUND(m2.multiple, 2)                                                         AS multiple_if_repeat_buyer,
    ROUND(t.median_margin * (m2.multiple - m1.multiple), 0)                       AS clv_gain_per_typical_customer,
    ROUND((SELECT SUM(annual_margin) FROM one_order) * (m2.multiple - m1.multiple), 0) AS clv_gain_if_all_became_repeat_buyers
FROM typical AS t
CROSS JOIN (SELECT multiple FROM multiples WHERE frequency_band = '1 order')    AS m1
CROSS JOIN (SELECT multiple FROM multiples WHERE frequency_band = '2-5 orders') AS m2;
