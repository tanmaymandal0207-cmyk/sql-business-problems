# Where is online ordering most and least adopted?

## Business problem
A delivery-focused operator or platform analyst wants to understand online-order availability across Bangalore localities.

## Business questions
- What proportion of listings accept online orders?
- Which localities have the highest and lowest online-order adoption?
- Are differences driven by the number of listings or the adoption rate?

## Method
Calculate Yes/No counts and adoption percentage by locality. Exclude missing locality values from the ranked locality view, and require a minimum listing count to reduce unstable percentages in very small groups.

## Interpretation
The field records whether online ordering is listed as available; it does not reveal order volume, delivery performance, platform commission, or revenue. Locality adoption rates should be compared alongside sample size.

## Run
Execute `solution.sql` in BigQuery Standard SQL against:
`zomatoanalytics.Zomato_csv.restaurants_clean`

## Output
The query returns the measures and dimensions needed to answer the business questions. Add the actual result and a concise business recommendation after execution; this package intentionally does not invent query outputs.
