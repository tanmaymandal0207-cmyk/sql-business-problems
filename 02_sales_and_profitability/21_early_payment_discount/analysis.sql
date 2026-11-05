/* =============================================================================
   Case study · Early-payment discount: would "2/10 net 60" pay for itself?
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The working-capital review proposes a 2 % discount for invoices paid
   within 10 days of delivery ("2/10 net 60"). The CFO likes the idea of
   cash arriving sooner but worries about paying 2 % to customers who
   already pay fast. Before the offer goes into the new terms she asks:
     1. How much would the discount cost on orders that are already paid
        within 10 days?
     2. For a slower order that switches to paying in 10 days, when does
        the financing saved outweigh the 2 %?
     3. What share of slower orders would have to switch for the offer to
        break even, by segment?
     4. Would a smaller discount, or one aimed at particular segments, work
        better?

   METHOD
     - Valid, fully delivered orders delivered 1 Oct 2024 - 30 Sep 2025,
       so every order has had at least a year to be paid by 30 Sep 2026.
       Days to pay = delivery to the day payments reach 99 % of value
       (paid before delivery = 0). Orders not settled by then are treated
       as bad debts that a discount would not recover.
     - Cost of money 12 % a year (as in the cost-to-serve studies).
     - Windfall: discount on orders already paid within the window.
     - A switcher pays at day 10 instead of its actual day d: financing
       saved = value x (d - 10) x 12 % / 365; net gain = saved - discount.
       It pays for itself only if d > 10 + discount x 365 / 12 %.
     - Break-even uptake: the share of slower settled orders that must
       switch (chosen at random) for total net gains to cover the windfall.
     - Terms compared: 1/10, 2/10 and 0.5/10, company-wide and by segment.
   ============================================================================= */

DECLARE delivered_from DATE    DEFAULT DATE '2024-10-01';
DECLARE delivered_to   DATE    DEFAULT DATE '2025-09-30';
DECLARE as_of          DATE    DEFAULT DATE '2026-09-30';
DECLARE cost_of_money  FLOAT64 DEFAULT 0.12;
DECLARE window_days    INT64   DEFAULT 10;
DECLARE settled_share  FLOAT64 DEFAULT 0.99;

-- -----------------------------------------------------------------------------
-- Step 1 · Orders with their days to pay
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ep_orders` AS
WITH value AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items` GROUP BY order_id
),
delivered AS (
    SELECT order_id, MAX(delivery_date) AS delivered_on
    FROM `sahyadri_b2b.shipments` GROUP BY order_id
    HAVING COUNT(delivery_date) = COUNT(*)
),
running AS (
    SELECT order_id, payment_date,
           SUM(amount) OVER (PARTITION BY order_id ORDER BY payment_date, payment_id) AS paid_so_far
    FROM `sahyadri_b2b.payments` WHERE payment_date <= as_of
),
base AS (
    SELECT o.order_id, o.customer_id, c.customer_segment, v.order_value, d.delivered_on
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN value AS v ON v.order_id = o.order_id
    JOIN delivered AS d ON d.order_id = o.order_id
    JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND d.delivered_on BETWEEN delivered_from AND delivered_to
),
settled AS (
    SELECT b.order_id, MIN(r.payment_date) AS settled_on
    FROM base AS b JOIN running AS r ON r.order_id = b.order_id
    WHERE r.paid_so_far >= settled_share * b.order_value
    GROUP BY b.order_id
)
SELECT b.*, s.settled_on, s.settled_on IS NOT NULL AS settled,
       IF(s.settled_on IS NOT NULL, GREATEST(DATE_DIFF(s.settled_on, b.delivered_on, DAY), 0), NULL) AS days_to_pay
FROM base AS b LEFT JOIN settled AS s ON s.order_id = b.order_id;

SELECT
    customer_segment,
    COUNT(*)                                                                          AS orders,
    ROUND(SUM(order_value) / 1e7, 2)                                                  AS value_crore,
    ROUND(100 * SUM(IF(settled AND days_to_pay <= window_days, order_value, 0)) / SUM(order_value), 1) AS value_paid_within_10_days_pct,
    ROUND(100 * SUM(IF(settled AND days_to_pay > window_days, order_value, 0)) / SUM(order_value), 1)  AS value_paid_later_pct,
    ROUND(100 * SUM(IF(NOT settled, order_value, 0)) / SUM(order_value), 1)            AS value_not_settled_pct,
    APPROX_QUANTILES(IF(settled, days_to_pay, NULL), 2)[OFFSET(1)]                    AS median_days_to_pay
FROM `sahyadri_b2b.ep_orders`
GROUP BY ROLLUP(customer_segment)
ORDER BY customer_segment;

