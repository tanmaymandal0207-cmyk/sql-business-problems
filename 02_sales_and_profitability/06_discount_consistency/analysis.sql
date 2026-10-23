/* =============================================================================
   Case study · Discount consistency and price leakage
   Category : Sales and profitability
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Salespeople set discounts order by order. The commercial director believes
   discounts follow volume: bigger customers get bigger discounts. If that is
   not true, large customers may be under-rewarded (a churn risk) and some
   customers may be discounted well beyond their peers (price leakage). The
   director wants to know:
     1. Do bigger customers actually get bigger discounts, or is something
        else driving the discount?
     2. Within the real driver, which customers sit outside the normal band,
        and what is the excess worth?
     3. Which salespeople grant the out-of-band discounts?
     4. Which large customers are not being rewarded for their volume?

   KEY RULES
     - Window: last 12 months, 1 Oct 2025 - 30 Sep 2026.
     - Orders not Cancelled or Returned; NULL discount = 0 %.
     - Gross value = quantity * unit_price (before discount).
     - Effective discount = discount amount / gross value, per customer.
     - Volume tier by 12-month gross value:
         1. Under ₹2 lakh   2. ₹2-10 lakh   3. ₹10-50 lakh   4. ₹50 lakh and above
     - Customers with fewer than min_lines order lines are not banded
       (too few transactions to judge).
     - Peer group: customer segment (Step 2 shows that segment, not volume,
       drives discount). Benchmark = median effective discount of banded
       customers in the segment.
     - Band: benchmark +/- band_width (2 percentage points).
         Above band -> "Over-discounted"; excess = (rate - (benchmark + band))
                       * gross value, the discount given beyond the band.
         Below band -> "Under-discounted" (pays more than peers).
     - Primary salesperson: the salesperson with the most gross value for the
       customer in the window.
   ============================================================================= */

DECLARE window_start DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end   DATE    DEFAULT DATE '2026-09-30';
DECLARE band_width   FLOAT64 DEFAULT 0.02;
DECLARE min_lines    INT64   DEFAULT 5;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per customer: volume, effective discount, tier and band
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_discount_band` AS
WITH lines AS (
    SELECT
        o.customer_id,
        o.employee_id,
        i.quantity * i.unit_price                                       AS gross_value,
        i.quantity * i.unit_price * IFNULL(i.discount_percent, 0) / 100 AS discount_amount
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.sales_orders`      AS o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
      AND o.order_date BETWEEN window_start AND window_end
),
customer_totals AS (
    SELECT
        l.customer_id,
        c.customer_name,
        c.customer_segment,
        COUNT(*)                                        AS order_lines,
        SUM(l.gross_value)                              AS gross_value,
        SUM(l.discount_amount)                          AS discount_amount,
        SUM(l.discount_amount) / SUM(l.gross_value)     AS effective_discount
    FROM lines AS l
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = l.customer_id
    GROUP BY l.customer_id, c.customer_name, c.customer_segment
),
primary_rep AS (
    SELECT customer_id, employee_id
    FROM (
        SELECT
            customer_id, employee_id,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY SUM(gross_value) DESC, employee_id) AS rn
        FROM lines
        WHERE employee_id IS NOT NULL
        GROUP BY customer_id, employee_id
    )
    WHERE rn = 1
),
benchmarks AS (
    SELECT DISTINCT
        customer_segment,
        PERCENTILE_CONT(effective_discount, 0.5) OVER (PARTITION BY customer_segment) AS segment_benchmark
    FROM customer_totals
    WHERE order_lines >= min_lines
)
SELECT
    t.customer_id,
    t.customer_name,
    t.customer_segment,
    p.employee_id                                      AS primary_employee_id,
    t.order_lines,
    ROUND(t.gross_value, 2)                            AS gross_value,
    ROUND(t.discount_amount, 2)                        AS discount_amount,
    ROUND(t.effective_discount, 4)                     AS effective_discount,
    CASE
        WHEN t.gross_value <  200000  THEN '1. Under 2 lakh'
        WHEN t.gross_value < 1000000  THEN '2. 2-10 lakh'
        WHEN t.gross_value < 5000000  THEN '3. 10-50 lakh'
        ELSE                               '4. 50 lakh and above'
    END                                                AS volume_tier,
    ROUND(b.segment_benchmark, 4)                      AS segment_benchmark,
    CASE
        WHEN t.order_lines < min_lines                                 THEN 'Not banded (too few lines)'
        WHEN t.effective_discount > b.segment_benchmark + band_width   THEN 'Over-discounted'
        WHEN t.effective_discount < b.segment_benchmark - band_width   THEN 'Under-discounted'
        ELSE 'Within band'
    END                                                AS band_status,
    ROUND(IF(t.order_lines >= min_lines AND t.effective_discount > b.segment_benchmark + band_width,
             (t.effective_discount - b.segment_benchmark - band_width) * t.gross_value, 0), 2) AS excess_discount
FROM customer_totals          AS t
JOIN benchmarks               AS b ON b.customer_segment = t.customer_segment
LEFT JOIN primary_rep         AS p ON p.customer_id = t.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · What drives discount: volume or segment?
-- -----------------------------------------------------------------------------
-- 2a. Correlation of discount with log volume, overall and within each segment
SELECT
    IFNULL(customer_segment, 'All customers')                        AS customer_segment,
    COUNT(*)                                                         AS banded_customers,
    ROUND(CORR(LN(gross_value), effective_discount), 2)              AS corr_volume_vs_discount,
    ROUND(100 * SUM(discount_amount) / SUM(gross_value), 2)          AS weighted_discount_pct
