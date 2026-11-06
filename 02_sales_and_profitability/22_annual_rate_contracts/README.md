# Case Study · Annual Rate Contracts: Who to Offer Them To, and What Volume to Ask For

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study covers 11 quarters of order lines (January 2024 – September 2026). It measures how steadily customers buy each product and each category, back-tests commitment levels on two pairs of years, and lists the contracts that would be offered now.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-06 |

---

## 1. Business problem

Several studies have recommended annual rate contracts for loyal accounts: a fixed price list for a year in return for a committed purchase value (see [discount consistency](../06_discount_consistency/) and [RFM segmentation](../../05_advanced_analytics/03_rfm_customer_segmentation/)). Before the sales head offers any, he needs to know what a contract should cover, who should get one, and how much each customer can commit to without the company having to chase shortfalls at year end.

## 2. Business questions

1. Should a contract be written per product or per category?
2. Which customer-category pairs buy steadily enough to commit?
3. What share of last year's value can they safely commit to, judged on what customers actually bought the following year?
4. How much revenue would the contracts cover, and with whom?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Line revenue |
| `products` | One row per product | Category |
| `product_categories` | One row per category | Category name |
| `customers` | One row per customer | Name, segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Revenue | Line value after discount, valid orders (not Cancelled or Returned) |
| Repeat buying | Quarters (out of 11) in which a customer bought a product or a category |
| Back-test A | Y1 = calendar 2024, Y2 = calendar 2025 |
| Back-test B | Y1 = October 2024 – September 2025, Y2 = October 2025 – September 2026 |
| **Qualifying pair** | A customer-category pair bought in all 4 quarters of Y1, with Y1 value of ₹2 lakh or more |
| Commitment | c × Y1 value; **met** if Y2 value ≥ commitment |
| Shortfall | MAX(0, commitment − Y2 value), summed and shown as a share of the commitments |
| **Safe level** | The highest commitment (in 5-point steps) met by at least 80 % of qualifying pairs in both back-tests |

## 5. Analytical approach

1. **Lines** (`sahyadri_b2b.rc_lines`) and repeat buying at product and category level.
2. **Pairs** (`sahyadri_b2b.rc_pairs`): every customer-category pair active in Y1 of each back-test, with quarters active, Y1 and Y2 value. Commitment met by quarters active and by size.
3. **Levels** (`sahyadri_b2b.rc_levels`): commitment levels from 30 % to 100 % for qualifying pairs; the safe level; pooled customer contracts as an alternative.
4. **Offers** (`sahyadri_b2b.rc_offers`): the contracts that the rule would offer from the latest year, by segment, category and customer.

## 6. SQL techniques used

- One query for two back-tests, by joining lines to a small table of test windows
- `COUNT(DISTINCT IF(date < y2_start, quarter, NULL))` to count active quarters in one year of a two-year window
- A grid of commitment levels from `GENERATE_ARRAY`, scored with `COUNTIF` and `GREATEST`
- `GROUP BY c HAVING MIN(met_share) >= 0.8` to pick a level that holds in every back-test

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Order lines and revenue = source |
| 02 | One row per test, customer and category; 1–4 quarters active in Y1 |
| 03 | Y1 value = all Y1 revenue of the window, both tests |
| 04 | Quarters active in Y1 = recount |
| 05 | Y2 value = recount (zero if the pair did not buy in Y2) |
| 06 | Qualifying = all 4 quarters and at least ₹2 lakh in Y1 |
| 07 | **Met share, commitment and shortfall at every level = recount**; 2 tests × 15 levels |
| 08 | **The safe level is met by 80 % in both tests, and the next level up is not** |
| 09 | Offers = latest-year pairs with 4 quarters and ₹2 lakh+; commitment = safe level × value |
| 10 | Offer values = back-test B's Y2 values for the same pairs |

## 8. Findings

**Contracts must be written per category, not per product.**

| Level | Pairs | Pairs bought in 9+ of 11 quarters | Revenue in 9+ quarters | Revenue in all 11 quarters | Revenue in only 1–2 quarters |
|---|---:|---:|---:|---:|---:|
| Customer × product | 13,526 | 85 | 8.8 % | 5.5 % | 54.2 % |
| Customer × category | 3,066 | 310 | **50.7 %** | 32.9 % | 7.5 % |

Customers rarely buy the same product quarter after quarter, but half of all revenue sits in customer-category pairs bought in at least 9 of the 11 quarters.

**Steady buying predicts next year's buying; the size of last year's purchases hardly does.**

| Quarters bought in Y1 | Pairs (A) | Commitment of 50 % met (A) | 80 % met (A) | Pairs (B) | 50 % met (B) | 80 % met (B) |
|---|---:|---:|---:|---:|---:|---:|
| 4 | 232 | **81.0 %** | 62.9 % | 278 | **79.9 %** | 60.8 % |
| 3 | 312 | 71.5 % | 55.1 % | 350 | 68.6 % | 51.4 % |
| 2 | 518 | 54.2 % | 45.9 % | 539 | 59.0 % | 46.6 % |
| 1 | 902 | 48.3 % | 43.5 % | 987 | 52.0 % | 46.3 % |

