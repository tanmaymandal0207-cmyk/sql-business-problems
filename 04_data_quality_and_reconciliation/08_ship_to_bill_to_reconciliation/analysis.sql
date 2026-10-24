/* =============================================================================
   Case study · Ship-to vs bill-to reconciliation
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   Every invoice carries the customer's billing address from the customer
   master; every shipment carries a delivery city typed at dispatch. The tax
   team needs the two to agree, because goods that move to a different state
   from the billing state need the right GST treatment and transport
   documents (e-way bills). A raw comparison shows about 1,000 shipments
   whose city does not match the customer's city. Before anyone reviews them
   one by one, the controller wants to know:
     1. How many mismatches are only spelling, casing or old city names?
     2. How many shipments really go to a different city, and how many of
        those cross a state border?
     3. Which differences are regular second sites (plants, branches) and
        which are one-off destinations that may be data-entry errors?
     4. Can the delivery history fill the missing cities in the customer
        master?

   KEY RULES
     - Both cities are standardised the same way: TRIM, case-fold, then an
       alias table for old or alternative names (Bangalore -> Bengaluru,
       Gurgaon -> Gurugram ...). The aliases are the same as the city map in
       the late delivery root cause study.
     - State of a delivery city: from the customer master, where every
       standardised city belongs to exactly one state (checked).
     - Recurring destination: the same customer shipped to the same other
       city 3 or more times. Otherwise occasional.
     - Order value over Rs 50,000 is shown as an indicator for e-way bill
       review; the actual consignment value per shipment is not recorded.
   ============================================================================= */

DECLARE recurring_min   INT64   DEFAULT 3;
DECLARE value_threshold NUMERIC DEFAULT 50000;

-- -----------------------------------------------------------------------------
-- Step 1 · Reference tables: city aliases and city -> state lookup
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.city_alias_map` AS
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

CREATE OR REPLACE TABLE `sahyadri_b2b.city_state_lookup` AS
SELECT DISTINCT
    COALESCE(a.standard_city, INITCAP(TRIM(c.city))) AS standard_city,
    c.state
FROM `sahyadri_b2b.customers` AS c
LEFT JOIN `sahyadri_b2b.city_alias_map` AS a ON a.raw_city_key = LOWER(TRIM(c.city))
WHERE c.city IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Step 2 · One row per shipment with both cities standardised and classified
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.ship_bill_reconciliation` AS
WITH order_value AS (
    SELECT i.order_id,
           SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS order_revenue
    FROM `sahyadri_b2b.sales_order_items` AS i
    GROUP BY i.order_id
),
base AS (
    SELECT
        s.shipment_id,
        s.order_id,
        o.customer_id,
        cu.customer_name,
        cu.customer_segment,
        s.shipment_date,
        s.shipping_city                                                AS raw_ship_city,
        cu.city                                                        AS raw_bill_city,
        cu.state                                                       AS bill_state,
        COALESCE(sa.standard_city, INITCAP(TRIM(s.shipping_city)))     AS ship_city,
        COALESCE(ba.standard_city, INITCAP(TRIM(cu.city)))             AS bill_city,
        v.order_revenue
    FROM `sahyadri_b2b.shipments`     AS s
    JOIN `sahyadri_b2b.sales_orders`  AS o  ON o.order_id = s.order_id
    JOIN `sahyadri_b2b.customers`     AS cu ON cu.customer_id = o.customer_id
    JOIN order_value                  AS v  ON v.order_id = s.order_id
    LEFT JOIN `sahyadri_b2b.city_alias_map` AS sa ON sa.raw_city_key = LOWER(TRIM(s.shipping_city))
    LEFT JOIN `sahyadri_b2b.city_alias_map` AS ba ON ba.raw_city_key = LOWER(TRIM(cu.city))
),
classified AS (
    SELECT
        b.*,
        l.state                                                        AS ship_state,
        CASE
            WHEN b.raw_bill_city IS NULL                               THEN '6. No billing city'
            WHEN b.raw_ship_city = b.raw_bill_city                     THEN '1. Exact match'
            WHEN LOWER(TRIM(b.raw_ship_city)) = LOWER(TRIM(b.raw_bill_city)) THEN '2. Case or spacing only'
            WHEN b.ship_city = b.bill_city                             THEN '3. City alias only'
            WHEN l.state = b.bill_state                                THEN '4. Different city, same state'
            ELSE                                                            '5. Different city, other state'
        END                                                            AS match_type
    FROM base AS b
    LEFT JOIN `sahyadri_b2b.city_state_lookup` AS l ON l.standard_city = b.ship_city
)
SELECT
    c.*,
    COUNT(*) OVER (PARTITION BY c.customer_id, c.ship_city)            AS customer_city_shipments,
    CASE WHEN c.match_type NOT IN ('4. Different city, same state', '5. Different city, other state') THEN NULL
         WHEN COUNT(*) OVER (PARTITION BY c.customer_id, c.ship_city) >= recurring_min THEN 'Recurring destination'
         ELSE 'Occasional destination' END                             AS destination_pattern
FROM classified AS c;

