# Case Study · Cancellation and Return Leakage

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Period: January 2024 – September 2026, closed orders only.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-22 |

---

## 1. Business problem

About one order in eighteen is cancelled or returned. Each one wastes order processing, picking and freight, and sometimes leaves stock or cash to unwind. The operations head wants to know how much this costs and **where to act**. Before anyone launches a fix aimed at one salesperson, segment or product line, the data should show whether the problem is really concentrated there or spread across the business.

## 2. Business questions

1. How much order value and gross profit is lost to cancellations and returns, and is it getting worse?
2. Is the cancellation rate higher in any customer, segment, industry, product category, salesperson, order size, promise window or month than chance would explain?
3. Are returns caused by late or split deliveries?
4. Which customers cancel repeatedly, and where has cash been received on cancelled orders?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, dates, customer and salesperson |
| `sales_order_items` | One row per product per order | Order value and categories |
| `products` | One row per product | Unit cost, category |
| `customers` | One row per customer | Segment and industry |
| `shipments` | One row per shipment | Delivery date, split shipments and freight |
| `payments` | One row per payment | Cash received |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Closed order | Delivered, Cancelled or Returned. Open orders could still change and are excluded. |
| Order value | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)` |
| Gross profit lost | Order value − product cost on cancelled and returned orders |
| Cancellation rate | Cancelled ÷ closed orders |
| z-score | (group rate − company rate) ÷ `SQRT(p * (1 - p) / n)`. Groups with \|z\| ≥ 2 are flagged. |
| Expected by chance | Groups tested × 4.55 %, the share that would reach \|z\| ≥ 2 if there were no real difference |
| Late | Final delivery date after the promised date |

**Why compare with chance?** When 206 groups are tested, about 9 will look unusual even if every group has the same true rate. A driver is only credible if far more groups are flagged than chance predicts, or if one group stands out very strongly.

## 5. Analytical approach

1. **Outcome table** (`sahyadri_b2b.order_outcomes`). One row per closed order with value, gross profit, size band, promise window, shipments, late flag, freight and cash received.
2. **Leakage by year.**
3. **Driver screen** (`sahyadri_b2b.cancellation_driver_screen`). Cancellation rate and z-score for every group in eight dimensions, with flagged versus expected counts.
4. **Returns versus delivery experience.** Two-proportion z-tests on late and split-shipment rates for returned against delivered orders.
5. **Follow-up lists.** Customers who cancel significantly more often, and cancelled orders with cash received.

## 6. SQL techniques used

- `UNION ALL` to stack eight dimensions into one long table, so a single query scores every group
- Statistical testing in SQL: one-sample and two-proportion z-tests with `SQRT`
- A multiple-testing control that compares flagged groups with the number expected by chance
- `GROUP BY ROLLUP` for yearly totals

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order |
| 02 | Rows = closed orders in the source |
| 03 | Order value = source line total |
| 04 | Cancelled and returned counts = source |
| 05 | Freight = source shipping cost for these orders |
| 06 | Cash received = source payments for these orders |
| 07 | The late flag is set exactly when both dates exist |
| 08 | Each single-valued dimension covers every order once |
| 09 | Every z-score matches an independent recompute |
| 10 | Category order counts match an independent recount |

## 8. Findings

**Cancellations and returns cost ₹5.23 crore of order value (5.5 %) and ₹69.1 lakh of gross profit over 33 months.**

| Year | Closed orders | Cancelled | Cancel rate | Returned | Return rate | Value lost | % of value | GP lost |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2024 | 3,106 | 157 | 5.05 % | 29 | 0.93 % | ₹1.59 crore | 5.3 % | ₹13.8 lakh |
| 2025 | 3,749 | 205 | 5.47 % | 25 | 0.67 % | ₹2.01 crore | 6.0 % | ₹25.4 lakh |
| 2026 (Jan–Sep) | 3,042 | 172 | 5.65 % | 21 | 0.69 % | ₹1.64 crore | 5.2 % | ₹29.9 lakh |
| **Total** | **9,897** | **534** | **5.40 %** | **75** | **0.76 %** | **₹5.23 crore** | **5.5 %** | **₹69.1 lakh** |

- Cancellations make up 88 % of the value lost. The cancellation rate edged up from 5.05 % to 5.65 %, but that change is within normal year-to-year variation (z ≈ 1.0). The return rate fell after 2024.
- Gross profit lost rises from ₹13.8 lakh to ₹29.9 lakh although value lost is similar. That is mostly a measurement effect: realised prices rose about 5 % a year (see [Price-volume-mix analysis](../../02_sales_and_profitability/03_price_volume_mix/)), while GP uses today's standard cost for every year, so earlier years show lower margins.

**No segment, industry, category, salesperson, order size or month explains the cancellations.**

| Dimension | Groups tested | Flagged (\|z\| ≥ 2) | Expected by chance | Rate range |
|---|---:|---:|---:|---|
| Customer segment | 4 | 0 | 0.2 | 5.3 – 5.5 % |
| Industry | 15 | 0 | 0.7 | 2.9 – 7.2 % |
| Product category | 10 | 0 | 0.5 | 4.9 – 6.2 % |
| Salesperson | 17 | 1 (low) | 0.8 | 3.7 – 7.5 % |
| Order size | 4 | 0 | 0.2 | 5.2 – 5.6 % |
| Promise window | 4 | 1 (low) | 0.2 | 3.5 – 6.8 % |
| Order month | 12 | 0 | 0.5 | 4.2 – 6.5 % |
| Customer (20+ orders) | 140 | 8 | 6.4 | 0 – 16.7 % |

- Across the 66 non-customer groups, 2 are flagged against about 3 expected by chance. **The rate is a company-wide process level, not a pocket.** Apparent gaps, such as Food Processing at 7.2 % against Pharmaceuticals at 2.9 %, are within normal variation for groups of that size.
- **Two groups cancel less, and are worth learning from.** Deepika Jadhav's orders cancel at 3.7 % (z = −2.2), and orders promised within 7 days at 3.5 % (z = −2.1). Fast, firm commitments may reduce cancellations, but with one flagged group each this needs confirming.
- **Seven customers cancel significantly more often** (z ≥ 2), led by Navkar Agencies (7 of 47 orders, ₹15.4 lakh) and Banerjee Sales Corporation (9 of 75, ₹18.4 lakh). Eight flags against 6.4 expected means some may be chance, so treat this as a call list, not a verdict.

**Returns are not caused by late or split delivery.**

| | Returned orders | Delivered orders | z-score |
|---|---:|---:|---:|
| Delivered late | 8.1 % | 18.3 % | −2.3 |
| Split shipment | 6.8 % | 6.5 % | 0.1 |

Returned orders were *less* often late than kept orders. Returns are more likely to come from product, specification or customer-side reasons, which the data does not record.

- **₹72,325.69 has been received on 6 cancelled orders** and should be refunded or credited. This matches the exception found in [Order-to-cash reconciliation](../../04_data_quality_and_reconciliation/01_order_to_cash_reconciliation/).

## 9. Business implications and recommendations

1. **Add a mandatory reason code and date to every cancellation and return.** The data cannot locate the cause because it does not record it. With reason codes, the same screen can be re-run on reasons instead of proxies.
2. **Treat cancellations as a process KPI, not a people problem.** No salesperson, segment or product line stands out, so targeting one would not move the rate. Set a company target (for example below 4.5 %) and review it monthly.
3. **Learn from the low-cancellation patterns.** Review how Deepika Jadhav confirms orders, and test whether firm short promise dates reduce cancellations.
4. **Call the seven repeat-cancelling customers** to understand whether orders are placed speculatively, duplicated or cancelled for availability reasons.
5. **Inspect returns at goods-in** and record the product, defect and reason. Delivery performance is not the cause, so fixing logistics will not reduce returns.
6. **Refund or credit the ₹72,325.69** held against cancelled orders before the next close.

## 10. Assumptions and limitations

- **No reason or cancellation date.** The analysis can rule causes out, but cannot confirm what the real cause is.
- **Statistical screen, not proof.** A z-test assumes orders are independent. Orders from the same customer may not be, so flagged customers are prompts for review.
- **Gross profit at standard cost.** The current `unit_cost` is applied to all years, so GP in 2024–2025 is understated. Lines with no unit cost add no cost, so GP lost is slightly overstated for those products.
- **Wasted freight is understated.** Only outbound freight on returned shipments is recorded (₹91,690). Return freight and handling are not in the data.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Outcome and driver-screen tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
