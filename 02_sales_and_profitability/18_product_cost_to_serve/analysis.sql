/* =============================================================================
   Case study · Product profitability after cost to serve
   Category : Sales and profitability
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The SKU review ranks products on gross profit. The finance controller
   points out that gross profit ignores what it costs to sell, pick, ship
   and collect each line: a ₹300 fastener on its own order line takes as
   much handling as a ₹3 lakh pump. Before the next range review she asks:
     1. What is each product's contribution after freight, order handling,
        sales effort, the cost of waiting for payment and credit losses?
     2. How many products lose money once those costs are charged, and how
        much do they give back?
     3. What makes a product lose money: low margin, small lines, or
        something else?
     4. How different is the ranking from the gross-profit ranking?

   METHOD
     - Lines of valid orders (not Cancelled or Returned) placed in the
       financial year April 2025 - March 2026 (so 180-day payment outcomes
       are known by September 2026). Products without a unit cost are
       excluded and listed.
     - Costs charged to each line (activity-based, as in the customer whale
       curve):
         Freight        order's shipping cost, split by line value
         Handling       Operations and Supply Chain salaries for the year /
                        all orders placed; per order, split equally by line
         Sales effort   each salesperson's salary for the year / orders they
                        booked; per order, split equally by line (Head of
                        Sales not charged)
         Cost of credit line value x days from final delivery to payment
                        (or 30 Sep 2026 if unpaid) x 12 % a year
         Credit loss    the order's balance unpaid 180 days after the order
                        date, split by line value
     - Contribution = gross profit - all five. Operating contribution
       leaves out the credit loss, which follows the customer rather than
       the product. A product whale curve sorts products by contribution
       and accumulates it in rupees.
   ============================================================================= */

DECLARE fy_start       DATE    DEFAULT DATE '2025-04-01';
DECLARE fy_end         DATE    DEFAULT DATE '2026-03-31';
DECLARE as_of          DATE    DEFAULT DATE '2026-09-30';
DECLARE cost_of_money  FLOAT64 DEFAULT 0.12;
DECLARE loss_days      INT64   DEFAULT 180;

