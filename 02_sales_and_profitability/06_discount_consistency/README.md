# Case Study · Discount Consistency and Price Leakage

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Window: 1 Oct 2025 – 30 Sep 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-23 |

---

## 1. Business problem

Salespeople set discounts order by order. The commercial director believes discounts follow volume: bigger customers get bigger discounts. If that is not true, large customers may be under-rewarded and some customers may be discounted well beyond their peers. Before writing a formal discount policy, the director wants to know **what actually drives the discount today**, and how much is given outside the normal range.

The [Discount and margin erosion](../01_discount_margin_erosion/) study measured how much discounting costs. This study asks whether it is **consistent and fair**.

## 2. Business questions

1. Do bigger customers get bigger discounts, or does something else drive the discount?
2. Within the real driver, which customers sit outside the normal band, and what is the excess worth?
3. Which salespeople grant the out-of-band discounts?
4. Which large customers are not being rewarded for their volume?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Gross value and discount |
| `sales_orders` | One row per order | Date, status, customer, salesperson |
| `customers` | One row per customer | Segment |
| `employees` | One row per employee | Salesperson names |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Gross value | `quantity * unit_price`, before discount, orders not Cancelled or Returned |
| Effective discount | Discount amount ÷ gross value, per customer, for the 12 months |
| Volume tier | 12-month gross value: under ₹2 lakh, ₹2–10 lakh, ₹10–50 lakh, ₹50 lakh and above |
| Segment benchmark | Median effective discount of the segment's customers with 5+ order lines |
| Band | Benchmark ± 2 percentage points |
| Excess discount | For customers above the band: (rate − benchmark − 2 points) × gross value |

Customers with fewer than 5 order lines (92) are not banded, because a handful of orders cannot show a pattern.

## 5. Analytical approach

1. **Customer table** (`sahyadri_b2b.customer_discount_band`). One row per active customer with gross value, discount, volume tier, segment benchmark, band status and excess.
2. **Driver test.** Correlation of discount with volume, overall and within each segment, and a segment × volume-tier matrix.
3. **Band status** by segment, and total excess discount.
4. **Salesperson view** of out-of-band customers.
5. **Review lists:** the largest over-discounted customers, and large customers not rewarded for volume.

## 6. SQL techniques used

- `CORR(LN(gross_value), effective_discount)` with `GROUP BY ROLLUP` to compare the overall relationship with the within-segment one
- A pivot of weighted discount by segment and tier with conditional `SUM(IF(...))`
- `PERCENTILE_CONT … OVER (PARTITION BY segment)` for peer benchmarks
- A median-property test in validation (at least half the peers on each side of the benchmark)

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer |
| 02 | Customers = active customers in the source (367) |
| 03 | Gross value = source |
| 04 | Discount amount = source (₹3.92 crore) |
| 05 | Effective discount = discount ÷ gross on every row |
| 06 | Every volume tier matches its thresholds |
| 07 | Each segment benchmark has at least half its peers on each side (median property) |
| 08 | Every band status obeys its rule |
| 09 | Excess discount appears only on over-discounted customers |
| 10 | The primary salesperson is the one with the most gross value |

## 8. Findings

**Discounts look volume-based, but they are set by customer segment.** Across all customers, discount rises with volume (correlation 0.64). Within each segment, the relationship disappears (−0.10 to 0.18). Bigger tiers simply contain more distributors and enterprises.

| Segment | Under ₹2 lakh | ₹2–10 lakh | ₹10–50 lakh | ₹50 lakh+ | All | Correlation with volume |
|---|---:|---:|---:|---:|---:|---:|
| Distributor | 9.5 % | 10.9 % | 11.0 % | 11.7 % | 11.4 % | −0.10 |
| Enterprise | 9.0 % | 8.7 % | 8.6 % | 8.9 % | 8.7 % | 0.15 |
| Mid-Market | 4.0 % | 3.9 % | 4.0 % | 4.0 % | 4.0 % | −0.03 |
| SMB | 1.3 % | 1.6 % | 1.6 % | – | 1.5 % | 0.18 |

- **Small distributors get big-account terms.** 31 distributors buying under ₹10 lakh a year receive about 10.9 % (₹15.8 lakh of discount on ₹1.45 crore). That is more than an enterprise buying over ₹50 lakh gets (8.9 %).
- **Large mid-market customers are not rewarded for volume.** 19 mid-market customers buying ₹10 lakh or more (₹3.66 crore gross) receive the same 4.0 % as the smallest mid-market accounts.

**Within each segment, discounting is consistent. Price leakage is small.**

| Segment | Median discount | Within band | Over-discounted | Under-discounted | Excess discount |
|---|---:|---:|---:|---:|---:|
| Distributor | 11.03 % | 44 | 7 | 4 | ₹2.35 lakh |
| Enterprise | 8.36 % | 51 | 4 | 1 | ₹2.20 lakh |
| Mid-Market | 3.96 % | 67 | 7 | 8 | ₹0.44 lakh |
| SMB | 1.18 % | 77 | 5 | 0 | ₹0.05 lakh |

- **₹5.04 lakh of discount (1.3 % of the ₹3.92 crore given) is beyond the band**, spread across 23 customers.
- Two customers account for half of it: **Banerjee Sales Corporation** at 13.8 % against an 11.0 % distributor median (₹1.54 lakh excess, served by Harish Tiwari), and **Sudarshan Autoparts** at 11.6 % against 8.4 % for enterprises (₹1.12 lakh, Prakash Sharma).
- No salesperson stands out. The highest share of over-discounted customers for any salesperson is 17 % (Vikram Gupta, 3 of 18).
- **The largest customers are discounted at or below their segment median.** Maa Joshi Industrial Suppliers (₹1.61 crore gross, 10.9 %) and Laxmi Enterprises (₹1.07 crore, 10.4 %) pay more than the median distributor.

## 9. Business implications and recommendations

1. **Write the discount policy as a segment × volume matrix.** Today the customer's label sets the price, not what they buy. Keep the segment base rates, and add volume steps within each segment.
2. **Review distributor status for small accounts.** Check that the 31 distributors buying under ₹10 lakh a year actually resell. If they don't, they are enterprise or mid-market customers on distributor terms.
3. **Reward the top accounts explicitly.** Offer a volume rebate or annual rate contract to the largest distributors and mid-market customers, starting with Maa Joshi Industrial Suppliers and Laxmi Enterprises. They rank 3rd and 6th by contribution in the [customer profitability whale curve](../../05_advanced_analytics/05_customer_profitability_whale_curve/).
4. **Review the two largest out-of-band accounts** (Banerjee Sales Corporation and Sudarshan Autoparts) at their next price review. Day-to-day discount discipline is otherwise good and does not need tighter approval rules.

## 10. Assumptions and limitations

- **Segment as recorded.** The analysis takes the customer master's segment at face value. If segments are wrong, the benchmark is wrong.
- **One year.** A customer's discount and volume can change between years.
- **Correlation is descriptive.** It shows how discounts are set in practice, not what policy salespeople were given.
- **Band width.** ±2 points and the 5-line minimum are declared at the top of the script and can be changed.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer discount table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
