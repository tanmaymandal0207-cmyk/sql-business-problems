-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 03 | VOTES
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 03 | VOTES
-- ---------------------------------------------------------------------------

-- 03.1 Votes distribution
SELECT votes, COUNT(*) AS frequency
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY votes
ORDER BY frequency DESC;

-- 03.2 Check cast eligibility
SELECT COUNT(*) AS total_records,
       COUNTIF(votes IS NULL) AS null_values,
       COUNTIF(TRIM(votes) = '') AS empty_values,
       COUNTIF(SAFE_CAST(TRIM(votes) AS INT64) IS NULL
               AND TRIM(votes) != '') AS non_numeric_values
FROM `zomatoanalytics.Zomato_csv.restaurants`;
