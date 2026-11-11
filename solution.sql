-- Business Problem 06: Popularity + quality shortlist
-- Screening assumptions: rating >= 4.0 and at least 100 votes.
-- Change the thresholds to test sensitivity.

WITH base AS (
  SELECT
    name,
    location,
    cuisines,
    SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating,
    votes_cleaned AS votes,
    approx_cost_cleaned AS cost_for_two,
    online_order,
    book_table
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
)
SELECT
  name,
  location,
  cuisines,
  rating,
  votes,
  cost_for_two,
  online_order,
  book_table,
  DENSE_RANK() OVER (ORDER BY votes DESC, rating DESC) AS engagement_rank
FROM base
WHERE rating >= 4.0
  AND votes >= 100
ORDER BY votes DESC, rating DESC
LIMIT 100;
