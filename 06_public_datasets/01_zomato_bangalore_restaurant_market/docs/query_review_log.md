# Query Review Log

Every business query in [`sql/04_analysis`](../sql/04_analysis) began as a practice attempt in the BigQuery console. The original attempts are preserved **verbatim** in [`sql/00_source/bigquery_export_analysis_query.sql`](../sql/00_source/bigquery_export_analysis_query.sql); this log records what was changed in review and why.

## Cross-cutting issue — counting listings instead of restaurants

| | Original | Corrected |
|---|---|---|
| Restaurant count | `COUNT(*)`, `COUNTIF(name IS NOT NULL)` or `COUNT(DISTINCT url)` | One row per `restaurant_id` (URL path), then `COUNT(*)` |
| Why it matters | `url` carries a unique `?context=` string, so all three equal the **listing** count (51,717) | 12,453 restaurants; each appears in 4.15 listings on average (max 34) |
| Impact | BTM looked like the largest locality (5,124 rows) | Whitefield is the largest (885 restaurants); BTM has 724 |
| Rating impact | Well-rated restaurants are listed in more contexts and are counted repeatedly | 11 localities averaged ≥3.8 at listing grain; **none** do at restaurant grain |

Validation: [`03_validation/02_restaurant_grain_checks.sql`](../sql/03_validation/02_restaurant_grain_checks.sql)

## Per-query changes

| ID | Question | Issue in original attempt | Fix |
|---|---|---|---|
| A01 | Locality concentration | Two near-identical questions; listing grain; `having Avg_Rating is not null` filter | Merged; restaurant grain; listing count kept as a comparison column; added rating coverage % |
| A02 | Investor: high-rated localities (≥500) | Listing grain threshold; `LIMIT 15` vs spec of 10 | Threshold on restaurants; `LIMIT 10`. Only 7 localities qualify |
| A03 | Online ordering adoption | `ROUND(SAFE_DIVIDE(yes, total*100))` → divides by 100× the total and rounds to 0 dp, returning **0 for every locality** | `ROUND(SAFE_DIVIDE(COUNTIF(online_order = 'Yes'), COUNT(*)) * 100, 2)` |
| A04 | High rating, low online adoption | Logic correct, but at listing grain | Restaurant grain. Spec rating ≥3.8 returns 0 rows → applied 3.7 and documented (max = 3.79, city avg = 3.63) |
| A05 | Top cuisines by presence | Grouped by `location` *and* cuisine; `TRIM(cuisines)` applied to the full string; UNNEST alias reused the column name `cuisines`; counted listing URLs | Separate `restaurant_cuisines` CTE: `TRIM` on each unnested value, `SELECT DISTINCT` per restaurant, group by cuisine only |
| A06 | Top-rated cuisines (≥100 restaurants) | Grouped by restaurant **name** + cuisine; `HAVING ≥ 70` instead of 100 | Group by cuisine; `HAVING COUNT(*) >= 100` |
| A07 | Locality × cuisine rating (extension) | Online % mixed `COUNTIF` over rows with `COUNT(DISTINCT url)`; unnested alias `cuisines` vs selected `Cuisines` | Clean CTEs; online % within the locality–cuisine pair |
| A08 | Cuisine diversity & online adoption | ≥20-outlet cuisine filter and *most popular cuisine* not implemented; threshold 100 vs 300; sorted by outlets, not acceptance % | All requirements implemented; `ARRAY_AGG(... ORDER BY ... LIMIT 1)` for the top cuisine |

## Conventions applied in corrected queries

- Each file runs on its own (no dependency on views that a sandbox could expire).
- Same `restaurants` CTE in every file, so all metrics share one grain.
- `SAFE_DIVIDE` for every ratio; `ROUND` applied after the multiplication.
- Deterministic ordering (secondary sort key) on every `LIMIT`.
- Header block: business question → requirements → grain & rules → original line range → result file.
- Executed in BigQuery on 2026-11-03; outputs saved to [`results/`](../results).
