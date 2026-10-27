# Case Study · January Price Increase and Price Discipline

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 28,201 order lines across two January price increases (2025 and 2026); 8,121 repeat purchases of 1,345 customer × product pairs tested for buying ahead.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-27 |

---

## 1. Business problem

List prices go up every January. The commercial team is planning the next increase, and the finance controller has three worries before approving it:

- the last increases may not have reached every product and customer;
- customers may have bought ahead in December at the old prices;
- invoice prices are entered on each order and may drift away from the price list.

She wants evidence on all three, and on whether any customer or salesperson gets systematically better prices than the list.

## 2. Business questions

1. How large was each January increase, and was it applied to every product?
2. Did customers buy ahead of the increase?
3. How closely do invoice prices follow the list, and how much is billed below it?
4. Does any customer, salesperson or product get systematically lower invoice prices?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Quantity, invoice price, discount |
| `sales_orders` | One row per order | Customer, salesperson, order date, status |
| `products` | One row per product | List price (`selling_price`) |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Lines | All order lines, any status (the price is set when the order is entered) |
| **Price factor** | Median of `unit_price ÷ selling_price` in a calendar year. `selling_price` is today's list, so the factor estimates the list in force that year relative to today. |
| List in force | `selling_price` × the year's price factor |
| **Price deviation** | `unit_price ÷ list in force − 1`: how far the invoice price (before discount) is from the list |
| January increase | Price factor this year ÷ last year − 1 |
| Product step | Mean price ratio of a product this year ÷ last year − 1; z = (product step − company step) ÷ standard error (delta method, from line variation) |
| **Over-dispersion ratio** | Σ n (group mean − overall mean)² ÷ overall variance ÷ (groups − 1). About 1 = groups differ only by chance; z = (ratio − 1) × √((groups − 1) ÷ 2) |
| **Quantity index** | Quantity ÷ the customer × product pair's median quantity (pairs bought 4+ times) |
| **Gap index** | Days to the pair's next purchase ÷ the pair's median gap |
| Buying ahead | Would show as more purchases above usual quantity **and** longer gaps after purchases made in late December (16–31 Dec) |

## 5. Analytical approach

1. **Line table** (`sahyadri_b2b.pi_lines`). Price factor, list in force and price deviation for every line.
2. **Product step table** (`sahyadri_b2b.pi_product_steps`). Each product's increase in 2025 and 2026 against the company step, with z-scores. Median price ratio by month, to date the step. Value of each increase on net revenue.
3. **Price band**: the distribution of deviations, value billed below and above list, and the **dispersion table** (`sahyadri_b2b.pi_dispersion`) of mean deviation by customer, salesperson, product and discount band.
4. **Repeat purchase table** (`sahyadri_b2b.pi_repeat_purchases`). Quantity and gap indices by purchase window (late December, early January, late March, rest of year), z-tests for late December, and monthly order seasonality.

## 6. SQL techniques used

- Inferring a historical price list from transactions with `PERCENTILE_CONT(…) OVER (PARTITION BY year)`
- Ratio-of-means standard errors (delta method) and z-scores per product
- Over-dispersion (between-group variance against within-group noise) for four dimensions in one `UNION ALL` table
- Customer × product purchase sequences with `LEAD()` and per-pair medians as baselines
- Two-proportion z-tests written in SQL
- Validation that recomputes `LEAD()` with a self-join and confirms the median factor splits each year's lines in half

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Line table = source order lines, one row each |
| 02 | **Price factor is each year's median** (splits lines in half) |
| 03 | Deviation = unit price ÷ list in force − 1 |
| 04 | Below-list + above-list = net difference |
| 05 | Product steps exist for every product sold in consecutive years |
| 06 | Product step z recomputed |
| 07 | Dispersion members cover every line in each dimension |
| 08 | Customer mean deviations = independent recount |
| 09 | Repeat-purchase rows = customer × product pairs bought 4+ times |
| 10 | **Next purchase date from `LEAD()` = a self-join recount** |

## 8. Findings

**Both increases were applied in full, to every product, from 1 January.**

