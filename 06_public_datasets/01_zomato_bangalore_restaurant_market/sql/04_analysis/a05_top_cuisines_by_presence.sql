-- =============================================================================
-- A05 | Top cuisines by presence
-- =============================================================================
-- Business question
--   Which individual cuisines have the strongest restaurant presence in Bangalore?
--
-- Requirements
--   - Split the comma-separated cuisines column into individual cuisines.
--   - Trim whitespace; exclude NULL / empty values.
--   - Count restaurants offering each cuisine; top 15.
--
-- Grain & rules
--   - Restaurant = distinct URL path (restaurant_id); latest snapshot by votes.
--   - Rating = numeric part of rate_cleaned; NEW, '-' and NULL are excluded from averages.
--   - Fix vs original: grouped by cuisine only (original also grouped by location) and
--     TRIM applied to the unnested value, not to the full cuisines string.
--
-- Original attempt : sql/00_source/bigquery_export_analysis_query.sql (lines 217-239)
-- Result           : results/a05_top_cuisines_by_presence.csv
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
    COUNT(DISTINCT restaurant_id)                                  AS restaurant_count,
    ROUND(SAFE_DIVIDE(COUNT(DISTINCT restaurant_id),
                      (SELECT COUNT(*) FROM restaurants WHERE cuisines IS NOT NULL)) * 100, 1)
                                                                   AS share_of_restaurants_pct
FROM restaurant_cuisines
GROUP BY cuisine
ORDER BY restaurant_count DESC, cuisine
LIMIT 15;
