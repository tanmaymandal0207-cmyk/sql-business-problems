-- Zomato Bangalore | BigQuery Standard SQL
-- Source table : `zomatoanalytics.Zomato_csv.restaurants` (raw, read-only)
-- Section      : 11 | PHONE, LISTED_IN_TYPE, MENU_ITEM AND REVIEWS_LIST
-- Origin       : sql/00_source/bigquery_export_zomato_query.sql (verbatim)

-- 11 | PHONE, LISTED_IN_TYPE, MENU_ITEM AND REVIEWS_LIST
-- ---------------------------------------------------------------------------

-- 11.1 NULL and distinct-value profile
SELECT 'phone' AS column_name, COUNT(*) AS total_records,
       COUNTIF(phone IS NULL) AS null_values, COUNT(DISTINCT phone) AS unique_values
FROM `zomatoanalytics.Zomato_csv.restaurants`
UNION ALL
SELECT 'listed_in_type', COUNT(*), COUNTIF(listed_in_type IS NULL), COUNT(DISTINCT listed_in_type)
FROM `zomatoanalytics.Zomato_csv.restaurants`
UNION ALL
SELECT 'menu_item', COUNT(*), COUNTIF(menu_item IS NULL), COUNT(DISTINCT menu_item)
FROM `zomatoanalytics.Zomato_csv.restaurants`
UNION ALL
SELECT 'reviews_list', COUNT(*), COUNTIF(reviews_list IS NULL), COUNT(DISTINCT reviews_list)
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 11.2 Empty strings, surrounding spaces and repeated whitespace
SELECT 'phone' AS column_name,
       COUNTIF(TRIM(phone) = '') AS empty_values,
       COUNTIF(phone != TRIM(phone)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(phone, r'\s{2,}')) AS repeated_spaces
FROM `zomatoanalytics.Zomato_csv.restaurants`
UNION ALL
SELECT 'listed_in_type', COUNTIF(TRIM(listed_in_type) = ''),
       COUNTIF(listed_in_type != TRIM(listed_in_type)),
       COUNTIF(REGEXP_CONTAINS(listed_in_type, r'\s{2,}'))
FROM `zomatoanalytics.Zomato_csv.restaurants`
UNION ALL
SELECT 'menu_item', COUNTIF(TRIM(menu_item) = ''),
       COUNTIF(menu_item != TRIM(menu_item)),
       COUNTIF(REGEXP_CONTAINS(menu_item, r'\s{2,}'))
FROM `zomatoanalytics.Zomato_csv.restaurants`
UNION ALL
SELECT 'reviews_list', COUNTIF(TRIM(reviews_list) = ''),
       COUNTIF(reviews_list != TRIM(reviews_list)),
       COUNTIF(REGEXP_CONTAINS(reviews_list, r'\s{2,}'))
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 11.3 Preview phone whitespace standardisation
SELECT phone,
       REGEXP_REPLACE(TRIM(phone), r'\s+', ' ') AS phone_cleaned
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE REGEXP_CONTAINS(phone, r'\s{2,}')
LIMIT 20;

-- 11.4 Preview menu_item whitespace standardisation
SELECT menu_item,
       REGEXP_REPLACE(TRIM(menu_item), r'\s+', ' ') AS menu_item_cleaned
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE REGEXP_CONTAINS(menu_item, r'\s{2,}')
LIMIT 20;
