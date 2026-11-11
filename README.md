# How available is table booking, and where is dine-in service concentrated?

## Business problem
A dine-in operator wants to understand the prevalence of table-booking availability and the localities where it is most common.

## Business questions
- What proportion of listings offer table booking?
- Which localities have the highest table-booking availability?
- Do table-booking listings have different average ratings or cost positioning?

## Method
Summarise table-booking status overall and by locality, then compare average rating and approximate cost-for-two by booking status. Exclude unknown status from the Yes/No comparison.

## Interpretation
Table booking is a service attribute, not a direct measure of dine-in traffic, occupancy or reservation conversion. The rating/cost comparison is observational and should not be presented as evidence that table booking causes higher ratings or prices.

## Run
Execute `solution.sql` in BigQuery Standard SQL against:
`zomatoanalytics.Zomato_csv.restaurants_clean`

## Output
The query returns the measures and dimensions needed to answer the business questions. Add the actual result and a concise business recommendation after execution; this package intentionally does not invent query outputs.
