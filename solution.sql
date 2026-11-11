-- Business Problem 04: Online ordering adoption by locality

WITH locality_ordering AS (
  SELECT
    location,
    COUNT(*) AS total_listings,
    COUNTIF(LOWER(TRIM(online_order)) = 'yes') AS online_order_listings,
    COUNTIF(LOWER(TRIM(online_order)) = 'no') AS non_online_order_listings,
    COUNTIF(online_order IS NULL OR TRIM(online_order) = '') AS unknown_listings
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
  WHERE location IS NOT NULL
  GROUP BY location
)
SELECT
  location,
  total_listings,
  online_order_listings,
  non_online_order_listings,
  unknown_listings,
  ROUND(100 * SAFE_DIVIDE(online_order_listings, total_listings - unknown_listings), 2)
    AS online_order_adoption_pct
FROM locality_ordering
WHERE total_listings >= 50
ORDER BY online_order_adoption_pct DESC, total_listings DESC;

-- Overall online-order availability profile.
SELECT
  LOWER(TRIM(online_order)) AS online_order_status,
  COUNT(*) AS restaurant_listings,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2) AS share_pct
FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
GROUP BY online_order_status
ORDER BY restaurant_listings DESC;
