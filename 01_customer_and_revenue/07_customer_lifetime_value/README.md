# Case Study · Customer Lifetime Value

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Retention measured from Oct 2024 – Sep 2025 to Oct 2025 – Sep 2026; CLV over five years from 30 Sep 2026.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-24 |

---

## 1. Business problem

Sales and marketing spend is allocated on last year's revenue. A customer who buys once and never returns looks the same as one who will buy for years. The CFO wants a **forward-looking value for every customer**: the margin they are expected to generate over the next five years, allowing for the chance that they leave. That value should guide account coverage, retention effort and how much the company can afford to spend converting one-off buyers into repeat customers.

## 2. Business questions

1. What is each customer's expected future margin over five years?
2. What drives retention, and how certain are the retention rates?
3. How concentrated is future value, and how does it differ by segment?
4. What is it worth to turn a one-order customer into a repeat buyer?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Order counts, activity in each year |
| `sales_order_items` | One row per product per order | Revenue |
| `products` | One row per product | Unit cost |
| `shipments` | One row per shipment | Freight |
| `customers` | One row per customer | Names and segment |

## 4. Method and metric definitions

**CLV = m × Σₜ₌₁…₅ (r ÷ (1 + d))ᵗ = m × q (1 − q⁵) ÷ (1 − q), where q = r ÷ (1 + d)**

| Term | Definition |
|---|---|
| m, annual margin | Gross profit − freight in the last 12 months (orders not Cancelled or Returned) |
| r, retention rate | Share of customers active in Oct 2024 – Sep 2025 who bought again in Oct 2025 – Sep 2026, by purchase-frequency band |
| Frequency band | Orders in the year: 1, 2–5, or 6 or more |
| Laplace smoothing | r = (retained + 1) ÷ (customers + 2), so a band with 100 % observed retention is not treated as certain |
| 95 % interval | r ± 1.96 × √(r (1 − r) ÷ n), capped to 0–1, used for low and high CLV |
| d, discount rate | 12 % a year, the same cost of capital as the [customer profitability](../../05_advanced_analytics/05_customer_profitability_whale_curve/) study |
| CLV multiple | CLV ÷ annual margin for the band |

CLV is **future value only**: the current year's margin is not included. Margin is before order handling and sales effort (see Limitations).

## 5. Analytical approach

1. **Retention bands** (`sahyadri_b2b.clv_retention_bands`). Observed and smoothed retention with 95 % intervals for each frequency band.
2. **Customer CLV table** (`sahyadri_b2b.customer_lifetime_value`). Annual margin, band, retention, CLV multiple, CLV with a low–high range, and rank.
3. **CLV by segment and band.**
4. **Concentration** of future value.
5. **Value of a second order** for one-order customers.

## 6. SQL techniques used

- A closed-form geometric series for the discounted annuity factor, computed with `POW`
- Laplace smoothing and a normal-approximation binomial interval for retention rates
- Low, central and high CLV from one pass, by applying three annuity factors
- Validation that recomputes the annuity factor as an explicit sum with `UNNEST(GENERATE_ARRAY(1, 5))`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer |
| 02 | Customers = active customers in the last 12 months (367) |
| 03 | Revenue = source (₹40.36 crore, matching other 12-month case studies) |
| 04 | Retention bands cover every customer active in the first year (340) |
| 05 | Smoothed rate = (retained + 1) ÷ (customers + 2) |
| 06 | Every interval contains its rate and stays within 0–1 |
| 07 | **The closed-form multiple equals the explicit sum of five discounted terms** |
| 08 | CLV = annual margin × multiple on every row |
| 09 | CLV lies within its low–high range |
| 10 | Every frequency band matches the order count |

## 8. Findings

**How often a customer orders is a far stronger predictor of retention than anything else.**

| Orders in the year | Customers | Retained next year | Smoothed rate (95 % interval) | CLV multiple of annual margin |
|---|---:|---:|---:|---:|
| 1 order | 56 | 20 | **36.2 %** (23.6–48.8 %) | 0.48 |
| 2–5 orders | 125 | 118 | 93.7 % (89.4–98.0 %) | 3.02 |
| 6+ orders | 159 | 159 | 99.4 % (98.2–100 %) | 3.54 |

