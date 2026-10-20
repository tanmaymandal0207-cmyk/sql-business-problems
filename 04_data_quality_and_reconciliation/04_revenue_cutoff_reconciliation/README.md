# Case Study · Revenue Cut-off Reconciliation

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Period: January 2024 – September 2026; half-year end 30 Sep 2026.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-21 |

---

## 1. Business problem

Management reports book revenue on the **order date**, because that is the first date the order system records. Under Ind AS 115, revenue on these sales is recognised when **control of the goods passes to the customer**, which for delivered sales is the **delivery date**. Orders placed near a month-end are often delivered in the following month. That matters most at the 31 March financial year-end, when sales teams push orders to close the year. Before the half-year close, finance wants to know how large the cut-off difference is and where it concentrates.

## 2. Business questions

1. How different is monthly revenue on an order-date basis from revenue on a delivery-date basis?
2. At each month-end, how much has been ordered but not yet delivered (the **cut-off exposure**)?
3. What is the effect on financial-year revenue (April–March)?
4. What is open at the 30 Sep 2026 half-year end?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order date and status |
| `sales_order_items` | One row per product per order | Revenue |
| `shipments` | One row per shipment | Final delivery date |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)`, orders not Cancelled or Returned |
| Order basis | Revenue in the month of the order date |
| Delivery basis | Revenue in the month of the final delivery date |
| Cut-off difference | Order basis − delivery basis for the period. Positive means order-date reporting **overstates** the period. |
| Month-end exposure | Revenue ordered on or before the month-end but delivered after it (or not yet delivered) |
| Financial year | April – March (FY2025-26 = Apr 2025 – Mar 2026) |

**A useful identity:** a period's cut-off difference = closing exposure − opening exposure. Validation check 05 proves it for FY2025-26.

## 5. Analytical approach

1. **Recognition table** (`sahyadri_b2b.revenue_recognition_basis`). One row per in-scope order with order date, delivery date, revenue and recognition status (Delivered, Not yet delivered, or Delivered without a delivery date).
2. **Monthly comparison.** Order basis, delivery basis, difference and month-end exposure, using a month spine from `GENERATE_DATE_ARRAY` and `LAST_DAY`.
3. **Financial-year comparison.**
4. **Year-end focus:** orders placed in the last 10 days of March and delivered after 31 March.
5. **Open at the half-year end**, plus the records excluded from the comparison.

## 6. SQL techniques used

- A month spine (`GENERATE_DATE_ARRAY … INTERVAL 1 MONTH`) with `LAST_DAY` for month-ends
- Conditional aggregation over a `CROSS JOIN` of months and orders to compute both bases and point-in-time exposure
- Indian financial-year labelling with `CASE` on `EXTRACT(MONTH …)`
- Reconciliation identities in validation: total bridge, exposure roll-forward, and as-of exposure = open orders

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order |
| 02 | Row count = in-scope orders in the source |
| 03 | Revenue = in-scope line-item total |
| 04 | Order-basis revenue = delivery-basis revenue + revenue still open |
| 05 | FY2025-26 cut-off difference = 31 Mar 2026 exposure − 31 Mar 2025 exposure |
| 06 | Exposure at 30 Sep 2026 = revenue on orders not yet delivered |
| 07 | Every "Delivered" row in the comparison has a delivery date |
| 08 | No "Not yet delivered" row has a delivery date |
| 09 | No delivery date after the as-of date |
| 10 | No delivery date before its order date |

Exposure at 30 Sep 2026 (₹1.07 crore) also equals the open-order value found independently in the [Open order backlog review](../../03_operations_and_supply_chain/03_open_order_backlog_review/).

## 8. Findings

**Order-date reporting overstated FY2025-26 revenue by ₹1.11 crore (3.4 %).**

| Financial year | Order basis | Delivery basis | Difference |
|---|---:|---:|---:|
| FY2024-25 (Apr 2024 – Mar 2025) | ₹29.95 crore | ₹30.43 crore | −₹0.48 crore |
| FY2025-26 (Apr 2025 – Mar 2026) | ₹33.68 crore | ₹32.57 crore | **+₹1.11 crore** |

FY2024-25 was *understated*, because the ₹1.59 crore of orders open at 31 Mar 2024 were delivered in April 2024 and counted in that year. FY2025-26 was overstated because far more was open at its close (₹2.22 crore) than at its opening (₹1.11 crore).

**March is where the cut-off risk sits.**

| Month-end | Exposure (ordered, not yet delivered) |
|---|---:|
| 31 Mar 2024 | ₹1.59 crore |
| 31 Mar 2025 | ₹1.11 crore |
| **31 Mar 2026** | **₹2.22 crore** |
| Typical other month-ends | ₹0.4 – ₹1.2 crore |
| 30 Sep 2026 (half-year end) | ₹1.07 crore |

- **March 2026 order-basis revenue was ₹5.42 crore against ₹4.11 crore on delivery, a difference of ₹1.31 crore for one month.** April 2026 shows the mirror image (−₹1.40 crore). A month-by-month order-basis report would show a March spike and an April slump that are partly timing.
- **Most late-March orders cross the year-end.** Of the orders placed in the last 10 days of March 2026, 81 of 126, worth **₹2.10 crore**, were delivered in April or later. The pattern was similar in 2024 (63 of 89) and 2025 (87 of 110).
- **₹1.07 crore is open at the 30 Sep 2026 half-year end** (29 Pending, 16 Processing and 58 Shipped orders). On a delivery basis, none of it belongs in the first half.
- 13 Delivered orders (₹5.4 lakh) have no delivery date and cannot be placed on a delivery basis. They are excluded and listed in Step 5.

## 9. Business implications and recommendations

1. **Post a cut-off adjustment at each quarter-end and year-end.** Defer revenue on orders not delivered by the period-end. For 30 Sep 2026 that is ₹1.07 crore. Step 2 gives the figure for any month-end.
2. **Report monthly revenue on a delivery basis** alongside order intake, so that management sees the March spike for what it is: orders, not recognised sales.
3. **Watch late-March orders closely.** Expedite dispatch of genuine year-end orders and review any that look pulled forward. In the last three years, 64–79 % of orders placed in the final 10 days of March were delivered after year-end.
4. **Make the delivery date mandatory for Delivered orders** so every sale can be placed in the right period. This is the same data gap found in the [Data quality scorecard](../02_data_quality_scorecard/).
5. **Confirm the recognition point by contract type with the auditors.** Some customers may collect from the warehouse (control passes at dispatch) rather than receive delivery.

## 10. Assumptions and limitations

- **Recognition point.** Control is assumed to pass on delivery for all sales. If some terms pass control at dispatch, the exposure would be smaller.
- **Data starts in January 2024.** Orders placed in December 2023 and delivered in January 2024 are not in the data, so January 2024 and FY2023-24 understate delivery-basis revenue. They are shown in the monthly output but not used for conclusions.
- **Partial year.** FY2026-27 covers April–September only.
- **Not an accounting opinion.** The analysis quantifies the timing difference. The accounting treatment should be confirmed against contract terms.
- **Returns.** Returned orders are excluded entirely. In the books, a return in a later period would reverse revenue in that period.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Recognition table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
