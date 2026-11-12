# Which dishes appear most frequently in customer-liked dish listings?

A menu researcher wants to find dish names recurring across restaurant listings.
**Questions:** Which dish labels appear most often in `dish_liked`? How many listings mention each? What are the associated average ratings and votes?
**Method:** Split comma-separated `dish_liked` values, trim tokens and aggregate by dish label. Require at least five mentions.
**Caveat:** This is a listed-liked-dish signal, not transaction-level sales or a representative customer survey. Commas inside dish names can affect tokenisation; manually inspect top values.

## Run
Execute `solution.sql` in BigQuery Standard SQL against `zomatoanalytics.Zomato_csv.restaurants_clean`.

## Results
Add actual query output and a concise business recommendation after execution. No numerical findings are pre-filled.
