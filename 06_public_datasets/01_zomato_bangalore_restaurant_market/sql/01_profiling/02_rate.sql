-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 02 | RATE
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 02 | RATE
-- ---------------------------------------------------------------------------

-- 02.1 Rating values and frequency
SELECT rate, COUNT(*) AS frequency
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY rate
ORDER BY frequency DESC;

-- 02.2 Preview slash-spacing standardisation
SELECT rate,
       TRIM(rate) AS trimmed_rate,
       REGEXP_REPLACE(TRIM(rate), r'\s*/\s*', '/') AS rate_cleaned
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY rate;