-- -----------------------------------------------------------------------------
-- Step 3 · How many mismatches are only naming?
-- -----------------------------------------------------------------------------
SELECT
    match_type,
    COUNT(*)                                                           AS shipments,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                   AS shipments_pct,
    COUNT(DISTINCT customer_id)                                        AS customers
FROM `sahyadri_b2b.ship_bill_reconciliation`
GROUP BY match_type
ORDER BY match_type;

-- The naming variants behind types 2 and 3
SELECT
    match_type,
    TRIM(raw_bill_city)                                                AS billing_city_as_recorded,
    TRIM(raw_ship_city)                                                AS shipping_city_as_recorded,
    bill_city                                                          AS standard_city,
    COUNT(*)                                                           AS shipments
FROM `sahyadri_b2b.ship_bill_reconciliation`
WHERE match_type IN ('2. Case or spacing only', '3. City alias only')
GROUP BY match_type, billing_city_as_recorded, shipping_city_as_recorded, standard_city
ORDER BY shipments DESC
LIMIT 15;

-- Where the variant sits: in the shipment record, the customer master, or both
SELECT
    CASE WHEN raw_bill_city = bill_city AND raw_ship_city != ship_city THEN 'Shipment record only'
         WHEN raw_bill_city != bill_city AND raw_ship_city = ship_city THEN 'Customer master only'
         ELSE 'Both' END                                               AS non_standard_in,
    COUNT(*)                                                           AS shipments,
    COUNT(DISTINCT customer_id)                                        AS customers
FROM `sahyadri_b2b.ship_bill_reconciliation`
WHERE match_type IN ('2. Case or spacing only', '3. City alias only')
GROUP BY non_standard_in
ORDER BY shipments DESC;

-- -----------------------------------------------------------------------------
-- Step 4 · Genuine differences: recurring second sites vs one-off destinations
-- -----------------------------------------------------------------------------
SELECT
    match_type,
    destination_pattern,
    COUNT(*)                                                           AS shipments,
    COUNT(DISTINCT CONCAT(CAST(customer_id AS STRING), '|', ship_city)) AS customer_city_pairs,
    COUNT(DISTINCT customer_id)                                        AS customers,
    COUNT(DISTINCT order_id)                                           AS orders,
    COUNT(DISTINCT IF(order_revenue > value_threshold, order_id, NULL)) AS orders_over_threshold
FROM `sahyadri_b2b.ship_bill_reconciliation`
WHERE destination_pattern IS NOT NULL
GROUP BY match_type, destination_pattern
ORDER BY match_type, destination_pattern;

-- Recurring second sites
SELECT
    customer_id,
    customer_name,
    bill_city,
    bill_state,
    ship_city,
    ship_state,
    customer_city_shipments                                            AS shipments_to_this_city,
    COUNT(*) OVER (PARTITION BY customer_id)                           AS recurring_rows_for_customer
FROM (
    SELECT DISTINCT customer_id, customer_name, bill_city, bill_state, ship_city, ship_state, customer_city_shipments
    FROM `sahyadri_b2b.ship_bill_reconciliation`
    WHERE destination_pattern = 'Recurring destination'
)
ORDER BY shipments_to_this_city DESC, customer_id
LIMIT 25;

-- Review list: occasional other-state destinations, largest orders first
SELECT
    shipment_id,
    order_id,
    customer_name,
    bill_city,
    bill_state,
    ship_city,
    ship_state,
    shipment_date,
    ROUND(order_revenue, 0)                                            AS order_revenue
FROM `sahyadri_b2b.ship_bill_reconciliation`
WHERE match_type = '5. Different city, other state'
  AND destination_pattern = 'Occasional destination'
ORDER BY order_revenue DESC
LIMIT 15;

-- -----------------------------------------------------------------------------
-- Step 5 · Proposed fills for customers with no city in the master
-- -----------------------------------------------------------------------------
WITH by_city AS (
    SELECT
        customer_id,
        ANY_VALUE(customer_name)                                       AS customer_name,
        ANY_VALUE(bill_state)                                          AS master_state,
        ship_city,
        ANY_VALUE(ship_state)                                          AS ship_state,
        COUNT(*)                                                       AS shipments
    FROM `sahyadri_b2b.ship_bill_reconciliation`
    WHERE match_type = '6. No billing city'
    GROUP BY customer_id, ship_city
),
ranked AS (
    SELECT
        *,
        SUM(shipments) OVER (PARTITION BY customer_id)                 AS customer_shipments,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY shipments DESC, ship_city) AS rn
    FROM by_city
)
SELECT
    customer_id,
    customer_name,
    master_state,
    ship_city                                                          AS most_frequent_ship_city,
    ship_state,
    shipments,
    customer_shipments,
    ROUND(100 * shipments / customer_shipments, 1)                     AS share_pct,
    CASE WHEN ship_state != master_state                 THEN 'Do not fill: state conflicts'
         WHEN customer_shipments < recurring_min         THEN 'Confirm with customer: too few shipments'
         WHEN shipments / customer_shipments >= 0.9      THEN 'Propose fill'
         ELSE 'Confirm with customer: several cities' END              AS proposal
FROM ranked
WHERE rn = 1
ORDER BY customer_shipments DESC;
