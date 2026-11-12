# Zomato Bangalore — SQL Business Case Studies

A set of six independent business problems built around the Zomato Bangalore restaurant dataset using **Google BigQuery Standard SQL**.

## Dataset
- BigQuery project: `zomatoanalytics`
- Dataset: `Zomato_csv`
- Cleaned table: `restaurants_clean`
- Original dataset: 51,717 restaurant records and 17 source columns.
- Cleaned fields used here: `rate_cleaned`, `votes_cleaned`, `approx_cost_cleaned`.
- The raw table is preserved; the analysis queries read from the cleaned table.

> **Important:** These scripts are analysis queries, not precomputed findings. Run them against your own BigQuery table to obtain current result sets. No numerical outcome has been fabricated.

## Six business problems

| # | Business problem | Business decision supported |
|---|---|---|
| 01 | Where is restaurant supply concentrated? | Identify high-density and relatively under-served localities |
| 02 | Which cuisine segments have meaningful market presence? | Prioritise cuisine categories for market-entry research |
| 03 | How does price positioning relate to customer ratings? | Understand value positioning and premium-market patterns |
| 04 | How widely is online ordering adopted? | Identify localities with stronger or weaker digital-ordering coverage |
| 05 | Which restaurants support dine-in/table booking? | Understand dine-in service availability and its market concentration |
| 06 | Which restaurants combine popularity and quality? | Build a shortlist using ratings and customer-vote engagement |

## Repository structure

Each numbered folder is one self-contained business problem. It contains:
- `README.md` — business context, analytical approach, interpretation guidance and limitations.
- `solution.sql` — executable BigQuery Standard SQL.

## How to run
1. Open BigQuery Studio.
2. Confirm that `zomatoanalytics.Zomato_csv.restaurants_clean` exists and contains the cleaned fields listed above.
3. Open one `solution.sql` file and run the query.
4. Export or capture the result set for your portfolio, then add a short findings section with the actual output.

## Data and interpretation notes
- Ratings are parsed from values such as `4.1/5`. Non-numeric labels (for example `NEW` or `-`) become `NULL` and are excluded from rating averages.
- `approx_cost_cleaned` represents approximate cost for two people, not per-person spend.
- Votes are an engagement proxy, not a direct measure of unique customers, revenue, or satisfaction.
- `location` and `listed_in_city` are distinct source dimensions. This project uses `location` for locality analysis and does not treat the two fields as interchangeable.
- Cuisine values are comma-separated combinations. Cuisine-level analysis splits these combinations into individual cuisine labels; whitespace is trimmed.
- Results describe listings in this dataset, not necessarily the current live Zomato marketplace.
