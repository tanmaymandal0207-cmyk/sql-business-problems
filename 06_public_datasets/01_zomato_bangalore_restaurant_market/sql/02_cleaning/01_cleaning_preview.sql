-- Zomato Bangalore | BigQuery Standard SQL
-- Purpose : preview the cleaned columns before materialising (no table is written)
-- Origin  : sql/00_source/bigquery_export_zomato_query.sql, section 13 (verbatim)

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
