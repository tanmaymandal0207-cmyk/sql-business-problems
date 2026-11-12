# How complete are menu and profile listings across restaurant records?

A marketplace operations team wants to prioritise catalogue-quality improvements.
**Questions:** What share of listings have menu text and `dish_liked` values? How does coverage vary by locality? Which localities have many listings but weaker menu-field coverage?
**Method:** Measure presence of `menu_item`, `dish_liked` and `cuisines`; also report average menu-text length.
**Caveat:** Text length is not a count of menu items and does not measure accuracy or freshness. Missing fields may reflect source capture rather than restaurant behaviour.

## Run
Execute `solution.sql` in BigQuery Standard SQL against `zomatoanalytics.Zomato_csv.restaurants_clean`.

## Results
Add actual query output and a concise business recommendation after execution. No numerical findings are pre-filled.