-- -----------------------------------------------------------------------------
-- Step 1 · Rates for handling and sales effort
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pc_rates` AS
WITH staff AS (
    SELECT employee_id, department_id, designation, IFNULL(salary, 0) AS salary,
           -- share of the financial year the person was employed
           GREATEST(DATE_DIFF(fy_end, GREATEST(hire_date, fy_start), DAY) + 1, 0) / (DATE_DIFF(fy_end, fy_start, DAY) + 1) AS year_share
    FROM `sahyadri_b2b.employees`
),
orders_fy AS (
    SELECT order_id, employee_id FROM `sahyadri_b2b.sales_orders` WHERE order_date BETWEEN fy_start AND fy_end
)
SELECT 'Handling per order' AS rate,
       NULL AS employee_id,
       (SELECT SUM(salary * year_share) FROM staff WHERE department_id IN (4, 5)) / (SELECT COUNT(*) FROM orders_fy) AS per_order
UNION ALL
SELECT 'Sales effort per order', s.employee_id,
       s.salary * s.year_share / COUNT(o.order_id)
FROM staff AS s
JOIN orders_fy AS o ON o.employee_id = s.employee_id
WHERE s.department_id = 1 AND s.designation != 'Head of Sales'
GROUP BY s.employee_id, s.salary, s.year_share;

-- -----------------------------------------------------------------------------
-- Step 2 · Every line with its revenue, gross profit and five costs
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.pc_lines` AS
WITH lines AS (
    SELECT o.order_id, o.order_date, o.customer_id, o.employee_id, i.order_item_id, i.product_id, p.unit_cost, i.quantity,
           i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100) AS revenue
    FROM `sahyadri_b2b.sales_orders` AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    JOIN `sahyadri_b2b.products` AS p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned') AND o.order_date BETWEEN fy_start AND fy_end
),
order_totals AS (
    SELECT order_id, order_date, SUM(revenue) AS order_revenue, COUNT(*) AS order_lines FROM lines GROUP BY order_id, order_date
),
freight AS (
    SELECT order_id, SUM(IFNULL(shipping_cost, 0)) AS freight,
           IF(COUNT(delivery_date) = COUNT(*), MAX(delivery_date), NULL) AS final_delivery_date
    FROM `sahyadri_b2b.shipments` GROUP BY order_id
),
paid AS (
    -- rupee-days outstanding on what was paid within the loss window; the rest is lost at day loss_days
    SELECT p.order_id,
           SUM(IF(DATE_DIFF(p.payment_date, o.order_date, DAY) <= loss_days, p.amount, 0))   AS paid_in_window,
           SUM(IF(DATE_DIFF(p.payment_date, o.order_date, DAY) <= loss_days,
                  p.amount * GREATEST(DATE_DIFF(p.payment_date, IFNULL(f.final_delivery_date, o.order_date), DAY), 0), 0)) AS paid_rupee_days
    FROM `sahyadri_b2b.payments` AS p
    JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
    LEFT JOIN freight AS f ON f.order_id = p.order_id
    GROUP BY p.order_id
),
orders AS (
    SELECT
        t.order_id, t.order_revenue, t.order_lines,
        IFNULL(f.freight, 0)                                                          AS order_freight,
        GREATEST(t.order_revenue - IFNULL(pd.paid_in_window, 0), 0)                   AS order_loss,
        IFNULL(pd.paid_rupee_days, 0)
          + GREATEST(t.order_revenue - IFNULL(pd.paid_in_window, 0), 0)
            * GREATEST(DATE_DIFF(DATE_ADD(t.order_date, INTERVAL loss_days DAY), IFNULL(f.final_delivery_date, t.order_date), DAY), 0) AS order_rupee_days
    FROM order_totals AS t
    LEFT JOIN freight AS f ON f.order_id = t.order_id
    LEFT JOIN paid AS pd ON pd.order_id = t.order_id
)
SELECT
    l.order_id, l.order_date, l.customer_id, l.employee_id, l.order_item_id, l.product_id, l.unit_cost, l.quantity, l.revenue,
    l.revenue / o.order_revenue                                                       AS value_share,
    l.quantity * l.unit_cost                                                          AS cogs,
    l.revenue - l.quantity * l.unit_cost                                              AS gross_profit,
    o.order_freight * l.revenue / o.order_revenue                                     AS freight_cost,
    h.per_order / o.order_lines                                                       AS handling_cost,
    IFNULL(se.per_order, 0) / o.order_lines                                           AS sales_effort_cost,
    o.order_rupee_days * l.revenue / o.order_revenue * cost_of_money / 365            AS credit_cost,
    o.order_loss * l.revenue / o.order_revenue                                        AS credit_loss
FROM lines AS l
JOIN orders AS o ON o.order_id = l.order_id
CROSS JOIN (SELECT per_order FROM `sahyadri_b2b.pc_rates` WHERE rate = 'Handling per order') AS h
LEFT JOIN (SELECT employee_id, per_order FROM `sahyadri_b2b.pc_rates` WHERE rate = 'Sales effort per order') AS se
  ON se.employee_id = l.employee_id;

CREATE OR REPLACE TABLE `sahyadri_b2b.pc_products` AS
SELECT
    l.product_id, p.product_name, pc.category_name,
    COUNT(*)                                   AS lines,
    SUM(l.revenue)                             AS revenue,
    SUM(l.gross_profit)                        AS gross_profit,
    SUM(l.freight_cost)                        AS freight_cost,
    SUM(l.handling_cost)                       AS handling_cost,
    SUM(l.sales_effort_cost)                   AS sales_effort_cost,
    SUM(l.credit_cost)                         AS credit_cost,
    SUM(l.credit_loss)                         AS credit_loss,
    SUM(l.gross_profit - l.freight_cost - l.handling_cost - l.sales_effort_cost - l.credit_cost)                 AS operating_contribution,
    SUM(l.gross_profit - l.freight_cost - l.handling_cost - l.sales_effort_cost - l.credit_cost - l.credit_loss) AS contribution
