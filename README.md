# Where is restaurant supply concentrated across Bangalore localities?

## Business problem
A restaurant operator or market researcher needs to understand where listed restaurant supply is concentrated and which localities have a comparatively smaller listing base.

## Business questions
- Which localities contain the largest number of restaurant listings?
- What share of all listings does each locality represent?
- How many listings have a valid numeric rating in each locality?

## Method
Aggregate listings by `location`, calculate each locality's share of the full dataset, and report rating coverage and average rating. Keep missing locality values visible as an explicit group so the denominator is transparent.

## Interpretation
High listing count indicates supply concentration, not automatically demand or profitability. A low-count locality is only a candidate for further research; population, footfall, rents, competition quality and delivery radius are not present in this dataset.

## Run
Execute `solution.sql` in BigQuery Standard SQL against:
`zomatoanalytics.Zomato_csv.restaurants_clean`

## Output
The query returns the measures and dimensions needed to answer the business questions. Add the actual result and a concise business recommendation after execution; this package intentionally does not invent query outputs.
