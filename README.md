# Which cuisine categories have the strongest listing presence?

## Business problem
A food-business operator wants to understand which cuisine categories are most represented in Bangalore listings before assessing potential market-entry opportunities.

## Business questions
- Which individual cuisine labels appear most frequently?
- How many restaurants are associated with each cuisine?
- What are the average rating and average cost-for-two for each cuisine?

## Method
Split the comma-separated `cuisines` field into individual labels, trim whitespace, and aggregate at the cuisine level. A restaurant with multiple cuisine labels contributes once to each associated cuisine.

## Interpretation
This measures listing presence, not market share by sales or customer demand. Because restaurants can appear in multiple cuisine categories, cuisine counts are non-additive and should not be summed to estimate unique restaurants. Treat high representation as evidence of competition intensity, not proof that a segment is saturated.

## Run
Execute `solution.sql` in BigQuery Standard SQL against:
`zomatoanalytics.Zomato_csv.restaurants_clean`

## Output
The query returns the measures and dimensions needed to answer the business questions. Add the actual result and a concise business recommendation after execution; this package intentionally does not invent query outputs.
