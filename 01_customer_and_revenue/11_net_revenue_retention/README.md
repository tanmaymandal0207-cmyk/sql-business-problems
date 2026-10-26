# Case Study · Net and Gross Revenue Retention

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Rolling 12-month retention measured at four quarter ends, December 2025 – September 2026.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

The company is preparing an information memorandum for a lender. The lender asks for two standard measures of the quality of recurring B2B revenue: **net revenue retention (NRR)** and **gross revenue retention (GRR)**, tracked quarter by quarter. A high NRR can hide weak foundations, for example if it comes from price increases or from two or three large accounts. The CFO wants the measures computed properly and wants to know what sits behind them.

## 2. Business questions

1. How much of last year's customer revenue is kept, lost, shrunk or expanded a year later?
2. Is retention improving or deteriorating quarter by quarter?
3. How much of NRR is price increase rather than customers buying more?
4. Which segments and customer sizes retain best?
5. How much does NRR depend on a handful of expanding accounts?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Revenue |
| `products` | One row per product | List price (for constant-price revenue) |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

For each quarter end Q:

| Term | Definition |
|---|---|
| Revenue | Quantity × unit price × (1 − discount %), orders not Cancelled or Returned; NULL discount = 0 % |
| Base revenue B | Customer revenue in the 12 months ending 12 months before Q |
| Current revenue C | Customer revenue in the 12 months ending at Q |
| Base customers | Customers with B > 0 |
| **Churn** | B of base customers with C = 0 |
| **Contraction** | B − C for base customers with 0 < C < B |
| **Expansion** | C − B for base customers with C > B |
| **NRR** | Σ C of base customers ÷ Σ B |
| **GRR** | Σ min(B, C) ÷ Σ B = 1 − (churn + contraction) ÷ base. It cannot exceed 100 %. |
| Logo retention | Base customers with C > 0 ÷ base customers |
| New or returning | C of customers with B = 0 (new customers, or customers silent for the whole base year) |
| **Constant-price NRR** | NRR on revenue valued at the current list price: quantity × list price × (1 − discount %). This removes the January 2025 and January 2026 price increases. |

## 5. Analytical approach

1. **Customer table** (`sahyadri_b2b.revenue_retention_customers`). Base and current revenue, at actual and at list price, for every customer and quarter end, with a movement type and base size band.
2. **Quarterly table** (`sahyadri_b2b.revenue_retention_quarterly`). The revenue bridge (churn, contraction, expansion, new), NRR, GRR, logo retention and constant-price NRR.
3. **Latest quarter by segment and by base size.**
4. **Concentration test**: NRR with the top 1, 5 and 10 expanding customers held flat, and the largest movements.

## 6. SQL techniques used

- Rolling 24-month windows for several quarter ends at once, from a `DECLARE`d `ARRAY<DATE>` and `UNNEST`
- Conditional aggregation to split each window into base and current years in one pass
- `LEAST(B, C)` for GRR, which caps every customer at its base
- Constant-price revaluation using the product list price
- "Hold top N flat" sensitivity with `ROW_NUMBER()`
- Validation through the revenue bridge identity: base − churn − contraction + expansion + new = current

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per quarter end and customer |
| 02 | Current 12-month revenue = source |
| 03 | Base 12-month revenue = source |
| 04 | **Bridge identity**: base − churn − contraction + expansion + new = current, every quarter |
| 05 | GRR = 1 − (churn + contraction) ÷ base |
| 06 | Retained customers = an independent recount from source |
| 07 | Base customers = an independent recount |
| 08 | Revenue at list price = source |
| 09 | Size band set exactly for base customers |
| 10 | Movement type agrees with base and current revenue |

## 8. Findings

**NRR jumped to 126.6 % in the latest quarter, but GRR shows the business loses about a fifth of its base each year.**

| 12 months to | Base customers | Base revenue | Churn | Contraction | Expansion | New or returning | Current revenue | **NRR** | **GRR** | Logo retention | NRR at constant price |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Dec 2025 | 318 | ₹28.36 cr | −₹0.28 cr | −₹4.99 cr | +₹6.76 cr | +₹1.80 cr | ₹31.65 cr | 105.2 % | 81.4 % | 88.7 % | 99.8 % |
| Mar 2026 | 323 | ₹29.96 cr | −₹0.54 cr | −₹6.21 cr | +₹7.54 cr | +₹2.93 cr | ₹33.70 cr | 102.7 % | **77.5 %** | 87.0 % | **97.4 %** |
| Jun 2026 | 331 | ₹30.40 cr | −₹0.40 cr | −₹5.51 cr | +₹8.61 cr | +₹3.78 cr | ₹36.88 cr | 108.9 % | 80.5 % | 87.9 % | 103.1 % |
| Sep 2026 | 340 | ₹30.45 cr | −₹0.32 cr | −₹4.40 cr | +₹12.83 cr | +₹1.79 cr | ₹40.36 cr | **126.6 %** | 84.5 % | 87.4 % | 120.0 % |

