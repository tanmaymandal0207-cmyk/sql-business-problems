# Case Study · Sales Commission Plan Simulation

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Four commission plans, each calibrated to the same ₹77.47 lakh budget, run on the last 12 months of orders (October 2025 – September 2026) for 15 salespeople.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-28 |

---

## 1. Business problem

The company is introducing commission for its salespeople, with a budget equal to 2 % of their net revenue. HR has drafted four designs. Earlier studies showed that discounts do not buy volume ([discount response](../../05_advanced_analytics/11_discount_volume_response/)) and that sales rankings are noisy ([ranking stability](../13_salesperson_ranking_stability/)). Before choosing a plan, the sales director wants each design run on the last 12 months of actual orders, so that everyone can see who would have earned what and what behaviour each plan rewards.

## 2. Business questions

1. How much would each salesperson have earned under each plan?
2. Which plan pays most for gross profit rather than for volume?
3. How strongly does each plan discourage discounting?
4. Which plan should be chosen, and with what safeguards?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Salesperson, order date, status |
| `sales_order_items` | One row per product per order | Revenue, discount |
| `products` | One row per product | Unit cost |
| `payments` | One row per payment | Collection status |
| `employees` | One row per employee | Name, designation, hire date, salary |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Period | Orders dated 1 Oct 2025 – 30 Sep 2026, not Cancelled or Returned |
| Salespeople | Everyone with orders in the period, except the Head of Sales (paid on team results) and unassigned orders: 15 people |
| Gross profit (GP) | Net revenue − quantity × unit cost, on lines with a known unit cost |
| **Budget** | 2 % of the team's net revenue = ₹77.47 lakh. Plans B–D are scaled to cost exactly the same, so only who gets paid differs. |
| **A. Revenue** | 2 % of net revenue |
| **B. Gross profit** | 13.02 % of GP |
| **C. Quota tiers** | 1.39 % of revenue up to quota, 4.16 % above it (a 1 : 3 ratio). Quota = prior-12-month revenue × 1.10, annualised for people hired during that year. |
| **D. GP on cash** | 17.48 % of the GP of orders fully paid by 30 Sep 2026 |
| Discount sensitivity | Commission lost for each extra ₹100 of discount on a line: ₹2 under A; the GP rate under B and D (a rupee of discount is a rupee of GP); the tier rate under C |

## 5. Analytical approach

1. **Base table** (`sahyadri_b2b.cp_base`). Revenue, GP, discount, collected GP, prior-year revenue, months employed and quota per salesperson.
2. **Plan table** (`sahyadri_b2b.cp_plans`). Calibrated rates and the payout under each plan.
3. **What each plan rewards**: spread, link to GP and margin, pay as a share of salary, discount sensitivity, winners and losers, and the quota outcomes.

## 6. SQL techniques used

- Budget-neutral calibration: each plan's rate solved in SQL so that all four cost the same
- Tiered payouts with `LEAST` and `GREATEST`
- Pro-rated quotas from hire dates with `DATE_DIFF(…, MONTH)`
- Order-level collection test feeding a person-level GP measure, without row multiplication
- Plans compared side by side in one long table (`UNION ALL`) with correlations to GP and margin

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Revenue and GP per salesperson = source |
| 02 | 15 salespeople; no Head of Sales, no unassigned orders |
| 03 | **Every plan costs exactly the budget** |
| 04 | Plan A = 2 % of net revenue for everyone |
| 05 | Plan B pays the same share of GP to everyone |
| 06 | Quota = 1.10 × prior revenue, annualised for months employed (1–12) |
| 07 | Plan C = k × (revenue to quota + 3 × revenue above quota) |
| 08 | **Collected GP = a rebuild from fully paid orders** |
| 09 | Plan D pays the same share of collected GP to everyone |
| 10 | Prior revenue = source for the prior 12 months |

## 8. Findings

**The budget is large: ₹77.47 lakh is 50 % of the 15 salaries (₹155.8 lakh) and 13 % of their gross profit (₹594.9 lakh).**

**Payouts by plan (₹ lakh a year)**

| Salesperson | Revenue | GP margin | Discount | % of quota | A. Revenue | B. GP | C. Quota tiers | D. GP on cash |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Deepak Chatterjee (106) | 483.6 | 16.6 % | 9.9 % | 103 % | 9.67 | **10.48** | **7.06** | **11.68** |
| Ritu Mishra (109) | 401.9 | 15.4 % | 9.3 % | 152 % | 8.04 | 8.07 | 9.39 | 7.74 |
| Manoj Verma (105) | 396.0 | 14.4 % | 9.2 % | 120 % | 7.92 | 7.43 | 7.34 | 6.90 |
| Prakash Sharma (103) | 376.0 | 14.0 % | 8.7 % | 151 % | 7.52 | 6.85 | 8.72 | 6.22 |
| Rohan Shah (104) | 352.7 | 16.0 % | 8.0 % | 105 % | 7.05 | 7.36 | **5.31** | 6.58 |
| Tanvi Sandhu (102) | 264.9 | 14.7 % | 10.0 % | **58 %** | 5.30 | 5.06 | **3.67** | 5.00 |
| Rahul Kapoor (111) | 229.8 | 15.5 % | 8.6 % | **226 %** | 4.60 | 4.63 | **6.74** | 4.82 |
| Harish Tiwari (114) | 221.4 | 15.8 % | 11.8 % | **243 %** | 4.43 | 4.56 | **6.68** | 5.61 |
| Arjun Gaikwad (107) | 169.0 | 14.7 % | 7.7 % | 68 % | 3.38 | 3.23 | 2.34 | **2.59** |
| Ramesh Patil (112) | 42.4 | 17.8 % | 5.4 % | 228 % | 0.85 | 0.98 | 1.25 | 1.15 |

