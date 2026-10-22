/* =============================================================================
   Case study · Customer profitability and the whale curve
   Category : Advanced analytics
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Customers are ranked by revenue, but revenue is not profit. Some customers
   buy at deep discounts, order often in small amounts, need costly freight,
   take sales time and pay slowly. Management accountants use a "whale curve"
   to show this: cumulative profit by customer, ranked from most to least
   profitable. The curve rises above 100 % and then falls back, because the
   least profitable customers give back part of the profit the best ones earn.
   The CFO wants to know:
     1. After product cost, freight, order handling, sales effort and the cost
        of credit, which customers make money and which lose it?
     2. How high does the whale curve peak, and how much profit do loss-making
        customers give away?
     3. Which costs make the loss-making customers unprofitable?
     4. How does profitability differ by segment?

   KEY RULES
     - Window: last 12 months, 1 Oct 2025 - 30 Sep 2026, by order date.
     - Revenue and product cost: orders not Cancelled or Returned; NULL
       discount = 0 %; product cost = quantity * unit_cost (NULL cost = 0).
     - Freight: shipping_cost on all shipments of orders in the window,
       including returned orders (NULL cost = 0).
     - Order handling: Operations and Supply Chain & Logistics salaries for
       the window (prorated for joiners), divided equally across every order
       placed in the window, including cancelled and returned orders.
     - Sales effort: each salesperson's salary for the window (prorated for
       joiners), divided across the orders that salesperson booked. The Head
       of Sales is management overhead and is not allocated; orders booked by
       the Head of Sales or with no salesperson carry no sales cost.
     - Cost of credit: for delivered orders, each payment is financed from
       final delivery to payment date, and any unpaid balance to the as-of
       date, at cost_of_capital a year.
     - Contribution = gross profit - freight - handling - sales effort - credit.
   ============================================================================= */

DECLARE window_start    DATE    DEFAULT DATE '2025-10-01';
DECLARE window_end      DATE    DEFAULT DATE '2026-09-30';
DECLARE cost_of_capital FLOAT64 DEFAULT 0.12;

