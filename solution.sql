WITH base AS (
  SELECT SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64) AS rating,
         votes_cleaned AS votes
  FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
),
with_engagement AS (
  SELECT *, NTILE(4) OVER (ORDER BY votes) AS vote_quartile
  FROM base WHERE votes IS NOT NULL
),
segmented AS (
  SELECT CASE
      WHEN rating IS NULL THEN 'Unrated'
      WHEN rating < 3.0 THEN 'Below 3.0'
      WHEN rating < 3.5 THEN '3.0-3.49'
      WHEN rating < 4.0 THEN '3.5-3.99'
      ELSE '4.0+'
    END AS rating_band,
    CASE vote_quartile
      WHEN 1 THEN 'Q1 - Lowest engagement'
      WHEN 2 THEN 'Q2 - Lower-middle engagement'
      WHEN 3 THEN 'Q3 - Upper-middle engagement'
      WHEN 4 THEN 'Q4 - Highest engagement'
    END AS engagement_tier,
    votes
  FROM with_engagement
)
SELECT rating_band, engagement_tier, COUNT(*) AS restaurant_listings,
       ROUND(AVG(votes), 0) AS average_votes
FROM segmented
GROUP BY rating_band, engagement_tier
ORDER BY rating_band, engagement_tier;
