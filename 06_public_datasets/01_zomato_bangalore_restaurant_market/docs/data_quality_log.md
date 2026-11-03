# Data Quality & Cleaning Log

Markdown version of [`zomato_data_quality_tracker.xlsx`](zomato_data_quality_tracker.xlsx), the working tracker kept during cleaning, plus the restaurant-grain findings added during the analysis phase.

**Scope:** 51,717 records · 17 columns · BigQuery Standard SQL · raw table never modified
**Method:** Profile → inspect examples → define transformation → apply to a new column → validate → document decision

---

## 1. Column-level tracker

| Column | Profiling / finding | Status | Treatment / decision | Next action | Phase |
|---|---|---|---|---|---|
| `url` | Unique per row (51,717); path without query string = 12,453 | ✅ Profiled in analysis phase | Use URL path as `restaurant_id`; keep original URL | — | Grain |
| `address` | 0 NULL, 0 empty, 0 surrounding spaces; 2 rows with repeated whitespace (both *Supreme Biryani*, same URL & address) | Transformation tested | `address_cleaned = REGEXP_REPLACE(TRIM(address), r'\s+', ' ')`; do not delete rows | Compare full rows; define duplicate criteria | Standardisation |
| `name` | 0 NULL, 0 empty, 0 surrounding / repeated whitespace | ✅ Passed | Retain original | — | Profiling |
| `online_order` | 0 NULL, 0 empty, 0 literal `'null'`; values `Yes` / `No` | ✅ Passed | Retain | — | Profiling |
| `book_table` | 0 NULL, 0 empty, 0 literal `'null'`; values `Yes` / `No` | ✅ Passed | Retain | — | Profiling |
| `rate` | Whitespace around slash (`2.5/ 5` vs `2.5/5`); 7,775 NULL · 2,208 `NEW` · 69 `-` · 41,665 numeric | Transformation applied | `rate_cleaned = REGEXP_REPLACE(TRIM(rate), r'\s*/\s*', '/')`; numeric rating derived in analysis with `SAFE_CAST` | Decide reporting treatment for `NEW` | Standardisation |
| `votes` | 0 NULL, 0 empty, 0 non-numeric in `SAFE_CAST` test | Conversion applied | `votes_cleaned = SAFE_CAST(TRIM(votes) AS INT64)` | Inspect min / max / median | Type conversion |
| `phone` | 1,208 NULL; whitespace checks in SQL §11.2 | Transformation applied | `phone_cleaned` collapses whitespace; source text preserved | Profile multi-number formats | Standardisation |
| `location` | 93 distinct non-NULL; **21 NULL**; no whitespace issues | Missing values deferred | Retain; do not infer from address | Treat NULLs in missing-value phase | Profiling |
| `rest_type` | 93 distinct; **227 NULL**; comma-combined classifications | Structure investigated | Retain original; do not split / merge yet | Quantify single vs combined types | Profiling |
| `dish_liked` | 28,078 NULL (54%) | Profiled (SQL §10) | Not used in analysis | Decide if usable | Profiling |
| `cuisines` | 45 NULL; comma-separated multi-value | Profiled (SQL §09) | Exploded with `UNNEST(SPLIT())` + `TRIM` at analysis time | — | Profiling |
| `approx_cost_for_two_people` | **346 NULL**; comma-formatted values (`1,800`) | Conversion applied | `approx_cost_cleaned = SAFE_CAST(REPLACE(TRIM(..), ',', '') AS INT64)`; NULLs not imputed | Validate failed casts | Standardisation + type |
| `reviews_list` | Long semi-structured text | Not transformed | Out of scope until analytical use is defined | — | Profiling |
| `menu_item` | Semi-structured; whitespace checks in SQL §11.2 | Transformation applied | `menu_item_cleaned` collapses whitespace | Decide retain / parse / exclude | Standardisation |
| `listed_in_type` | 7 distinct listing categories | Profiled (SQL §11) | Retain | — | Profiling |
| `listed_in_city` | 30 distinct; 0 NULL; no whitespace issues | ✅ Passed | Retain; **do not merge with `location`** | Establish exact semantics | Profiling |

> Status column reflects the tracker snapshot plus SQL sections 09–11 and the validation queries run afterwards.

## 2. Key findings

| Finding | Evidence | Decision |
|---|---|---|
| Dataset size | 51,717 records, 17 columns | Preserve raw import as source of truth |
| Initial schema | All 17 columns imported as `STRING` | Convert selected fields in the clean layer |
| `rate` | Whitespace around slash; `NEW` / `-` / NULL present | Regex standardisation now; numeric rating derived with `SAFE_CAST` |
| `votes` | 0 NULL / empty / non-numeric | Safe `INT64` conversion |
| `approx_cost_for_two_people` | 346 NULL; comma thousands separator | Strip commas, `INT64`; missing-value treatment deferred |
| `address` | 2 rows with repeated whitespace — same restaurant, URL and address | Whitespace cleaned; potential duplicate flagged, **not deleted** |
| Geography | One `location` can appear under many `listed_in_city` values (BTM under 21) | `location` and `listed_in_city` are not interchangeable |
| `rest_type` | Comma-separated combined classifications | Preserve; investigate before splitting |
| NULL policy | — | Imputation / deletion intentionally deferred |
| **Grain (analysis phase)** | 51,717 listing rows → **12,453 restaurants** (avg 4.15 rows each, max 34) | All business metrics computed at restaurant grain |
| **Snapshot drift** | Within one restaurant: rating varies for 1,839, votes for 3,926, online_order for 389 | Keep the row with the highest `votes_cleaned` per restaurant |

## 3. Validation results (`restaurants_clean`)

| Check | Result | Expected |
|---|---|---|
| Row count | 51,717 | = raw ✅ |
| `votes_cleaned` NULL | 0 | 0 ✅ |
| `approx_cost_cleaned` NULL | 346 | = raw NULLs (no new cast failures) ✅ |
| Rating buckets (NULL + NEW + `-` + numeric) | 7,775 + 2,208 + 69 + 41,665 = 51,717 | = row count ✅ |
| Dedup layer: restaurants | 12,453 | = distinct URL paths ✅ |
| Dedup layer: duplicates left | 0 | 0 ✅ |
| Dedup layer: rating range | 1.8 – 4.9 | within 0–5 ✅ |

Full figures: [`results/v01_data_quality_summary.csv`](../results/v01_data_quality_summary.csv)
