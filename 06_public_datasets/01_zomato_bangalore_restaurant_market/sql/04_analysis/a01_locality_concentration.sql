-- =============================================================================
-- A01 | Locality concentration
-- =============================================================================
-- Business question
--   Which Bangalore localities have the largest restaurant presence, and how well
--   are they rated?
--
-- Requirements
--   - Exclude NULL locations.
--   - restaurant_count, rated_restaurant_count, average_rating (1 dp).
--   - Show listing_records alongside to expose the listing-vs-restaurant gap.
--   - Sort by restaurant count desc; top 15.
--
-- Grain & rules
--   - Restaurant = distinct URL path (restaurant_id); latest snapshot by votes.
--   - Rating = numeric part of rate_cleaned; NEW, '-' and NULL are excluded from averages.
--   - Merges the two locality questions from the practice sheet (scenario + Challenge 01).
--
-- Original attempt : sql/00_source/bigquery_export_analysis_query.sql (lines 30-110)
-- Result           : results/a01_locality_concentration.csv
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
listing_rows AS (                           -- raw listing grain, for comparison only
    SELECT location, COUNT(*) AS listing_records
    FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
    WHERE location IS NOT NULL
    GROUP BY location
)
SELECT
    r.location,
    COUNT(*)                                             AS restaurant_count,
    l.listing_records,
    COUNTIF(r.rating IS NOT NULL)                        AS rated_restaurant_count,
    ROUND(SAFE_DIVIDE(COUNTIF(r.rating IS NOT NULL), COUNT(*)) * 100, 1) AS rating_coverage_pct,
    ROUND(AVG(r.rating), 1)                              AS average_rating
FROM restaurants AS r
JOIN listing_rows AS l
  ON l.location = r.location
WHERE r.location IS NOT NULL
GROUP BY r.location, l.listing_records
ORDER BY restaurant_count DESC, r.location
LIMIT 15;