FROM `sahyadri_b2b.pc_lines` AS l
JOIN `sahyadri_b2b.products` AS p ON p.product_id = l.product_id
JOIN `sahyadri_b2b.product_categories` AS pc ON pc.category_id = p.category_id
WHERE l.unit_cost IS NOT NULL
GROUP BY l.product_id, p.product_name, pc.category_name;

-- -----------------------------------------------------------------------------
-- Step 3 · From gross profit to contribution
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                                         AS products,
    ROUND(SUM(revenue) / 1e7, 2)                                                     AS revenue_crore,
    ROUND(SUM(gross_profit) / 1e5, 1)                                                AS gross_profit_lakh,
    ROUND(SUM(freight_cost) / 1e5, 1)                                                AS freight_lakh,
    ROUND(SUM(handling_cost) / 1e5, 1)                                               AS handling_lakh,
    ROUND(SUM(sales_effort_cost) / 1e5, 1)                                           AS sales_effort_lakh,
    ROUND(SUM(credit_cost) / 1e5, 1)                                                 AS credit_cost_lakh,
    ROUND(SUM(operating_contribution) / 1e5, 1)                                      AS operating_contribution_lakh,
    ROUND(SUM(credit_loss) / 1e5, 1)                                                 AS credit_loss_lakh,
    ROUND(SUM(contribution) / 1e5, 1)                                                AS contribution_lakh,
    ROUND(100 * SUM(gross_profit) / SUM(revenue), 1)                                 AS gp_margin_pct,
    ROUND(100 * SUM(operating_contribution) / SUM(revenue), 1)                       AS operating_margin_pct,
    ROUND(100 * SUM(contribution) / SUM(revenue), 1)                                 AS contribution_margin_pct,
    COUNTIF(gross_profit < 0)                                                        AS losing_on_gp,
    COUNTIF(operating_contribution < 0)                                              AS losing_before_credit_loss,
    COUNTIF(contribution < 0)                                                        AS losing_after_all_costs
FROM `sahyadri_b2b.pc_products`;

-- Products excluded for want of a unit cost
SELECT l.product_id, p.product_name, COUNT(*) AS lines, ROUND(SUM(l.revenue) / 1e5, 2) AS revenue_lakh
FROM `sahyadri_b2b.pc_lines` AS l JOIN `sahyadri_b2b.products` AS p ON p.product_id = l.product_id
WHERE l.unit_cost IS NULL
GROUP BY l.product_id, p.product_name
ORDER BY revenue_lakh DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · The product whale curve (operating contribution and full contribution)
-- -----------------------------------------------------------------------------
WITH ranked AS (
    SELECT 'Operating contribution' AS measure, product_id, operating_contribution AS c FROM `sahyadri_b2b.pc_products`
    UNION ALL
    SELECT 'Contribution after credit loss', product_id, contribution FROM `sahyadri_b2b.pc_products`
),
curve AS (
    SELECT measure, c,
           ROW_NUMBER() OVER (PARTITION BY measure ORDER BY c DESC, product_id)              AS rk,
           COUNT(*) OVER (PARTITION BY measure)                                              AS n,
           SUM(c) OVER (PARTITION BY measure ORDER BY c DESC, product_id
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)                   AS cum_c
    FROM ranked
)
SELECT
    measure,
    ROUND(MAX(IF(rk = CEIL(0.1 * n), cum_c, NULL)) / 1e5, 1)                         AS top_10pct_products_lakh,
    ROUND(MAX(IF(rk = CEIL(0.2 * n), cum_c, NULL)) / 1e5, 1)                         AS top_20pct_products_lakh,
    COUNTIF(c >= 0)                                                                  AS profitable_products,
    ROUND(MAX(cum_c) / 1e5, 1)                                                       AS peak_lakh,
    ROUND(SUM(IF(c < 0, c, 0)) / 1e5, 1)                                             AS given_back_lakh,
    ROUND(SUM(c) / 1e5, 1)                                                           AS total_lakh,
    ROUND(100 * MAX(cum_c) / SUM(c), 1)                                              AS peak_pct_of_total
