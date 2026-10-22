# Case Study · Salesperson Relationship Risk

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Window: 1 Oct 2025 – 30 Sep 2026, with 24 months used to count salesperson coverage.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-22 |

---

## 1. Business problem

In B2B distribution, many customers buy through one salesperson. When that person resigns, the relationship can leave with them. Two new sales executives joined in September 2026, and the sales head wants to **plan account coverage before anyone leaves**, not after. They need to know how much revenue depends on a single relationship, who holds it, and whether a change of salesperson has actually hurt revenue in the past.

## 2. Business questions

1. How much revenue depends on one salesperson relationship?
2. Which salespeople carry the most of that exposure?
3. What has happened to customers whose main salesperson changed?
4. Which accounts need a second contact first?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, salesperson, order date, status |
| `sales_order_items` | One row per product per order | Revenue |
| `customers` | One row per customer | Name and segment |
| `employees` | One row per employee | Salesperson name, designation and hire date |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)`, orders not Cancelled or Returned |
| Primary salesperson | The employee with the most attributed revenue for the customer in the 12-month window (ties go to the lower `employee_id`) |
| Primary share | Primary salesperson's revenue ÷ the customer's attributed revenue |
| Single-threaded | Only one salesperson has served the customer in 24 months |
| Dominant | More than one salesperson in 24 months, but the primary holds ≥ 80 % of attributed revenue |
| Shared | Primary holds less than 80 % |
| High-dependency revenue | Revenue from Single-threaded plus Dominant customers |
| Handover outcome | Compares the customer's primary in Oct 2024 – Sep 2025 with Oct 2025 – Sep 2026: same, changed, stopped buying, or no salesperson recorded |

Orders with no salesperson (3.5 % of orders) stay in customer revenue but are not credited to anyone.

## 5. Analytical approach

1. **Coverage table** (`sahyadri_b2b.customer_relationship_coverage`). One row per active customer with 12-month revenue, primary salesperson, primary share, salespeople seen in 24 months, and relationship type.
2. **Revenue by relationship type.**
3. **Exposure by salesperson.** Book size, high-dependency revenue and how much of the book is one account.
4. **Handover evidence** (`sahyadri_b2b.salesperson_handover`). Revenue change for customers who kept their salesperson against those whose salesperson changed.
5. **Succession list.** The 10 largest single-threaded accounts.

## 6. SQL techniques used

- `ROW_NUMBER() OVER (PARTITION BY customer ORDER BY SUM(revenue) DESC, employee_id)` for a deterministic primary salesperson
- `COUNT(DISTINCT employee_id)` over a longer coverage window than the revenue window
- A rule-based `CASE` classification with an explicit order of precedence
- A period-on-period comparison at customer level, classified by outcome
- `QUALIFY` to take the top 10 after computing shares over all rows

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer |
| 02 | Customer count = active customers in the source |
| 03 | 12-month revenue = source total |
| 04 | Unattributed revenue = source revenue on orders with no salesperson |
| 05 | **Primary recomputed independently:** each primary has the customer's maximum salesperson revenue |
| 06 | Salesperson count recomputed independently |
| 07 | Every relationship type obeys its rule |
| 08 | Primary share is between 0 and 1 |
| 09 | Handover prior-period revenue = source revenue for customers with a salesperson in that period |
| 10 | Every handover outcome obeys its rule |

## 8. Findings

**69.7 % of revenue sits with customers where one salesperson holds at least 80 % of the relationship.**

| Relationship type | Customers | 12-month revenue | Share |
|---|---:|---:|---:|
| Dominant (one person ≥ 80 %) | 169 | ₹25.65 crore | 63.5 % |
| Shared | 79 | ₹12.24 crore | 30.3 % |
| Single-threaded (one person only) | 118 | ₹2.47 crore | 6.1 % |
| Unassigned | 1 | ₹0.1 lakh | 0.0 % |
| **Total** | **367** | **₹40.36 crore** | |

- **Pure single-threading is a small-account issue.** The 118 single-threaded customers average ₹2.1 lakh a year. Large accounts have usually seen several salespeople, but one of them still holds almost all the business.

**Changing salesperson has gone with weaker revenue.**

| Handover outcome (Oct 2024 – Sep 2025 → Oct 2025 – Sep 2026) | Customers | Revenue change | Median customer | Customers declining |
|---|---:|---:|---:|---:|
| Same salesperson | 234 | **+35.0 %** | +20.0 % | 42.3 % |
| Salesperson changed | 61 | **−7.1 %** | +0.3 % | 49.2 % |
| Stopped buying | 41 | −100 % | | 100 % |

- The largest handover moved **15 customers from Tanvi Sandhu to Rahul Kapoor** (joined June 2025). Their revenue fell from ₹2.41 crore to ₹2.27 crore (−5.8 %) in a year when the company grew.

**Exposure is concentrated in a few people, including recent joiners:**

| Salesperson | Designation | High-dependency revenue | % of their book | Largest account, % of book |
|---|---|---:|---:|---:|
| Manoj Verma | Regional Sales Manager | ₹4.15 crore | 98.3 % | 46.2 % (Krishna Castings) |
| Prakash Sharma | Regional Sales Manager | ₹3.77 crore | 92.4 % | 20.0 % |
| Deepika Jadhav | Key Account Manager | ₹3.38 crore | 91.8 % | 28.0 % |
| Rahul Kapoor | Senior Sales Executive, joined Jun 2025 | ₹2.42 crore | 95.5 % | 56.7 % (Maa Joshi Industrial) |
| Harish Tiwari | Sales Executive, joined Nov 2024 | ₹1.86 crore | 95.4 % | **85.7 %** (Banerjee Sales Corporation) |

- **The top three salespeople alone hold ₹11.30 crore (28.0 % of company revenue) in high-dependency relationships.**
- **A junior sales executive holds one of the largest accounts almost alone.** Banerjee Sales Corporation (customer 1178, ₹1.67 crore) buys 99.3 % through Harish Tiwari. This is the account behind the ₹1.19 crore single order flagged in [Customer revenue risk](../01_customer_revenue_risk/).

The largest single-threaded accounts are Indus Specialty Chemicals (₹18.9 lakh, Tanvi Sandhu), Royal Petrochem (₹18.4 lakh, Deepak Chatterjee) and Bharat Shah Enterprises (₹12.5 lakh, Deepak Chatterjee). Deepak Chatterjee and Anjali Jadhav each hold several of the top ten.

## 9. Business implications and recommendations

1. **Assign a named second contact to every account above ₹50 lakh a year** where one salesperson holds 80 % or more. Start with Krishna Castings, Banerjee Sales Corporation and Maa Joshi Industrial Suppliers.
2. **Pair senior cover with junior owners of key accounts.** Harish Tiwari and Rahul Kapoor hold large accounts almost alone. A regional manager should join the relationship formally.
3. **Plan handovers rather than reassigning accounts outright.** Accounts that changed hands declined while retained accounts grew 35 %. Use a joint-visit period and a handover note for every reassignment.
4. **Give the two September 2026 joiners single-threaded small accounts first**, as second contacts, before any key account moves.
5. **Track high-dependency revenue as a quarterly risk KPI** per salesperson, alongside sales targets.
6. **Make the salesperson mandatory on orders.** 352 orders have none, which hides who owns the relationship.

## 10. Assumptions and limitations

- **Order taker as relationship owner.** The data records who booked each order, not who manages the account. Where a team serves an account, the dependency may be lower than it looks.
- **Association, not cause.** Accounts may change hands *because* they were already declining or the salesperson left. The handover comparison shows the risk is real enough to manage, not its exact size.
- **No leaver data.** `employees` has no exit date, so the analysis cannot tell a planned reassignment from a resignation.
- **Thresholds.** The 80 % dominance threshold and 24-month coverage window are declared at the top of the script and can be changed.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Coverage and handover tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
