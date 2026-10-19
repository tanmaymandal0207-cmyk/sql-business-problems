/* =============================================================================
   Case study · Customer payment behaviour and credit terms
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The company offers the same informal credit to every customer. Finance
   wants to set credit terms by customer group and identify accounts whose
   payment behaviour has become a risk. The questions:
     1. How quickly does each customer segment actually pay after delivery?
     2. How much cash is tied up in receivables because of that, by segment?
     3. Which customers pay much more slowly than their segment peers?
     4. Is payment speed improving or getting worse year by year?

   KEY RULES
     - Population: Delivered orders that are fully paid (payment_status = Paid)
       and have a delivery date. Unpaid balances are covered separately in
       the order-to-cash reconciliation case study.
     - Days to pay = date of the final payment - final delivery date.
       Negative values mean the customer paid before delivery (advance).
     - Order value: SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)).
     - Average cash tied up = SUM(order value x days to pay) / days in period:
       the average receivable balance these orders created over the period.
     - Customer payment tier (customers with at least 5 paid orders), by the
       customer's median days to pay:
         Prompt <= 30 · Standard 31-60 · Slow 61-90 · Very slow > 90
     - Slower than peers: customer median > 1.5 x the segment median.
   ============================================================================= */

DECLARE period_start DATE  DEFAULT DATE '2024-01-01';
DECLARE period_end   DATE  DEFAULT DATE '2026-09-30';
DECLARE min_orders   INT64 DEFAULT 5;

