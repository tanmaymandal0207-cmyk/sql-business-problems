/* =============================================================================
   Case study · RFM customer segmentation
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Sales and marketing treat all 426 active customers the same: the same
   visits, the same offers. The commercial director wants customers grouped by
   behaviour so each group gets a different plan (retain, grow, win back or
   serve at low cost). The standard tool for this is RFM:
     Recency   - how recently did the customer order?
     Frequency - how often do they order?
     Monetary  - how much do they spend?
   Questions:
     1. How many customers, and how much revenue, fall in each RFM segment?
     2. How do RFM segments line up with the existing customer segments
        (Enterprise, Distributor, Mid-Market, SMB)?
     3. Which high-value customers are slipping away ("Cannot lose")?

   KEY RULES
     - As-of date 30 Sep 2026. Lookback window: 12 months (1 Oct 2025 - 30 Sep 2026).
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
     - Population: customers with at least one in-scope order at any time.
     - R = days since last order (all time). F = orders in the last 12 months.
       M = revenue in the last 12 months.
     - Each of R, F and M is scored 1-5 with NTILE(5) (5 = best: most recent,
       most frequent, highest spend). Customers with no orders in the window
       get F = 1 and M = 1.
     - Segments (first matching rule wins):
         Champions            R >= 4, F >= 4, M >= 4
         Cannot lose          R <= 2, M >= 4
         Loyal                R >= 3, F >= 4
         At risk              R <= 2, F >= 3
         Potential loyalists  R >= 4, F >= 2
         New or returning     R >= 4, F = 1
         Hibernating          R <= 2
         Need attention       everything else
   ============================================================================= */

DECLARE as_of_date   DATE DEFAULT DATE '2026-09-30';
DECLARE window_start DATE DEFAULT DATE '2025-10-01';

-- -----------------------------------------------------------------------------
-- Step 1 · RFM table: one row per customer
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_rfm` AS
WITH order_value AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.customer_id, o.order_id, o.order_date
),
rfm_values AS (
    SELECT
        customer_id,
        DATE_DIFF(as_of_date, MAX(order_date), DAY)                       AS recency_days,
        COUNTIF(order_date >= window_start)                               AS frequency_12m,
        SUM(IF(order_date >= window_start, order_revenue, 0))             AS monetary_12m
    FROM order_value
    GROUP BY customer_id
),
scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC, customer_id)           AS r_score,
        IF(frequency_12m = 0, 1,
           NTILE(5) OVER (ORDER BY frequency_12m ASC, customer_id))       AS f_score,
        IF(monetary_12m = 0, 1,
           NTILE(5) OVER (ORDER BY monetary_12m ASC, customer_id))        AS m_score
    FROM rfm_values
)
SELECT
    s.customer_id,
    c.customer_name,
    c.customer_segment,
    s.recency_days,
    s.frequency_12m,
    ROUND(s.monetary_12m, 2)                                              AS monetary_12m,
    s.r_score,
    s.f_score,
    s.m_score,
    CONCAT(CAST(s.r_score AS STRING), CAST(s.f_score AS STRING), CAST(s.m_score AS STRING)) AS rfm_code,
    CASE
        WHEN s.r_score >= 4 AND s.f_score >= 4 AND s.m_score >= 4 THEN '1. Champions'
        WHEN s.r_score <= 2 AND s.m_score >= 4                     THEN '2. Cannot lose'
        WHEN s.r_score >= 3 AND s.f_score >= 4                     THEN '3. Loyal'
        WHEN s.r_score <= 2 AND s.f_score >= 3                     THEN '4. At risk'
        WHEN s.r_score >= 4 AND s.f_score >= 2                     THEN '5. Potential loyalists'
        WHEN s.r_score >= 4 AND s.f_score = 1                      THEN '6. New or returning'
        WHEN s.r_score <= 2                                        THEN '7. Hibernating'
        ELSE                                                            '8. Need attention'
    END                                                                   AS rfm_segment
FROM scored                   AS s
JOIN `sahyadri_b2b.customers` AS c
    ON c.customer_id = s.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · RFM segment summary
-- -----------------------------------------------------------------------------
SELECT
    rfm_segment,
    COUNT(*)                                                             AS customers,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                     AS pct_of_customers,
    ROUND(SUM(monetary_12m), 2)                                          AS revenue_12m,
    ROUND(100 * SUM(monetary_12m) / SUM(SUM(monetary_12m)) OVER (), 1)   AS pct_of_revenue_12m,
    ROUND(AVG(recency_days), 0)                                          AS avg_recency_days,
    ROUND(AVG(frequency_12m), 1)                                         AS avg_orders_12m
FROM `sahyadri_b2b.customer_rfm`
GROUP BY rfm_segment
ORDER BY rfm_segment;

-- -----------------------------------------------------------------------------
-- Step 3 · RFM segments by customer segment (customers)
-- -----------------------------------------------------------------------------
SELECT
    rfm_segment,
    COUNTIF(customer_segment = 'Enterprise')  AS enterprise,
    COUNTIF(customer_segment = 'Distributor') AS distributor,
    COUNTIF(customer_segment = 'Mid-Market')  AS mid_market,
    COUNTIF(customer_segment = 'SMB')         AS smb,
    COUNT(*)                                  AS total
FROM `sahyadri_b2b.customer_rfm`
GROUP BY rfm_segment
ORDER BY rfm_segment;

-- -----------------------------------------------------------------------------
-- Step 4 · "Cannot lose" and "At risk" customers, by 12-month revenue
-- -----------------------------------------------------------------------------
SELECT
    rfm_segment,
    customer_id,
    customer_name,
    customer_segment,
    recency_days,
    frequency_12m,
    monetary_12m,
    rfm_code
FROM `sahyadri_b2b.customer_rfm`
WHERE rfm_segment IN ('2. Cannot lose', '4. At risk')
ORDER BY monetary_12m DESC
LIMIT 15;
