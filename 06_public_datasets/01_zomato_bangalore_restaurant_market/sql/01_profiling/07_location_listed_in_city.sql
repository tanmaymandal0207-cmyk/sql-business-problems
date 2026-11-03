-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 07 | LOCATION AND LISTED_IN_CITY
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 07 | LOCATION AND LISTED_IN_CITY
-- ---------------------------------------------------------------------------

-- 07.1 Location quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(location IS NULL) AS null_values,
       COUNTIF(TRIM(location) = '') AS empty_values,
       COUNTIF(location != TRIM(location)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(location, r'\s{2,}')) AS multiple_consecutive_spaces
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 07.2 Location distribution (GROUP BY includes a NULL group)
SELECT location, COUNT(*) AS restaurant_count
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY location
ORDER BY restaurant_count DESC;

-- 07.3 Distinct non-NULL locations and total records
SELECT COUNT(DISTINCT location) AS unique_non_null_locations,
       COUNT(*) AS total_records,
       COUNTIF(location IS NULL) AS null_locations
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 07.4 Inspect name, location and address together
SELECT name, location, address
FROM `zomatoanalytics.Zomato_csv.restaurants`
LIMIT 100;

-- 07.5 listed_in_city quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(listed_in_city IS NULL) AS null_values,
       COUNTIF(TRIM(listed_in_city) = '') AS empty_values,
       COUNTIF(listed_in_city != TRIM(listed_in_city)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(listed_in_city, r'\s{2,}')) AS multiple_consecutive_spaces,
       COUNT(DISTINCT listed_in_city) AS unique_listed_in_city_values
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 07.6 Compare listed_in_city groups with distinct location values
SELECT listed_in_city,
       COUNT(DISTINCT location) AS unique_locations,
       COUNT(*) AS restaurant_records
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY listed_in_city
ORDER BY restaurant_records DESC;

-- 07.7 Find location values associated with multiple listed_in_city values
SELECT location,
       COUNT(DISTINCT listed_in_city) AS listed_city_count,
       STRING_AGG(DISTINCT listed_in_city, ', ') AS listed_cities
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE location IS NOT NULL
GROUP BY location
HAVING COUNT(DISTINCT listed_in_city) > 1
ORDER BY listed_city_count DESC;
