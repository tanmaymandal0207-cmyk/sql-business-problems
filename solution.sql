-- Business Problem 01: Locality market concentration
-- Output: locality listing count, share of dataset, rating coverage and average rating.

WITH base AS (
  SELECT
    location,
    SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
),
locality_summary AS (
  SELECT
    COALESCE(location, '[Missing location]') AS locality,
    COUNT(*) AS restaurant_listings,
    COUNT(rating) AS rated_listings,
    ROUND(AVG(rating), 2) AS average_rating
  FROM base
  GROUP BY locality
)
SELECT
  locality,
  restaurant_listings,
  ROUND(100 * SAFE_DIVIDE(
    restaurant_listings,
    SUM(restaurant_listings) OVER ()
  ), 2) AS share_of_listings_pct,
  rated_listings,
  ROUND(100 * SAFE_DIVIDE(rated_listings, restaurant_listings), 2) AS rating_coverage_pct,
  average_rating
FROM locality_summary
ORDER BY restaurant_listings DESC
LIMIT 30;
