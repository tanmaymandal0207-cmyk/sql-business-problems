/* =============================================================================
   Case study · A quarterly volume rebate: what it would cost at today's
   volumes, how much extra volume it must buy, and how easily it is gamed
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The sales head proposes a quarterly volume rebate, open to every
   customer, to win more volume from the larger accounts. A customer whose
   purchases in a calendar quarter reach Rs 10 lakh earns 1 % back on the
   whole quarter, Rs 20 lakh earns 2 % and Rs 40 lakh earns 3 %
   ("retroactive" tiers). Before agreeing, the CFO asks:
     1. What would the scheme have cost on the volumes customers already
        bought, and how much of the gross profit is that?
     2. How much extra volume must it bring in just to pay for itself?
     3. How easily can customers earn it by moving orders between quarters
        rather than buying more?
     4. Is there a cheaper design that rewards the same customers?

   METHOD AND ASSUMPTIONS
     - Invoices: valid orders (not Cancelled or Returned) with a shipment;
       invoice date = first shipment date; purchases = order value after
       discount; cost = quantity x product unit cost. Invoices dated
       1 January 2024 - 30 September 2026: 11 calendar quarters.
     - Gross profit = purchases - cost (freight and other costs to serve
       are not deducted).
     - Retroactive rebate = purchases x the rate of the highest tier
       reached in the quarter.
     - Incremental rebate (alternative) = 1 % of purchases above Rs 10
       lakh + 1 % above Rs 20 lakh + 1 % above Rs 40 lakh: the same
       marginal rates, paid only on the amount above each threshold.
     - Break-even extra purchases for a customer-quarter = rebate /
       (gross margin - rebate rate): the extra sales whose gross profit,
       after the rebate on them, pays back the rebate.
     - Timing tests: (a) pull forward the next month's invoices into the
       quarter; (b) place a half-year's purchases in one of its quarters.
     - Annual alternative: the same tiers x 4 over a financial year
       (April - March), 2024-25 and 2025-26.
   ============================================================================= */

DECLARE first_invoice DATE DEFAULT DATE '2024-01-01';
DECLARE last_invoice  DATE DEFAULT DATE '2026-09-30';
DECLARE years_covered FLOAT64 DEFAULT 2.75;

