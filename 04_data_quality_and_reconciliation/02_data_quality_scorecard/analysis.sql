/* =============================================================================
   Case study · Data quality scorecard
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The company is about to build management dashboards on its order data.
   Earlier analyses kept running into the same gaps: missing costs, missing
   freight, inconsistent city names, duplicate receipts. Before the dashboards
   go live, the data owner needs a repeatable scorecard that answers:
     1. Which data quality rules fail, on which tables, and how many records?
     2. Which failures are serious enough to distort financial reporting?
     3. Which table and which quality dimension need attention first?

   METHOD
   Each rule is one SELECT that returns the number of records checked and the
   number that fail. Rules follow the standard data quality dimensions:
     Completeness · Validity · Uniqueness · Consistency · Referential integrity
   Severity reflects business impact:
     High   – distorts revenue, margin, cash or receivables reporting
     Medium – distorts operational reporting (delivery, sales attribution)
     Low    – descriptive attributes; limits segmentation only
   Results are saved to `data_quality_results` so the scorecard can be
   re-run and compared over time.
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- Step 1 · Run every rule and save the results
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.data_quality_results` AS

-- ---------- Completeness --------------------------------------------------------
SELECT 'C01' AS rule_id, 'products' AS table_name, 'unit_cost' AS column_name,
       'Completeness' AS dimension, 'High' AS severity,
       'Every product has a unit cost' AS rule_description,
       COUNT(*) AS records_checked, COUNTIF(unit_cost IS NULL) AS records_failed
FROM `sahyadri_b2b.products`
UNION ALL
SELECT 'C02', 'sales_order_items', 'discount_percent', 'Completeness', 'High',
       'Every order line has a discount value (0 if none)',
       COUNT(*), COUNTIF(discount_percent IS NULL)
FROM `sahyadri_b2b.sales_order_items`
UNION ALL
SELECT 'C03', 'shipments', 'shipping_cost', 'Completeness', 'High',
       'Every shipment has a freight cost',
       COUNT(*), COUNTIF(shipping_cost IS NULL)
FROM `sahyadri_b2b.shipments`
UNION ALL
SELECT 'C04', 'sales_orders', 'promised_delivery_date', 'Completeness', 'Medium',
       'Every order has a promised delivery date',
       COUNT(*), COUNTIF(promised_delivery_date IS NULL)
FROM `sahyadri_b2b.sales_orders`
UNION ALL
SELECT 'C05', 'sales_orders', 'employee_id', 'Completeness', 'Medium',
       'Every order has a salesperson',
       COUNT(*), COUNTIF(employee_id IS NULL)
FROM `sahyadri_b2b.sales_orders`
UNION ALL
SELECT 'C06', 'shipments', 'delivery_date', 'Completeness', 'Medium',
       'Every shipment marked Delivered has a delivery date',
       COUNTIF(shipment_status = 'Delivered'),
       COUNTIF(shipment_status = 'Delivered' AND delivery_date IS NULL)
FROM `sahyadri_b2b.shipments`
UNION ALL
SELECT 'C07', 'payments', 'payment_method', 'Completeness', 'Low',
       'Every payment has a payment method',
       COUNT(*), COUNTIF(payment_method IS NULL)
FROM `sahyadri_b2b.payments`
UNION ALL
SELECT 'C08', 'customers', 'city', 'Completeness', 'Low',
       'Every customer has a city',
       COUNT(*), COUNTIF(city IS NULL)
FROM `sahyadri_b2b.customers`
UNION ALL
SELECT 'C09', 'customers', 'industry', 'Completeness', 'Low',
       'Every customer has an industry',
       COUNT(*), COUNTIF(industry IS NULL)
FROM `sahyadri_b2b.customers`
UNION ALL
SELECT 'C10', 'customers', 'registration_date', 'Completeness', 'Low',
       'Every customer has a registration date',
       COUNT(*), COUNTIF(registration_date IS NULL)
FROM `sahyadri_b2b.customers`
UNION ALL
SELECT 'C11', 'employees', 'salary', 'Completeness', 'Low',
       'Every employee has a salary',
       COUNT(*), COUNTIF(salary IS NULL)
FROM `sahyadri_b2b.employees`

-- ---------- Validity ------------------------------------------------------------
UNION ALL
SELECT 'V01', 'products', 'selling_price', 'Validity', 'High',
       'List price is not below unit cost',
       COUNTIF(unit_cost IS NOT NULL), COUNTIF(selling_price < unit_cost)
FROM `sahyadri_b2b.products`
UNION ALL
SELECT 'V02', 'sales_order_items', 'quantity', 'Validity', 'High',
       'Quantity is greater than zero',
       COUNT(*), COUNTIF(quantity <= 0)
FROM `sahyadri_b2b.sales_order_items`
UNION ALL
SELECT 'V03', 'sales_order_items', 'discount_percent', 'Validity', 'High',
       'Discount is between 0 and 100 %',
       COUNTIF(discount_percent IS NOT NULL),
       COUNTIF(discount_percent < 0 OR discount_percent > 100)
FROM `sahyadri_b2b.sales_order_items`
UNION ALL
SELECT 'V04', 'payments', 'amount', 'Validity', 'High',
       'Payment amount is greater than zero',
       COUNT(*), COUNTIF(amount <= 0)
FROM `sahyadri_b2b.payments`
UNION ALL
SELECT 'V05', 'shipments', 'delivery_date', 'Validity', 'Medium',
       'Delivery date is not before shipment date',
       COUNTIF(delivery_date IS NOT NULL), COUNTIF(delivery_date < shipment_date)
FROM `sahyadri_b2b.shipments`
UNION ALL
SELECT 'V06', 'sales_orders', 'promised_delivery_date', 'Validity', 'Medium',
       'Promised delivery date is not before order date',
       COUNTIF(promised_delivery_date IS NOT NULL),
       COUNTIF(promised_delivery_date < order_date)
FROM `sahyadri_b2b.sales_orders`

-- ---------- Uniqueness ----------------------------------------------------------
UNION ALL
SELECT 'U01', 'customers', 'customer_id', 'Uniqueness', 'High',
       'Customer ID is unique',
       COUNT(*), COUNT(*) - COUNT(DISTINCT customer_id)
FROM `sahyadri_b2b.customers`
UNION ALL
SELECT 'U02', 'customers', 'customer_name', 'Uniqueness', 'Medium',
       'Customer name is unique after ignoring case and spacing',
       COUNT(*),
       COUNT(*) - COUNT(DISTINCT LOWER(REGEXP_REPLACE(TRIM(customer_name), r'\s+', ' ')))
FROM `sahyadri_b2b.customers`
UNION ALL
SELECT 'U03', 'payments', 'order_id, payment_date, amount', 'Uniqueness', 'High',
       'No payment is recorded twice (same order, date and amount)',
       COUNT(*),
       COUNT(*) - COUNT(DISTINCT CONCAT(CAST(order_id AS STRING), '|',
                                        CAST(payment_date AS STRING), '|',
                                        CAST(amount AS STRING)))
FROM `sahyadri_b2b.payments`

-- ---------- Consistency ---------------------------------------------------------
UNION ALL
SELECT 'K01', 'shipments', 'shipping_city', 'Consistency', 'Medium',
       'City name is trimmed and in title case',
       COUNT(*), COUNTIF(shipping_city <> INITCAP(TRIM(shipping_city)))
FROM `sahyadri_b2b.shipments`
UNION ALL
SELECT 'K02', 'sales_orders', 'order_status', 'Consistency', 'Medium',
       'Orders still marked Shipped have no shipment already delivered',
       COUNTIF(o.order_status = 'Shipped'),
       COUNTIF(o.order_status = 'Shipped' AND d.order_id IS NOT NULL)
FROM `sahyadri_b2b.sales_orders` AS o
LEFT JOIN (SELECT DISTINCT order_id FROM `sahyadri_b2b.shipments`
           WHERE shipment_status = 'Delivered') AS d
    ON d.order_id = o.order_id
UNION ALL
SELECT 'K03', 'sales_orders', 'order_status', 'Consistency', 'Medium',
       'Every Delivered order has a shipment record',
       COUNTIF(o.order_status = 'Delivered'),
       COUNTIF(o.order_status = 'Delivered' AND s.order_id IS NULL)
FROM `sahyadri_b2b.sales_orders` AS o
LEFT JOIN (SELECT DISTINCT order_id FROM `sahyadri_b2b.shipments`) AS s
    ON s.order_id = o.order_id
UNION ALL
SELECT 'K04', 'sales_orders', 'payment_status', 'Consistency', 'High',
       'Orders marked Unpaid have no payments recorded',
       COUNTIF(o.payment_status = 'Unpaid'),
       COUNTIF(o.payment_status = 'Unpaid' AND p.order_id IS NOT NULL)
FROM `sahyadri_b2b.sales_orders` AS o
LEFT JOIN (SELECT DISTINCT order_id FROM `sahyadri_b2b.payments`) AS p
    ON p.order_id = o.order_id
UNION ALL
SELECT 'K05', 'shipments', 'shipment_date', 'Consistency', 'Medium',
       'No shipment is dated before its order',
       COUNT(*), COUNTIF(s.shipment_date < o.order_date)
FROM `sahyadri_b2b.shipments`         AS s
JOIN `sahyadri_b2b.sales_orders`      AS o
    ON o.order_id = s.order_id

-- ---------- Referential integrity -----------------------------------------------
UNION ALL
SELECT 'R01', 'sales_orders', 'customer_id', 'Referential integrity', 'High',
       'Every order refers to an existing customer',
       COUNT(*), COUNTIF(c.customer_id IS NULL)
FROM `sahyadri_b2b.sales_orders`  AS o
LEFT JOIN `sahyadri_b2b.customers` AS c ON c.customer_id = o.customer_id
UNION ALL
SELECT 'R02', 'sales_order_items', 'product_id', 'Referential integrity', 'High',
       'Every order line refers to an existing product',
       COUNT(*), COUNTIF(p.product_id IS NULL)
FROM `sahyadri_b2b.sales_order_items` AS i
LEFT JOIN `sahyadri_b2b.products`      AS p ON p.product_id = i.product_id
UNION ALL
SELECT 'R03', 'payments', 'order_id', 'Referential integrity', 'High',
       'Every payment refers to an existing order',
       COUNT(*), COUNTIF(o.order_id IS NULL)
FROM `sahyadri_b2b.payments`         AS p
LEFT JOIN `sahyadri_b2b.sales_orders` AS o ON o.order_id = p.order_id
UNION ALL
SELECT 'R04', 'sales_orders', 'employee_id', 'Referential integrity', 'Medium',
       'Every salesperson on an order exists in employees',
       COUNTIF(o.employee_id IS NOT NULL),
       COUNTIF(o.employee_id IS NOT NULL AND e.employee_id IS NULL)
FROM `sahyadri_b2b.sales_orders`   AS o
LEFT JOIN `sahyadri_b2b.employees` AS e ON e.employee_id = o.employee_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Full scorecard, worst first
-- -----------------------------------------------------------------------------
SELECT
    rule_id,
    table_name,
    column_name,
    dimension,
    severity,
    rule_description,
    records_checked,
    records_failed,
    ROUND(100 * (1 - SAFE_DIVIDE(records_failed, records_checked)), 2) AS pass_rate_pct,
    IF(records_failed = 0, 'Pass', 'Fail')                              AS result
FROM `sahyadri_b2b.data_quality_results`
ORDER BY
    CASE severity WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END,
    records_failed DESC,
    rule_id;

-- -----------------------------------------------------------------------------
-- Step 3 · Summary by table
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    COUNT(*)                                                    AS rules,
    COUNTIF(records_failed > 0)                                 AS rules_failing,
    COUNTIF(records_failed > 0 AND severity = 'High')           AS high_severity_failing,
    SUM(records_failed)                                         AS records_failed,
    ROUND(AVG(100 * (1 - SAFE_DIVIDE(records_failed, records_checked))), 2)
                                                                AS avg_rule_pass_rate_pct
FROM `sahyadri_b2b.data_quality_results`
GROUP BY table_name
ORDER BY high_severity_failing DESC, rules_failing DESC, table_name;

-- -----------------------------------------------------------------------------
-- Step 4 · Summary by quality dimension
-- -----------------------------------------------------------------------------
SELECT
    dimension,
    COUNT(*)                                                    AS rules,
    COUNTIF(records_failed > 0)                                 AS rules_failing,
    SUM(records_failed)                                         AS records_failed,
    ROUND(AVG(100 * (1 - SAFE_DIVIDE(records_failed, records_checked))), 2)
                                                                AS avg_rule_pass_rate_pct
FROM `sahyadri_b2b.data_quality_results`
GROUP BY dimension
ORDER BY rules_failing DESC, dimension;
