-- =============================================================================
-- A06 | Top rated cuisines
-- =============================================================================
-- Business question
--   Which cuisines have the highest average restaurant rating across Bangalore?
--
-- Requirements
--   - Expand cuisines with UNNEST.
--   - Only cuisines served by at least 100 restaurants.
--   - Average rating rounded to 2 dp; top 15 by average rating.
--
-- Grain & rules
--   - Restaurant = distinct URL path (restaurant_id); latest snapshot by votes.
--   - Rating = numeric part of rate_cleaned; NEW, '-' and NULL are excluded from averages.
--   - Fix vs original: grouped by cuisine (original grouped by restaurant name + cuisine)
--     and threshold set to 100 restaurants as specified (original used 70).
--
-- Original attempt : sql/00_source/bigquery_export_analysis_query.sql (lines 241-273)
-- Result           : results/a06_top_rated_cuisines.csv
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
)
SELECT
    cuisine,
    COUNT(*)                         AS restaurant_count,
    COUNTIF(rating IS NOT NULL)      AS rated_restaurant_count,
    ROUND(AVG(rating), 2)            AS average_rating
FROM restaurant_cuisines
GROUP BY cuisine
HAVING COUNT(*) >= 100
ORDER BY average_rating DESC, restaurant_count DESC
LIMIT 15;
