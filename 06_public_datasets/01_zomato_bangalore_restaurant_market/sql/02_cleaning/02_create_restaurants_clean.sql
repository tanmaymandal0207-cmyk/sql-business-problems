-- Zomato Bangalore | BigQuery Standard SQL
-- Purpose : materialise the cleaned layer `restaurants_clean`
--           Raw table is never modified; all 17 original columns are retained
--           alongside 6 *_cleaned columns for traceability.
-- Origin  : sql/00_source/bigquery_export_zomato_query.sql, section 13 (verbatim)
-- NOTE    : BigQuery sandbox tables expire after 60 days - re-run this script to rebuild.

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