- **The leak is contraction, not churn.** Customers who stop buying entirely take only ₹0.28–0.54 crore a year (about 1–2 % of base). Customers who buy less take ₹4.4–6.2 crore (14–21 %). About one customer in eight is lost each year, but they are small.
- **Until mid-2026 retention rested on price.** At constant prices NRR was 99.8 % in December 2025 and 97.4 % in March 2026. Existing customers were buying slightly fewer goods each year; the January price increases kept NRR above 100 %. Price adds about 5–7 points in every quarter.
- **The September 2026 jump is real volume**: 120.0 % at constant price. It comes from expansion of ₹12.83 crore, up from ₹6.76 crore a year earlier.

**But the latest NRR is concentrated in a few accounts.**

| 12 months to | NRR | Top 1 expander held flat | Top 5 held flat | Top 10 held flat |
|---|---:|---:|---:|---:|
| Dec 2025 | 105.2 % | 103.9 % | 99.5 % | 97.3 % |
| Mar 2026 | 102.7 % | 99.0 % | 94.5 % | 91.5 % |
| Jun 2026 | 108.9 % | 105.1 % | 99.9 % | 96.8 % |
| Sep 2026 | 126.6 % | 122.7 % | **111.8 %** | **106.1 %** |

- The five largest expanders in the latest year added ₹4.52 crore: Siddhivinayak Mishra Trading (+₹1.19 crore), Banerjee Sales Corporation (+₹1.10 crore), Jai Consumer Care India (+₹82 lakh), Laxmi Enterprises (+₹79 lakh) and Krishna Castings (+₹61 lakh). Without them NRR is 111.8 %. In earlier quarters, without the top five, NRR was below 100 %.
- The largest contractions: Universal Gupta Fabricators (−₹34.3 lakh), Mahavir Fabrics (−₹27.8 lakh) and Thakkar Distributors (−₹25.2 lakh).

**Large accounts are kept; small accounts leak.** (12 months to September 2026)

| Group | Base customers | Base revenue | NRR | GRR | Logo retention |
|---|---:|---:|---:|---:|---:|
| Distributor | 58 | ₹12.11 cr | 129.5 % | 83.4 % | 91.4 % |
| Enterprise | 59 | ₹12.33 cr | 125.2 % | **87.2 %** | 93.2 % |
| Mid-Market | 91 | ₹4.23 cr | 133.2 % | 85.3 % | 87.9 % |
| SMB | 132 | ₹1.78 cr | 101.8 % | **71.0 %** | 82.6 % |
| Base ₹50 lakh+ | 12 | ₹11.61 cr | 126.2 % | **94.3 %** | 100.0 % |
| ₹10–50 lakh | 65 | ₹12.63 cr | 114.2 % | 77.9 % | 100.0 % |
| ₹2–10 lakh | 104 | ₹5.20 cr | 147.8 % | 81.8 % | 95.2 % |
| Under ₹2 lakh | 159 | ₹1.01 cr | 177.8 % | 68.7 % | 76.1 % |

- **No customer worth ₹10 lakh or more a year was lost.** But the ₹10–50 lakh band has a GRR of only 77.9 %: these mid-sized accounts kept buying, but often much less. They hold ₹12.63 crore of base revenue, the largest band.
- SMB customers have the weakest GRR (71.0 %) and logo retention (82.6 %).
- The very high NRR of small customers (177.8 %) comes from a small base growing into larger accounts; it is a small amount of money.

## 9. Business implications and recommendations

1. **Report NRR, GRR and constant-price NRR together to the lender.** NRR alone (126.6 %) overstates the strength of the base. GRR of about 80 % and constant-price NRR of about 100 % before mid-2026 give the fuller picture.
2. **Disclose concentration.** NRR without the top five expanders (111.8 %) is the fair "underlying" figure; the [revenue concentration trend](../08_revenue_concentration_trend/) study shows the same accounts.
3. **Target contraction in the ₹10–50 lakh band.** These 65 accounts have a GRR of 77.9 % and hold the most base revenue. A quarterly review of any account down more than 25 % on its prior year would catch the ₹4–6 crore annual leak early. Use the [cross-sell white space](../../02_sales_and_profitability/04_cross_sell_white_space/) lists to recover lost categories.
4. **Do not plan on price for retention.** The January increases contributed about 5–7 NRR points each year. Without them, the base was shrinking slightly in volume until mid-2026.
5. **Track this quarterly.** The quarterly table can be refreshed by adding the next quarter end to the array.

## 10. Assumptions and limitations

- **Four quarter ends.** Data starts in January 2024, so December 2025 is the first quarter end with a full 24 months of history.
- **Constant-price revenue** uses today's list price for every year. It assumes the list price changed by the same percentage for all products; the [price-volume-mix](../../02_sales_and_profitability/03_price_volume_mix/) study measures the actual price change by category.
- **Order date basis.** Revenue is counted when ordered, not when delivered or invoiced.
- **Customer-level, not group-level.** Related companies are treated separately.
- "New or returning" includes customers who were silent for the whole base year and came back, not only newly acquired customers.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer and quarterly retention tables, and 2 analysis steps |
| `validation.sql` | 10 pass/fail checks |
