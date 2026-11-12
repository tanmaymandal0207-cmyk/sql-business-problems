# What is the mix of restaurant operating formats in Bangalore?

An operator wants to understand the listing base across source-defined restaurant formats.
**Questions:** Which `rest_type` labels have the largest counts? What share of listings does each represent? How do average ratings and cost-for-two vary by format?
**Method:** Aggregate using original `rest_type` labels and calculate listing share, rating and cost.
**Caveat:** Combined labels are retained as supplied. This is a listing-mix analysis, not a count of physical outlets by standardised industry segment.

## Run
Execute `solution.sql` in BigQuery Standard SQL against `zomatoanalytics.Zomato_csv.restaurants_clean`.

## Results
Add actual query output and a concise business recommendation after execution. No numerical findings are pre-filled.
