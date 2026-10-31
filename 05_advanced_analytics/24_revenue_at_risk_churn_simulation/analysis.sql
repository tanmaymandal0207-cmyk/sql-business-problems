/* =============================================================================
   Case study · Revenue at risk from customer churn: a Monte Carlo stress test
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The lender reviewing the company's working-capital facility asks for a
   "revenue at risk" figure: how much of today's revenue base could be lost
   next year if customers stop buying, at a 95 % confidence level. The CFO
   asks the analytics team:
     1. How likely is each kind of customer to stop buying within a year?
     2. What revenue loss should be expected, and how bad could it be in one
        year in twenty?
     3. Would last year's method have predicted this year's actual loss?
     4. Where does the risk sit?

   METHOD
     - Snapshot dates 30 Sep 2024, 30 Sep 2025 and 30 Sep 2026. At each,
       customers with a valid order (not Cancelled or Returned) in the
       previous 9 months (the longest window available at the first
       snapshot). Exposure = their revenue in those 9 months.
     - Churn: no valid order in the 12 months after the snapshot.
     - Churn probability by frequency band (orders in the 9 months: 1,
       2-3, 4-8, 9+), estimated at the previous snapshot as
       (churners + 0.5) / (customers + 1), so a band with no churn so far
       still carries a small risk.
     - Monte Carlo: 2,000 scenarios; in each, every customer churns with
       its band probability (independent draws from an integer hash).
       Revenue lost = exposure of the customers that churn. Reported: mean,
       median, 95th and 99th percentiles. A stress case doubles every
       probability.
     - Back-test: the 2025 snapshot, with probabilities from 2024, against
       the loss that actually happened by September 2026.
   ============================================================================= */

DECLARE scenarios    INT64 DEFAULT 2000;
DECLARE window_days  INT64 DEFAULT 273;
DECLARE prime        INT64 DEFAULT 2147483647;

-- -----------------------------------------------------------------------------
-- Step 1 · Customers at each snapshot, their exposure and what happened next
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rr_customers` AS
WITH snapshots AS (
    SELECT DATE '2024-09-30' AS snapshot_date UNION ALL SELECT DATE '2025-09-30' UNION ALL SELECT DATE '2026-09-30'
),
orders AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id, o.order_date
),
history AS (
    SELECT s.snapshot_date, o.customer_id, COUNT(*) AS orders, SUM(o.order_value) AS exposure
    FROM snapshots AS s
    JOIN orders AS o ON o.order_date > DATE_SUB(s.snapshot_date, INTERVAL window_days DAY) AND o.order_date <= s.snapshot_date
    GROUP BY s.snapshot_date, o.customer_id
),
future AS (
    SELECT s.snapshot_date, o.customer_id, COUNT(*) AS orders_next_year
    FROM snapshots AS s
    JOIN orders AS o ON o.order_date > s.snapshot_date AND o.order_date <= DATE_ADD(s.snapshot_date, INTERVAL 365 DAY)
    GROUP BY s.snapshot_date, o.customer_id
)
SELECT
    h.snapshot_date, h.customer_id, c.customer_segment, h.orders, h.exposure,
    CASE WHEN h.orders = 1 THEN '1. One order' WHEN h.orders <= 3 THEN '2. 2-3 orders'
         WHEN h.orders <= 8 THEN '3. 4-8 orders' ELSE '4. 9+ orders' END            AS band,
    DATE_ADD(h.snapshot_date, INTERVAL 365 DAY) <= DATE '2026-09-30'                   AS outcome_known,
    IFNULL(f.orders_next_year, 0) = 0                                                  AS churned
FROM history AS h
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = h.customer_id
LEFT JOIN future AS f ON f.snapshot_date = h.snapshot_date AND f.customer_id = h.customer_id;

SELECT
    snapshot_date, band,
    COUNT(*)                                                         AS customers,
    ROUND(SUM(exposure) / 1e5, 1)                                    AS exposure_lakh,
    ROUND(100 * SUM(exposure) / SUM(SUM(exposure)) OVER (PARTITION BY snapshot_date), 1) AS exposure_share_pct,
    IF(ANY_VALUE(outcome_known), COUNTIF(churned), NULL)             AS churned,
    IF(ANY_VALUE(outcome_known), ROUND(100 * COUNTIF(churned) / COUNT(*), 1), NULL) AS churn_pct
FROM `sahyadri_b2b.rr_customers`
GROUP BY snapshot_date, band
ORDER BY snapshot_date, band;

-- -----------------------------------------------------------------------------
-- Step 2 · Churn probabilities from the previous snapshot
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rr_probabilities` AS
WITH rates AS (
    SELECT snapshot_date, band, (COUNTIF(churned) + 0.5) / (COUNT(*) + 1) AS p, COUNT(*) AS n, COUNTIF(churned) AS k
    FROM `sahyadri_b2b.rr_customers`
    WHERE outcome_known
    GROUP BY snapshot_date, band
)
SELECT DATE_ADD(snapshot_date, INTERVAL 1 YEAR) AS applied_at, band, p, n AS trained_on_customers, k AS trained_on_churners
FROM rates;

