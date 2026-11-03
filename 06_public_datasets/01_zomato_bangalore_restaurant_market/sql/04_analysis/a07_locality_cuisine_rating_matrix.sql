-- =============================================================================
-- A07 | Locality cuisine rating matrix
-- =============================================================================
-- Business question
--   Within dense localities, which locality x cuisine combinations are rated highest?
--   (self-directed extension of A06)
--
-- Requirements
--   - Localities with at least 100 restaurants.
--   - Locality x cuisine pairs with at least 30 restaurants.
--   - Show average rating and online acceptance % for each pair; top 20 by rating.
--
-- Grain & rules
--   - Restaurant = distinct URL path (restaurant_id); latest snapshot by votes.
--   - Rating = numeric part of rate_cleaned; NEW, '-' and NULL are excluded from averages.
--   - Fix vs original: online % = online restaurants / restaurants in the pair (original
--     mixed COUNTIF over rows with COUNT(DISTINCT url)).
--
-- Original attempt : sql/00_source/bigquery_export_analysis_query.sql (lines 276-315)
-- Result           : results/a07_locality_cuisine_rating_matrix.csv
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
dense_localities AS (
    SELECT location
    FROM restaurants
    WHERE location IS NOT NULL
    GROUP BY location
    HAVING COUNT(*) >= 100
)
SELECT
    rc.location,
    rc.cuisine,
    COUNT(*)                                                         AS restaurant_count,
    ROUND(AVG(rc.rating), 2)                                         AS average_rating,
    ROUND(SAFE_DIVIDE(COUNTIF(rc.online_order = 'Yes'), COUNT(*)) * 100, 1) AS online_acceptance_pct
FROM restaurant_cuisines AS rc
JOIN dense_localities AS d
  ON d.location = rc.location
GROUP BY rc.location, rc.cuisine
HAVING COUNT(*) >= 30
ORDER BY average_rating DESC, restaurant_count DESC
LIMIT 20;