FROM curve
GROUP BY measure
ORDER BY measure DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · What makes a product lose money?
-- -----------------------------------------------------------------------------
-- (a) Line size: every line, banded by its value
SELECT
    CASE WHEN revenue < 5000 THEN '1. Under Rs 5k' WHEN revenue < 20000 THEN '2. Rs 5-20k'
         WHEN revenue < 50000 THEN '3. Rs 20-50k' WHEN revenue < 200000 THEN '4. Rs 50k-2 lakh' ELSE '5. Rs 2 lakh+' END AS line_value,
    COUNT(*)                                                                         AS lines,
    ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)                         AS revenue_share_pct,
    ROUND(100 * SUM(gross_profit) / SUM(revenue), 1)                                 AS gp_margin_pct,
    ROUND(100 * SUM(handling_cost + sales_effort_cost) / SUM(revenue), 1)            AS order_costs_pct,
    ROUND(100 * SUM(freight_cost + credit_cost) / SUM(revenue), 1)                   AS freight_and_credit_pct,
    ROUND(100 * SUM(gross_profit - freight_cost - handling_cost - sales_effort_cost - credit_cost) / SUM(revenue), 1) AS operating_margin_pct,
    ROUND(100 * SUM(credit_loss) / SUM(revenue), 1)                                  AS credit_loss_pct
FROM `sahyadri_b2b.pc_lines`
WHERE unit_cost IS NOT NULL
GROUP BY line_value
ORDER BY line_value;

-- (b) Loss-making against profitable products (operating contribution)
SELECT
    IF(operating_contribution < 0, 'Loss-making', 'Profitable')                      AS products_group,
    COUNT(*)                                                                         AS products,
    ROUND(SUM(revenue) / SUM(lines))                                                 AS revenue_per_line,
    ROUND(100 * SUM(gross_profit) / SUM(revenue), 1)                                 AS gp_margin_pct,
    ROUND(100 * SUM(handling_cost + sales_effort_cost) / SUM(revenue), 1)            AS order_costs_pct,
    ROUND(100 * SUM(freight_cost) / SUM(revenue), 1)                                 AS freight_pct,
    ROUND(100 * SUM(credit_cost) / SUM(revenue), 1)                                  AS credit_cost_pct,
    ROUND(100 * SUM(operating_contribution) / SUM(revenue), 1)                       AS operating_margin_pct,
    ROUND(100 * SUM(credit_loss) / SUM(revenue), 1)                                  AS credit_loss_pct
FROM `sahyadri_b2b.pc_products`
GROUP BY products_group
ORDER BY products_group DESC;

-- (c) Margin and line size together
SELECT
    CASE WHEN gross_profit / revenue < 0.10 THEN '1. Under 10 %' WHEN gross_profit / revenue < 0.15 THEN '2. 10-15 %' ELSE '3. 15 %+' END AS gp_margin,
    IF(revenue / lines < 20000, '1. Under Rs 20k', '2. Rs 20k+')                     AS revenue_per_line,
    COUNT(*)                                                                         AS products,
    COUNTIF(operating_contribution < 0)                                              AS loss_making,
    ROUND(SUM(operating_contribution) / 1e5, 1)                                      AS operating_contribution_lakh
FROM `sahyadri_b2b.pc_products`
GROUP BY gp_margin, revenue_per_line
ORDER BY gp_margin, revenue_per_line;

-- (d) Which measures are a property of the product? Same product, first and second half of the year
WITH halves AS (
    SELECT product_id,
           IF(order_date < DATE_ADD(fy_start, INTERVAL 6 MONTH), 'H1', 'H2')         AS half,
           SUM(gross_profit) / SUM(revenue)                                          AS gp_margin,
           SUM(gross_profit - freight_cost - handling_cost - sales_effort_cost - credit_cost) / SUM(revenue) AS operating_margin,
           SUM(credit_loss) / SUM(revenue)                                           AS credit_loss_rate
    FROM `sahyadri_b2b.pc_lines`
    WHERE unit_cost IS NOT NULL
    GROUP BY product_id, half
)
SELECT
    COUNT(*)                                                                         AS products_in_both_halves,
    ROUND(CORR(a.gp_margin, b.gp_margin), 3)                                         AS corr_gp_margin,
    ROUND(CORR(a.operating_margin, b.operating_margin), 3)                           AS corr_operating_margin,
    ROUND(CORR(a.credit_loss_rate, b.credit_loss_rate), 3)                           AS corr_credit_loss_rate
