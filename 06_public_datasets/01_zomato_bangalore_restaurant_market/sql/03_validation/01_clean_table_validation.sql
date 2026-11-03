-- Zomato Bangalore | BigQuery Standard SQL
-- Purpose : post-build checks on `restaurants_clean` - row count, NULLs after
--           conversion, data types and presence of the 6 *_cleaned columns
-- Origin  : sql/00_source/bigquery_export_analysis_query.sql, lines 1-28 (verbatim)

SELECT                                  -- Clean Table Check
    COUNT(*) AS total_records,
    COUNT(DISTINCT url) AS unique_urls,
    COUNTIF(approx_cost_cleaned IS NULL) AS null_costs,
    COUNTIF(votes_cleaned IS NULL) AS null_votes
FROM `zomatoanalytics.Zomato_csv.restaurants_clean`;

SELECT                                          ----- Data Type Check
    column_name,
    data_type
FROM `zomatoanalytics.Zomato_csv.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'restaurants_clean'
ORDER BY ordinal_position;

SELECT                                          ----- Schema Validation
    column_name,
    data_type
FROM `zomatoanalytics.Zomato_csv.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'restaurants_clean'
AND column_name IN (
    'approx_cost_cleaned',
    'rate_cleaned',
    'votes_cleaned',
    'address_cleaned',
    'phone_cleaned',
    'menu_item_cleaned'
)
ORDER BY ordinal_position;
