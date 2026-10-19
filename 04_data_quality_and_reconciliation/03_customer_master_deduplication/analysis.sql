/* =============================================================================
   Case study · Customer master de-duplication
   Category : Data quality and reconciliation
   Dialect  : Google BigQuery Standard SQL (multi-statement script)
   Dataset  : sahyadri_b2b

   BUSINESS PROBLEM
   The customer master has 500 records. Sales and finance suspect that some
   customers were created twice, for example once as "Navkar Agencies" and
   again as "Navkar Agencies Pvt Ltd". Duplicates split one customer's sales,
   receivables and credit exposure across two accounts, so customer rankings,
   credit limits and churn flags are all wrong for those accounts.
   The master data team wants to:
     1. Find candidate duplicate customer records.
     2. Rate each candidate by how confident the match is.
     3. Propose which record should survive (the master) for each
        high-confidence pair, as a reviewable mapping table.
     4. Show how merging changes revenue and customer rankings.

   METHOD
     - Normalised name: lower case, punctuation removed, legal-form words
       removed (pvt, private, ltd, limited, llp, co, company), spaces collapsed.
       "Navkar Agencies Pvt. Ltd." and "NAVKAR AGENCIES" both become
       "navkar agencies".
     - Candidate pair: two customer IDs with the same normalised name.
     - Match confidence:
         High   = same city and state      -> likely the same company
         Medium = same state, other city   -> possibly a branch; review
         Low    = different state          -> possibly a different company; review
     - Survivorship (High pairs): the master is the record with more orders;
       ties go to the earlier registration date, then the lower customer ID.
     - Revenue: orders not Cancelled or Returned; NULL discount = 0 %.
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- Step 1 · Customer records with normalised name and activity
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_name_keys` AS
WITH activity AS (
    SELECT
        o.customer_id,
        COUNT(DISTINCT o.order_id)                                               AS orders,
        SUM(i.quantity * i.unit_price * (1 - IFNULL(i.discount_percent, 0) / 100)) AS revenue
    FROM `sahyadri_b2b.sales_orders`      AS o
    JOIN `sahyadri_b2b.sales_order_items` AS i ON i.order_id = o.order_id
    WHERE o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY o.customer_id
)
SELECT
    c.customer_id,
    c.customer_name,
    c.city,
    c.state,
    c.customer_segment,
    c.industry,
    c.registration_date,
    TRIM(REGEXP_REPLACE(
        REGEXP_REPLACE(
            REGEXP_REPLACE(LOWER(c.customer_name), r'[^a-z0-9 ]', ' '),
            r'\b(pvt|private|ltd|limited|llp|co|company)\b', ' '),
        r'\s+', ' '))                                   AS normalised_name,
    IFNULL(a.orders, 0)                                 AS orders,
    ROUND(IFNULL(a.revenue, 0), 2)                      AS revenue
FROM `sahyadri_b2b.customers` AS c
LEFT JOIN activity            AS a
    ON a.customer_id = c.customer_id;

-- -----------------------------------------------------------------------------
-- Step 2 · Candidate duplicate pairs with match confidence
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_duplicate_candidates` AS
SELECT
    a.normalised_name,
    a.customer_id                                        AS customer_id_a,
    b.customer_id                                        AS customer_id_b,
    a.customer_name                                      AS name_a,
    b.customer_name                                      AS name_b,
    a.city                                               AS city_a,
    b.city                                               AS city_b,
    a.customer_segment                                   AS segment_a,
    b.customer_segment                                   AS segment_b,
    a.customer_segment = b.customer_segment              AS same_segment,
    a.orders                                             AS orders_a,
    b.orders                                             AS orders_b,
    a.revenue + b.revenue                                AS combined_revenue,
    CASE
        WHEN a.city = b.city AND a.state = b.state THEN 'High'
        WHEN a.state = b.state                     THEN 'Medium'
        ELSE                                            'Low'
    END                                                  AS match_confidence
FROM `sahyadri_b2b.customer_name_keys` AS a
JOIN `sahyadri_b2b.customer_name_keys` AS b
    ON  a.normalised_name = b.normalised_name
    AND a.customer_id     < b.customer_id;

-- -----------------------------------------------------------------------------
-- Step 3 · Summary by match confidence
-- -----------------------------------------------------------------------------
SELECT
    match_confidence,
    COUNT(*)                                  AS candidate_pairs,
    COUNTIF(same_segment)                     AS pairs_same_segment,
    SUM(orders_a + orders_b)                  AS orders_involved,
    ROUND(SUM(combined_revenue), 2)           AS revenue_involved
FROM `sahyadri_b2b.customer_duplicate_candidates`
GROUP BY match_confidence
ORDER BY CASE match_confidence WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;

-- -----------------------------------------------------------------------------
-- Step 4 · Proposed master mapping for high-confidence pairs (for review)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.customer_master_map` AS
WITH pair_records AS (
    SELECT d.normalised_name, k.*
    FROM `sahyadri_b2b.customer_duplicate_candidates` AS d
    JOIN `sahyadri_b2b.customer_name_keys`            AS k
        ON k.customer_id IN (d.customer_id_a, d.customer_id_b)
    WHERE d.match_confidence = 'High'
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY normalised_name
            ORDER BY orders DESC, registration_date ASC, customer_id ASC
        ) AS survivorship_rank
    FROM pair_records
)
SELECT
    r.customer_id                         AS duplicate_customer_id,
    r.customer_name                       AS duplicate_name,
    m.customer_id                         AS master_customer_id,
    m.customer_name                       AS master_name,
    r.orders                              AS duplicate_orders,
    m.orders                              AS master_orders,
    r.revenue                             AS duplicate_revenue,
    'Proposed - pending review'           AS review_status
FROM ranked AS r
JOIN ranked AS m
    ON  m.normalised_name   = r.normalised_name
    AND m.survivorship_rank = 1
WHERE r.survivorship_rank > 1;

SELECT *
FROM `sahyadri_b2b.customer_master_map`
ORDER BY duplicate_revenue DESC;

-- -----------------------------------------------------------------------------
-- Step 5 · Impact of merging on revenue and customer ranking
-- -----------------------------------------------------------------------------
WITH before_merge AS (
    SELECT customer_id, revenue,
           RANK() OVER (ORDER BY revenue DESC) AS rank_before
    FROM `sahyadri_b2b.customer_name_keys`
),
after_merge AS (
    SELECT
        IFNULL(m.master_customer_id, k.customer_id) AS customer_id,
        SUM(k.revenue)                              AS revenue
    FROM `sahyadri_b2b.customer_name_keys`     AS k
    LEFT JOIN `sahyadri_b2b.customer_master_map` AS m
        ON m.duplicate_customer_id = k.customer_id
    GROUP BY 1
),
after_ranked AS (
    SELECT customer_id, revenue,
           RANK() OVER (ORDER BY revenue DESC) AS rank_after
    FROM after_merge
)
SELECT
    m.master_customer_id,
    m.master_name,
    b.revenue                         AS master_revenue_before,
    ROUND(a.revenue, 2)               AS merged_revenue,
    b.rank_before,
    a.rank_after,
    b.rank_before - a.rank_after      AS places_gained
FROM `sahyadri_b2b.customer_master_map` AS m
JOIN before_merge  AS b ON b.customer_id = m.master_customer_id
JOIN after_ranked  AS a ON a.customer_id = m.master_customer_id
ORDER BY merged_revenue DESC;

-- -----------------------------------------------------------------------------
-- Step 6 · Medium and low confidence pairs for manual review
-- -----------------------------------------------------------------------------
SELECT
    match_confidence,
    customer_id_a, name_a, city_a, segment_a, orders_a,
    customer_id_b, name_b, city_b, segment_b, orders_b
FROM `sahyadri_b2b.customer_duplicate_candidates`
WHERE match_confidence <> 'High'
ORDER BY match_confidence, combined_revenue DESC;
