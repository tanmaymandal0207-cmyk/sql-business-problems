-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 10 | DISH_LIKED
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 10 | DISH_LIKED
-- ---------------------------------------------------------------------------

-- 10.1 dish_liked quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(dish_liked IS NULL) AS null_values,
       COUNTIF(TRIM(dish_liked) = '') AS empty_values,
       COUNTIF(dish_liked != TRIM(dish_liked)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(dish_liked, r'\s{2,}')) AS multiple_consecutive_spaces,
       COUNT(DISTINCT dish_liked) AS unique_values
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 10.2 Most frequent values
SELECT dish_liked, COUNT(*) AS frequency
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY dish_liked
ORDER BY frequency DESC
LIMIT 20;
