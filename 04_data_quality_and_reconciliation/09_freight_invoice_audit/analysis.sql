/* =============================================================================
   Case study · Freight invoice audit
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Freight costs about Rs 1.2 crore over the period and is paid on carrier
   invoices without a rate check, because the signed rate cards were never
   loaded into the system. Internal audit wants to know whether the
   company is being charged consistently, and asks:
     1. Can a rate card be inferred from the charges themselves, and how
        well does it explain them?
     2. Which shipments are charged materially more or less than the card?
     3. Have rates crept up over time?
     4. How are very large consignments charged?
     5. What freight should be accrued for shipments with no cost recorded?

   METHOD
     - Rate card per destination city: cost = fixed charge + variable rate x
       consignment value, fitted by least squares on single-shipment orders
       (so the consignment value is the order value) with order value up to
       Rs 10 lakh. Larger consignments are excluded from fitting because a
       handful of very large values would dominate a least-squares line.
     - Cities with fewer than 30 fitting shipments share one pooled card.
     - Variance % = (charged - card) / card. Within tolerance: +/- 15 %.
     - Cities are standardised with the alias table used in the
       ship-to/bill-to reconciliation.

   KEY RULES
     - Consignment value = order revenue (quantity x price x (1 - discount)),
       for single-shipment orders only. Split shipments are not audited
       because the value of each part is not recorded.
     - Missing cost: shipping_cost is NULL. The accrual estimate applies the
       card to single-shipment orders.
   ============================================================================= */

DECLARE fit_max_value      FLOAT64 DEFAULT 1000000;
DECLARE tolerance_band     FLOAT64 DEFAULT 0.15;
DECLARE min_city_shipments INT64   DEFAULT 30;

-- -----------------------------------------------------------------------------
-- Step 1 · City aliases (same table as the ship-to/bill-to reconciliation)
--          and the shipment base table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `sahyadri_b2b.city_alias_map` AS
SELECT 'ahmadabad' AS raw_city_key, 'Ahmedabad' AS standard_city UNION ALL
SELECT 'bangalore', 'Bengaluru'     UNION ALL
SELECT 'baroda',    'Vadodara'      UNION ALL
SELECT 'bombay',    'Mumbai'        UNION ALL
SELECT 'calcutta',  'Kolkata'       UNION ALL
SELECT 'delhi',     'New Delhi'     UNION ALL
SELECT 'gurgaon',   'Gurugram'      UNION ALL
SELECT 'madras',    'Chennai'       UNION ALL
SELECT 'mysore',    'Mysuru'        UNION ALL
SELECT 'vizag',     'Visakhapatnam';

CREATE OR REPLACE TABLE `sahyadri_b2b.freight_audit_base` AS
WITH order_value AS (
    SELECT order_id,
           SUM(quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)) AS order_value
    FROM `sahyadri_b2b.sales_order_items`
    GROUP BY order_id
)
SELECT
    s.shipment_id,
    s.order_id,
    s.shipment_date,
    COALESCE(a.standard_city, INITCAP(TRIM(s.shipping_city)))            AS city,
    v.order_value,
    COUNT(*) OVER (PARTITION BY s.order_id)                              AS shipments_in_order,
    s.shipping_cost
FROM `sahyadri_b2b.shipments` AS s
JOIN order_value AS v ON v.order_id = s.order_id
LEFT JOIN `sahyadri_b2b.city_alias_map` AS a ON a.raw_city_key = LOWER(TRIM(s.shipping_city));

