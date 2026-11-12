# Do multi-outlet restaurant brands deliver consistent ratings?

After identifying repeated-name groups, assess whether outlet ratings appear consistent or vary substantially.
**Questions:** Which groups have at least three rated listings? What are their average, minimum and maximum ratings? Which show the widest rating spread?
**Method:** Group by standardised name and calculate rating statistics from the numeric part of `rate_cleaned`.
**Caveat:** Names are only a proxy for brand identity. Rating spread is descriptive and can reflect sample size, outlet age, locality and listing quality.

## Run
Execute `solution.sql` in BigQuery Standard SQL against `zomatoanalytics.Zomato_csv.restaurants_clean`.

## Results
Add actual query output and a concise business recommendation after execution. No numerical findings are pre-filled.