-- -----------------------------------------------------------------------------
-- Step 1 · One row per customer: activity-based customer P&L
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_profitability` AS
WITH window_orders AS (
    SELECT order_id, customer_id, employee_id, order_status
    FROM `sahyadri_b2b.sales_orders`
    WHERE order_date BETWEEN window_start AND window_end
),
-- salary cost for the window, prorated for anyone who joined during it
salary_in_window AS (
    SELECT
        e.employee_id,
        e.designation,
        d.department_name,
        e.salary * (DATE_DIFF(window_end, GREATEST(e.hire_date, window_start), DAY) + 1)
                 / (DATE_DIFF(window_end, window_start, DAY) + 1)      AS window_salary
    FROM `sahyadri_b2b.employees`   AS e
    JOIN `sahyadri_b2b.departments` AS d ON d.department_id = e.department_id
    WHERE e.hire_date <= window_end
),
handling_rate AS (
    SELECT
        (SELECT SUM(window_salary) FROM salary_in_window
          WHERE department_name IN ('Operations', 'Supply Chain & Logistics'))
        / (SELECT COUNT(*) FROM window_orders)                        AS cost_per_order
),
sales_rate AS (
    SELECT w.employee_id, s.window_salary / COUNT(*) AS cost_per_order
    FROM window_orders    AS w
    JOIN salary_in_window AS s ON s.employee_id = w.employee_id
    WHERE s.designation <> 'Head of Sales'          -- management overhead, not order effort
    GROUP BY w.employee_id, s.window_salary
),
line_values AS (
    SELECT
        i.order_id,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue,
        SUM(i.quantity * IFNULL(p.unit_cost, 0))                                   AS product_cost
    FROM `sahyadri_b2b.sales_order_items` AS i
    JOIN `sahyadri_b2b.products`          AS p ON p.product_id = i.product_id
    GROUP BY i.order_id
),
freight AS (
    SELECT order_id, SUM(IFNULL(shipping_cost, 0)) AS freight, MAX(delivery_date) AS final_delivery_date
    FROM `sahyadri_b2b.shipments`
    GROUP BY order_id
),
credit AS (
    -- rupee-days financed: payments from delivery to payment, unpaid balance to as-of
    SELECT
        w.order_id,
        SUM(GREATEST(DATE_DIFF(p.payment_date, f.final_delivery_date, DAY), 0) * p.amount) AS paid_rupee_days,
        SUM(p.amount)                                                                       AS amount_paid
    FROM window_orders AS w
    JOIN freight       AS f ON f.order_id = w.order_id
    JOIN `sahyadri_b2b.payments` AS p ON p.order_id = w.order_id
    WHERE w.order_status = 'Delivered' AND f.final_delivery_date IS NOT NULL
    GROUP BY w.order_id
),
order_pnl AS (
    SELECT
        w.order_id,
        w.customer_id,
        IF(w.order_status NOT IN ('Cancelled', 'Returned'), v.revenue,      0) AS revenue,
        IF(w.order_status NOT IN ('Cancelled', 'Returned'), v.product_cost, 0) AS product_cost,
        IFNULL(f.freight, 0)                                                   AS freight,
        h.cost_per_order                                                       AS handling_cost,
        IFNULL(s.cost_per_order, 0)                                            AS sales_cost,
        IF(w.order_status = 'Delivered' AND f.final_delivery_date IS NOT NULL,
           (IFNULL(c.paid_rupee_days, 0)
            + GREATEST(v.revenue - IFNULL(c.amount_paid, 0), 0)
              * DATE_DIFF(window_end, f.final_delivery_date, DAY))
           * cost_of_capital / 365, 0)                                         AS credit_cost
    FROM window_orders   AS w
    JOIN line_values     AS v ON v.order_id = w.order_id
    CROSS JOIN handling_rate AS h
    LEFT JOIN freight    AS f ON f.order_id    = w.order_id
    LEFT JOIN sales_rate AS s ON s.employee_id = w.employee_id
    LEFT JOIN credit     AS c ON c.order_id    = w.order_id
),
customer_pnl AS (
    SELECT
        customer_id,
        COUNT(*)                         AS orders_placed,
        SUM(revenue)                     AS revenue,
        SUM(revenue - product_cost)      AS gross_profit,
        SUM(freight)                     AS freight,
        SUM(handling_cost)               AS handling_cost,
        SUM(sales_cost)                  AS sales_cost,
        SUM(credit_cost)                 AS credit_cost
    FROM order_pnl
    GROUP BY customer_id
),
with_contribution AS (
    SELECT
        *,
        gross_profit - freight - handling_cost - sales_cost - credit_cost AS contribution
    FROM customer_pnl
)
SELECT
    w.customer_id,
    c.customer_name,
    c.customer_segment,
    w.orders_placed,
    ROUND(w.revenue, 2)                                  AS revenue,
    ROUND(w.gross_profit, 2)                             AS gross_profit,
    ROUND(w.freight, 2)                                  AS freight,
    ROUND(w.handling_cost, 2)                            AS handling_cost,
    ROUND(w.sales_cost, 2)                               AS sales_cost,
    ROUND(w.credit_cost, 2)                              AS credit_cost,
    ROUND(w.contribution, 2)                             AS contribution,
    ROUND(SAFE_DIVIDE(w.contribution, w.revenue), 4)     AS contribution_margin,
    ROW_NUMBER() OVER (ORDER BY w.contribution DESC, w.customer_id) AS profit_rank,
    ROUND(SUM(w.contribution) OVER (ORDER BY w.contribution DESC, w.customer_id
                                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(w.contribution) OVER (), 4)              AS cumulative_share_of_profit,
    CASE
        WHEN w.revenue      = 0     THEN 'No revenue (cancelled or returned only)'
        WHEN w.contribution < 0     THEN 'Loss-making'
        ELSE 'Profitable'
    END                                                  AS profitability
FROM with_contribution        AS w
JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = w.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Company P&L from revenue to contribution
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                    AS customers,
    ROUND(SUM(revenue), 2)                                      AS revenue,
    ROUND(SUM(gross_profit), 2)                                 AS gross_profit,
    ROUND(SUM(freight), 2)                                      AS freight,
    ROUND(SUM(handling_cost), 2)                                AS handling_cost,
    ROUND(SUM(sales_cost), 2)                                   AS sales_cost,
    ROUND(SUM(credit_cost), 2)                                  AS credit_cost,
    ROUND(SUM(contribution), 2)                                 AS contribution,
    ROUND(100 * SUM(contribution) / SUM(revenue), 1)            AS contribution_margin_pct
FROM `sahyadri_b2b.customer_profitability`;

-- -----------------------------------------------------------------------------
-- Step 3 · The whale curve: cumulative profit by customer decile
-- -----------------------------------------------------------------------------
WITH deciles AS (
    SELECT *, NTILE(10) OVER (ORDER BY profit_rank) AS decile
    FROM `sahyadri_b2b.customer_profitability`
)
SELECT
    decile,
    COUNT(*)                                                       AS customers,
    ROUND(SUM(revenue), 2)                                         AS revenue,
    ROUND(SUM(contribution), 2)                                    AS contribution,
    ROUND(100 * MAX(cumulative_share_of_profit), 1)                AS cumulative_profit_pct_at_end,
    COUNTIF(profitability = 'Loss-making')                         AS loss_making_customers
FROM deciles
GROUP BY decile
ORDER BY decile;

-- Peak of the curve and the profit given back
SELECT
    COUNTIF(contribution >= 0)                                     AS profitable_customers,
    COUNTIF(contribution <  0)                                     AS loss_making_customers,
    ROUND(100 * MAX(cumulative_share_of_profit), 1)                AS whale_curve_peak_pct,
    ROUND(SUM(IF(contribution >= 0, contribution, 0)), 2)          AS profit_from_profitable,
    ROUND(SUM(IF(contribution <  0, contribution, 0)), 2)          AS profit_given_back,
    ROUND(SUM(IF(contribution <  0, revenue, 0)), 2)               AS revenue_of_loss_makers
FROM `sahyadri_b2b.customer_profitability`;

-- -----------------------------------------------------------------------------
-- Step 4 · Why loss-making customers lose money: cost per ₹100 of revenue
-- -----------------------------------------------------------------------------
SELECT
    profitability,
    COUNT(*)                                                      AS customers,
    ROUND(AVG(orders_placed), 1)                                  AS avg_orders,
    ROUND(SUM(revenue) / SUM(orders_placed), 0)                   AS revenue_per_order,
    ROUND(100 * SUM(gross_profit)  / NULLIF(SUM(revenue), 0), 1)  AS gross_margin_pct,
    ROUND(100 * SUM(freight)       / NULLIF(SUM(revenue), 0), 1)  AS freight_pct,
    ROUND(100 * SUM(handling_cost) / NULLIF(SUM(revenue), 0), 1)  AS handling_pct,
    ROUND(100 * SUM(sales_cost)    / NULLIF(SUM(revenue), 0), 1)  AS sales_pct,
    ROUND(100 * SUM(credit_cost)   / NULLIF(SUM(revenue), 0), 1)  AS credit_pct,
    ROUND(100 * SUM(contribution)  / NULLIF(SUM(revenue), 0), 1)  AS contribution_pct
FROM `sahyadri_b2b.customer_profitability`
GROUP BY profitability
ORDER BY profitability;

-- The 10 largest loss-makers and their largest cost driver
SELECT
    customer_id,
    customer_name,
    customer_segment,
    orders_placed,
    revenue,
    gross_profit,
    contribution,
    CASE GREATEST(freight, handling_cost, sales_cost, credit_cost)
        WHEN handling_cost THEN 'Order handling'
        WHEN sales_cost    THEN 'Sales effort'
        WHEN credit_cost   THEN 'Cost of credit'
        ELSE 'Freight'
    END                                                           AS largest_cost_to_serve
FROM `sahyadri_b2b.customer_profitability`
WHERE profitability = 'Loss-making'
ORDER BY contribution
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Step 5 · Profitability by segment
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                                     AS customers,
    COUNTIF(profitability = 'Loss-making')                       AS loss_making,
    ROUND(SUM(revenue), 2)                                       AS revenue,
    ROUND(SUM(contribution), 2)                                  AS contribution,
    ROUND(100 * SUM(contribution) / NULLIF(SUM(revenue), 0), 1)  AS contribution_margin_pct,
    ROUND(100 * SUM(contribution) / SUM(SUM(contribution)) OVER (), 1) AS pct_of_total_contribution
FROM `sahyadri_b2b.customer_profitability`
GROUP BY customer_segment
ORDER BY contribution DESC;
