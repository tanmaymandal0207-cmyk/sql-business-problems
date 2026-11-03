-- =============================================================================
-- A03 | Online ordering adoption
-- =============================================================================
-- Business question
--   Which localities have the highest share of restaurants accepting online orders?
--
-- Requirements
--   - Location, total restaurants, restaurants accepting online orders, acceptance %.
--   - Only localities with at least 300 restaurants.
--   - Highest acceptance % first; top 10.
--
-- Grain & rules
--   - Restaurant = distinct URL path (restaurant_id); latest snapshot by votes.
--   - Rating = numeric part of rate_cleaned; NEW, '-' and NULL are excluded from averages.
--   - Fix vs original: SAFE_DIVIDE(yes, total) * 100 - the original divided by (total*100) and
--     rounded to 0 dp, which returned 0 for every locality.
--
-- Original attempt : sql/00_source/bigquery_export_analysis_query.sql (lines 145-174)
-- Result           : results/a03_online_ordering_adoption.csv
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
    COUNT(*)                                                       AS restaurant_count,
    COUNTIF(online_order = 'Yes')                                  AS online_order_restaurants,
    ROUND(SAFE_DIVIDE(COUNTIF(online_order = 'Yes'), COUNT(*)) * 100, 2) AS online_acceptance_pct,
    ROUND(AVG(rating), 2)                                          AS average_rating
FROM restaurants
WHERE location IS NOT NULL
GROUP BY location
HAVING COUNT(*) >= 300
ORDER BY online_acceptance_pct DESC, restaurant_count DESC
LIMIT 10;
