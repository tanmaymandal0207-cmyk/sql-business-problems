-- =============================================================================
-- A08 | Cuisine diversity and online adoption
-- =============================================================================
-- Business question
--   Which localities combine a diverse cuisine mix with strong online-ordering adoption?
--
-- Requirements
--   - Only localities with at least 300 restaurants.
--   - Distinct cuisines counted only if offered by at least 20 restaurants in the locality.
--   - Most popular cuisine (highest restaurant count) per locality.
--   - Online ordering acceptance %; sort by acceptance desc.
--
-- Grain & rules
--   - Restaurant = distinct URL path (restaurant_id); latest snapshot by votes.
--   - Rating = numeric part of rate_cleaned; NEW, '-' and NULL are excluded from averages.
--   - Fix vs original: implements the >=20 cuisine filter, the most-popular-cuisine column,
--     the 300 threshold (original used 100) and the requested sort order.
--
-- Original attempt : sql/00_source/bigquery_export_analysis_query.sql (lines 317-355)
-- Result           : results/a08_cuisine_diversity_and_online_adoption.csv
-- =============================================================================

WITH restaurants AS (                       -- one row per restaurant (see 03_validation/02)
    SELECT
        REGEXP_EXTRACT(url, r'^[^?]+')                                 AS restaurant_id,
        name,
        location,
        online_order,
        cuisines,
        SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating   -- NEW / '-' / NULL -> NULL
    FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
    WHERE url IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY REGEXP_EXTRACT(url, r'^[^?]+')
        ORDER BY votes_cleaned DESC, url
    ) = 1
),
restaurant_cuisines AS (                    -- one row per restaurant x individual cuisine
    SELECT DISTINCT
        r.restaurant_id,
        r.location,
        r.online_order,
        r.rating,
        TRIM(cuisine_raw) AS cuisine
    FROM restaurants AS r,
         UNNEST(SPLIT(r.cuisines, ',')) AS cuisine_raw
    WHERE r.cuisines IS NOT NULL
      AND TRIM(cuisine_raw) != ''
),
locality_summary AS (
    SELECT
        location,
        COUNT(*)                                                       AS restaurant_count,
        ROUND(SAFE_DIVIDE(COUNTIF(online_order = 'Yes'), COUNT(*)) * 100, 2) AS online_acceptance_pct
    FROM restaurants
    WHERE location IS NOT NULL
    GROUP BY location
    HAVING COUNT(*) >= 300
),
locality_cuisine AS (
    SELECT location, cuisine, COUNT(*) AS cuisine_restaurants
    FROM restaurant_cuisines
    WHERE location IS NOT NULL
    GROUP BY location, cuisine
    HAVING COUNT(*) >= 20
)
SELECT
    s.location,
    s.restaurant_count,
    COUNT(lc.cuisine)                                                  AS distinct_cuisines_20plus,
    ARRAY_AGG(lc.cuisine ORDER BY lc.cuisine_restaurants DESC, lc.cuisine LIMIT 1)[OFFSET(0)]
                                                                       AS most_popular_cuisine,
    MAX(lc.cuisine_restaurants)                                        AS most_popular_cuisine_restaurants,
    s.online_acceptance_pct
FROM locality_summary AS s
JOIN locality_cuisine AS lc
  ON lc.location = s.location
GROUP BY s.location, s.restaurant_count, s.online_acceptance_pct
ORDER BY s.online_acceptance_pct DESC, s.restaurant_count DESC;
