/* =============================================================================
   Case study · Discount creep: do customers get bigger discounts the longer
   they buy?
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The pricing manager's monthly report shows that a customer's first order
   carries a discount of about 5 %, while orders from customers who have
   placed thirty or more carry about 7 %. She reads it as "discount creep":
   loyal customers negotiate a little more each year, and margin leaks
   away. Before asking sales for a discount freeze on long-standing
   accounts she asks:
     1. Does the same customer's discount rise from order to order and from
        year to year?
     2. If not, why do frequent customers get bigger discounts?
     3. Is there creep in any segment, or on large orders?
     4. What would a creep cap actually save?

   METHOD
     - Valid orders (not Cancelled or Returned), January 2024 - September
       2026. Order discount = discount given / list-price value of its lines.
     - Cross-section: average discount by order number (1st, 2nd-3rd, ...)
       and by the customer's total orders.
     - Within customer: each order's discount and its time since the
       customer's first order are centred on the customer's own averages;
       the pooled slope is the change in discount per year for the same
       customer. Tested against 500 shuffles of each customer's discounts
       across its own orders.
     - The same within-customer comparison by segment, and for the first
       ten orders against later orders of customers with 30 or more.
   ============================================================================= */

DECLARE shuffles INT64 DEFAULT 500;
DECLARE prime    INT64 DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Orders in sequence for each customer
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dc_orders` AS
WITH orders AS (
    SELECT o.order_id, o.customer_id, c.customer_segment, o.order_date,
           SUM(i.quantity * i.unit_price)                                                    AS list_value,
           SUM(i.quantity * i.unit_price * IFNULL(i.discount_percent, 0) / 100)               AS discount_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, c.customer_segment, o.order_date
),
sequenced AS (
    SELECT *,
           discount_value / list_value                                                       AS discount_rate,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id)        AS order_no,
           COUNT(*) OVER (PARTITION BY customer_id)                                          AS customer_orders,
           MIN(order_date) OVER (PARTITION BY customer_id)                                   AS first_order
    FROM orders
),
timed AS (
    SELECT *, DATE_DIFF(order_date, first_order, DAY) / 365.25 AS years_since_first FROM sequenced
)
SELECT *,
       discount_rate - AVG(discount_rate) OVER (PARTITION BY customer_id)                   AS discount_dev,
       years_since_first - AVG(years_since_first) OVER (PARTITION BY customer_id)            AS years_dev,
       LN(list_value) - AVG(LN(list_value)) OVER (PARTITION BY customer_id)                  AS size_dev
FROM timed;

-- -----------------------------------------------------------------------------
-- Step 2 · The cross-section: what the report shows
-- -----------------------------------------------------------------------------
SELECT
    CASE WHEN order_no = 1 THEN '1. First order' WHEN order_no <= 3 THEN '2. Orders 2-3'
         WHEN order_no <= 10 THEN '3. Orders 4-10' WHEN order_no <= 30 THEN '4. Orders 11-30' ELSE '5. Order 31+' END AS order_number,
    COUNT(*)                                                                          AS orders,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(100 * SUM(discount_value) / SUM(list_value), 2)                             AS discount_pct_value_weighted,
    ROUND(100 * AVG(discount_rate), 2)                                                AS discount_pct_order_average
FROM `sahyadri_b2b.dc_orders`
GROUP BY order_number
ORDER BY order_number;

-- Customers by how many orders they place: the bigger buyers get the bigger discounts
SELECT
    CASE WHEN customer_orders <= 3 THEN '1. 1-3 orders' WHEN customer_orders <= 10 THEN '2. 4-10'
         WHEN customer_orders <= 30 THEN '3. 11-30' ELSE '4. 31+' END                AS customer_size,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    COUNT(*)                                                                          AS orders,
    ROUND(100 * AVG(discount_rate), 2)                                                AS discount_pct,
    ROUND(100 * AVG(IF(order_no = 1, discount_rate, NULL)), 2)                         AS first_order_discount_pct,
    ROUND(AVG(list_value) / 1e3, 1)                                                   AS avg_order_list_value_k
FROM `sahyadri_b2b.dc_orders`
GROUP BY customer_size
ORDER BY customer_size;

-- -----------------------------------------------------------------------------
-- Step 3 · Within the customer: does the same customer's discount rise?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.dc_shuffles` AS
WITH eligible AS (
    SELECT * FROM `sahyadri_b2b.dc_orders` WHERE customer_orders >= 2
),
draws AS (
    SELECT e.customer_id, e.order_no, e.years_dev, b,
           ROW_NUMBER() OVER (PARTITION BY b, e.customer_id
                              ORDER BY MOD(MOD(b * 7919 + e.order_id * 104729, prime)
                                         * MOD(b * 7919 + e.order_id * 104729, prime) + 12345, prime)) AS shuffled_no
    FROM eligible AS e
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, shuffles)) AS b
)
SELECT d.b, SUM(d.years_dev * s.discount_dev) / SUM(d.years_dev * d.years_dev) AS slope_per_year
FROM draws AS d
JOIN eligible AS s ON s.customer_id = d.customer_id AND s.order_no = d.shuffled_no
GROUP BY d.b;

