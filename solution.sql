WITH rated_listings AS (
  SELECT LOWER(TRIM(name)) AS normalized_name, location,
         SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating,
         votes_cleaned AS votes
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
  WHERE name IS NOT NULL AND TRIM(name) != ''
)
SELECT normalized_name, COUNT(*) AS total_listings, COUNT(rating) AS rated_listings,
       ROUND(AVG(rating), 2) AS average_rating,
       ROUND(MIN(rating), 2) AS minimum_rating, ROUND(MAX(rating), 2) AS maximum_rating,
       ROUND(MAX(rating) - MIN(rating), 2) AS rating_spread,
       SUM(COALESCE(votes, 0)) AS total_votes,
       COUNT(DISTINCT location) AS distinct_localities
FROM rated_listings
GROUP BY normalized_name
HAVING COUNT(*) >= 3 AND COUNT(rating) >= 3
ORDER BY rating_spread DESC, rated_listings DESC
LIMIT 50;
