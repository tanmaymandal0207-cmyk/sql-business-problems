# How does restaurant price positioning relate to customer ratings?

## Business problem
A restaurant operator wants to benchmark price positioning against customer ratings and understand whether higher-cost listings consistently receive stronger ratings.

## Business questions
- How do average ratings vary across cost-for-two bands?
- How many listings and votes sit in each band?
- Does the dataset show a simple positive relationship between price and rating?

## Method
Create transparent cost bands from `approx_cost_cleaned`, calculate average rating, average votes and listing count per band, and calculate a correlation between cost and rating for records with both values.

## Interpretation
Cost is approximate for two people. Correlation is descriptive and does not establish causation. Ratings and votes may be affected by cuisine, locality, restaurant age, brand, service model and selection bias. Do not interpret higher price as better quality.

## Run
Execute `solution.sql` in BigQuery Standard SQL against:
`zomatoanalytics.Zomato_csv.restaurants_clean`

## Output
The query returns the measures and dimensions needed to answer the business questions. Add the actual result and a concise business recommendation after execution; this package intentionally does not invent query outputs.
