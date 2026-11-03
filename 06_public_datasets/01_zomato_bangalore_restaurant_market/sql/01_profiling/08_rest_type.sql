-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 08 | REST_TYPE
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 08 | REST_TYPE
-- ---------------------------------------------------------------------------

-- 08.1 rest_type quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(rest_type IS NULL) AS null_values,
       COUNTIF(TRIM(rest_type) = '') AS empty_values,
       COUNTIF(rest_type != TRIM(rest_type)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(rest_type, r'\s{2,}')) AS multiple_consecutive_spaces,
       COUNT(DISTINCT rest_type) AS unique_types
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 08.2 Category distribution
SELECT rest_type, COUNT(*) AS restaurant_count
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY rest_type
ORDER BY restaurant_count DESC;

-- 08.3 Inspect category count within each rest_type value
SELECT rest_type,
       COUNT(*) AS frequency,
       ARRAY_LENGTH(SPLIT(rest_type, ',')) AS category_count
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE rest_type IS NOT NULL
GROUP BY rest_type, category_count
ORDER BY category_count DESC, frequency DESC;

-- 08.4 Summarise single and combined classifications
WITH cte_rest_type AS (
    SELECT rest_type,
           COUNT(*) AS frequency,
           ARRAY_LENGTH(SPLIT(rest_type, ',')) AS category_count
    FROM `zomatoanalytics.Zomato_csv.restaurants`
    WHERE rest_type IS NOT NULL
    GROUP BY rest_type
)
SELECT category_count,
       COUNT(*) AS distinct_combinations,
       SUM(frequency) AS restaurant_records
FROM cte_rest_type
GROUP BY category_count
ORDER BY category_count;
