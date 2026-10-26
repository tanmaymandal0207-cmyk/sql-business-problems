# Case Study · Sales Force Cost Efficiency

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 18 salespeople and the unassigned orders, 1 October 2025 – 30 September 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

The sales team costs about ₹2 crore a year in salaries. The CEO is preparing next year's budget and asks what the company gets back for that money, and whether pay is aligned with what each person and each role delivers. The [salesperson scorecard](../02_salesperson_scorecard/) measured the quality of each person's revenue; this study puts it against **what each person costs**.

## 2. Business questions

1. How much gross profit does each salesperson generate per rupee of salary, and what is the cost of sales as a share of revenue?
2. Which roles are most cost-efficient: managers and key account managers, or executives?
3. Does higher pay go with higher gross profit?
4. How much gross profit comes from orders with no salesperson?
5. Who is below a break-even level of gross profit for their cost, and by how much?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `employees`, `departments` | One row per employee / department | Salary, designation, hire date |
| `sales_orders` | One row per order | Salesperson, order date, status |
| `sales_order_items` | One row per product per order | Revenue |
| `products` | One row per product | Unit cost |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Period | 1 Oct 2025 – 30 Sep 2026 |
| Revenue | Quantity × unit price × (1 − discount %), orders not Cancelled or Returned; NULL discount = 0 % |
| Gross profit (GP) | Revenue − quantity × unit cost on lines with a known cost, plus uncosted revenue at the salesperson's own margin % |
| Salary cost | Annual salary × share of the period employed (from hire date) |
| **GP return** | GP ÷ salary cost |
| **Cost of sales** | Salary cost ÷ revenue |
| **Break-even** | GP return of **3.0**: gross profit covers the salary three times (salary, overheads and a contribution to profit). This is a rule-of-thumb parameter, not a finding; it can be changed in the script. |
| Role groups | Managers and key accounts (Regional Sales Managers, Key Account Managers) · Executives (Senior and Sales Executives) · Management (Head of Sales, not judged against break-even) |
| Too new to judge | Employed for less than a quarter of the period (the two September 2026 joiners) |

## 5. Analytical approach

1. **Efficiency table** (`sahyadri_b2b.sales_cost_efficiency`). One row per salesperson and one for unassigned orders: salary cost, orders, customers, revenue, GP, margin, GP return, cost of sales and break-even status.
2. **Role groups** and the team total.
3. **Pay alignment**: Pearson and Spearman correlation of salary with GP, for the 15 salespeople employed all year.
4. **Break-even gap**: GP needed, surplus or shortfall, and the extra revenue that would close it.

## 6. SQL techniques used

- `FULL OUTER JOIN` of the sales team with order activity, so people with no orders and orders with no salesperson both appear
- Pro-rated salary cost from hire date with `DATE_DIFF` and `GREATEST`
- Estimated GP on uncosted lines at each person's own margin, kept separate from measured GP
- Pearson and rank (Spearman) correlation in SQL
- Parameterised break-even threshold with `DECLARE`

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per salesperson plus one unassigned row |
| 02 | Revenue = source revenue for the period |
| 03 | Costed GP = source |
| 04 | GP = costed GP + uncosted revenue × own margin |
| 05 | Salary cost never above annual salary, and equal to it for full-year staff |
| 06 | **Salary cost = an independent recount** from the employee table |
| 07 | Orders = distinct source orders |
| 08 | Role group agrees with designation |
| 09 | No orders booked by people outside the Sales department |
| 10 | Gross margin between 0 and 100 % |

## 8. Findings

**The sales team returns ₹3.3 of gross profit for every rupee of salary; executives return more than managers.**

| Role group | People | Salary cost | Revenue | Gross profit | GP return | Cost of sales | Revenue per person-year |
|---|---:|---:|---:|---:|---:|---:|---:|
| Managers and key accounts | 7 | ₹1.09 crore | ₹24.10 crore | ₹3.67 crore | 3.4 | 4.53 % | ₹3.44 crore |
| Executives | 10 | ₹47.1 lakh | ₹14.64 crore | ₹2.31 crore | **4.9** | **3.21 %** | ₹1.81 crore |
| Head of Sales | 1 | ₹34.1 lakh | ₹42.7 lakh | ₹5.5 lakh | 0.2 | 79.7 % | — |
| No salesperson recorded | — | — | ₹1.19 crore | ₹20.2 lakh | — | — | — |
| **All** | **18** | **₹1.90 crore** | **₹40.36 crore** | **₹6.25 crore** | **3.3** | **4.71 %** | |

- Managers and key account managers sell about twice as much per person, but cost 2.7 times as much: ₹15.6 lakh on average against ₹5.8 lakh for the eight executives employed all year.
- **₹1.19 crore of revenue (138 orders, 91 customers) has no salesperson.** It earns ₹20.2 lakh of GP at no recorded sales cost. It is either inbound business or a recording gap.

**Individual returns range from 0.9 to 9.5.**