WITH observed AS (
    SELECT SUM(years_dev * discount_dev) / SUM(years_dev * years_dev)                 AS slope,
           SUM(size_dev * discount_dev) / SUM(size_dev * size_dev)                    AS size_slope,
           COUNT(DISTINCT customer_id)                                               AS customers,
           COUNT(*)                                                                  AS orders
    FROM `sahyadri_b2b.dc_orders`
    WHERE customer_orders >= 2
)
SELECT
    o.customers, o.orders,
    ROUND(100 * o.slope, 3)                                                           AS within_slope_pts_per_year,
    ROUND(100 * APPROX_QUANTILES(s.slope_per_year, 40)[OFFSET(1)], 3)                 AS shuffle_p2_5,
    ROUND(100 * APPROX_QUANTILES(s.slope_per_year, 40)[OFFSET(39)], 3)                AS shuffle_p97_5,
    ROUND(AVG(IF(ABS(s.slope_per_year) >= ABS(o.slope), 1, 0)), 3)                    AS p_value_two_sided,
    ROUND(100 * o.size_slope * LN(2), 3)                                              AS within_pts_per_doubling_of_order_size
FROM observed AS o
CROSS JOIN `sahyadri_b2b.dc_shuffles` AS s
GROUP BY o.customers, o.orders, o.slope, o.size_slope;

-- The same customers early and late: customers with 31 or more orders, each customer weighted equally
WITH stages AS (
    SELECT customer_id,
           CASE WHEN order_no <= 10 THEN '1. Their orders 1-10' WHEN order_no <= 30 THEN '2. Their orders 11-30'
                ELSE '3. Their orders 31+' END                                        AS stage,
           AVG(discount_rate)                                                         AS discount_rate,
           COUNT(*)                                                                   AS orders
    FROM `sahyadri_b2b.dc_orders`
    WHERE customer_orders >= 31
    GROUP BY customer_id, stage
)
SELECT stage, COUNT(*) AS customers, SUM(orders) AS orders,
       ROUND(100 * AVG(discount_rate), 2)                                             AS discount_pct_customer_weighted
FROM stages
GROUP BY stage
ORDER BY stage;

-- Year by year for the same customers (bought in all three calendar years)
WITH yearly AS (
    SELECT customer_id, EXTRACT(YEAR FROM order_date) AS yr, AVG(discount_rate) AS discount_rate
    FROM `sahyadri_b2b.dc_orders` GROUP BY customer_id, yr
),
all_years AS (
    SELECT customer_id FROM yearly GROUP BY customer_id HAVING COUNT(*) = 3
)
SELECT yr, COUNT(*) AS customers, ROUND(100 * AVG(discount_rate), 2) AS discount_pct
FROM yearly JOIN all_years USING (customer_id)
GROUP BY yr
ORDER BY yr;

-- -----------------------------------------------------------------------------
-- Step 4 · Segments, and where the discount difference comes from
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    COUNT(*)                                                                          AS orders,
    ROUND(100 * AVG(discount_rate), 2)                                                AS discount_pct,
    ROUND(100 * SUM(years_dev * discount_dev) / SUM(years_dev * years_dev), 3)        AS within_slope_pts_per_year
FROM `sahyadri_b2b.dc_orders`
WHERE customer_orders >= 2
GROUP BY customer_segment
ORDER BY customer_segment;

-- Between-customer view: customer average discount against customer size and segment
WITH per_customer AS (
    SELECT customer_id, customer_segment, ANY_VALUE(customer_orders) AS orders, AVG(discount_rate) AS discount_rate,
           LN(SUM(list_value)) AS ln_value
    FROM `sahyadri_b2b.dc_orders` GROUP BY customer_id, customer_segment
)
SELECT
    COUNT(*)                                                                          AS customers,
    ROUND(CORR(discount_rate, orders), 3)                                             AS corr_discount_vs_orders,
    ROUND(CORR(discount_rate, ln_value), 3)                                           AS corr_discount_vs_log_value,
    -- within segment: correlation after removing each segment's average
    ROUND(CORR(discount_rate - seg_d, ln_value - seg_v), 3)                           AS corr_within_segment_vs_log_value
FROM (
    SELECT *, AVG(discount_rate) OVER (PARTITION BY customer_segment) AS seg_d,
              AVG(ln_value) OVER (PARTITION BY customer_segment)      AS seg_v
    FROM per_customer
);

-- -----------------------------------------------------------------------------
-- Step 5 · What would a "no creep" rule recover?
-- -----------------------------------------------------------------------------
-- Each customer's later orders (after its first 365 days in the data) against its own
-- first-year average discount: rupees above that level, below it, and the net
WITH base AS (
    SELECT customer_id, SUM(discount_value) / SUM(list_value) AS first_year_rate
    FROM `sahyadri_b2b.dc_orders`
    WHERE years_since_first < 1
    GROUP BY customer_id
),
later AS (
    SELECT o.customer_id, o.list_value, o.discount_rate, b.first_year_rate,
           o.list_value * (o.discount_rate - b.first_year_rate)                       AS excess
    FROM `sahyadri_b2b.dc_orders` AS o
    JOIN base AS b USING (customer_id)
    WHERE o.years_since_first >= 1
)
SELECT
    COUNT(DISTINCT customer_id)                                                       AS customers,
    COUNT(*)                                                                          AS later_orders,
    ROUND(SUM(list_value) / 1e7, 2)                                                   AS later_list_value_crore,
    ROUND(SUM(IF(excess > 0, excess, 0)) / 1e5, 1)                                    AS above_own_first_year_lakh,
    ROUND(SUM(IF(excess < 0, -excess, 0)) / 1e5, 1)                                   AS below_own_first_year_lakh,
    ROUND(SUM(excess) / 1e5, 1)                                                       AS net_lakh,
    ROUND(100 * SUM(excess) / SUM(list_value), 3)                                     AS net_pct_of_list_value
FROM later;
