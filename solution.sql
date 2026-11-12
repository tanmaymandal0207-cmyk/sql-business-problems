WITH dish_rows AS (
  SELECT TRIM(dish) AS dish,
         SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating,
         votes_cleaned AS votes
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`,
  UNNEST(SPLIT(dish_liked, ',')) AS dish
  WHERE dish_liked IS NOT NULL AND TRIM(dish) != ''
)
SELECT dish, COUNT(*) AS restaurant_mentions, COUNT(rating) AS rated_listings,
       ROUND(AVG(rating), 2) AS average_rating, ROUND(AVG(votes), 0) AS average_votes
FROM dish_rows
GROUP BY dish
HAVING COUNT(*) >= 5
ORDER BY restaurant_mentions DESC, average_rating DESC
LIMIT 50;
