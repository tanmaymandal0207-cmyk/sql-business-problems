-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 00 | SCHEMA AND SAMPLE
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 00 | SCHEMA AND SAMPLE
-- ---------------------------------------------------------------------------

-- 00.1 Source schema
SELECT column_name, data_type, ordinal_position
FROM `zomatoanalytics.Zomato_csv.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'restaurants'
ORDER BY ordinal_position;

-- 00.2 Sample records
SELECT *
FROM `zomatoanalytics.Zomato_csv.restaurants`
LIMIT 10;