| Year | Price factor (list in force ÷ today's list) | January increase | Products | Range of product steps | Products off policy (\|z\| ≥ 3) | Value of the increase |
|---|---:|---:|---:|---|---:|---:|
| 2024 | 0.8997 | – | | | | |
| 2025 | 0.9497 | **+5.55 %** | 186 | 4.3 % to 7.1 % | 0 | ₹1.66 crore |
| 2026 | 1.0002 | **+5.32 %** | 186 | 3.5 % to 7.8 % | 1 | ₹1.58 crore (Jan–Sep) |

- The spread of product steps is what line-level price variation alone would produce (mean z² of 0.81 and 1.17, against 1 for pure chance).
- **One exception:** Y-Strainer CI 2 in rose 7.81 % in January 2026 against 5.32 % for the company (z = 4.53), on only 6 lines in 2026. Worth confirming that its 2026 list entry is correct.
- The step happens at the start of January; monthly price factors are flat within each year.

**Customers did not buy ahead of the increase.**

| Purchase window | Purchases | Quantity index | Above usual quantity | Gap index | Next purchase later than usual |
|---|---:|---:|---:|---:|---:|
| Late December | 414 | 1.36 | 45.4 % | 1.35 | 44.1 % |
| Early January | 439 | 1.23 | 41.2 % | 1.44 | 46.8 % |
| Late March | 595 | 1.65 | 46.9 % | 1.55 | 48.1 % |
| Rest of year | 6,673 | 1.33 | 43.3 % | 1.60 | 47.4 % |

- Late-December purchases are **not** larger than usual (45.4 % vs 43.3 %, z = 0.84) and are **not** followed by a longer wait (44.1 % vs 47.4 %, z = −1.26). Buying ahead would show both.
- December is a busy month (orders 1.35 × the monthly average, close to March at 1.30, the financial year-end), but January does not fall below normal (0.96, against 0.94 for February). The December peak is seasonal demand, not orders pulled forward from January.

**Invoice prices are not taken from the price list. They are spread evenly within ±3 % of it.**

| Deviation from list in force | Lines | Share |
|---|---:|---:|
| −3 % | 2,296 | 8.1 % |
| −2 % | 4,675 | 16.6 % |
| −1 % | 4,823 | 17.1 % |
| 0 % | 4,642 | 16.5 % |
| +1 % | 4,623 | 16.4 % |
| +2 % | 4,685 | 16.6 % |
| +3 % | 2,457 | 8.7 % |

- **Only 4 of 28,201 lines are billed at the list price** (within half a paisa). Every deviation lies between −3.01 % and +3.03 %, and within that band all values are about equally common: a flat distribution, as if the price were typed in anywhere inside a permitted tolerance.
- **The deviations cancel out.** ₹77.9 lakh was billed below list and ₹80.7 lakh above, a net **+₹2.8 lakh** on ₹105.66 crore at list prices.
- **No one gets systematically better prices.**

| Dimension | Members | Over-dispersion ratio | z | Members beyond \|z\| ≥ 3 |
|---|---:|---:|---:|---:|
| Customer | 431 | 1.11 | 1.59 | 2 (about 1 expected by chance) |
| Product | 186 | 1.04 | 0.43 | 1 |
| Salesperson | 17 | 0.55 | −1.27 | 0 |
| Discount band | 4 | 0.38 | −0.75 | 0 |

- The deviation is unrelated to the discount (correlation 0.005), so it is not used as a hidden second discount.

## 9. Business implications and recommendations

1. **The January increase mechanism works; repeat it.** Both increases reached every product from the first day, added ₹1.66 crore in 2025 and ₹1.58 crore in January–September 2026, and did not trigger buying ahead. There is no need for order caps or price protection in December.
2. **Lock invoice prices to the price list in the ERP.** Today the price on each line can be anywhere within ±3 % of the list. The net effect is small (+₹2.8 lakh), but ₹77.9 lakh was billed below list without any approval trail, and the [discount consistency](../06_discount_consistency/) controls do not cover it. Price concessions should go through the discount field only, where they are visible and approved.
3. **Investigate how the ±3 % band arises.** A flat spread with no customer, salesperson or product pattern points to a system tolerance or manual entry rather than negotiation. Check the order-entry screen and any price override rights.
4. **Confirm the 2026 list price of Y-Strainer CI 2 in** (+7.8 % against +5.3 % for everything else).
5. **Plan December capacity for seasonal demand.** The December peak (1.35 × normal) is real demand, not pre-buying; the [dispatch workload plan](../../03_operations_and_supply_chain/04_dispatch_workload_planning/) should treat December like March.

## 10. Assumptions and limitations

- **Historical list prices are inferred.** Only today's list price is stored. The list in force in 2024 and 2025 is estimated as today's list × the year's median price ratio. Because the step is the same for all products, this matches the data closely; a true price-list history table would remove the assumption.
- **Calendar-year price changes.** The study assumes increases take effect on 1 January, which the monthly price factors confirm.
- **Invoice price before discount.** Discounts are a separate decision, studied in [discount consistency](../06_discount_consistency/) and [discount and margin erosion](../01_discount_margin_erosion/).
- **Buying ahead tested on regular purchases only** (customer × product pairs bought 4+ times). Occasional buyers have no usual quantity or gap to compare with.
- **Two price increases** only. A different size of increase could produce a different response.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Line, product step, dispersion and repeat purchase tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
