-- =============================================================================
-- Zomato Bangalore | BigQuery Standard SQL
-- 03.2 RESTAURANT GRAIN CHECKS
--
-- Why this file exists
--   The dataset is a scrape of Zomato *listings*, not a restaurant master.
--   One restaurant appears once per (listed_in_type x listed_in_city) context,
--   and every `url` carries a unique `?context=...` query string.
--   => COUNT(*) and COUNT(DISTINCT url) both count LISTING ROWS (51,717),
--      not restaurants.
--
-- Decision
--   restaurant_id = URL path without the query string
--                   REGEXP_EXTRACT(url, r'^[^?]+')
--   Restaurant-level analysis keeps ONE row per restaurant_id: the snapshot
--   with the highest votes_cleaned (most recent / most complete), url as a
--   deterministic tie-break.
-- =============================================================================


-- 03.2.1 Listing rows vs candidate restaurant keys
SELECT
    COUNT(*)                                             AS listing_rows,
    COUNT(DISTINCT url)                                  AS distinct_url,
    COUNT(DISTINCT REGEXP_EXTRACT(url, r'^[^?]+'))       AS distinct_url_path,
    COUNT(DISTINCT CONCAT(name, '|', address_cleaned))   AS distinct_name_address,
    COUNT(DISTINCT listed_in_type)                       AS listed_types,
    COUNT(DISTINCT listed_in_city)                       AS listed_cities
FROM `zomatoanalytics.Zomato_csv.restaurants_clean`;


-- 03.2.2 Rating categories - every row must fall in exactly one bucket
SELECT
    COUNTIF(rate_cleaned IS NULL)                                                   AS rate_null,
    COUNTIF(rate_cleaned = 'NEW')                                                   AS rate_new,
    COUNTIF(rate_cleaned = '-')                                                     AS rate_dash,
    COUNTIF(SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) IS NOT NULL) AS rate_numeric,
    COUNT(*)                                                                        AS total_rows
FROM `zomatoanalytics.Zomato_csv.restaurants_clean`;


-- 03.2.3 Attribute stability within a restaurant_id
--        (how many restaurants have >1 distinct value across their listing rows)
WITH listings AS (
    SELECT REGEXP_EXTRACT(url, r'^[^?]+') AS restaurant_id, *
    FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
),
per_restaurant AS (
    SELECT
        restaurant_id,
        COUNT(*)                                         AS rows_per_restaurant,
        COUNT(DISTINCT IFNULL(location, '~'))            AS location_variants,
        COUNT(DISTINCT IFNULL(rate_cleaned, '~'))        AS rate_variants,
        COUNT(DISTINCT votes_cleaned)                    AS vote_variants,
        COUNT(DISTINCT IFNULL(cuisines, '~'))            AS cuisine_variants,
        COUNT(DISTINCT online_order)                     AS online_order_variants,
        COUNT(DISTINCT name)                             AS name_variants,
        COUNT(DISTINCT listed_in_type)                   AS listed_type_variants,
        COUNT(DISTINCT listed_in_city)                   AS listed_city_variants
    FROM listings
    GROUP BY restaurant_id
)
SELECT
    COUNT(*)                              AS restaurants,
    MAX(rows_per_restaurant)              AS max_rows_per_restaurant,
    ROUND(AVG(rows_per_restaurant), 2)    AS avg_rows_per_restaurant,
    COUNTIF(location_variants > 1)        AS multi_location,
    COUNTIF(rate_variants > 1)            AS multi_rate,
    COUNTIF(vote_variants > 1)            AS multi_votes,
    COUNTIF(cuisine_variants > 1)         AS multi_cuisines,
    COUNTIF(online_order_variants > 1)    AS multi_online_order,
    COUNTIF(name_variants > 1)            AS multi_name,
    COUNTIF(listed_type_variants > 1)     AS multi_listed_type,
    COUNTIF(listed_city_variants > 1)     AS multi_listed_city
FROM per_restaurant;


-- 03.2.4 Deduplicated restaurant layer - reconciliation check
--        Expected: restaurants = distinct_url_path from 03.2.1; duplicates_left = 0
WITH restaurants AS (
    SELECT
        REGEXP_EXTRACT(url, r'^[^?]+') AS restaurant_id,
        location,
        SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating
    FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
    WHERE url IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY REGEXP_EXTRACT(url, r'^[^?]+')
        ORDER BY votes_cleaned DESC, url
    ) = 1
)
SELECT
    COUNT(*)                                 AS restaurants,
    COUNT(*) - COUNT(DISTINCT restaurant_id) AS duplicates_left,
    COUNTIF(location IS NULL)                AS null_location,
    COUNTIF(rating IS NOT NULL)              AS rated_restaurants,
    MIN(rating)                              AS min_rating,
    MAX(rating)                              AS max_rating
FROM restaurants;