- Among pairs bought in all 4 quarters, the 50 % commitment is met by 73–89 % of pairs in every size band, with no consistent pattern by size. No pair of ₹2 lakh or more stopped buying the category altogether.
- The ₹2 lakh floor is there to keep the number of contracts manageable, not because smaller pairs are riskier.

**The safe commitment is half of last year's value.** Qualifying pairs: 153 in test A, 169 in test B.

| Commitment (% of Y1) | Met (A) | Shortfall (A) | Met (B) | Shortfall (B) |
|---:|---:|---:|---:|---:|
| 50 % | **81.7 %** | 7.8 % | **82.8 %** | 5.3 % |
| 55 % | 79.7 % | 9.6 % | 79.9 % | 6.5 % |
| 60 % | 75.8 % | 11.5 % | 76.3 % | 7.6 % |
| 70 % | 69.9 % | 15.0 % | 69.8 % | 10.2 % |
| 80 % | 62.7 % | 18.3 % | 62.1 % | 12.9 % |
| 100 % | 46.4 % | 25.4 % | 46.2 % | 19.8 % |

- At 50 %, about four in five contracts are met, and the shortfall on the rest is 5–8 % of the committed value.
- Asking for 80 % would leave more than a third of contracts short, even in test B, where qualifying pairs grew from ₹13.02 crore to ₹15.68 crore.
- The level holds in a flat year (test A, where qualifying pairs fell from ₹12.95 crore to ₹12.06 crore) and in a growth year (test B).

**One contract per customer, pooling its categories, is not safer.**

| Test | Customers | Categories per customer | 50 % met | 70 % met | 80 % met |
|---|---:|---:|---:|---:|---:|
| A | 39 | 3.9 | 74.4 % | 66.7 % | 59.0 % |
| B | 42 | 4.0 | 78.6 % | 57.1 % | 52.4 % |

A customer's categories tend to rise and fall together, so pooling them does not cancel out the risk.

**Contracts on offer now** (latest year, October 2025 – September 2026)

| | Value |
|---|---:|
| Contracts (customer-category pairs) | **221** |
| Customers | 60 |
| Last year's value | ₹20.01 crore (49.6 % of the year's revenue) |
| Committed at 50 % | **₹10.00 crore** |

| Segment | Contracts | Customers | Last year's value | Committed |
|---|---:|---:|---:|---:|
| Distributor | 87 | 21 | ₹9.97 crore | ₹4.99 crore |
| Enterprise | 102 | 27 | ₹8.42 crore | ₹4.21 crore |
| Mid-Market | 29 | 10 | ₹1.47 crore | ₹0.74 crore |
| SMB | 3 | 2 | ₹0.14 crore | ₹0.07 crore |

- Pumps carry the most contract value (25 customers, ₹6.08 crore), then Valves & Fittings (₹2.82 crore), Industrial Safety Equipment (₹2.77 crore) and Electric Motors & Drives (₹2.73 crore).
- The largest contracts: Siddhivinayak Mishra Trading Co. (10 categories, ₹3.32 crore last year, ₹1.66 crore committed), Krishna Castings Ltd (₹1.95 crore), Mahavir Pillai Spinning Mills (₹1.50 crore), Banerjee Sales Corporation (₹1.48 crore) and Maa Joshi Industrial Suppliers (₹1.44 crore).

## 9. Business implications and recommendations

1. **Write contracts per category, with a price list for every product in the category.** Product-level commitments would cover less than a tenth of revenue.
2. **Offer them only where the customer bought the category in every quarter of the last year,** and at least ₹2 lakh in value: 221 contracts with 60 customers.
3. **Ask for a commitment of 50 % of last year's value.** It was met by about 82 % of pairs in both back-tests. Higher commitments fail too often to be credible, and pooling categories in one customer contract does not change that.
4. **Price the contract for the security, not the volume.** A ₹10 crore committed base is about a quarter of annual revenue. Any price concession should be weighed against that certainty and the reduced selling effort. The data cannot say how much extra volume a contract would bring.
5. **Start with distributors and enterprise accounts,** which hold 92 % of the contract value, and with the four largest categories.
6. **Review the contracts each quarter** against a pro-rata commitment, so that a shortfall is spotted in time.

## 10. Assumptions and limitations

- **Back-tests use behaviour without contracts.** A signed commitment may raise purchases (customers consolidate suppliers) or not; the hit rates are a floor, not a forecast.
- **Two back-tests, sharing nine months.** Test B's Y1 overlaps test A's Y1 and Y2, so the tests are not independent.
- **Revenue, not quantity.** Commitments are in rupees; a price list change would change what a rupee commitment means.
- **Category as defined in the product master** (10 categories). Finer families might allow tighter contracts.
- **No price effect is modelled.** The study shows who can commit and how much, not what discount a contract should carry.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Line, pair, level and offer tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