-- -----------------------------------------------------------------------------
-- Step 2 · Cost and gain of each term, order by order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ep_terms` AS
WITH terms AS (
    SELECT 0.005 AS discount UNION ALL SELECT 0.01 UNION ALL SELECT 0.02
)
SELECT
    o.*, t.discount,
    -- days after which a switch pays for itself
    window_days + t.discount * 365 / cost_of_money                                    AS break_even_day,
    IF(o.settled AND o.days_to_pay <= window_days, t.discount * o.order_value, 0)     AS windfall,
    IF(o.settled AND o.days_to_pay > window_days,
       o.order_value * (o.days_to_pay - window_days) * cost_of_money / 365, 0)        AS financing_saved_if_switch,
    IF(o.settled AND o.days_to_pay > window_days, t.discount * o.order_value, 0)      AS discount_if_switch
FROM `sahyadri_b2b.ep_orders` AS o
CROSS JOIN terms AS t;

-- -----------------------------------------------------------------------------
-- Step 3 · Company-wide and by segment: windfall, gains and break-even uptake
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ep_summary` AS
SELECT
    IFNULL(customer_segment, 'All segments')                                          AS segment,
    discount,
    ANY_VALUE(break_even_day)                                                         AS break_even_day,
    SUM(windfall)                                                                     AS windfall,
    SUM(financing_saved_if_switch)                                                    AS saved_if_all_switch,
    SUM(discount_if_switch)                                                           AS discount_if_all_switch,
    SUM(financing_saved_if_switch - discount_if_switch)                               AS net_if_all_switch,
    SUM(IF(financing_saved_if_switch > discount_if_switch, financing_saved_if_switch - discount_if_switch, 0)) AS net_if_only_paying_switchers,
    SUM(IF(settled AND days_to_pay > window_days, order_value * (days_to_pay - window_days), 0)) / 365 AS receivable_released_if_all_switch
FROM `sahyadri_b2b.ep_terms`
GROUP BY ROLLUP(customer_segment), discount
HAVING discount IS NOT NULL;

SELECT
    segment,
    CONCAT(CAST(discount * 100 AS STRING), '/10 net 60')                              AS terms,
    ROUND(break_even_day, 0)                                                          AS switch_pays_after_day,
    ROUND(windfall / 1e5, 1)                                                          AS windfall_lakh,
    ROUND(net_if_all_switch / 1e5, 1)                                                 AS net_gain_if_every_slower_order_switches_lakh,
    ROUND((net_if_all_switch - windfall) / 1e5, 1)                                    AS result_if_all_switch_lakh,
    IF(net_if_all_switch > 0, ROUND(100 * windfall / net_if_all_switch, 1), NULL)     AS break_even_uptake_pct,
    ROUND((net_if_only_paying_switchers - windfall) / 1e5, 1)                         AS result_if_only_slow_payers_switch_lakh,
    ROUND(receivable_released_if_all_switch / 1e5, 1)                                 AS receivable_released_lakh
FROM `sahyadri_b2b.ep_summary`
ORDER BY CASE segment WHEN 'All segments' THEN 0 ELSE 1 END, segment, discount;

-- -----------------------------------------------------------------------------
-- Step 4 · Who the discount would reach: speed of payment by value
-- -----------------------------------------------------------------------------
SELECT
    CASE WHEN NOT settled THEN '6. Not settled after a year'
         WHEN days_to_pay <= 10 THEN '1. 0-10 days'
         WHEN days_to_pay <= 30 THEN '2. 11-30 days'
         WHEN days_to_pay <= 60 THEN '3. 31-60 days'
         WHEN days_to_pay <= 71 THEN '4. 61-71 days'
         ELSE '5. 72+ days' END                                                       AS days_to_pay_band,
    COUNT(*)                                                                          AS orders,
    ROUND(SUM(order_value) / 1e5, 1)                                                  AS value_lakh,
    ROUND(100 * SUM(order_value) / SUM(SUM(order_value)) OVER (), 1)                  AS value_share_pct
FROM `sahyadri_b2b.ep_orders`
GROUP BY days_to_pay_band
ORDER BY days_to_pay_band;

-- The implied interest rate a customer earns by taking each discount instead of paying at its usual day
SELECT
    customer_segment,
    APPROX_QUANTILES(IF(settled, days_to_pay, NULL), 2)[OFFSET(1)]                    AS median_days_to_pay,
    ROUND(100 * 0.01 / 0.99 * 365 / GREATEST(APPROX_QUANTILES(IF(settled, days_to_pay, NULL), 2)[OFFSET(1)] - window_days, 1), 1) AS implied_rate_1pct_discount,
    ROUND(100 * 0.02 / 0.98 * 365 / GREATEST(APPROX_QUANTILES(IF(settled, days_to_pay, NULL), 2)[OFFSET(1)] - window_days, 1), 1) AS implied_rate_2pct_discount
FROM `sahyadri_b2b.ep_orders`
GROUP BY customer_segment
ORDER BY customer_segment;