-- -----------------------------------------------------------------------------
-- Step 1 · Tiers, invoices and the rebate for every customer-quarter
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.qr_tiers` AS
SELECT 1 AS tier, 1000000 AS threshold, 0.01 AS rate, 0.01 AS step UNION ALL
SELECT 2,          2000000,             0.02,         0.01         UNION ALL
SELECT 3,          4000000,             0.03,         0.01;

CREATE OR REPLACE TABLE `sahyadri_b2b.qr_invoices` AS
WITH lines AS (
    SELECT o.order_id, o.customer_id,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS purchases,
           SUM(i.quantity * p.unit_cost)                                              AS cost
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.order_id, o.customer_id
),
dated AS (
    SELECT l.order_id, l.customer_id, l.purchases, l.cost, MIN(s.shipment_date) AS invoice_date
    FROM lines AS l JOIN `sahyadri_b2b.shipments` AS s ON s.order_id = l.order_id
    GROUP BY l.order_id, l.customer_id, l.purchases, l.cost
)
SELECT d.*,
       DATE_TRUNC(d.invoice_date, QUARTER)                                            AS quarter_start,
       DATE_TRUNC(d.invoice_date, MONTH)                                              AS invoice_month
FROM dated AS d
WHERE d.invoice_date BETWEEN first_invoice AND last_invoice;

CREATE OR REPLACE TABLE `sahyadri_b2b.qr_quarters` AS
WITH cq AS (
    SELECT customer_id, quarter_start, COUNT(*) AS invoices, SUM(purchases) AS purchases, SUM(cost) AS cost
    FROM `sahyadri_b2b.qr_invoices`
    GROUP BY customer_id, quarter_start
),
next_month AS (
    SELECT customer_id, invoice_month, SUM(purchases) AS purchases
    FROM `sahyadri_b2b.qr_invoices`
    GROUP BY customer_id, invoice_month
),
base AS (
    SELECT cq.*,
           -- invoices of the first month of the next quarter (none after September 2026)
           IF(cq.quarter_start < DATE '2026-07-01', IFNULL(nm.purchases, 0), NULL)    AS next_month_purchases
    FROM cq
    LEFT JOIN next_month AS nm
      ON nm.customer_id = cq.customer_id AND nm.invoice_month = DATE_ADD(cq.quarter_start, INTERVAL 3 MONTH)
),
tiered AS (
    SELECT b.customer_id, b.quarter_start,
           IFNULL(MAX(IF(t.threshold <= b.purchases, t.rate, NULL)), 0)               AS rate,
           IFNULL(SUM(t.step * GREATEST(0, b.purchases - t.threshold)), 0)            AS incremental_rebate,
           MIN(IF(t.threshold > b.purchases, t.threshold, NULL))                      AS next_threshold,
           IFNULL(MAX(IF(t.threshold <= b.purchases + IFNULL(b.next_month_purchases, 0), t.rate, NULL)), 0) AS rate_if_pulled_forward
    FROM base AS b CROSS JOIN `sahyadri_b2b.qr_tiers` AS t
    GROUP BY b.customer_id, b.quarter_start
)
SELECT b.*, c.customer_name, c.customer_segment,
       b.purchases - b.cost                                                           AS gross_profit,
       t.rate,
       b.purchases * t.rate                                                           AS retroactive_rebate,
       t.incremental_rebate,
       t.next_threshold,
       t.next_threshold - b.purchases                                                 AS gap_to_next_threshold,
       t.rate_if_pulled_forward,
       EXTRACT(YEAR FROM DATE_SUB(b.quarter_start, INTERVAL 3 MONTH))                 AS financial_year
FROM base AS b
JOIN tiered AS t USING (customer_id, quarter_start)
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = b.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · What the scheme would have cost on the volumes already bought
-- -----------------------------------------------------------------------------
SELECT
    rate                                                                              AS tier_rate,
    COUNT(*)                                                                          AS customer_quarters,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(SUM(purchases) / 1e7, 2)                                                    AS purchases_crore,
    ROUND(100 * SUM(gross_profit) / SUM(purchases), 1)                                AS gross_margin_pct,
    ROUND(SUM(retroactive_rebate) / 1e5, 2)                                           AS retroactive_rebate_lakh,
    ROUND(100 * SUM(retroactive_rebate) / SUM(gross_profit), 1)                       AS rebate_share_of_their_gross_profit_pct
FROM `sahyadri_b2b.qr_quarters`
GROUP BY rate
ORDER BY rate;

SELECT
    COUNT(*)                                                                          AS customer_quarters,
    COUNTIF(rate > 0)                                                                 AS customer_quarters_earning,
    ROUND(SUM(purchases) / 1e7, 2)                                                    AS purchases_crore,
    ROUND(100 * SUM(IF(rate > 0, purchases, 0)) / SUM(purchases), 1)                  AS share_of_purchases_earning_pct,
    ROUND(SUM(gross_profit) / 1e5, 1)                                                 AS gross_profit_lakh,
    ROUND(SUM(retroactive_rebate) / 1e5, 2)                                           AS retroactive_rebate_lakh,
    ROUND(SUM(retroactive_rebate) / years_covered / 1e5, 2)                           AS retroactive_rebate_per_year_lakh,
    ROUND(100 * SUM(retroactive_rebate) / SUM(gross_profit), 1)                       AS rebate_share_of_all_gross_profit_pct
FROM `sahyadri_b2b.qr_quarters`;

SELECT
    customer_segment,
    COUNTIF(rate > 0)                                                                 AS customer_quarters_earning,
    COUNT(DISTINCT IF(rate > 0, customer_id, NULL))                                   AS customers_earning,
    ROUND(SUM(retroactive_rebate) / 1e5, 2)                                           AS retroactive_rebate_lakh,
    ROUND(100 * SUM(retroactive_rebate) / SUM(SUM(retroactive_rebate)) OVER (), 1)    AS share_of_rebate_pct
FROM `sahyadri_b2b.qr_quarters`
GROUP BY customer_segment
ORDER BY retroactive_rebate_lakh DESC;

SELECT
    customer_name, customer_segment,
    COUNTIF(rate > 0)                                                                 AS quarters_earning,
    ROUND(SUM(purchases) / 1e5, 1)                                                    AS purchases_lakh,
    ROUND(SUM(retroactive_rebate) / 1e5, 2)                                           AS retroactive_rebate_lakh,
    ROUND(100 * SUM(gross_profit) / SUM(purchases), 1)                                AS gross_margin_pct,
    ROUND(100 * (SUM(gross_profit) - SUM(retroactive_rebate)) / SUM(purchases), 1)    AS margin_after_rebate_pct
FROM `sahyadri_b2b.qr_quarters`
GROUP BY customer_name, customer_segment
ORDER BY retroactive_rebate_lakh DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 3 · How much extra volume the scheme must buy to pay for itself
-- -----------------------------------------------------------------------------
WITH by_tier AS (
    SELECT rate, SUM(purchases) AS purchases, SUM(gross_profit) AS gross_profit, SUM(retroactive_rebate) AS rebate,
           COUNTIF(gross_profit <= retroactive_rebate)                                AS quarters_margin_below_rebate
    FROM `sahyadri_b2b.qr_quarters`
    WHERE rate > 0
    GROUP BY rate
)
SELECT
    rate                                                                              AS tier_rate,
    ROUND(100 * gross_profit / purchases, 1)                                          AS gross_margin_pct,
    -- extra purchases, as a share of the tier's purchases, whose margin after the rebate repays it
    ROUND(100 * rate / (gross_profit / purchases - rate), 1)                          AS break_even_uplift_pct,
    ROUND(rebate / (gross_profit / purchases - rate) / 1e7, 2)                        AS break_even_extra_purchases_crore,
    quarters_margin_below_rebate
FROM by_tier
UNION ALL
SELECT
    NULL,
    ROUND(100 * SUM(gross_profit) / SUM(purchases), 1),
    ROUND(100 * SUM(rebate / (gross_profit / purchases - rate)) / SUM(purchases), 1),
    ROUND(SUM(rebate / (gross_profit / purchases - rate)) / 1e7, 2),
    SUM(quarters_margin_below_rebate)
FROM by_tier
ORDER BY tier_rate;

-- Customer-quarters that fell just short (within 15 %) of a threshold: the volume the scheme could win
SELECT
    next_threshold,
    COUNT(*)                                                                          AS customer_quarters_within_15_pct,
    COUNT(DISTINCT customer_id)                                                       AS customers,
    ROUND(SUM(gap_to_next_threshold) / 1e5, 1)                                        AS extra_purchases_to_cross_lakh,
    ROUND(SUM(next_threshold * t.rate - retroactive_rebate) / 1e5, 2)                 AS extra_rebate_if_crossed_lakh,
    ROUND(SUM(gap_to_next_threshold * gross_profit / purchases) / 1e5, 2)             AS gross_profit_on_the_extra_lakh
FROM `sahyadri_b2b.qr_quarters` AS q
JOIN `sahyadri_b2b.qr_tiers` AS t ON t.threshold = q.next_threshold
WHERE q.purchases >= 0.85 * q.next_threshold
GROUP BY next_threshold
ORDER BY next_threshold;

-- -----------------------------------------------------------------------------
-- Step 4 · How easily the rebate is earned by timing alone
-- -----------------------------------------------------------------------------
-- (a) Pull the next month's invoices into the quarter (quarters to June 2026)
SELECT
    COUNT(*)                                                                          AS customer_quarters,
    COUNTIF(rate_if_pulled_forward > rate)                                            AS reach_a_higher_tier,
    COUNT(DISTINCT IF(rate_if_pulled_forward > rate, customer_id, NULL))              AS customers,
    ROUND(SUM(IF(rate_if_pulled_forward > rate,
                 (purchases + next_month_purchases) * rate_if_pulled_forward - retroactive_rebate, 0)) / 1e5, 2) AS extra_rebate_lakh
FROM `sahyadri_b2b.qr_quarters`
WHERE next_month_purchases IS NOT NULL;

-- (b) Place each half-year's purchases in one of its two quarters (January 2024 - June 2026)
WITH halves AS (
    SELECT customer_id,
           EXTRACT(YEAR FROM quarter_start)                                           AS yr,
           CAST(FLOOR((EXTRACT(MONTH FROM quarter_start) - 1) / 6) AS INT64)          AS half,
           SUM(purchases)                                                             AS half_purchases,
           SUM(retroactive_rebate)                                                    AS actual_rebate
    FROM `sahyadri_b2b.qr_quarters`
    WHERE quarter_start < DATE '2026-07-01'
    GROUP BY customer_id, yr, half
),
concentrated AS (
    SELECT h.*, h.half_purchases * IFNULL(MAX(IF(t.threshold <= h.half_purchases, t.rate, NULL)), 0) AS concentrated_rebate
    FROM halves AS h CROSS JOIN `sahyadri_b2b.qr_tiers` AS t
    GROUP BY h.customer_id, h.yr, h.half, h.half_purchases, h.actual_rebate
)
SELECT
    COUNT(*)                                                                          AS customer_half_years,
    COUNTIF(concentrated_rebate > actual_rebate)                                      AS gain_by_concentrating,
    ROUND(SUM(actual_rebate) / 1e5, 2)                                                AS rebate_as_ordered_lakh,
    ROUND(SUM(concentrated_rebate) / 1e5, 2)                                          AS rebate_if_concentrated_lakh,
    ROUND(100 * (SUM(concentrated_rebate) / SUM(actual_rebate) - 1), 1)               AS increase_pct
FROM concentrated;

-- (c) Does a tier earned once tend to be earned again next quarter?
WITH s AS (
    SELECT customer_id, quarter_start, rate,
           LEAD(rate) OVER (PARTITION BY customer_id ORDER BY quarter_start)          AS next_rate,
           LEAD(quarter_start) OVER (PARTITION BY customer_id ORDER BY quarter_start) AS next_quarter
    FROM `sahyadri_b2b.qr_quarters`
)
SELECT
    rate                                                                              AS tier_rate,
    COUNT(*)                                                                          AS customer_quarters,
    -- a missing next quarter means no purchases at all, so no rebate
    COUNTIF(next_quarter IS NULL OR next_quarter <> DATE_ADD(quarter_start, INTERVAL 3 MONTH) OR next_rate = 0) AS next_quarter_none,
    COUNTIF(next_quarter = DATE_ADD(quarter_start, INTERVAL 3 MONTH) AND next_rate > 0 AND next_rate < rate) AS next_quarter_lower,
    COUNTIF(next_quarter = DATE_ADD(quarter_start, INTERVAL 3 MONTH) AND next_rate = rate) AS next_quarter_same,
    COUNTIF(next_quarter = DATE_ADD(quarter_start, INTERVAL 3 MONTH) AND next_rate > rate) AS next_quarter_higher
FROM s
WHERE rate > 0 AND quarter_start < DATE '2026-07-01'
GROUP BY rate
ORDER BY rate;

SELECT
    quarters_earning, COUNT(*) AS customers
FROM (
    SELECT customer_id, COUNTIF(rate > 0) AS quarters_earning
    FROM `sahyadri_b2b.qr_quarters`
    GROUP BY customer_id
)
WHERE quarters_earning > 0
GROUP BY quarters_earning
ORDER BY quarters_earning;

-- -----------------------------------------------------------------------------
-- Step 5 · Cheaper designs that reward the same customers
-- -----------------------------------------------------------------------------
WITH fy AS (
    SELECT customer_id, financial_year,
           SUM(purchases)                                                             AS fy_purchases,
           SUM(retroactive_rebate)                                                    AS quarterly_retroactive,
           SUM(incremental_rebate)                                                    AS quarterly_incremental,
           COUNTIF(rate > 0)                                                          AS quarters_earning
    FROM `sahyadri_b2b.qr_quarters`
    WHERE financial_year IN (2024, 2025)
    GROUP BY customer_id, financial_year
),
annual AS (
    SELECT f.customer_id, f.financial_year,
           f.fy_purchases * IFNULL(MAX(IF(4 * t.threshold <= f.fy_purchases, t.rate, NULL)), 0) AS annual_retroactive,
           SUM(t.step * GREATEST(0, f.fy_purchases - 4 * t.threshold))                AS annual_incremental
    FROM fy AS f CROSS JOIN `sahyadri_b2b.qr_tiers` AS t
    GROUP BY f.customer_id, f.financial_year, f.fy_purchases
)
SELECT
    CONCAT(CAST(f.financial_year AS STRING), '-', CAST(MOD(f.financial_year + 1, 100) AS STRING)) AS financial_year,
    ROUND(SUM(f.quarterly_retroactive) / 1e5, 2)                                      AS quarterly_retroactive_lakh,
    ROUND(SUM(f.quarterly_incremental) / 1e5, 2)                                      AS quarterly_incremental_lakh,
    ROUND(SUM(a.annual_retroactive) / 1e5, 2)                                         AS annual_retroactive_lakh,
    ROUND(SUM(a.annual_incremental) / 1e5, 2)                                         AS annual_incremental_lakh,
    COUNTIF(f.quarters_earning > 0)                                                   AS customers_earning_quarterly,
    COUNTIF(a.annual_retroactive > 0)                                                 AS customers_earning_annual
FROM fy AS f
JOIN annual AS a USING (customer_id, financial_year)
GROUP BY f.financial_year
ORDER BY f.financial_year;

SELECT
    ROUND(SUM(retroactive_rebate) / 1e5, 2)                                           AS retroactive_lakh,
    ROUND(SUM(incremental_rebate) / 1e5, 2)                                           AS incremental_lakh,
    ROUND(100 * SUM(incremental_rebate) / SUM(retroactive_rebate), 1)                 AS incremental_as_pct_of_retroactive
FROM `sahyadri_b2b.qr_quarters`;

-- The cliff: the jump in rebate on the rupee of purchases that crosses each threshold
SELECT
    threshold,
    rate,
    threshold * (rate - IFNULL(LAG(rate) OVER (ORDER BY threshold), 0))               AS retroactive_jump_at_threshold,
    0                                                                                 AS incremental_jump_at_threshold
FROM `sahyadri_b2b.qr_tiers`
ORDER BY threshold;
