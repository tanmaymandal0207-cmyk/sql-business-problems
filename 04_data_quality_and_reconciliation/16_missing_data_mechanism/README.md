# Case Study · Missing Data: Random Gaps, Structural Blanks or a Broken Process?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Six fields with missing values (1,425 gaps in 78,831 records) tested in 29 chi-square tests across dimensions for whether the gaps are structural, random or systematic, with the effect of each gap on the reported KPIs.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-31 |

---

## 1. Business problem

The [data quality scorecard](../02_data_quality_scorecard/) counted the missing values in every table. Before the dashboards go live, the BI lead must decide for each field whether to exclude the gaps, fill them in, or send the problem back to the source process. The right choice depends on why values are missing. A blank can be **structural** (no delivery date while a shipment is still in transit, which is correct), **random** (equally likely anywhere, so leaving it out biases nothing), or **systematic** (concentrated in one period, customer, salesperson or status, which points to a broken process and biases every total).

## 2. Business questions

1. For each field, is the missing pattern structural, random or systematic?
2. What does each gap do to the reported KPIs?
3. What should the dashboard do with each field?

## 3. Dataset and relevant tables

| Table | Field tested | Records |
|---|---|---:|
| `sales_orders` | Promised delivery date, salesperson | 10,000 |
| `sales_order_items` | Discount % | 28,201 |
| `payments` | Payment method | 10,568 |
| `shipments` | Delivery date, freight cost | 10,031 |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Missing rate | Records with a NULL in the field ÷ all records |
| **Chi-square test** | For a field and a dimension (year, month, weekday, segment, status, customer, city, category, salesperson, payment type, amount band): Σ (missing − n p)² ÷ (n p (1 − p)) over groups, against one common rate p. Groups under 30 records are pooled into "Other". |
| **Systematic** | Chi-square above its 1 % critical value (Wilson–Hilferty approximation); 1 % is used because about 30 tests are run |
| Dispersion ratio | Chi-square ÷ degrees of freedom: about 1 when gaps are random |
| **Structural** | A blank that the record's own status explains (here: delivery date while In Transit) |
| KPI impact | What the gap adds to or removes from a reported total |

## 5. Analytical approach

1. **Observations** (`sahyadri_b2b.md_observations`): one row per record, field and dimension.
2. **Missing rates** per field, and the **structural check** for delivery dates.
3. **Tests** (`sahyadri_b2b.md_tests`): chi-square, critical value and the group with the highest rate for every field × dimension.
4. **KPI impact** (`sahyadri_b2b.md_impact`) of each gap.

## 6. SQL techniques used

- Reshaping several tables into one long field × dimension × group table with `UNION ALL`
- A missing-completely-at-random screen with chi-square tests, small-group pooling and a critical value computed in SQL
- Separating structural from accidental blanks with a status cross-tab
- Validation that recomputes every statistic as a Pearson chi-square on the full missing/present table

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Missing counts per field = source `COUNT(*) − COUNT(column)` |
| 02 | Every dimension covers every record exactly once |
| 03 | **Chi-square = the Pearson statistic on the full missing/present table** |
| 04 | Groups under 30 records pooled; every other group has 30+ |
| 05 | Critical values exceed the degrees of freedom and rise with them |
| 06 | Delivery date is blank for every shipment still in transit |
| 07 | Unattributed revenue = a recount from source |
| 08 | Each test counts the field's records and missing values |
| 09 | Highest group rate ≥ overall rate ≥ lowest group rate |
| 10 | Dispersion ratio = chi-square ÷ degrees of freedom |

## 8. Findings

**One field is structural; the other five have random gaps.**