| Salesperson | Role | Salary cost | Revenue | GP | GP return | Status |
|---|---|---:|---:|---:|---:|---|
| Ritu Mishra | Senior Sales Executive | ₹6.60 lakh | ₹4.02 crore | ₹62.4 lakh | **9.5** | Above |
| Harish Tiwari | Sales Executive | ₹4.28 lakh | ₹2.21 crore | ₹35.0 lakh | 8.2 | Above |
| Deepak Chatterjee | Key Account Manager | ₹10.86 lakh | ₹4.84 crore | ₹80.7 lakh | 7.4 | Above |
| Rahul Kapoor | Senior Sales Executive | ₹6.57 lakh | ₹2.30 crore | ₹36.2 lakh | 5.5 | Above |
| Anjali Jadhav | Senior Sales Executive | ₹6.96 lakh | ₹2.36 crore | ₹34.8 lakh | 5.0 | Above |
| Tushar Gill | Sales Executive | ₹5.26 lakh | ₹1.45 crore | ₹24.7 lakh | 4.7 | Above |
| Deepika Jadhav | Key Account Manager | ₹11.70 lakh | ₹3.68 crore | ₹55.2 lakh | 4.7 | Above |
| Vikram Gupta | Sales Executive | ₹4.75 lakh | ₹1.17 crore | ₹19.1 lakh | 4.0 | Above |
| Prakash Sharma | Regional Sales Manager | ₹15.90 lakh | ₹3.76 crore | ₹52.9 lakh | 3.3 | Above |
| Manoj Verma | Regional Sales Manager | ₹17.62 lakh | ₹3.96 crore | ₹57.5 lakh | 3.3 | Above |
| Deepak Patil | Sales Executive | ₹3.87 lakh | ₹70.9 lakh | ₹11.7 lakh | 3.0 | Above (by ₹0.1 lakh) |
| Rohan Shah | Regional Sales Manager | ₹20.14 lakh | ₹3.53 crore | ₹56.9 lakh | 2.8 | **Below** |
| Tanvi Sandhu | Regional Sales Manager | ₹18.90 lakh | ₹2.65 crore | ₹39.0 lakh | 2.1 | **Below** |
| Arjun Gaikwad | Key Account Manager | ₹13.98 lakh | ₹1.69 crore | ₹25.0 lakh | 1.8 | **Below** |
| Ramesh Patil | Senior Sales Executive | ₹8.40 lakh | ₹42.4 lakh | ₹7.6 lakh | **0.9** | **Below** |

**Four people are below break-even, three of them in the highest-paid roles.**

| Salesperson | GP needed at 3.0 | Shortfall | Extra revenue needed at own margin |
|---|---:|---:|---:|
| Tanvi Sandhu | ₹56.7 lakh | ₹17.7 lakh | ₹1.20 crore |
| Ramesh Patil | ₹25.2 lakh | ₹17.6 lakh | ₹97.5 lakh |
| Arjun Gaikwad | ₹41.9 lakh | ₹16.9 lakh | ₹1.15 crore |
| Rohan Shah | ₹60.4 lakh | ₹3.5 lakh | ₹21.5 lakh |

- **Ramesh Patil is the clearest case**: the highest-paid executive (₹8.40 lakh) with the lowest revenue (₹42.4 lakh) and 91 orders in a year.
- Rohan Shah, the highest-paid regional manager, is only ₹3.5 lakh short; the gap is small enough to be noise.

**Pay follows gross profit only loosely.** For the 15 salespeople employed all year, the correlation between salary and GP is 0.47 (rank correlation 0.54). GP varies 10.6 times between the highest and lowest, salary 5.2 times. Pay is set by role and seniority more than by contribution.

## 9. Business implications and recommendations

1. **Review the four below-break-even roles before next year's budget.** For the two Regional Sales Managers and the Key Account Manager, check what non-selling work (team management, key account service) their salary covers. For Ramesh Patil, agree a target that closes a ₹17.6 lakh GP shortfall, or move his accounts to a more productive executive.
2. **Add a variable component linked to gross profit.** A correlation of 0.47 means high contributors such as Ritu Mishra (GP return 9.5) and Harish Tiwari (8.2) are paid the same as weaker peers in their role. A GP-linked incentive aligns cost with contribution.
3. **Hire executives rather than managers for growth.** Executives return ₹4.9 of GP per rupee against ₹3.4 for managers. The [salesperson ramp-up](../09_salesperson_ramp_up/) study shows new executives are productive from month 3.
4. **Assign the ₹1.19 crore of unassigned revenue.** Either record the salesperson or create an inside-sales owner; otherwise the business has no one responsible for 91 customers.
5. **Judge results on GP, not revenue.** Rankings by GP return differ from revenue rankings: Manoj Verma sells 82 % of Deepak Chatterjee's revenue but returns less than half as much per rupee of salary.

## 10. Assumptions and limitations

- **Salary only.** Incentives, benefits, travel and vehicle costs are not in the data. Fully loaded cost would lower every GP return; relative rankings would hold if those costs are similar within a role.
- **Break-even of 3.0 is a parameter.** It is a common rule of thumb, not a company standard. At 2.5, Rohan Shah would be above break-even; at 3.5, Prakash Sharma, Manoj Verma and Deepak Patil would fall below.
- **Order attribution.** Revenue is credited to the salesperson recorded on the order. Managers' time on coaching, team management and key-account service is not measured.
- **Accounts drive results.** As the ramp-up study showed, revenue depends heavily on the accounts each person holds; a low return can reflect a weak territory rather than weak selling.
- **Current unit cost**, as elsewhere in the repository. Uncosted lines (missing unit cost) are valued at the person's own margin.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Efficiency table, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
