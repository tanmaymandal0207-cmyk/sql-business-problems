-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 12 | INITIAL BUSINESS DISCOVERY: JUST BAKE OUTLETS
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 12 | INITIAL BUSINESS DISCOVERY: JUST BAKE OUTLETS
-- ---------------------------------------------------------------------------

WITH cte_just_bake AS (
    SELECT listed_in_city, name
    FROM `zomatoanalytics.Zomato_csv.restaurants`
    WHERE name = 'Just Bake'
)
SELECT listed_in_city,
       COUNTIF(name = 'Just Bake') AS outlets
FROM cte_just_bake
GROUP BY listed_in_city
HAVING COUNTIF(name = 'Just Bake') >= 3
ORDER BY listed_in_city ASC;