-- -----------------------------------------------------------------------------
-- Step 3 · Monte Carlo: 2,000 scenarios for the 2025 back-test and the 2026 book
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.rr_scenarios` AS
WITH exposed AS (
    SELECT c.snapshot_date, c.customer_id, c.exposure, p.p
    FROM `sahyadri_b2b.rr_customers` AS c
    JOIN `sahyadri_b2b.rr_probabilities` AS p ON p.applied_at = c.snapshot_date AND p.band = c.band
),
draws AS (
    SELECT e.snapshot_date, b, e.exposure, e.p,
           MOD(MOD(MOD(b * 7919 + e.customer_id * 104729 + EXTRACT(YEAR FROM e.snapshot_date) * 1299709, prime)
                 * MOD(b * 7919 + e.customer_id * 104729 + EXTRACT(YEAR FROM e.snapshot_date) * 1299709, prime) + 12345, prime)
               * 48271, prime) / prime AS u
    FROM exposed AS e
    CROSS JOIN UNNEST(GENERATE_ARRAY(1, scenarios)) AS b
)
SELECT snapshot_date, b,
       SUM(IF(u < p, exposure, 0))          AS revenue_lost,
       COUNTIF(u < p)                       AS customers_lost,
       SUM(IF(u < 2 * p, exposure, 0))      AS revenue_lost_stress,
       SUM(exposure)                        AS exposure
FROM draws
GROUP BY snapshot_date, b;

SELECT
    snapshot_date,
    ROUND(ANY_VALUE(exposure) / 1e7, 2)                                              AS exposure_crore,
    ROUND(AVG(revenue_lost) / 1e5, 1)                                                AS expected_loss_lakh,
    ROUND(APPROX_QUANTILES(revenue_lost, 100)[OFFSET(50)] / 1e5, 1)                  AS median_loss_lakh,
    ROUND(APPROX_QUANTILES(revenue_lost, 100)[OFFSET(95)] / 1e5, 1)                  AS p95_loss_lakh,
    ROUND(APPROX_QUANTILES(revenue_lost, 100)[OFFSET(99)] / 1e5, 1)                  AS p99_loss_lakh,
    ROUND(100 * APPROX_QUANTILES(revenue_lost, 100)[OFFSET(95)] / ANY_VALUE(exposure), 2) AS p95_loss_pct_of_exposure,
    ROUND(AVG(customers_lost), 1)                                                    AS expected_customers_lost,
    ROUND(APPROX_QUANTILES(revenue_lost_stress, 100)[OFFSET(95)] / 1e5, 1)           AS stress_p95_loss_lakh
FROM `sahyadri_b2b.rr_scenarios`
GROUP BY snapshot_date
ORDER BY snapshot_date;

-- Closed-form check: mean = SUM p x exposure; SD = SQRT(SUM p (1 - p) exposure^2)
SELECT
    c.snapshot_date,
    ROUND(SUM(p.p * c.exposure) / 1e5, 1)                                            AS expected_loss_formula_lakh,
    ROUND(SQRT(SUM(p.p * (1 - p.p) * POW(c.exposure, 2))) / 1e5, 1)                  AS sd_formula_lakh,
    ROUND((SUM(p.p * c.exposure) + 1.645 * SQRT(SUM(p.p * (1 - p.p) * POW(c.exposure, 2)))) / 1e5, 1) AS normal_p95_lakh
FROM `sahyadri_b2b.rr_customers` AS c
JOIN `sahyadri_b2b.rr_probabilities` AS p ON p.applied_at = c.snapshot_date AND p.band = c.band
GROUP BY c.snapshot_date
ORDER BY c.snapshot_date;

-- -----------------------------------------------------------------------------
-- Step 4 · Back-test: what the 2025 model predicted against what happened
-- -----------------------------------------------------------------------------
WITH actual AS (
    SELECT snapshot_date, SUM(IF(churned, exposure, 0)) AS lost, COUNTIF(churned) AS customers_lost
    FROM `sahyadri_b2b.rr_customers`
    WHERE snapshot_date = DATE '2025-09-30'
    GROUP BY snapshot_date
)
SELECT
    a.snapshot_date,
    ROUND(a.lost / 1e5, 1)                                                           AS actual_loss_lakh,
    a.customers_lost                                                                 AS actual_customers_lost,
    ROUND(AVG(s.revenue_lost) / 1e5, 1)                                              AS predicted_mean_lakh,
    ROUND(APPROX_QUANTILES(s.revenue_lost, 100)[OFFSET(5)] / 1e5, 1)                 AS predicted_p5_lakh,
    ROUND(APPROX_QUANTILES(s.revenue_lost, 100)[OFFSET(95)] / 1e5, 1)                AS predicted_p95_lakh,
    ROUND(100 * AVG(IF(s.revenue_lost <= a.lost, 1, 0)), 1)                          AS actual_loss_percentile,
    ROUND(AVG(s.customers_lost), 1)                                                  AS predicted_customers_lost
FROM actual AS a
JOIN `sahyadri_b2b.rr_scenarios` AS s ON s.snapshot_date = a.snapshot_date
GROUP BY a.snapshot_date, a.lost, a.customers_lost;

-- -----------------------------------------------------------------------------
-- Step 5 · Where the risk sits today (30 Sep 2026)
-- -----------------------------------------------------------------------------
SELECT
    c.band,
    COUNT(*)                                                                         AS customers,
    ROUND(SUM(c.exposure) / 1e5, 1)                                                  AS exposure_lakh,
    ROUND(100 * ANY_VALUE(p.p), 1)                                                   AS churn_probability_pct,
    ANY_VALUE(p.trained_on_churners)                                                 AS churners_in_training,
    ANY_VALUE(p.trained_on_customers)                                                AS customers_in_training,
    ROUND(SUM(p.p * c.exposure) / 1e5, 1)                                            AS expected_loss_lakh,
    ROUND(100 * SUM(p.p * c.exposure) / SUM(SUM(p.p * c.exposure)) OVER (), 1)       AS share_of_expected_loss_pct
FROM `sahyadri_b2b.rr_customers` AS c
JOIN `sahyadri_b2b.rr_probabilities` AS p ON p.applied_at = c.snapshot_date AND p.band = c.band
WHERE c.snapshot_date = DATE '2026-09-30'
GROUP BY c.band
ORDER BY c.band;
