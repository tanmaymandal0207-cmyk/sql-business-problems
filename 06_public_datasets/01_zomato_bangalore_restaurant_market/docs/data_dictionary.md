# Data Dictionary

**Dataset:** Zomato Bangalore Restaurants (Kaggle, Himanshu Poddar) — scraped Zomato listings for Bangalore.
**BigQuery project / dataset:** `zomatoanalytics.Zomato_csv`

| Layer | Object | Grain | Rows | Built by |
|---|---|---|---|---|
| Raw | `restaurants` | One row per **listing** (restaurant × listed_in_type × listed_in_city) | 51,717 | CSV upload, all columns `STRING` |
| Clean | `restaurants_clean` | Same as raw — 17 original + 6 `*_cleaned` columns | 51,717 | [`02_cleaning/02_create_restaurants_clean.sql`](../sql/02_cleaning/02_create_restaurants_clean.sql) |
| Analysis | `restaurants` CTE | One row per **restaurant** (`restaurant_id`) | 12,453 | Inline CTE in every [`04_analysis`](../sql/04_analysis) query |

---

## 1. Source columns (raw table, all `STRING`)

| # | Column | Description | Profile highlights |
|---|---|---|---|
| 1 | `url` | Zomato restaurant page URL **plus a per-listing `?context=` query string** | 51,717 distinct — unique per row, so it is a *listing* key, not a restaurant key |
| 2 | `address` | Street address | 0 NULL; 2 rows with repeated whitespace |
| 3 | `name` | Restaurant name | 0 NULL / blank / whitespace issues |
| 4 | `online_order` | Accepts online orders | `Yes` / `No` only |
| 5 | `book_table` | Accepts table booking | `Yes` / `No` only |
| 6 | `rate` | Rating text, e.g. `4.1/5`, `3.9 /5`, `NEW`, `-` | Inconsistent spacing around `/` |
| 7 | `votes` | Number of ratings | All rows cast cleanly to `INT64` |
| 8 | `phone` | One or more phone numbers | 1,208 NULL |
| 9 | `location` | Locality of the restaurant | 93 distinct; 21 NULL |
| 10 | `rest_type` | Restaurant type, may be comma-combined (`Casual Dining, Bar`) | 93 distinct; 227 NULL |
| 11 | `dish_liked` | Popular dishes, comma-separated | 28,078 NULL |
| 12 | `cuisines` | Cuisines served, comma-separated | 45 NULL |
| 13 | `approx_cost_for_two_people` | Approx. cost for two (₹), thousands separator (`1,800`) | 346 NULL |
| 14 | `reviews_list` | Review text array (long, semi-structured) | Not used in analysis |
| 15 | `menu_item` | Menu items array | Not used in analysis |
| 16 | `listed_in_type` | Listing category (Delivery, Dine-out, Buffet …) | 7 distinct |
| 17 | `listed_in_city` | Zomato listing zone | 30 distinct; **not** equivalent to `location` |

> Kaggle header names `approx_cost(for two people)`, `listed_in(type)` and `listed_in(city)` were renamed to BigQuery-safe snake_case at load.

## 2. Cleaned columns (`restaurants_clean`)

| Column | Type | Expression | Purpose |
|---|---|---|---|
| `approx_cost_cleaned` | INT64 | `SAFE_CAST(REPLACE(TRIM(approx_cost_for_two_people), ',', '') AS INT64)` | Remove thousands separator, numeric type |
| `rate_cleaned` | STRING | `REGEXP_REPLACE(TRIM(rate), r'\s*/\s*', '/')` | Standardise `3.9 /5` → `3.9/5` |
| `votes_cleaned` | INT64 | `SAFE_CAST(TRIM(votes) AS INT64)` | Numeric type |
| `address_cleaned` | STRING | `REGEXP_REPLACE(TRIM(address), r'\s+', ' ')` | Collapse repeated whitespace |
| `phone_cleaned` | STRING | `REGEXP_REPLACE(TRIM(phone), r'\s+', ' ')` | Collapse repeated whitespace |
| `menu_item_cleaned` | STRING | `REGEXP_REPLACE(TRIM(menu_item), r'\s+', ' ')` | Collapse repeated whitespace |

Original columns are retained next to every cleaned column for traceability.

## 3. Derived analysis fields (restaurant-grain CTE)

| Field | Expression | Notes |
|---|---|---|
| `restaurant_id` | `REGEXP_EXTRACT(url, r'^[^?]+')` | URL path without query string — 12,453 distinct values |
| `rating` | `SAFE_CAST(SPLIT(rate_cleaned, '/')[SAFE_OFFSET(0)] AS FLOAT64)` | `NEW`, `-` and NULL → NULL; valid range observed 1.8–4.9 |
| Deduplication | `QUALIFY ROW_NUMBER() OVER (PARTITION BY restaurant_id ORDER BY votes_cleaned DESC, url) = 1` | Keeps the snapshot with the most votes; `url` makes the pick deterministic |
| `cuisine` | `TRIM(cuisine_raw)` from `UNNEST(SPLIT(cuisines, ','))` | Exploded in the `restaurant_cuisines` CTE, `SELECT DISTINCT` per restaurant |
