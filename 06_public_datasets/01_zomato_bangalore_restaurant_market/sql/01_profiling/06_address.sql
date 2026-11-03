-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 06 | ADDRESS
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 06 | ADDRESS
-- ---------------------------------------------------------------------------

-- 06.1 Address quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(address IS NULL) AS null_values,
       COUNTIF(TRIM(address) = '') AS empty_values,
       COUNTIF(address != TRIM(address)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(address, r'\s{2,}')) AS multiple_consecutive_spaces
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 06.2 Inspect the two records with repeated whitespace.
-- Matching name, URL and address are evidence to investigate, not proof of
-- duplicate rows. Do not delete them at this stage.
SELECT name, url, address
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE REGEXP_CONTAINS(address, r'\s{2,}');

-- 06.3 Preview address cleaning
SELECT address,
       REGEXP_REPLACE(TRIM(address), r'\s+', ' ') AS address_cleaned
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE REGEXP_CONTAINS(address, r'\s{2,}');
