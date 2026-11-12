WITH listing_quality AS (
  SELECT location,
    CASE WHEN menu_item IS NOT NULL AND TRIM(menu_item) != '' THEN 1 ELSE 0 END AS has_menu_text,
    CASE WHEN dish_liked IS NOT NULL AND TRIM(dish_liked) != '' THEN 1 ELSE 0 END AS has_dish_liked,
    CASE WHEN cuisines IS NOT NULL AND TRIM(cuisines) != '' THEN 1 ELSE 0 END AS has_cuisine_text,
    LENGTH(TRIM(menu_item)) AS menu_text_characters
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
)
SELECT COALESCE(location, '[Missing location]') AS locality, COUNT(*) AS restaurant_listings,
       SUM(has_menu_text) AS listings_with_menu_text,
       ROUND(100 * AVG(has_menu_text), 2) AS menu_text_coverage_pct,
       SUM(has_dish_liked) AS listings_with_dish_liked,
       ROUND(100 * AVG(has_dish_liked), 2) AS dish_liked_coverage_pct,
       ROUND(100 * AVG(has_cuisine_text), 2) AS cuisine_text_coverage_pct,
       ROUND(AVG(menu_text_characters), 0) AS average_menu_text_characters
FROM listing_quality
GROUP BY locality
HAVING COUNT(*) >= 50
ORDER BY menu_text_coverage_pct ASC, restaurant_listings DESC;
