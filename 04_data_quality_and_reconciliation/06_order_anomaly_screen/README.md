# Case Study · Order Anomaly Screen

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Orders dated January 2024 – September 2026, all statuses.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-23 |

---

## 1. Business problem

Orders are keyed in by hand. A slipped digit (100 typed as 1,000) or a wrong price can ship the wrong goods, start a dispute, and distort sales and stock figures. The [Data quality scorecard](../02_data_quality_scorecard/) tests fields and relationships. It cannot see a value that is valid but **unusual**. Internal audit wants a repeatable screen that flags unusual order lines for review before dispatch and before month-end, and wants to know whether the flagged orders are real problems or just large genuine orders.

## 2. Business questions

1. How many order lines and orders look unusual, and on which rule?
2. Do flagged orders end badly (cancelled, returned, unpaid) more often than normal orders?
3. Which flagged orders are still open or unpaid and need review now?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Quantity and unit price |
| `sales_orders` | One row per order | Customer, date, status |
| `payments` | One row per payment | Whether the customer paid |
| `products`, `customers` | One row per product / customer | Names for the review lists |

## 4. Metric definitions

| Rule | Flags an order line when… | Benchmark history needed |
|---|---|---|
| **Q1** Product quantity | Quantity ≥ 10 × the product's median quantity | Product has 20+ lines |
| **Q2** Customer quantity | Quantity ≥ 5 × this customer's median quantity for this product | Customer-product pair has 4+ lines |
| **P1** Price | Unit price more than 10 % from the product's median price in the same quarter | – |
| **V1** Order value | The order's gross value ≥ 10 × the customer's median order | Customer has 20+ orders |

Medians are used because a few extreme orders cannot pull them, unlike averages.

| Outcome of a flagged order | Meaning |
|---|---|
| Paid in full | The customer accepted and paid: genuine |
| Reversed | Cancelled or returned: check the cause |
| Delivered, not fully paid | Review before chasing payment |
| Open | Pending, Processing or Shipped: verify now |

## 5. Analytical approach

1. **Line table** (`sahyadri_b2b.order_line_anomalies`). Every order line with its benchmarks and four rule flags.
2. **Rule summary:** lines, orders and value flagged by each rule.
3. **Order table** (`sahyadri_b2b.order_anomaly_review`). One row per order with its flags, payment and outcome. Flagged and unflagged outcomes are compared with a two-proportion z-test.
4. **Review queue** of flagged orders that are open, unpaid or reversed, and the most extreme quantity lines.

## 6. SQL techniques used

- Robust benchmarks with `PERCENTILE_CONT … OVER (PARTITION BY …)` at product, customer-product and product-quarter level
- Several rules evaluated in one pass as boolean columns, then reshaped with `UNION ALL` for a rule summary
- `LOGICAL_OR` and `COUNTIF` to roll line flags up to orders
- Outcome classification by joining payments, and a significance test on the outcome mix

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per order line |
| 02 | Lines = source lines in the period (28,201) |
| 03 | One row per order in the review table, matching the source (10,000) |
| 04 | Every product median passes the median property (half the lines on each side) |
| 05 | Q1 flags match the rule, with product history counted independently |
| 06 | P1 flags match the rule |
| 07 | Order gross value matches the source for every order |
| 08 | An order is flagged exactly when at least one of its lines is |
| 09 | Every outcome matches status and payment |
| 10 | Amount paid = source payments |

## 8. Findings

**307 orders (3.1 %) are flagged, holding ₹17.15 crore (17.8 %) of order value.**

| Rule | Lines flagged | Orders flagged | Gross value of flagged lines |
|---|---:|---:|---:|
| Q1 Product quantity | 150 | 68 | ₹7.98 crore |
| Q2 Customer quantity | 209 | 167 | ₹5.90 crore |
| P1 Price | **0** | **0** | – |
| V1 Order value | 570 | 123 | ₹15.11 crore |

- **No price keying errors.** Every line is within 10 % of its product's median price for the quarter.
- **Quantities vary much more.** The most extreme line is 2,682 Taper Roller Bearings 30207, **149 times** the usual order quantity of 18 (order 103914, Siddhivinayak Mishra Trading, paid in full).

**Most flagged orders are genuine large orders, not errors.**

| | Orders | Paid in full | Reversed | Delivered, not fully paid | Open |
|---|---:|---:|---:|---:|---:|
| Flagged | 307 | 77.5 % | 7.5 % | 14.0 % | 1.0 % |
| Not flagged | 9,693 | 78.7 % | 6.0 % | 14.3 % | 1.0 % |

The reversal rate is not significantly higher for flagged orders (7.5 % against 6.0 %, z = 1.0). 238 flagged orders worth ₹14.42 crore were paid in full, which confirms them as genuine. They are mostly the project and year-end orders seen in other case studies.

**The screen still finds the orders that matter.** The review queue has 69 flagged orders:

| Outcome | Orders | Order value | Not yet received |
|---|---:|---:|---:|
| Delivered, not fully paid | 43 | ₹1.78 crore | ₹1.53 crore |
| Reversed | 23 | ₹68.5 lakh | – |
| Open: verify now | 3 | ₹26.4 lakh | – |

- **The oldest large unpaid invoice is also the second most extreme quantity.** Order 100888 (Hindustan Joshi Agencies, April 2024) has 972 air pressure regulators, 81 times the usual quantity, and solenoid valves at 44 times. It is worth ₹30.97 lakh and **nothing has been paid in 2.5 years**. It is most of the ₹31.30 lakh balance that the [order-to-cash reconciliation](../01_order_to_cash_reconciliation/) found as the largest overdue customer balance. An unpaid order this unusual points to a disputed or wrongly keyed order, not just a slow payer.
- **Three open orders** (Siddhivinayak Mishra Trading ₹14.3 lakh, Krishna Castings ₹6.8 lakh, Royal Reddy Moulders ₹5.3 lakh) are each at least 10 times their customer's usual order. They should be confirmed before delivery.

## 9. Business implications and recommendations

1. **Run the screen daily on new orders.** Confirm any order flagged Q1, Q2 or V1 with the customer before dispatch. It affects about 3 % of orders, so the workload is small.
2. **Investigate order 100888 before chasing payment.** Check the purchase order and delivery note with the customer. If the quantity was keyed wrongly, issue a credit note. If not, escalate it as a disputed debt.
3. **Review the 43 delivered-but-unpaid flagged orders** at month-end with finance, starting with the oldest. Unusual and unpaid together is the combination worth checking.
4. **Keep the price rule (P1) in the screen.** It found nothing, which is the evidence auditors want that pricing is controlled.
5. **Tune thresholds over time.** Most flags today are genuine large orders. Excluding orders with an approved customer purchase order would shorten the queue further.

## 10. Assumptions and limitations

- **Unusual is not wrong.** The screen finds outliers. Only a review against the customer's purchase order can confirm an error.
- **Payment as confirmation.** A customer paying in full is taken as acceptance of the order. Customers sometimes pay and dispute later.
- **History needed.** New products and customers have too little history for Q1, Q2 and V1, so their first orders are not screened.
- **Full-period benchmarks.** Medians use the whole period. A daily production screen should use only history before each order's date.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Line and order review tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