(Selected rows; Step 2 lists all 15.)

**What each plan rewards**

| Plan | Lowest | Highest | Correlation with GP | Correlation of pay rate with margin | Average pay as % of salary | Highest |
|---|---:|---:|---:|---:|---:|---:|
| A. Revenue | 0.85 | 9.67 | 0.991 | 0.15 | 56.4 % | 121.8 % |
| B. Gross profit | 0.98 | 10.48 | **1.000** | **1.00** | 57.1 % | 122.2 % |
| C. Quota tiers | 0.98 | 9.39 | **0.831** | 0.21 | 61.0 % | **156.1 %** |
| D. GP on cash | 1.15 | 11.68 | 0.979 | 0.82 | 58.8 % | 131.1 % |

- **Revenue and GP plans pay almost the same people almost the same amounts.** GP margins only range from 14.0 % to 17.8 % across the team, so moving from A to B changes individual pay by −9.0 % to +15.9 %. Nine people gain (average margin 16.1 %) and six lose (14.5 %); ₹1.96 lakh moves between the groups.
- **The real difference is the price of a discount.**

| Commission lost per ₹100 of extra discount | A. Revenue | B. Gross profit | C. below quota | C. above quota | D. GP on cash |
|---|---:|---:|---:|---:|---:|
| ₹ | 2.00 | **13.02** | 1.39 | 4.16 | **17.48** |

Under the revenue plan, a salesperson gives up ₹2 of commission to give away ₹100 of discount; under the GP plan, ₹13. Since discounts do not buy volume on this data, the GP plan aligns the incentive with the company's interest at no extra cost.

**The quota plan pays for weak quotas, not for performance.**

- Its payouts track GP least (correlation 0.83). The three people furthest above quota (Harish Tiwari 243 %, Ramesh Patil 228 %, Rahul Kapoor 226 %) had small or partial prior years; even with annualisation, their quotas were low.
- The top seller by revenue and GP, Deepak Chatterjee, would earn 27 % less than under the revenue plan because his quota was already high (103 % attained).
- Tanvi Sandhu, whose revenue fell 36 % from the prior year, would still earn ₹3.67 lakh.

**GP on cash rewards collection, but pays later.** 74.5 % of the period's GP was on orders fully paid by 30 September. Arjun Gaikwad would earn 23 % less than under the revenue plan because more of his orders are unpaid; Harish Tiwari 27 % more.

## 9. Business implications and recommendations

1. **Choose the gross profit plan (B), paid on collection (D) where cash discipline matters.** It costs the same as a revenue plan, pays the same people similar amounts, and makes discounting 6.5 times more expensive to the salesperson.
2. **Do not use last-year-based quotas without a quota review.** On this data a 1 : 3 tier plan transfers money to people with weak prior years and away from the strongest seller. If quotas are wanted, set them from territory potential, not from history alone.
3. **Reconsider the 2 % budget.** It equals half of base salaries on average and more than a full salary for two people. A lower rate, or a cap (for example 50 % of salary), keeps the incentive and the cost under control.
4. **Pay in bands, not ranks.** The [ranking stability](../13_salesperson_ranking_stability/) study shows most differences between salespeople are not statistically real; a proportional GP plan already avoids rank-based cliffs.
5. **Assign or exclude unassigned orders before the plan starts**, so that no one is paid for them by default, and set a team-based plan for the Head of Sales.

## 10. Assumptions and limitations

- **Behaviour is held constant.** The simulation applies each plan to what actually happened; real plans change behaviour, which is the point of choosing one.
- **Current unit cost.** GP uses `products.unit_cost`, a single current cost (see [gross margin bridge](../11_gross_margin_bridge/) for its limits).
- **Collection timing.** Plan D counts orders paid by 30 Sep 2026; recent orders would be paid in later months, so D's payouts would catch up over time.
- **Annualised quotas** assume an even sales rate over the months employed; ramp-up (see [salesperson ramp-up](../09_salesperson_ramp_up/)) makes early months lower.
- **Salaries as recorded** in `employees`; incentives are compared with base salary only.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Base and plan tables, and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
