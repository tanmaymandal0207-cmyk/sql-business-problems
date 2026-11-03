-- ZOMATO BANGALORE RESTAURANT DATASET | BIGQUERY SQL WORKBOOK
-- Source: `zomatoanalytics.Zomato_csv.restaurants`
-- 51,717 records | 17 original columns
-- Raw table remains unchanged. NULL treatment and duplicate removal are deferred.


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


-- 07 | LOCATION AND LISTED_IN_CITY
-- ---------------------------------------------------------------------------

-- 07.1 Location quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(location IS NULL) AS null_values,
       COUNTIF(TRIM(location) = '') AS empty_values,
       COUNTIF(location != TRIM(location)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(location, r'\s{2,}')) AS multiple_consecutive_spaces
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 07.2 Location distribution (GROUP BY includes a NULL group)
SELECT location, COUNT(*) AS restaurant_count
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY location
ORDER BY restaurant_count DESC;

-- 07.3 Distinct non-NULL locations and total records
SELECT COUNT(DISTINCT location) AS unique_non_null_locations,
       COUNT(*) AS total_records,
       COUNTIF(location IS NULL) AS null_locations
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 07.4 Inspect name, location and address together
SELECT name, location, address
FROM `zomatoanalytics.Zomato_csv.restaurants`
LIMIT 100;

-- 07.5 listed_in_city quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(listed_in_city IS NULL) AS null_values,
       COUNTIF(TRIM(listed_in_city) = '') AS empty_values,
       COUNTIF(listed_in_city != TRIM(listed_in_city)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(listed_in_city, r'\s{2,}')) AS multiple_consecutive_spaces,
       COUNT(DISTINCT listed_in_city) AS unique_listed_in_city_values
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 07.6 Compare listed_in_city groups with distinct location values
SELECT listed_in_city,
       COUNT(DISTINCT location) AS unique_locations,
       COUNT(*) AS restaurant_records
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY listed_in_city
ORDER BY restaurant_records DESC;

-- 07.7 Find location values associated with multiple listed_in_city values
SELECT location,
       COUNT(DISTINCT listed_in_city) AS listed_city_count,
       STRING_AGG(DISTINCT listed_in_city, ', ') AS listed_cities
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE location IS NOT NULL
GROUP BY location
HAVING COUNT(DISTINCT listed_in_city) > 1
ORDER BY listed_city_count DESC;


-- 08 | REST_TYPE
-- ---------------------------------------------------------------------------

-- 08.1 rest_type quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(rest_type IS NULL) AS null_values,
       COUNTIF(TRIM(rest_type) = '') AS empty_values,
       COUNTIF(rest_type != TRIM(rest_type)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(rest_type, r'\s{2,}')) AS multiple_consecutive_spaces,
       COUNT(DISTINCT rest_type) AS unique_types
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 08.2 Category distribution
SELECT rest_type, COUNT(*) AS restaurant_count
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY rest_type
ORDER BY restaurant_count DESC;

-- 08.3 Inspect category count within each rest_type value
SELECT rest_type,
       COUNT(*) AS frequency,
       ARRAY_LENGTH(SPLIT(rest_type, ',')) AS category_count
FROM `zomatoanalytics.Zomato_csv.restaurants`
WHERE rest_type IS NOT NULL
GROUP BY rest_type, category_count
ORDER BY category_count DESC, frequency DESC;

-- 08.4 Summarise single and combined classifications
WITH cte_rest_type AS (
    SELECT rest_type,
           COUNT(*) AS frequency,
           ARRAY_LENGTH(SPLIT(rest_type, ',')) AS category_count
    FROM `zomatoanalytics.Zomato_csv.restaurants`
    WHERE rest_type IS NOT NULL
    GROUP BY rest_type
)
SELECT category_count,
       COUNT(*) AS distinct_combinations,
       SUM(frequency) AS restaurant_records
FROM cte_rest_type
GROUP BY category_count
ORDER BY category_count;


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


-- 10 | DISH_LIKED
-- ---------------------------------------------------------------------------

-- 10.1 dish_liked quality checks
SELECT COUNT(*) AS total_records,
       COUNTIF(dish_liked IS NULL) AS null_values,
       COUNTIF(TRIM(dish_liked) = '') AS empty_values,
       COUNTIF(dish_liked != TRIM(dish_liked)) AS surrounding_spaces,
       COUNTIF(REGEXP_CONTAINS(dish_liked, r'\s{2,}')) AS multiple_consecutive_spaces,
       COUNT(DISTINCT dish_liked) AS unique_values
FROM `zomatoanalytics.Zomato_csv.restaurants`;

-- 10.2 Most frequent values
SELECT dish_liked, COUNT(*) AS frequency
FROM `zomatoanalytics.Zomato_csv.restaurants`
GROUP BY dish_liked
ORDER BY frequency DESC
LIMIT 20;


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


-- =============================================================================
-- 13 | CURRENT CONSOLIDATED CLEANING QUERY — KEEP THIS LAST
--
-- Appends cleaned columns while retaining all original columns:
--   approx_cost_cleaned : comma removal + INT64 conversion
--   rate_cleaned        : standardise whitespace around slash
--   votes_cleaned       : INT64 conversion
--   address_cleaned     : collapse repeated whitespace
--   phone_cleaned       : collapse repeated whitespace
--   menu_item_cleaned   : collapse repeated whitespace
--
-- Missing-value treatment is deferred.
-- This SELECT does not create or replace a permanent table.
-- =============================================================================

SELECT
    *,
    SAFE_CAST(
        REPLACE(TRIM(approx_cost_for_two_people), ',', '')
        AS INT64
    ) AS approx_cost_cleaned,

    REGEXP_REPLACE(
        TRIM(rate),
        r'\s*/\s*',
        '/'
    ) AS rate_cleaned,

    SAFE_CAST(
        TRIM(votes) AS INT64
    ) AS votes_cleaned,

    REGEXP_REPLACE(
        TRIM(address),
        r'\s+',
        ' '
    ) AS address_cleaned,

    REGEXP_REPLACE(
        TRIM(phone),
        r'\s+',
        ' '
    ) AS phone_cleaned,

    REGEXP_REPLACE(
        TRIM(menu_item),
        r'\s+',
        ' '
    ) AS menu_item_cleaned

FROM `zomatoanalytics.Zomato_csv.restaurants`;

---------------------------------------------------------------------
--Cleaned Table
CREATE OR REPLACE TABLE
`zomatoanalytics.Zomato_csv.restaurants_clean` AS

SELECT
    *,

    SAFE_CAST(
        REPLACE(TRIM(approx_cost_for_two_people), ',', '')
        AS INT64
    ) AS approx_cost_cleaned,

    REGEXP_REPLACE(
        TRIM(rate),
        r'\s*/\s*',
        '/'
    ) AS rate_cleaned,

    SAFE_CAST(
        TRIM(votes) AS INT64
    ) AS votes_cleaned,

    REGEXP_REPLACE(
        TRIM(address),
        r'\s+',
        ' '
    ) AS address_cleaned,

    REGEXP_REPLACE(
        TRIM(phone),
        r'\s+',
        ' '
    ) AS phone_cleaned,

    REGEXP_REPLACE(
        TRIM(menu_item),
        r'\s+',
        ' '
    ) AS menu_item_cleaned

FROM `zomatoanalytics.Zomato_csv.restaurants`;