-- -----------------------------------------------------------------------------
-- Step 2 · Inferred rate card per city (least squares on the fitting set)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.freight_rate_card` AS
WITH fitting AS (
    SELECT
        b.*,
        IF(COUNT(*) OVER (PARTITION BY b.city) >= min_city_shipments, b.city, 'Pooled (small cities)') AS card_city
    FROM `sahyadri_b2b.freight_audit_base` AS b
    WHERE b.shipments_in_order = 1
      AND b.shipping_cost IS NOT NULL
      AND b.order_value <= fit_max_value
)
SELECT
    card_city,
    COUNT(*)                                                             AS fitting_shipments,
    COUNT(DISTINCT city)                                                 AS cities,
    COVAR_POP(order_value, shipping_cost) / VAR_POP(order_value)        AS variable_rate,
    AVG(shipping_cost) - COVAR_POP(order_value, shipping_cost) / VAR_POP(order_value) * AVG(order_value) AS fixed_charge,
    POW(CORR(order_value, shipping_cost), 2)                             AS r_squared,
    AVG(shipping_cost)                                                   AS mean_charge
FROM fitting
GROUP BY card_city;

-- Card city for every audited city (cities below the threshold use the pooled card)
CREATE OR REPLACE TABLE `sahyadri_b2b.freight_audit` AS
WITH card_lookup AS (
    SELECT city,
           IF(COUNTIF(shipments_in_order = 1 AND shipping_cost IS NOT NULL AND order_value <= fit_max_value) >= min_city_shipments,
              city, 'Pooled (small cities)') AS card_city
    FROM `sahyadri_b2b.freight_audit_base`
    GROUP BY city
)
SELECT
    b.*,
    l.card_city,
    -- the card applies only where the shipment value is known (single-shipment orders)
    IF(b.shipments_in_order = 1, r.fixed_charge + r.variable_rate * b.order_value, NULL)                     AS card_charge,
    IF(b.shipments_in_order = 1, b.shipping_cost - (r.fixed_charge + r.variable_rate * b.order_value), NULL) AS variance,
    IF(b.shipments_in_order = 1,
       SAFE_DIVIDE(b.shipping_cost - (r.fixed_charge + r.variable_rate * b.order_value),
                   r.fixed_charge + r.variable_rate * b.order_value), NULL)                                   AS variance_pct,
    CASE
        WHEN b.shipments_in_order > 1                       THEN '6. Split shipment (not audited)'
        WHEN b.shipping_cost IS NULL                        THEN '5. Missing cost'
        WHEN b.order_value > fit_max_value                  THEN '4. Above card range'
        WHEN b.shipping_cost > (r.fixed_charge + r.variable_rate * b.order_value) * (1 + tolerance_band) THEN '2. Over-charged'
        WHEN b.shipping_cost < (r.fixed_charge + r.variable_rate * b.order_value) * (1 - tolerance_band) THEN '3. Under-charged'
        ELSE '1. Within tolerance' END                                    AS audit_status
FROM `sahyadri_b2b.freight_audit_base` AS b
JOIN card_lookup AS l ON l.city = b.city
JOIN `sahyadri_b2b.freight_rate_card` AS r ON r.card_city = l.card_city;

SELECT
    card_city,
    fitting_shipments,
    ROUND(fixed_charge, 0)                                              AS fixed_charge_rs,
    ROUND(100 * variable_rate, 3)                                       AS variable_rate_pct_of_value,
    ROUND(r_squared, 3)                                                 AS r_squared
FROM `sahyadri_b2b.freight_rate_card`
ORDER BY fitting_shipments DESC;

SELECT
    COUNT(*)                                                            AS cards,
    ROUND(MIN(fixed_charge), 0)                                         AS min_fixed_charge,
    ROUND(MAX(fixed_charge), 0)                                         AS max_fixed_charge,
    ROUND(100 * MIN(variable_rate), 3)                                  AS min_variable_pct,
    ROUND(100 * MAX(variable_rate), 3)                                  AS max_variable_pct,
    ROUND(MIN(r_squared), 3)                                            AS min_r_squared,
    ROUND(APPROX_QUANTILES(r_squared, 2)[OFFSET(1)], 3)                 AS median_r_squared
FROM `sahyadri_b2b.freight_rate_card`;

-- -----------------------------------------------------------------------------
-- Step 3 · Audit result: how many charges sit outside the card?
-- -----------------------------------------------------------------------------
SELECT
    audit_status,
    COUNT(*)                                                            AS shipments,
    ROUND(SUM(shipping_cost), 0)                                        AS charged,
    ROUND(SUM(IF(shipping_cost IS NOT NULL, card_charge, NULL)), 0)     AS card_value,
    ROUND(SUM(variance), 0)                                             AS variance
FROM `sahyadri_b2b.freight_audit`
GROUP BY audit_status
ORDER BY audit_status;

-- Spread of variances inside the fitting range
SELECT
    ROUND(100 * APPROX_QUANTILES(variance_pct, 100)[OFFSET(1)], 1)       AS p01_pct,
    ROUND(100 * APPROX_QUANTILES(variance_pct, 100)[OFFSET(5)], 1)       AS p05_pct,
    ROUND(100 * APPROX_QUANTILES(variance_pct, 100)[OFFSET(50)], 1)      AS median_pct,
    ROUND(100 * APPROX_QUANTILES(variance_pct, 100)[OFFSET(95)], 1)      AS p95_pct,
    ROUND(100 * APPROX_QUANTILES(variance_pct, 100)[OFFSET(99)], 1)      AS p99_pct
FROM `sahyadri_b2b.freight_audit`
WHERE shipments_in_order = 1 AND shipping_cost IS NOT NULL AND order_value <= fit_max_value;

-- Where are the exceptions? Cities on their own card vs the pooled card
SELECT
    city,
    card_city,
    COUNTIF(audit_status = '2. Over-charged')                           AS over_charged,
    COUNTIF(audit_status = '3. Under-charged')                          AS under_charged,
    COUNTIF(audit_status IN ('1. Within tolerance', '2. Over-charged', '3. Under-charged')) AS audited,
    ROUND(SUM(IF(audit_status IN ('2. Over-charged', '3. Under-charged'), variance, 0)), 0) AS exception_variance
FROM `sahyadri_b2b.freight_audit`
GROUP BY city, card_city
HAVING COUNTIF(audit_status IN ('2. Over-charged', '3. Under-charged')) > 0
ORDER BY over_charged + under_charged DESC
LIMIT 12;

SELECT
    IF(card_city = 'Pooled (small cities)', 'Pooled card', 'Own city card')           AS card_type,
    COUNT(DISTINCT city)                                                AS cities,
    COUNTIF(audit_status IN ('1. Within tolerance', '2. Over-charged', '3. Under-charged')) AS audited,
    COUNTIF(audit_status IN ('2. Over-charged', '3. Under-charged'))    AS exceptions,
    ROUND(100 * COUNTIF(audit_status IN ('2. Over-charged', '3. Under-charged'))
          / COUNTIF(audit_status IN ('1. Within tolerance', '2. Over-charged', '3. Under-charged')), 2) AS exception_pct
FROM `sahyadri_b2b.freight_audit`
GROUP BY card_type
ORDER BY card_type;

-- Exceptions: charges outside tolerance, largest variance first
SELECT
    shipment_id, order_id, city, shipment_date,
    ROUND(order_value, 0)                                               AS order_value,
    ROUND(shipping_cost, 0)                                             AS charged,
    ROUND(card_charge, 0)                                               AS card_charge,
    ROUND(100 * variance_pct, 1)                                        AS variance_pct,
    audit_status
FROM `sahyadri_b2b.freight_audit`
WHERE audit_status IN ('2. Over-charged', '3. Under-charged')
ORDER BY ABS(variance) DESC
LIMIT 15;

-- -----------------------------------------------------------------------------
-- Step 4 · Have rates crept up? Median variance by year (fitting range)
-- -----------------------------------------------------------------------------
SELECT
    EXTRACT(YEAR FROM shipment_date)                                    AS year,
    COUNT(*)                                                            AS shipments,
    ROUND(100 * APPROX_QUANTILES(variance_pct, 2)[OFFSET(1)], 2)        AS median_variance_pct,
    ROUND(100 * AVG(variance_pct), 2)                                   AS mean_variance_pct
FROM `sahyadri_b2b.freight_audit`
WHERE shipments_in_order = 1 AND shipping_cost IS NOT NULL AND order_value <= fit_max_value
GROUP BY year
ORDER BY year;

-- -----------------------------------------------------------------------------
-- Step 5 · Very large consignments: how are they charged?
-- -----------------------------------------------------------------------------
SELECT
    shipment_id, city, shipment_date,
    ROUND(order_value / 1e5, 1)                                         AS order_value_lakh,
    ROUND(shipping_cost, 0)                                             AS charged,
    ROUND(card_charge, 0)                                               AS card_charge,
    ROUND(100 * shipping_cost / order_value, 2)                         AS charged_pct_of_value
FROM `sahyadri_b2b.freight_audit`
WHERE audit_status = '4. Above card range'
ORDER BY order_value DESC;

-- -----------------------------------------------------------------------------
-- Step 6 · Accrual for shipments with no recorded cost
-- -----------------------------------------------------------------------------
SELECT
    EXTRACT(YEAR FROM shipment_date)                                    AS year,
    COUNTIF(shipping_cost IS NULL)                                      AS shipments_missing_cost,
    COUNTIF(shipping_cost IS NULL AND shipments_in_order = 1)           AS single_shipment_missing,
    ROUND(SUM(IF(shipping_cost IS NULL AND shipments_in_order = 1, card_charge, 0)), 0) AS estimated_accrual_single,
    ROUND(SUM(shipping_cost), 0)                                        AS recorded_freight
FROM `sahyadri_b2b.freight_audit`
GROUP BY year
ORDER BY year;
