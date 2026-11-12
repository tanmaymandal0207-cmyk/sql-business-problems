-- Business Problem 03: Price vs rating positioning
-- Cost bands are analytical groupings; adjust thresholds if needed for the market.

WITH base AS (
  SELECT
    approx_cost_cleaned AS cost_for_two,
    votes_cleaned AS votes,
    SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
),
banded AS (
  SELECT
    CASE
      WHEN cost_for_two IS NULL THEN 'Unknown cost'
      WHEN cost_for_two < 300 THEN 'Under 300'
      WHEN cost_for_two < 600 THEN '300–599'
      WHEN cost_for_two < 1000 THEN '600–999'
      WHEN cost_for_two < 1500 THEN '1,000–1,499'
      WHEN cost_for_two < 2500 THEN '1,500–2,499'
      ELSE '2,500+'
    END AS cost_band,
    cost_for_two,
    votes,
    rating
  FROM base
)
SELECT
  cost_band,
  COUNT(*) AS restaurant_listings,
  COUNT(rating) AS rated_listings,
  ROUND(AVG(rating), 2) AS average_rating,
  ROUND(AVG(cost_for_two), 0) AS average_cost_for_two,
  ROUND(AVG(votes), 0) AS average_votes
FROM banded
GROUP BY cost_band
ORDER BY
  CASE cost_band
    WHEN 'Under 300' THEN 1
    WHEN '300–599' THEN 2
    WHEN '600–999' THEN 3
    WHEN '1,000–1,499' THEN 4
    WHEN '1,500–2,499' THEN 5
    WHEN '2,500+' THEN 6
    ELSE 7
  END;

-- Overall Pearson correlation between cost-for-two and rating.
-- This is descriptive association, not a causal estimate.
WITH base AS (
  SELECT
    approx_cost_cleaned AS cost_for_two,
    SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
)
SELECT
  COUNT(*) AS records_with_cost_and_rating,
  ROUND(CORR(CAST(cost_for_two AS FLOAT64), rating), 3) AS cost_rating_correlation
FROM base
WHERE cost_for_two IS NOT NULL
  AND rating IS NOT NULL;
