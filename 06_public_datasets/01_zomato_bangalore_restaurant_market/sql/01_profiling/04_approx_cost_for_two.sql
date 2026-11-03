-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 04 | APPROXIMATE COST FOR TWO
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 04 | APPROXIMATE COST FOR TWO
-- ---------------------------------------------------------------------------

-- 04.1 Cost values and frequency
SELECT approx_cost_for_two_people, COUNT(*) AS frequency
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY approx_cost_for_two_people
ORDER BY frequency DESC
LIMIT 1000;

-- 04.2 Check NULLs, blanks, text-null and failed numeric conversions
SELECT COUNT(*) AS total_records,
       COUNTIF(approx_cost_for_two_people IS NULL) AS actual_nulls,
       COUNTIF(TRIM(approx_cost_for_two_people) = '') AS empty_strings,
       COUNTIF(LOWER(TRIM(approx_cost_for_two_people)) = 'null') AS text_nulls,
       COUNTIF(
           SAFE_CAST(REPLACE(TRIM(approx_cost_for_two_people), ',', '') AS INT64) IS NULL
           AND approx_cost_for_two_people IS NOT NULL
           AND TRIM(approx_cost_for_two_people) != ''
       ) AS non_numeric_values
FROM `zomatoanalytics.Zomato_csv.restaurants`;
