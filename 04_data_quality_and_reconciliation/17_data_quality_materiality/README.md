# Case Study · Data Quality Materiality: Which Issues Move the Board KPIs?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Ten headline KPIs for October 2025 – September 2026, each computed as a plain query reports it and again with one data rule applied. The study judges each issue material or not, and ranks the fixes.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-02 |

---

## 1. Business problem

Sixteen earlier data quality studies have listed issues: missing discounts and unit costs, duplicate customers, city spellings, orders without a salesperson, duplicate receipts, stale payment flags, missing delivery dates and missing freight. The data team cannot fix all of them before the next board pack. The CFO wants to know which issues actually change the numbers the board sees, by how much, and which fixes to build into the reporting layer first.

## 2. Business questions

1. For each headline KPI of the last 12 months, what does a plain query report, and what is the corrected figure?
2. Which issues are material, and which can wait?
3. How many records sit behind each issue?
4. Which corrections should be built into the reporting layer first?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, dates, salesperson, payment flag |
| `sales_order_items` | One row per product per order | Revenue and discount |
| `products` | One row per product | Unit cost |
| `customers` | One row per customer | Name, city, state |
| `shipments` | One row per shipment | Delivery date, freight |
| `payments` | One row per receipt | Cash collected |

## 4. Method and metric definitions

| KPI | As reported (plain query) | Corrected |
|---|---|---|
| Revenue | `quantity × price × (1 − discount/100)`; a NULL discount makes the line NULL and drops it | NULL discount = 0 % |
| Gross margin % | Lines without a unit cost add revenue but no cost | Lines without a unit cost left out of both |
| Active customers | Distinct customer IDs | Duplicate records merged (same normalised name, city and state: the six high-confidence pairs of the [deduplication](../03_customer_master_deduplication/) study) |
| On-time delivery % | Delivered orders with last dated delivery ≤ promise ÷ all delivered orders | Orders without a promise date or with an undated shipment left out |
| Cash collected | Sum of receipts | Duplicate receipts (same order, date and amount) counted once |
| Paid in full % | `payment_status = 'Paid'` | Payments reach 99 % of order value |
| League table total | Sum over salespeople | Including an "Unassigned" row |
| Freight % of revenue | Missing shipping cost ignored | Filled with the city's average cost per shipment |
| Customer cities / Bengaluru revenue | Raw city text | Standardised: case, spacing, aliases (Bangalore → Bengaluru) |
| **Material** | | A change of **1 %** or more for amounts and counts, **0.5 points** or more for rates |

Window: 1 Oct 2025 – 30 Sep 2026; valid orders exclude Cancelled and Returned in both versions.

## 5. Analytical approach

1. **Lines** (`sahyadri_b2b.dq_lines`), **city map** (`dq_city_map`) and **customer master** (`dq_customer_master`).
2. **KPI table** (`sahyadri_b2b.dq_kpis`): each KPI as reported and corrected, with the materiality verdict.
3. **Records behind each issue.**
4. **Payment flag against payments.**
5. **On-time delivery**: which of its two gaps moves it.

## 6. SQL techniques used

- Paired calculations in one pass: the same aggregate with and without `IFNULL`, a filter or a de-duplication
- How SQL treats NULL as the subject: `SUM` skipping NULL lines, and `COUNTIF` on a NULL comparison counting as false
- Name normalisation with `REGEXP_REPLACE` and survivorship with `FIRST_VALUE() OVER (PARTITION BY name, city, state ORDER BY orders DESC …)`
- Duplicate receipts with `ROW_NUMBER() OVER (PARTITION BY order, date, amount)`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Lines = valid lines of the window; corrected revenue = source (₹40.36 crore, matching other 12-month studies) |
| 02 | **Reported revenue = corrected − value of the NULL-discount lines** |
| 03 | Corrected margin = margin recomputed on costed lines only |
| 04 | Six duplicate customers; each master has at least as many orders |
| 05 | On-time base = delivered orders with a promise and every shipment dated |
| 06 | Cash difference = amounts of the extra duplicate receipts |
| 07 | Paid-in-full share = recount from payments |
| 08 | **League table + unassigned revenue = company revenue** |
| 09 | Freight filled in = city averages for the shipments without a cost |
| 10 | Every customer city maps; Bengaluru = all its spellings |