FROM `sahyadri_b2b.customer_discount_band`
WHERE band_status <> 'Not banded (too few lines)'
GROUP BY ROLLUP(customer_segment)
ORDER BY customer_segment IS NULL DESC, weighted_discount_pct DESC;

-- 2b. Weighted discount % by segment (rows) and volume tier (columns)
SELECT
    customer_segment,
    ROUND(100 * SAFE_DIVIDE(SUM(IF(volume_tier LIKE '1.%', discount_amount, 0)), SUM(IF(volume_tier LIKE '1.%', gross_value, 0))), 1) AS under_2_lakh,
    ROUND(100 * SAFE_DIVIDE(SUM(IF(volume_tier LIKE '2.%', discount_amount, 0)), SUM(IF(volume_tier LIKE '2.%', gross_value, 0))), 1) AS lakh_2_to_10,
    ROUND(100 * SAFE_DIVIDE(SUM(IF(volume_tier LIKE '3.%', discount_amount, 0)), SUM(IF(volume_tier LIKE '3.%', gross_value, 0))), 1) AS lakh_10_to_50,
    ROUND(100 * SAFE_DIVIDE(SUM(IF(volume_tier LIKE '4.%', discount_amount, 0)), SUM(IF(volume_tier LIKE '4.%', gross_value, 0))), 1) AS lakh_50_plus,
    ROUND(100 * SUM(discount_amount) / SUM(gross_value), 1)          AS all_tiers
FROM `sahyadri_b2b.customer_discount_band`
GROUP BY customer_segment
ORDER BY all_tiers DESC;

-- -----------------------------------------------------------------------------
-- Step 3 · Band status within each segment
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    ROUND(100 * ANY_VALUE(segment_benchmark), 2)   AS segment_median_pct,
    COUNTIF(band_status = 'Within band')            AS within_band,
    COUNTIF(band_status = 'Over-discounted')        AS over_discounted,
    COUNTIF(band_status = 'Under-discounted')       AS under_discounted,
    COUNTIF(band_status = 'Not banded (too few lines)') AS not_banded,
    ROUND(SUM(excess_discount), 2)                  AS excess_discount
FROM `sahyadri_b2b.customer_discount_band`
GROUP BY customer_segment
ORDER BY excess_discount DESC;

-- Total excess discount (price leakage) and its share of all discount given
SELECT
    COUNTIF(band_status = 'Over-discounted')                         AS over_discounted_customers,
    COUNTIF(band_status = 'Under-discounted')                        AS under_discounted_customers,
    ROUND(SUM(excess_discount), 2)                                   AS excess_discount,
    ROUND(SUM(discount_amount), 2)                                   AS total_discount,
    ROUND(100 * SUM(excess_discount) / SUM(discount_amount), 1)      AS excess_pct_of_discount
FROM `sahyadri_b2b.customer_discount_band`;

-- -----------------------------------------------------------------------------
-- Step 4 · Who grants out-of-band discounts? By primary salesperson
-- -----------------------------------------------------------------------------
SELECT
    IFNULL(e.employee_name, 'No salesperson recorded')               AS salesperson,
    e.designation,
    COUNTIF(d.band_status <> 'Not banded (too few lines)')            AS banded_customers,
    COUNTIF(d.band_status = 'Over-discounted')                        AS over_discounted,
    COUNTIF(d.band_status = 'Under-discounted')                       AS under_discounted,
    ROUND(100 * COUNTIF(d.band_status = 'Over-discounted')
          / NULLIF(COUNTIF(d.band_status <> 'Not banded (too few lines)'), 0), 1) AS pct_over_discounted,
    ROUND(SUM(d.excess_discount), 2)                                  AS excess_discount
FROM `sahyadri_b2b.customer_discount_band` AS d
LEFT JOIN `sahyadri_b2b.employees`         AS e ON e.employee_id = d.primary_employee_id
WHERE d.band_status <> 'Not banded (too few lines)'
GROUP BY salesperson, e.designation
ORDER BY excess_discount DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Review lists
-- -----------------------------------------------------------------------------
-- 5a. The 10 largest over-discounted customers by excess discount
SELECT customer_id, customer_name, customer_segment, volume_tier,
       gross_value, ROUND(100 * effective_discount, 2) AS discount_pct,
       ROUND(100 * segment_benchmark, 2) AS segment_median_pct, excess_discount
FROM `sahyadri_b2b.customer_discount_band`
WHERE band_status = 'Over-discounted'
ORDER BY excess_discount DESC
LIMIT 10;

-- 5b. Volume not rewarded: ₹10 lakh+ customers discounted at or below their segment median
SELECT customer_id, customer_name, customer_segment, volume_tier,
       gross_value, ROUND(100 * effective_discount, 2) AS discount_pct,
       ROUND(100 * segment_benchmark, 2) AS segment_median_pct
FROM `sahyadri_b2b.customer_discount_band`
WHERE volume_tier IN ('3. 10-50 lakh', '4. 50 lakh and above')
  AND band_status <> 'Not banded (too few lines)'
  AND effective_discount <= segment_benchmark
ORDER BY gross_value DESC
LIMIT 10;
