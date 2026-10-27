# Case Study · Data Drift Monitoring with the Population Stability Index

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 15 monitored fields (13 source fields and 2 adjusted versions) across orders, order lines, payments and shipments; 313 field-months tested against the 2024 reference year.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-27 |

---

## 1. Business problem

The BI team refreshes the management dashboards every month. Twice last year a dashboard looked wrong and nobody could say quickly whether the business had changed or the data feed had. The team wants an automatic monthly check that compares each month's data with a reference year, and raises an alert only when a change is real and worth a look. A [data quality scorecard](../02_data_quality_scorecard/) already tests individual records against rules; this check looks at whole distributions.

## 2. Business questions

1. Which fields shift from month to month, and by how much?
2. Which shifts are larger than normal sampling noise?
3. Which real shifts are expected business changes, and which need investigation?
4. What alert rule should the monthly refresh use?

## 3. Dataset and relevant tables

| Table | Grain | Fields monitored |
|---|---|---|
| `sales_orders` (+ `customers`, `sales_order_items`) | One row per order | Order value, customer segment, order status, promise window, salesperson assigned, lines per order |
| `sales_order_items` (+ `products`, `product_categories`) | One row per order line | Product category, discount %, quantity, price ratio (unit price ÷ list price) |
| `payments` | One row per payment | Payment method |
| `shipments` | One row per shipment | Shipping cost, shipment status |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Month | Order month for order and line fields; payment month; shipment month |
| Reference period | Calendar 2024 |
| Monitored months | January 2025 to September 2026 (21 months) |
| Bins | Categories for text fields; deciles of the reference period for numeric fields; NULL is always its own bin |
| **Population stability index (PSI)** | Σ over bins (a − e) × ln(a ÷ e), where a and e are the month's and the reference period's shares, with 0.5 added to each bin count. Usual reading: below 0.10 stable, 0.10–0.25 moderate shift, above 0.25 major shift. |
| **Noise test** | n·N ÷ (n + N) × PSI is approximately chi-square with (bins − 1) degrees of freedom when nothing has changed. Converted to a z-score (Wilson–Hilferty). **Alert when z ≥ 3.30**: a 1 % false-alarm rate across 21 months (Bonferroni). |
| Sample size | The number of **orders** behind the month and the reference period, for every grain. Lines and payments of one order are not independent. |
| Adjusted fields | Price ratio indexed to its calendar-year median (removes the January list price increase). Order status for complete order months at least 60 days old (removes orders still being fulfilled). |

## 5. Analytical approach

1. **Observation table** (`sahyadri_b2b.dd_observations`). One row per field × record: grain, month, reference flag and the value.
2. **Bins** (`sahyadri_b2b.dd_cuts`, `sahyadri_b2b.dd_binned`). Reference deciles for numeric fields and a bin label for every observation.
3. **PSI table** (`sahyadri_b2b.dd_psi`). PSI, the order-based z and the naive record-based z for every field and month; field summary.
4. **Alerts and their causes**: the alert list, raw against adjusted price ratio, order status maturity, bin detail for any other alert, and the PSI that noise alone produces at weekly, monthly and quarterly volumes.

## 6. SQL techniques used

- One long observation table for fields of four different grains, built with `UNION ALL`
- Reference-period deciles with `PERCENTILE_CONT` and binning with summed comparisons (no `RANGE_BUCKET`, so the logic is portable)
- A full field × bin × month grid with `LEFT JOIN` so empty bins count, and additive smoothing
- PSI, a chi-square approximation and the Wilson–Hilferty transformation to a z-score, all in SQL
- Validation that recomputes every PSI with conditional aggregation and checks that each reference decile holds 10 % of the records

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Observations = source records for each grain |
| 02 | Reference flag = event before the monitoring start |
| 03 | Decile cut points are in ascending order |
| 04 | Continuous fields: each reference decile holds 10 % of records (within one record) |
| 05 | Every observation has exactly one bin |
| 06 | **PSI = an independent recount** for all 313 field-months |
| 07 | PSI is never negative |
| 08 | Bins per field = distinct bins observed; degrees of freedom = bins − 1 |
| 09 | z recomputed from the order-based statistic |
| 10 | Order-grain fields: records = orders, so the two tests agree |

## 8. Findings

**The data is stable. Only three fields raise alerts, and all three have a known cause.**