## 8. Findings

**Five of the ten KPIs move materially; five do not.**

| KPI (Oct 2025 – Sep 2026) | Issue | As reported | Corrected | Change | Verdict |
|---|---|---:|---:|---:|---|
| Revenue | NULL discount drops the line | ₹39.83 crore | **₹40.36 crore** | **+1.3 %** | **Material** |
| Salesperson league table total | Orders without a salesperson | ₹39.16 crore | ₹40.36 crore | **+3.1 %** | **Material** |
| On-time delivery | Missing promise or undated delivery | 79.76 % | **81.32 %** | **+1.56 pts** | **Material** |
| Bengaluru revenue | City spellings | ₹1.27 crore | ₹1.56 crore | **+23.1 %** | **Material** |
| Customer cities | City spellings | 51 | 49 | −3.9 % | Material |
| Active customers | Duplicate records | 367 | 364 | −0.8 % | Not material |
| Gross margin | Lines without unit cost | 15.38 % | 15.48 % | +0.10 pts | Not material |
| Freight % of revenue | Missing shipping cost | 1.26 % | 1.31 % | +0.04 pts | Not material |
| Cash collected | Duplicate receipts | ₹35.70 crore | ₹35.64 crore | −0.2 % | Not material |
| Paid in full | Stale payment flag | 78.00 % | 78.03 % | +0.03 pts | Not material |

**The number of bad records does not predict the damage.**

| Issue | Records | Out of |
|---|---:|---:|
| NULL discount lines | 116 | 11,219 lines (1.0 %) |
| Lines without unit cost | 118 | 11,219 |
| Orders without a salesperson | 148 | 4,225 orders (3.5 %) |
| Shipments without shipping cost | 145 | 4,250 |
| Delivered orders without a promise date | 70 | 3,864 |
| Customer IDs that are duplicates | 6 | 500 |
| Extra customer city spellings | 2 | 54 spellings |
| Duplicate receipts | 1 | 4,670 receipts |

- 116 NULL discounts (1 % of lines) take ₹53 lakh off revenue because SQL drops the whole line, not just the discount. 118 lines without a unit cost barely move margin, because margin is a ratio and they are left out of both sides.
- **Two city spellings cut Bengaluru's revenue by a fifth.** Four customers are recorded as "Bangalore"; any city ranking or territory target built on raw text is wrong for that city.
- **On-time delivery is understated by 1.6 points, almost all from the 70 orders without a promise date** (81.23 % with that fix alone, against 79.84 % with only the four undated shipments fixed). A missing promise counts as late in a plain query.
- The payment flag agrees with payments on all but one of 3,864 delivered orders, so the "stale flag" issue no longer affects the paid-in-full rate.

## 9. Business implications and recommendations

1. **Build four rules into the reporting layer before the board pack:** treat a NULL discount as 0 %; exclude orders without a promise date from on-time delivery (and report how many); show an "Unassigned" row in every salesperson table; and map cities through the standard alias table.
2. **Fix the sources next:**
   - make discount and promise date mandatory at order entry;
   - make salesperson mandatory at order entry ([missing data mechanism](../16_missing_data_mechanism/) found salesperson gaps are random, so the fix is mechanical);
   - correct the four "Bangalore" customers.
3. **Let the immaterial issues wait,** but keep them on the [data quality scorecard](../02_data_quality_scorecard/): merge the six duplicate customers and reverse the duplicate receipt (they matter for customer-level credit and receivables, not for totals), accrue missing freight, and fill the three missing unit costs.
4. **Add this table to the month-end close.** Re-run it each month: an issue that is immaterial today becomes material if its record count grows.

## 10. Assumptions and limitations

- **One issue per KPI.** Each KPI is corrected for the issue most likely to affect it; issues do not interact here.
- **"As reported" is a plain query**, not the company's actual board pack, which may already apply some of these rules.
- **Materiality thresholds are a judgement:** 1 % of an amount or 0.5 points of a rate. A stricter board would also flag active customers (−0.8 %).
- **The freight fill uses city averages,** as a stand-in for the rate card in the [freight invoice audit](../09_freight_invoice_audit/).
- **Twelve months only.** Earlier periods may have different issue counts.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Line, city map, customer master and KPI tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
