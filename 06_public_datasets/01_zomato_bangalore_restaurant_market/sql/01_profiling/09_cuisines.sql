-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 09 | CUISINES
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 09 | CUISINES
-- ---------------------------------------------------------------------------

-- 09.1 Cuisine quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(cuisines IS NULL) AS null_values,
       COUNTIF(TRIM(cuisines) = '') AS empty_values,
       COUNTIF(cuisines != TRIM(cuisines)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(cuisines, r'\s{2,}')) AS multiple_consecutive_spaces,
       COUNT(DISTINCT cuisines) AS unique_cuisine_combinations
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 09.2 Most frequent cuisine combinations
SELECT cuisines, COUNT(*) AS frequency
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY cuisines
ORDER BY frequency DESC
LIMIT 30;

-- 09.3 Number of comma-separated cuisines per record
SELECT ARRAY_LENGTH(SPLIT(cuisines, ',')) AS cuisine_count,
       COUNT(*) AS restaurant_records
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE cuisines IS NOT NULL
GROUP BY cuisine_count
ORDER BY cuisine_count;

-- 09.4 Distinct combinations and records at each cuisine-count level
WITH cte_cuisines AS (
    SELECT cuisines,
           COUNT(*) AS frequency,
           ARRAY_LENGTH(SPLIT(cuisines, ',')) AS cuisine_count
    FROM `zomatoanalytics.Zomato_csv.restaurants`
    WHERE cuisines IS NOT NULL
    GROUP BY cuisines
)
SELECT cuisine_count,
       COUNT(*) AS distinct_combinations,
       SUM(frequency) AS restaurant_records
FROM cte_cuisines
GROUP BY cuisine_count
ORDER BY cuisine_count;

-- 09.5 Find commas immediately followed by a non-whitespace character
SELECT cuisines, COUNT(*) AS frequency
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE REGEXP_CONTAINS(cuisines, r',\S')
GROUP BY cuisines
ORDER BY frequency DESC
LIMIT 30;