| Field | Average PSI | Highest PSI | Months PSI ≥ 0.10 | Alerts (z ≥ 3.30) | Alerts if lines were independent |
|---|---:|---:|---:|---:|---:|
| Order value | 0.035 | 0.073 | 0 | 0 | 0 |
| Customer segment | 0.010 | 0.031 | 0 | 0 | 0 |
| **Order status** | 0.082 | **1.442** | 1 | **1** | 1 |
| Order status (months 60+ days old) | 0.008 | 0.026 | 0 | 0 | 0 |
| Promise window | 0.035 | 0.052 | 0 | 0 | 0 |
| Salesperson assigned | 0.004 | 0.025 | 0 | 0 | 0 |
| Lines per order | 0.017 | 0.044 | 0 | 0 | 0 |
| Product category | 0.010 | 0.020 | 0 | 0 | 0 |
| Discount % | 0.034 | 0.062 | 0 | 0 | **8** |
| Quantity | 0.012 | 0.027 | 0 | 0 | 0 |
| **Price ratio (unit price ÷ list)** | **6.721** | 7.043 | 21 | **21** | 21 |
| Price ratio indexed to its year | 0.012 | 0.025 | 0 | 0 | 0 |
| Payment method | 0.015 | 0.032 | 0 | 0 | 0 |
| Shipping cost | 0.033 | 0.061 | 0 | 0 | 0 |
| **Shipment status** | 0.035 | **0.625** | 1 | **1** | 1 |

**Alert 1: price ratio, every month since January 2025 — the annual list price increase.** `selling_price` holds today's list, so every 2025 and 2026 invoice price sits in a different place relative to it than in 2024. Indexed to each year's median, the same field is stable (PSI 0.007–0.025). See the [price increase study](../../02_sales_and_profitability/12_price_increase_and_price_discipline/).

| Month | PSI, raw price ratio | PSI, indexed to the year |
|---|---:|---:|
| January 2025 | 6.707 | 0.025 |
| June 2025 | 6.426 | 0.011 |
| December 2025 | 7.012 | 0.007 |
| January 2026 | 6.774 | 0.015 |
| June 2026 | 6.756 | 0.012 |

**Alerts 2 and 3: order status and shipment status, September 2026 — data maturity.** 25.3 % of September 2026 orders are still Pending, Processing or Shipped, and 12.8 % of September shipments are In Transit; in every earlier month both are below 0.5 %. Restricted to complete months at least 60 days old, order status never moves (PSI ≤ 0.026).

**No other field shows a shift beyond noise.** The bin-detail query for unexplained alerts returns no rows.

**Treating order lines as independent would have raised 8 false alarms on discount %.** PSI on discount never exceeded 0.062, but with about 926 lines a month the record-based test reaches z = 5.1. Lines of the same order usually share a discount, so the real sample is about 328 orders; on that basis no month comes near the alert level (highest z = 1.7).

**A fixed PSI threshold of 0.10 is only right for monthly data.**

| Monitoring period | Orders per period | PSI from noise alone (10 bins) | PSI that reaches z = 3.30 |
|---|---:|---:|---:|
| Week | 59 | **0.154** | 0.514 |
| Month | 255 | 0.038 | 0.127 |
| Quarter | 773 | 0.015 | 0.048 |

On weekly data, noise alone produces a PSI above 0.10, so a 0.10 rule would alarm most weeks; on quarterly data it would miss real shifts between 0.05 and 0.10.

## 9. Business implications and recommendations

1. **Adopt the monthly check with a noise-based alert**: z ≥ 3.30 on the order-based statistic, and report PSI alongside it for size. Set it to run after each dashboard refresh.
2. **Monitor prices as an index, not against today's list.** The raw price ratio will alert every month until a price-list history is stored; the indexed version is stable and would catch a real pricing change.
3. **Exclude immature months from status fields.** Compare order and shipment status only for months that are at least 60 days old, or the latest month will always alert.
4. **Use orders as the sample size for line and payment fields.** Line-level tests produced 8 false alarms on discount in 21 months.
5. **Scale thresholds with volume.** If the check is run weekly or on a single segment, use the z-test rather than a fixed PSI; the threshold that means "real change" moves from 0.05 (quarterly) to 0.5 (weekly).
6. **Investigate drift only after the explanations above are ruled out.** On this data, no field outside the three explained ones needs investigation.

## 10. Assumptions and limitations

- **One reference year.** 2024 is used as normal. Seasonality is not modelled; a month-on-same-month-last-year comparison would be a useful addition for seasonal fields such as order volume.
- **Distributions, not volumes.** PSI compares shares. A month with half the usual orders but the same mix would not alert; volume needs its own control chart (see [statistical process control](../../03_operations_and_supply_chain/09_statistical_process_control/)).
- **Chi-square approximation.** The z-score is approximate for bins with very few records; the 0.5 smoothing keeps PSI finite but makes it slightly conservative.
- **Orders as the sample size** is conservative for line fields (lines of one order are partly independent). It avoids false alarms at the cost of a little sensitivity.
- **Bin labels for discount** depend on how each engine prints numbers (`5` or `5.0`); the bins and counts are the same.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Observation, cut, bin and PSI tables, and the alert analysis |
| `validation.sql` | 10 pass/fail checks |
