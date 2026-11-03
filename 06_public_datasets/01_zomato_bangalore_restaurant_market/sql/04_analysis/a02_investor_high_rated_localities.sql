-- =============================================================================
-- A02 | Investor high-rated localities
-- =============================================================================
-- Business question
--   Which localities are the most highly rated, ignoring localities with very few
--   restaurants?
--
-- Requirements
--   - At least 500 restaurants per locality.
--   - Average uses valid numeric ratings only.
--   - Show location, restaurant count, rated count and average rating.
--   - Top 10 by average rating.
--
-- Grain & rules
--   - Restaurant = distinct URL path (restaurant_id); latest snapshot by votes.
--   - Rating = numeric part of rate_cleaned; NEW, '-' and NULL are excluded from averages.
--   - Threshold applies to restaurants (not listing rows) - only 7 localities qualify.
--   - Restaurant count uses all restaurants; the average uses rated restaurants only (WHERE vs HAVING split).
--
-- Original attempt : sql/00_source/bigquery_export_analysis_query.sql (lines 113-142)
-- Result           : results/a02_investor_high_rated_localities.csv
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
)
SELECT
    location,
    COUNT(*)                         AS restaurant_count,
    COUNTIF(rating IS NOT NULL)      AS rated_restaurant_count,
    ROUND(AVG(rating), 2)            AS average_rating
FROM restaurants
WHERE location IS NOT NULL
GROUP BY location
HAVING COUNT(*) >= 500
   AND AVG(rating) IS NOT NULL
ORDER BY average_rating DESC, restaurant_count DESC
LIMIT 10;