-- -----------------------------------------------------------------------------
-- Step 1 · Paid-order table: one row per fully paid delivered order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.paid_order_timing` AS
WITH order_value AS (
    SELECT order_id,
           SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
),
final_delivery AS (
    SELECT order_id, MAX(delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
final_payment AS (
    SELECT order_id, MAX(payment_date) AS final_payment_date, COUNT(*) AS payments
    FROM `sahyadri_b2b.payments`
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    c.customer_segment,
    EXTRACT(YEAR FROM d.final_delivery_date)                          AS delivery_year,
    v.order_value,
    d.final_delivery_date,
    p.final_payment_date,
    p.payments,
    DATE_DIFF(p.final_payment_date, d.final_delivery_date, DAY)       AS days_to_pay
FROM `sahyadri_b2b.sales_orders` AS o
JOIN `sahyadri_b2b.customers`    AS c ON c.customer_id = o.customer_id
JOIN order_value                 AS v ON v.order_id    = o.order_id
JOIN final_delivery              AS d ON d.order_id    = o.order_id
JOIN final_payment               AS p ON p.order_id    = o.order_id
WHERE o.order_status   = 'Delivered'
  AND o.payment_status = 'Paid'
  AND d.final_delivery_date IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Step 2 · Payment profile and cash tied up, by segment
-- -----------------------------------------------------------------------------
WITH segment_stats AS (
    SELECT DISTINCT
        customer_segment,
        PERCENTILE_CONT(days_to_pay, 0.5) OVER (PARTITION BY customer_segment) AS median_days,
        PERCENTILE_CONT(days_to_pay, 0.9) OVER (PARTITION BY customer_segment) AS p90_days
    FROM `sahyadri_b2b.paid_order_timing`
)
SELECT
    t.customer_segment,
    COUNT(*)                                                            AS paid_orders,
    ANY_VALUE(s.median_days)                                            AS median_days_to_pay,
    ANY_VALUE(s.p90_days)                                               AS p90_days_to_pay,
    ROUND(100 * COUNTIF(t.days_to_pay <= 30) / COUNT(*), 1)             AS pct_paid_within_30,
    ROUND(100 * COUNTIF(t.days_to_pay > 60)  / COUNT(*), 1)             AS pct_paid_after_60,
    ROUND(100 * COUNTIF(t.payments > 1)      / COUNT(*), 1)             AS pct_paid_in_instalments,
    ROUND(SUM(t.order_value * t.days_to_pay)
          / (DATE_DIFF(period_end, period_start, DAY) + 1), 2)          AS avg_cash_tied_up
FROM `sahyadri_b2b.paid_order_timing` AS t
JOIN segment_stats                    AS s
    ON s.customer_segment = t.customer_segment
GROUP BY t.customer_segment
ORDER BY median_days_to_pay;

-- -----------------------------------------------------------------------------
-- Step 3 · Customer payment tiers by segment
-- -----------------------------------------------------------------------------
WITH customer_medians AS (
    SELECT DISTINCT
        customer_id,
        customer_segment,
        COUNT(*) OVER (PARTITION BY customer_id)                         AS paid_orders,
        PERCENTILE_CONT(days_to_pay, 0.5) OVER (PARTITION BY customer_id) AS median_days
    FROM `sahyadri_b2b.paid_order_timing`
)
SELECT
    customer_segment,
    COUNTIF(median_days <= 30)                         AS prompt_customers,
    COUNTIF(median_days > 30 AND median_days <= 60)    AS standard_customers,
    COUNTIF(median_days > 60 AND median_days <= 90)    AS slow_customers,
    COUNTIF(median_days > 90)                          AS very_slow_customers,
    COUNT(*)                                           AS customers
FROM customer_medians
WHERE paid_orders >= min_orders
GROUP BY customer_segment
ORDER BY customer_segment;

-- -----------------------------------------------------------------------------
-- Step 4 · Customers paying much more slowly than their segment peers
-- -----------------------------------------------------------------------------
WITH customer_medians AS (
    SELECT DISTINCT
        customer_id,
        customer_segment,
        COUNT(*) OVER (PARTITION BY customer_id)                          AS paid_orders,
        SUM(order_value) OVER (PARTITION BY customer_id)                  AS paid_value,
        PERCENTILE_CONT(days_to_pay, 0.5) OVER (PARTITION BY customer_id) AS median_days
    FROM `sahyadri_b2b.paid_order_timing`
),
segment_medians AS (
    SELECT DISTINCT
        customer_segment,
        PERCENTILE_CONT(days_to_pay, 0.5) OVER (PARTITION BY customer_segment) AS segment_median_days
    FROM `sahyadri_b2b.paid_order_timing`
)
SELECT
    m.customer_id,
    cu.customer_name,
    m.customer_segment,
    m.paid_orders,
    ROUND(m.paid_value, 2)                                   AS paid_value,
    m.median_days                                            AS customer_median_days,
    s.segment_median_days,
    ROUND(m.median_days / s.segment_median_days, 2)          AS times_segment_median
FROM customer_medians          AS m
JOIN segment_medians           AS s  ON s.customer_segment = m.customer_segment
JOIN `sahyadri_b2b.customers`  AS cu ON cu.customer_id     = m.customer_id
WHERE m.paid_orders >= min_orders
  AND m.median_days > 1.5 * s.segment_median_days
ORDER BY m.paid_value DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Trend: median days to pay by delivery year and segment
-- -----------------------------------------------------------------------------
SELECT DISTINCT
    customer_segment,
    delivery_year,
    COUNT(*) OVER (PARTITION BY customer_segment, delivery_year)              AS paid_orders,
    PERCENTILE_CONT(days_to_pay, 0.5) OVER (PARTITION BY customer_segment, delivery_year)
                                                                              AS median_days_to_pay
FROM `sahyadri_b2b.paid_order_timing`
ORDER BY customer_segment, delivery_year;

-- -----------------------------------------------------------------------------
-- Step 6 · Scenario: cash released if every order were paid within proposed
--          segment terms (orders already paid faster are unchanged)
--          Proposed terms: SMB 15 · Distributor 30 · Mid-Market 45 · Enterprise 60 days
-- -----------------------------------------------------------------------------
WITH with_terms AS (
    SELECT
        *,
        CASE customer_segment
            WHEN 'SMB'         THEN 15
            WHEN 'Distributor' THEN 30
            WHEN 'Mid-Market'  THEN 45
            WHEN 'Enterprise'  THEN 60
        END AS proposed_terms_days
    FROM `sahyadri_b2b.paid_order_timing`
)
SELECT
    customer_segment,
    ANY_VALUE(proposed_terms_days)                                        AS proposed_terms_days,
    ROUND(100 * COUNTIF(days_to_pay > proposed_terms_days) / COUNT(*), 1) AS pct_orders_beyond_terms,
    ROUND(SUM(order_value * days_to_pay)
          / (DATE_DIFF(period_end, period_start, DAY) + 1), 2)            AS avg_cash_tied_up_actual,
    ROUND(SUM(order_value * LEAST(days_to_pay, proposed_terms_days))
          / (DATE_DIFF(period_end, period_start, DAY) + 1), 2)            AS avg_cash_tied_up_at_terms,
    ROUND(SUM(order_value * (days_to_pay - LEAST(days_to_pay, proposed_terms_days)))
          / (DATE_DIFF(period_end, period_start, DAY) + 1), 2)            AS cash_released
FROM with_terms
GROUP BY customer_segment
ORDER BY cash_released DESC;