| Field | Records | Missing | Rate | Tests | Systematic | Largest dispersion ratio |
|---|---:|---:|---:|---:|---:|---|
| Shipment delivery date | 10,031 | 65 | 0.65 % | status | **structural** (55 in transit) + 10 delivered | – |
| Order salesperson | 10,000 | 352 | 3.52 % | 6 | 0 | 1.22 (month) |
| Shipment freight cost | 10,031 | 316 | 3.15 % | 4 | 0 | 0.96 (year) |
| Payment method | 10,568 | 190 | 1.80 % | 6 | 0 | 5.74 (payment type, 2 groups) |
| Order promise date | 10,000 | 166 | 1.66 % | 7 | 0 | 3.24 (year, 3 groups) |
| Line discount | 28,201 | 336 | 1.19 % | 6 | 0 | 3.74 (year, 3 groups) |

- **None of 29 tests crosses the 1 % threshold.** The gaps are spread evenly across years, months, weekdays, segments, statuses, salespeople, product categories, cities and customers (about 100 customers with 30+ records: dispersion 0.74–1.27).
- The largest ratios are on two- and three-group splits, where one unlucky year or type moves the ratio a lot: instalment payments miss the method 2.2 % of the time against 1.8 % overall, and 2024 lines miss a discount 1.4 % against 1.2 %. Neither crosses the 1 % threshold; both would cross 5 %, which is about what 29 tests produce by chance (1.5 expected).
- **Delivery date is blank for all 55 shipments in transit, as it should be.** The 10 shipments marked Delivered without a date are the only true errors in this field.

**What the gaps do to the KPIs.**

| Field | Effect if handled naively | Size |
|---|---|---:|
| Order salesperson | Valid-order revenue with no salesperson to credit | **₹393.8 lakh (4.3 % of revenue)** |
| Payment method | Receipts a bank-feed rule cannot route by method | ₹160.8 lakh (2.0 % of receipts) |
| Order promise date | Delivered orders left out of the on-time rate | 151 (1.6 %) |
| Line discount | Revenue overstated if a missing discount is read as 0 % | ₹10.8 lakh (0.12 %) |
| Shipment freight cost | Freight understated if a missing cost is read as zero | ₹3.9 lakh (3.3 % of freight) |
| Shipment delivery date | Delivered shipments with no lead time | 10 (0.1 %) |

- Because the gaps are random, leaving the records out does not bias rates or averages; it only shrinks totals.
- **Missing salespeople matter most**: ₹3.94 crore of revenue is credited to nobody in the [salesperson scorecard](../../02_sales_and_profitability/02_salesperson_scorecard/) and the [commission simulation](../../02_sales_and_profitability/14_commission_plan_simulation/).

## 9. Business implications and recommendations

1. **Treat the five random fields as data-entry slips, not process failures.** Make each mandatory at entry (salesperson, promise date, discount, payment method, freight cost); there is no broken feed to fix.
2. **Restore the salesperson on the 352 orders from the customer's usual salesperson.** With random gaps, the customer's most frequent salesperson is the safest imputation; flag the field as imputed.
3. **For KPIs, exclude rather than zero-fill.** On-time rates, average discount and freight per shipment are unbiased if the gaps are left out; reading a blank discount as 0 % or a blank freight as ₹0 is what creates bias.
4. **Fill freight from the inferred rate card** (see the [freight invoice audit](../09_freight_invoice_audit/)) when a total is needed, adding about ₹3.9 lakh.
5. **Keep delivery date blank for shipments in transit, and fix the 10 delivered shipments without a date.** Add a rule: a shipment cannot move to Delivered without a delivery date.
6. **Re-run the tests monthly.** A test turning systematic is the earliest sign that a feed or a team has stopped recording a field.

## 10. Assumptions and limitations

- **"Random" here means unrelated to the dimensions tested.** A gap could still depend on something not recorded, such as the clerk who entered the order.
- **The test detects concentration, not cause.** With 352 or fewer gaps per field, a modest difference (for example 2 % against 1.5 %) between two groups can go undetected.
- **Customers and cities with fewer than 30 records** are pooled into "Other".
- **Small master-data gaps** (5 customer cities, 18 industries, 6 registration dates, 4 product costs, 2 salaries) are listed in the scorecard and are too few to test.
- **Impact sizes use simple averages** (average discount, average freight); they show the scale of the problem, not a precise correction.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Observation, test and impact tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
