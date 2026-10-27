/* =============================================================================
   Case study · Real differences or noise? Empirical Bayes for operational rates
   Category : Operations and supply chain
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The operations review ranks customers, salespeople, products and cities
   on cancellation, return and late-delivery rates, and sends "worst ten"
   lists to managers every quarter. Many entries are customers with a
   handful of orders, and the lists change completely from one quarter to
   the next. The operations head asks:
     1. For which rates do customers, products, salespeople or cities really
        differ, and for which is the variation just chance?
     2. What is each member's credible rate once small samples are allowed
        for?
     3. How many of the members flagged on raw rates survive?
     4. Which lists are worth sending, and which should stop?

   METHOD
     - Six measures:
         Cancellation by customer / by salesperson   (closed orders: Delivered,
                                                       Cancelled, Returned)
         Cancellation by product                      (lines of closed orders)
         Return by destination city                   (shipments)
         Late delivery by customer / by destination city
                                                      (delivered orders with a
                                                       promise date)
     - Overall rate p; member rate r = k / n.
     - Heterogeneity: Q = SUM n (r - p)^2 / (p (1 - p)), compared with
       chi-square on (members - 1) degrees of freedom (Wilson-Hilferty z).
     - Between-member variance (DerSimonian-Laird):
         tau^2 = MAX(0, (Q - (K - 1)) / (SUM w - SUM w^2 / SUM w)), w = n / (p (1 - p)).
     - Empirical Bayes (normal approximation): shrinkage
         B = (p (1 - p) / n) / (p (1 - p) / n + tau^2);
       credible rate = B p + (1 - B) r; posterior s.d. = SQRT(tau^2 B).
       When tau^2 = 0 every member is shrunk fully to p.
     - "Reliably above average" = posterior probability of at least 0.95 that
       the true rate exceeds the overall rate p. Normal probabilities use the logistic approximation
       PHI(x) = 1 / (1 + EXP(-1.702 x)).
   ============================================================================= */

DECLARE high_multiple FLOAT64 DEFAULT 1.0;
DECLARE prob_cutoff   FLOAT64 DEFAULT 0.95;

-- -----------------------------------------------------------------------------
-- Step 1 · Counts per member for every measure
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.eb_counts` AS
WITH closed AS (
    SELECT order_id, customer_id, employee_id, order_status
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_status IN ('Delivered', 'Cancelled', 'Returned')
),
delivered AS (
    SELECT o.order_id, o.customer_id,
           MAX(s.delivery_date) > o.promised_delivery_date                                  AS is_late,
           ARRAY_AGG(INITCAP(TRIM(s.shipping_city)) ORDER BY s.shipment_date, s.shipment_id LIMIT 1)[OFFSET(0)] AS city
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND o.promised_delivery_date IS NOT NULL
    GROUP BY o.order_id, o.customer_id, o.promised_delivery_date
    HAVING COUNT(s.delivery_date) = COUNT(*)
)
          SELECT '1. Cancellation by customer'     AS measure, CAST(customer_id AS STRING) AS member, COUNT(*) AS n, COUNTIF(order_status = 'Cancelled') AS k
          FROM closed GROUP BY customer_id
UNION ALL SELECT '2. Cancellation by salesperson',  IFNULL(CAST(employee_id AS STRING), 'Unassigned'), COUNT(*), COUNTIF(order_status = 'Cancelled')
          FROM closed GROUP BY employee_id
UNION ALL SELECT '3. Cancellation by product',      CAST(i.product_id AS STRING), COUNT(*), COUNTIF(c.order_status = 'Cancelled')
          FROM closed AS c JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = c.order_id GROUP BY i.product_id
UNION ALL SELECT '4. Return by city',               INITCAP(TRIM(shipping_city)), COUNT(*), COUNTIF(shipment_status = 'Returned')
          FROM `sahyadri_b2b.shipments` GROUP BY INITCAP(TRIM(shipping_city))
UNION ALL SELECT '5. Late delivery by customer',    CAST(customer_id AS STRING), COUNT(*), COUNTIF(is_late)
          FROM delivered GROUP BY customer_id
UNION ALL SELECT '6. Late delivery by city',        city, COUNT(*), COUNTIF(is_late)
          FROM delivered GROUP BY city;

-- -----------------------------------------------------------------------------
-- Step 2 · Is there real variation? Heterogeneity and between-member variance
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.eb_measures` AS
WITH base AS (
    SELECT measure, SUM(k) / SUM(n) AS p, COUNT(*) AS members, SUM(n) AS records, SUM(k) AS events
    FROM `sahyadri_b2b.eb_counts`
    GROUP BY measure
),
q AS (
    SELECT c.measure,
           SUM(c.n * POW(c.k / c.n - b.p, 2) / (b.p * (1 - b.p)))                         AS q_stat,
           SUM(c.n / (b.p * (1 - b.p)))                                                   AS sum_w,
           SUM(POW(c.n / (b.p * (1 - b.p)), 2))                                           AS sum_w2
    FROM `sahyadri_b2b.eb_counts` AS c JOIN base AS b ON b.measure = c.measure
    GROUP BY c.measure
)
SELECT
    b.*, q.q_stat,
    -- Wilson-Hilferty z for Q against chi-square(members - 1)
    (POW(q.q_stat / (b.members - 1), 1 / 3) - (1 - 2 / (9 * (b.members - 1)))) / SQRT(2 / (9 * (b.members - 1))) AS heterogeneity_z,
    GREATEST(0, (q.q_stat - (b.members - 1)) / (q.sum_w - q.sum_w2 / q.sum_w))       AS tau2
