-- Business Problem 02: Cuisine market presence
-- Each restaurant contributes to each cuisine label listed in its cuisines field.

WITH cuisine_rows AS (
  SELECT
    TRIM(cuisine) AS cuisine,
    SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating,
    approx_cost_cleaned
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`,
  UNNEST(SPLIT(cuisines, ',')) AS cuisine
  WHERE cuisines IS NOT NULL
    AND TRIM(cuisine) != ''
)
SELECT
  cuisine,
  COUNT(*) AS restaurant_listings,
  COUNT(rating) AS rated_listings,
  ROUND(AVG(rating), 2) AS average_rating,
  ROUND(AVG(approx_cost_cleaned), 0) AS average_cost_for_two
FROM cuisine_rows
GROUP BY cuisine
HAVING COUNT(*) >= 25
ORDER BY restaurant_listings DESC, average_rating DESC
LIMIT 30;
