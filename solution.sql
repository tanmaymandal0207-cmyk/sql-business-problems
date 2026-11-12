-- Repeated-name footprint. Three listings is a screening threshold, not proof of chain ownership.
WITH normalized AS (
  SELECT LOWER(TRIM(name)) AS normalized_name, location, url
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
  WHERE name IS NOT NULL AND TRIM(name) != ''
)
SELECT normalized_name, COUNT(*) AS listing_count,
       COUNT(DISTINCT location) AS distinct_localities,
       COUNT(DISTINCT url) AS distinct_listing_urls,
       STRING_AGG(DISTINCT location, ', ' ORDER BY location LIMIT 20) AS locality_footprint
FROM normalized
GROUP BY normalized_name
HAVING COUNT(*) >= 3
ORDER BY listing_count DESC, distinct_localities DESC
LIMIT 50;
