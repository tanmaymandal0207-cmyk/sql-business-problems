# Which restaurants combine strong ratings with meaningful customer engagement?

## Business problem
A market analyst needs a shortlist of restaurants that combine a strong customer rating with meaningful review engagement, rather than ranking listings by rating alone.

## Business questions
- Which restaurants have high ratings and substantial vote counts?
- How does the shortlist vary by locality and cuisine?
- Which candidates have enough votes to make their rating more credible than a very low-volume listing?

## Method
Parse numeric ratings, retain listings with at least 100 votes and a rating of 4.0 or above, and rank by votes then rating. The vote threshold is an explicit screening assumption and can be adjusted.

## Interpretation
Votes are not necessarily unique customers and do not equal review count, orders or revenue. A high vote count may reflect age or visibility as well as popularity. This is a screening shortlist, not a definitive quality ranking. The query preserves restaurant names and locations for manual validation.

## Run
Execute `solution.sql` in BigQuery Standard SQL against:
`zomatoanalytics.Zomato_csv.restaurants_clean`

## Output
The query returns the measures and dimensions needed to answer the business questions. Add the actual result and a concise business recommendation after execution; this package intentionally does not invent query outputs.