A customer who orders once has about a one-in-three chance of coming back. Customers with two to five orders are retained 2.6 times as often.

**The current base is worth ₹20.71 crore of margin over five years** (range ₹19.92 – ₹21.21 crore), about 3.5 times this year's ₹5.97 crore.

| Segment | Customers | Annual margin | 5-year CLV | Share | Average CLV |
|---|---:|---:|---:|---:|---:|
| Enterprise | 62 | ₹2.27 crore | ₹7.99 crore | 38.6 % | ₹12.9 lakh |
| Distributor | 64 | ₹2.25 crore | ₹7.77 crore | 37.5 % | ₹12.1 lakh |
| Mid-Market | 104 | ₹1.09 crore | ₹3.75 crore | 18.1 % | ₹3.6 lakh |
| SMB | 137 | ₹0.37 crore | ₹1.20 crore | 5.8 % | ₹0.9 lakh |

**Future value is concentrated.**

| Customer group | Customers | 5-year CLV | Share |
|---|---:|---:|---:|
| Top 10 | 10 | ₹7.40 crore | 35.7 % |
| Next 40 | 40 | ₹6.91 crore | 33.4 % |
| All others | 312 | ₹6.40 crore | 30.9 % |
| Zero or negative margin | 5 | – | – |

- **50 customers hold 69 % of future value.** The top five are Siddhivinayak Mishra Trading (₹1.76 crore), Krishna Castings (₹92.1 lakh), Banerjee Sales Corporation (₹83.9 lakh), Maa Joshi Industrial Suppliers (₹83.5 lakh) and Mahavir Pillai Spinning Mills (₹76.8 lakh).
- **Customers with 6 or more orders a year hold 94.8 % of CLV.** The 65 one-order customers hold 0.2 %.

**A second order is worth about ₹9,800 for a typical one-order customer.** Moving a one-order customer (median annual margin ₹3,848) to the repeat-buyer band raises their CLV multiple from 0.48 to 3.02. If all 65 became repeat buyers, future margin would rise by ₹21.3 lakh.

## 9. Business implications and recommendations

1. **Use CLV, not last year's revenue, to allocate key-account cover.** The top 50 customers hold 69 % of future value. Each should have a named owner and a second contact (see [Salesperson relationship risk](../04_salesperson_relationship_risk/)).
2. **Make the second order the onboarding goal.** Retention jumps from 36 % to 94 % once a customer orders more than once. Follow up every first order within 30 days (see [New customer activation](../05_new_customer_activation/)).
3. **Cap the cost of chasing a second order at about ₹5,000 per customer.** The typical gain is about ₹9,800 of margin, so spending up to half of it leaves a margin of safety for the uncertainty in the one-order retention rate (23.6–48.8 %).
4. **Value SMB customers after cost to serve.** SMB CLV is ₹1.20 crore before sales and handling costs. The [whale curve](../../05_advanced_analytics/05_customer_profitability_whale_curve/) shows these costs exceed SMB margin, so SMB growth should come through lower-cost channels.
5. **Refresh CLV every quarter** and track the total as a measure of the health of the customer base, alongside revenue.

## 10. Assumptions and limitations

- **Margin before selling costs.** m is gross profit less freight. Order handling, sales effort and cost of credit are not deducted, so CLV is higher than contribution-based value, especially for SMB.
- **Constant margin and retention.** Each customer's margin is assumed flat for five years, and retention is assumed constant for their band. In practice, customers move between bands (see the [Markov customer-state model](../../05_advanced_analytics/08_customer_state_markov/)).
- **One year of retention history.** Retention is measured over a single year-to-year transition. The intervals show the resulting uncertainty.
- **Large one-off orders.** A customer with an unusual large order in the last 12 months (for example Banerjee Sales Corporation) has an inflated m, and so an inflated CLV.
- **Parameters.** The 12 % discount rate and 5-year horizon are declared at the top of the script and can be changed.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Retention band and CLV tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
