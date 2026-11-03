-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 05 | RESTAURANT NAME
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 05 | RESTAURANT NAME
-- ---------------------------------------------------------------------------

-- 05.1 Name frequency
SELECT name, COUNT(*) AS frequency
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY name
ORDER BY frequency DESC, name ASC;

-- 05.2 Name quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(name IS NULL) AS null_values,
       COUNTIF(TRIM(name) = '') AS empty_values,
       COUNTIF(name != TRIM(name)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(name, r'\s{2,}')) AS multiple_consecutive_spaces
FROM `zomatoanalytics.Zomato_csv.restaurants`;