FROM halves AS a
JOIN halves AS b ON b.product_id = a.product_id AND a.half = 'H1' AND b.half = 'H2';

-- (e) Products sold below cost
SELECT p.product_name, ROUND(p.unit_cost, 2) AS unit_cost, ROUND(p.selling_price, 2) AS list_price,
       COUNT(*) AS lines, COUNTIF(l.revenue < l.cogs) AS lines_below_cost, ROUND(SUM(l.gross_profit) / 1e3, 1) AS gp_k
FROM `sahyadri_b2b.pc_lines` AS l
JOIN `sahyadri_b2b.products` AS p ON p.product_id = l.product_id
WHERE l.product_id IN (SELECT product_id FROM `sahyadri_b2b.pc_products` WHERE gross_profit < 0)
GROUP BY p.product_name, p.unit_cost, p.selling_price
ORDER BY gp_k;

-- (f) Categories
SELECT
    category_name,
    COUNT(*)                                                                         AS products,
    ROUND(SUM(revenue) / 1e5, 1)                                                     AS revenue_lakh,
    ROUND(SUM(revenue) / SUM(lines))                                                 AS revenue_per_line,
    ROUND(100 * SUM(gross_profit) / SUM(revenue), 1)                                 AS gp_margin_pct,
    ROUND(100 * SUM(operating_contribution) / SUM(revenue), 1)                       AS operating_margin_pct,
    ROUND(100 * SUM(contribution) / SUM(revenue), 1)                                 AS contribution_margin_pct,
    COUNTIF(operating_contribution < 0)                                              AS loss_making_operating,
    ROUND(SUM(operating_contribution) / 1e5, 1)                                      AS operating_contribution_lakh
FROM `sahyadri_b2b.pc_products`
GROUP BY category_name
ORDER BY operating_margin_pct DESC;

-- -----------------------------------------------------------------------------
-- Step 6 · How different is the ranking from gross profit?
-- -----------------------------------------------------------------------------
WITH r AS (
    SELECT product_id, gross_profit, operating_contribution,
           RANK() OVER (ORDER BY gross_profit DESC)           AS gp_rank,
           RANK() OVER (ORDER BY operating_contribution DESC) AS oc_rank,
           COUNT(*) OVER ()                                   AS n
    FROM `sahyadri_b2b.pc_products`
)
SELECT
    ROUND(CORR(gp_rank, oc_rank), 3)                                                 AS rank_correlation,
    COUNTIF(gross_profit > 0 AND operating_contribution < 0)                         AS profitable_on_gp_but_losing,
    COUNTIF(gp_rank <= CEIL(0.2 * n))                                                AS top_20pct_on_gp,
    COUNTIF(gp_rank <= CEIL(0.2 * n) AND oc_rank <= CEIL(0.2 * n))                   AS still_top_20pct,
    COUNTIF(ABS(gp_rank - oc_rank) >= 20)                                            AS moved_20_places_or_more
FROM r;

-- The biggest loss-makers on operating contribution, and their largest cost
SELECT
    product_name, category_name, lines, ROUND(revenue / lines) AS revenue_per_line,
    ROUND(100 * gross_profit / revenue, 1)                                           AS gp_margin_pct,
    ROUND(gross_profit / 1e3, 1)                                                     AS gp_k,
    ROUND((handling_cost + sales_effort_cost) / 1e3, 1)                              AS order_costs_k,
    ROUND(freight_cost / 1e3, 1)                                                     AS freight_k,
    ROUND(credit_cost / 1e3, 1)                                                      AS credit_cost_k,
    ROUND(operating_contribution / 1e3, 1)                                           AS operating_contribution_k,
    ROUND(credit_loss / 1e3, 1)                                                      AS credit_loss_k
FROM `sahyadri_b2b.pc_products`
ORDER BY operating_contribution
LIMIT 8;
