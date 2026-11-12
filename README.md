# How do customer engagement and ratings combine across restaurant listings?

A marketplace analyst wants to segment listings using both rating and vote volume rather than a single ranking.
**Questions:** How many listings fall into each rating/engagement segment? Which have high ratings but low engagement? Which have high engagement but weaker ratings?
**Method:** Parse numeric ratings, calculate vote-count quartiles with `NTILE(4)`, then cross-tabulate engagement tiers and rating bands.
**Caveat:** Votes are an engagement proxy, not sales or unique customers. Quartiles are relative to this dataset, not universal thresholds.

## Run
Execute `solution.sql` in BigQuery Standard SQL against `zomatoanalytics.Zomato_csv.restaurants_clean`.

## Results
Add actual query output and a concise business recommendation after execution. No numerical findings are pre-filled.
