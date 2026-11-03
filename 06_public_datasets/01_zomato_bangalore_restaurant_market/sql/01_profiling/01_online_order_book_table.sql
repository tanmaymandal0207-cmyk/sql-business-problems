-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 01 | ONLINE ORDERING AND TABLE BOOKING
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 01 | ONLINE ORDERING AND TABLE BOOKING
-- ---------------------------------------------------------------------------

-- 01.1 Online-order distribution
SELECT online_order, COUNT(*) AS record_count,
       SUM(COUNT(*)) OVER () AS total_records
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY online_order
ORDER BY record_count DESC;

-- 01.2 Table-booking distribution
SELECT book_table, COUNT(*) AS record_count,
       SUM(COUNT(*)) OVER () AS total_records
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY book_table
ORDER BY record_count DESC;

-- 01.3 book_table missing / blank / literal-null check
SELECT COUNTIF(book_table IS NULL) AS actual_nulls,
       COUNTIF(TRIM(book_table) = '') AS empty_strings,
       COUNTIF(LOWER(TRIM(book_table)) = 'null') AS text_nulls
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 01.4 online_order missing / blank / literal-null check
SELECT COUNTIF(online_order IS NULL) AS actual_nulls,
       COUNTIF(TRIM(online_order) = '') AS empty_strings,
       COUNTIF(LOWER(TRIM(online_order)) = 'null') AS text_nulls
FROM `zomatoanalytics.Zomato_csv.restaurants`;
