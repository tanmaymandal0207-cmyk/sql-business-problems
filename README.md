# Which restaurant brands have the widest outlet footprint?

A market analyst wants to identify repeated restaurant names and their geographic reach.
**Questions:** Which names have the most listings? Across how many localities do they appear? Which have the broadest footprint?
**Method:** Standardise names for case and whitespace, then count listings, distinct localities and distinct URLs. The query screens names with at least three listings.
**Caveat:** Repeated names are brand candidates, not proof of common ownership. Validate addresses, URLs and ownership before calling a group a chain. No deduplication is performed.

## Run
Execute `solution.sql` in BigQuery Standard SQL against `zomatoanalytics.Zomato_csv.restaurants_clean`.

## Results
Add actual query output and a concise business recommendation after execution. No numerical findings are pre-filled.
