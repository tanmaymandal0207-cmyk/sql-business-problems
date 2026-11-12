WITH base AS (
  SELECT COALESCE(NULLIF(TRIM(rest_type), ''), '[Missing rest_type]') AS restaurant_format,
         SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating,
         approx_cost_cleaned AS cost_for_two
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
),
summary AS (
  SELECT restaurant_format, COUNT(*) AS listing_count, COUNT(rating) AS rated_listings,
         ROUND(AVG(rating), 2) AS average_rating,
         ROUND(AVG(cost_for_two), 0) AS average_cost_for_two
  FROM base GROUP BY restaurant_format
)
SELECT restaurant_format, listing_count,
       ROUND(100 * SAFE_DIVIDE(listing_count, SUM(listing_count) OVER ()), 2) AS dataset_share_pct,
       rated_listings, average_rating, average_cost_for_two
FROM summary
ORDER BY listing_count DESC
LIMIT 40;