FROM base AS b JOIN q ON q.measure = b.measure;

SELECT
    measure, members, records, events,
    ROUND(100 * p, 2)                                                AS overall_rate_pct,
    ROUND(q_stat, 1)                                                 AS q, members - 1 AS df,
    ROUND(heterogeneity_z, 2)                                        AS heterogeneity_z,
    ROUND(100 * SQRT(tau2), 2)                                       AS between_member_sd_pct,
    ROUND(SQRT(tau2) / p, 2)                                         AS sd_relative_to_rate,
    IF(heterogeneity_z >= 3.09, 'Real differences', 'Consistent with chance') AS verdict
FROM `sahyadri_b2b.eb_measures`
ORDER BY measure;

-- -----------------------------------------------------------------------------
-- Step 3 · Credible (shrunk) rates per member
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.eb_members` AS
WITH s AS (
    SELECT c.*, m.p, m.tau2,
           c.k / c.n                                                                          AS raw_rate,
           (c.k / c.n - m.p) / SQRT(m.p * (1 - m.p) / c.n)                                    AS raw_z,
           IF(m.tau2 = 0, 1, (m.p * (1 - m.p) / c.n) / (m.p * (1 - m.p) / c.n + m.tau2))     AS shrinkage
    FROM `sahyadri_b2b.eb_counts` AS c JOIN `sahyadri_b2b.eb_measures` AS m ON m.measure = c.measure
)
SELECT
    *,
    shrinkage * p + (1 - shrinkage) * raw_rate                                                AS credible_rate,
    SQRT(tau2 * shrinkage)                                                                    AS posterior_sd,
    IF(tau2 = 0, 0,
       1 / (1 + EXP(-1.702 * ((shrinkage * p + (1 - shrinkage) * raw_rate - high_multiple * p)
                              / NULLIF(SQRT(tau2 * shrinkage), 0)))))                         AS prob_clearly_high
FROM s;

SELECT
    measure,
    COUNTIF(raw_rate >= 1.5 * p)                                                    AS raw_rate_at_least_1_5x,
    COUNTIF(raw_z >= 2)                                                             AS raw_z_2_or_more,
    ROUND(COUNT(*) * 0.0228, 1)                                                     AS expected_z_2_by_chance,
    COUNTIF(prob_clearly_high >= prob_cutoff)                                       AS reliably_above_average,
    ROUND(100 * MIN(raw_rate), 1)                                                   AS raw_min_pct,
    ROUND(100 * MAX(raw_rate), 1)                                                   AS raw_max_pct,
    ROUND(100 * MIN(credible_rate), 1)                                              AS credible_min_pct,
    ROUND(100 * MAX(credible_rate), 1)                                              AS credible_max_pct
FROM `sahyadri_b2b.eb_members`
GROUP BY measure
ORDER BY measure;

-- -----------------------------------------------------------------------------
-- Step 4 · What the lists should contain
-- -----------------------------------------------------------------------------
-- Raw "worst ten" for customer cancellations against their credible rates
SELECT m.member AS customer_id, c.customer_name, m.n AS closed_orders, CAST(m.k AS INT64) AS cancelled,
       ROUND(100 * m.raw_rate, 1) AS raw_pct, ROUND(m.raw_z, 2) AS raw_z,
       ROUND(100 * m.credible_rate, 1) AS credible_pct
FROM `sahyadri_b2b.eb_members` AS m
JOIN `sahyadri_b2b.customers` AS c ON CAST(c.customer_id AS STRING) = m.member
WHERE m.measure = '1. Cancellation by customer' AND m.n >= 20
ORDER BY m.raw_rate DESC, m.n DESC
LIMIT 10;

-- Members reliably above average (posterior probability >= 0.95)
SELECT
    m.measure,
    IF(m.measure LIKE '%customer%', IFNULL(c.customer_name, m.member), m.member)    AS member_name,
    m.n, CAST(m.k AS INT64) AS events,
    ROUND(100 * m.raw_rate, 1)                                                     AS raw_pct,
    ROUND(100 * m.credible_rate, 1)                                                AS credible_pct,
    ROUND(m.shrinkage, 2)                                                          AS shrinkage,
    ROUND(m.prob_clearly_high, 3)                                                  AS prob_clearly_high
FROM `sahyadri_b2b.eb_members` AS m
LEFT JOIN `sahyadri_b2b.customers` AS c ON m.measure LIKE '%customer%' AND CAST(c.customer_id AS STRING) = m.member
WHERE m.prob_clearly_high >= prob_cutoff
ORDER BY m.measure, m.credible_rate DESC;

-- Late delivery by city: the most and least reliable destinations (credible rate)
SELECT member AS city, n AS delivered_orders, CAST(k AS INT64) AS late,
       ROUND(100 * raw_rate, 1) AS raw_pct, ROUND(100 * credible_rate, 1) AS credible_pct,
       ROUND(shrinkage, 2) AS shrinkage
FROM `sahyadri_b2b.eb_members`
WHERE measure = '6. Late delivery by city'
  AND (credible_rate >= (SELECT APPROX_QUANTILES(credible_rate, 10)[OFFSET(9)] FROM `sahyadri_b2b.eb_members` WHERE measure = '6. Late delivery by city')
    OR credible_rate <= (SELECT APPROX_QUANTILES(credible_rate, 10)[OFFSET(1)] FROM `sahyadri_b2b.eb_members` WHERE measure = '6. Late delivery by city'))
ORDER BY credible_rate DESC;

-- Is it the customer or the destination? Late delivery by customer after allowing
-- for each order's city (expected = sum of city late rates over the customer's orders)
WITH delivered AS (
    SELECT o.order_id, o.customer_id,
           IF(MAX(s.delivery_date) > o.promised_delivery_date, 1, 0)                         AS is_late,
           ARRAY_AGG(INITCAP(TRIM(s.shipping_city)) ORDER BY s.shipment_date, s.shipment_id LIMIT 1)[OFFSET(0)] AS city
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = o.order_id
    WHERE o.order_status = 'Delivered' AND o.promised_delivery_date IS NOT NULL
    GROUP BY o.order_id, o.customer_id, o.promised_delivery_date
    HAVING COUNT(s.delivery_date) = COUNT(*)
),
city_rate AS (
    SELECT city, AVG(is_late) AS pc FROM delivered GROUP BY city
),
cust AS (
    SELECT d.customer_id, SUM(d.is_late) AS observed, SUM(c.pc) AS expected, SUM(c.pc * (1 - c.pc)) AS variance, COUNT(*) AS n
    FROM delivered AS d JOIN city_rate AS c ON c.city = d.city
    GROUP BY d.customer_id
)
SELECT
    COUNT(*)                                                                        AS customers,
    ROUND(SUM(POW(observed - expected, 2) / variance), 1)                           AS q_city_adjusted,
    COUNT(*) - 1                                                                    AS df,
    ROUND((POW(SUM(POW(observed - expected, 2) / variance) / (COUNT(*) - 1), 1 / 3)
           - (1 - 2 / (9 * (COUNT(*) - 1)))) / SQRT(2 / (9 * (COUNT(*) - 1))), 2)   AS heterogeneity_z,
    COUNTIF((observed - expected) / SQRT(variance) >= 2)                            AS customers_z_2_or_more
FROM cust
WHERE variance > 0;
