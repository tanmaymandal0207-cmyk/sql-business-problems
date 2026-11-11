-- Business Problem 05: Table-booking and dine-in service profile

-- Locality-level availability.
WITH locality_booking AS (
  SELECT
    location,
    COUNT(*) AS total_listings,
    COUNTIF(LOWER(TRIM(book_table)) = 'yes') AS booking_listings,
    COUNTIF(LOWER(TRIM(book_table)) = 'no') AS non_booking_listings
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
  WHERE location IS NOT NULL
  GROUP BY location
)
SELECT
  location,
  total_listings,
  booking_listings,
  non_booking_listings,
  ROUND(100 * SAFE_DIVIDE(
    booking_listings,
    booking_listings + non_booking_listings
  ), 2) AS table_booking_availability_pct
FROM locality_booking
WHERE total_listings >= 50
ORDER BY table_booking_availability_pct DESC, total_listings DESC;

-- Rating and price comparison by table-booking status.
WITH base AS (
  SELECT
    LOWER(TRIM(book_table)) AS booking_status,
    SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating,
    approx_cost_cleaned
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
)
SELECT
  booking_status,
  COUNT(*) AS restaurant_listings,
  ROUND(AVG(rating), 2) AS average_rating,
  ROUND(AVG(approx_cost_cleaned), 0) AS average_cost_for_two
FROM base
WHERE booking_status IN ('yes', 'no')
GROUP BY booking_status
ORDER BY restaurant_listings DESC;
