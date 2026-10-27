# Case Study · Key-Account Selection and Regression to the Mean

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Customer revenue compared across three January–September windows (2024, 2025, 2026): 288 customers in the first pair and 322 in the second.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-28 |

---

## 1. Business problem

Each October the sales director names the 30 largest customers of the year to date as key accounts and gives every account a growth target equal to the company's planned growth. Account managers on the biggest accounts say the targets are never met, while managers of small accounts beat theirs easily. The director wants to know whether this is a performance problem or a statistical one, and whether the way key accounts are chosen should change.

## 2. Business questions

1. How stable is the top of the customer list from one year to the next?
2. Do last year's biggest customers grow more slowly than the rest (regression to the mean), and is the effect consistent?
3. Which simple rule picks the key-account list that holds the most revenue next year?
4. Where do next year's top customers come from?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Customer, order date, status |
| `sales_order_items` | One row per product per order | Net revenue |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Revenue | Net revenue on orders not Cancelled or Returned |
| Windows | January–September of 2024, 2025 and 2026, so that every year is compared on the same months |
| Pairs | 2024 → 2025 and 2025 → 2026. Customers with first-year revenue are ranked (1 = largest) and put in deciles. |
| Growth | Second-year revenue ÷ first-year revenue − 1; customers who stop buying count with zero |
| **Regression to the mean** | Unusually high (or low) values tend to be followed by values closer to average. Measured by the least-squares slope of ln(year 2) on ln(year 1) for customers active in both years: below 1 means large customers grow less, in proportion, than small ones. |
| Selection back-test | For 2025 → 2026: choose 30 accounts by four rules using only 2024–2025 data, and measure the share of all 2026 revenue they deliver, against the best 30 chosen with hindsight |
| Uniform target | Each account's 2025 revenue × the growth of all existing customers (31.8 %) |

## 5. Analytical approach

1. **Customer windows** (`sahyadri_b2b.ka_customer_years`) and **pair table** (`sahyadri_b2b.ka_pairs`) with ranks and deciles.
2. **Growth by decile** for both pairs; top decile against the rest; log-log slope.
3. **Stability of the top**: how many of the top 10, 20, 30 and 50 stay there, and where next year's top 30 come from.
4. **Selection back-test** (`sahyadri_b2b.ka_selection`) and the effect of uniform targets on key accounts.

## 6. SQL techniques used

- Comparable year-to-date windows with conditional aggregation
- Reshaping wide to long with `UNION ALL`, then ranking and deciles per pair with `ROW_NUMBER()` and `CEIL()`
- A log-log regression slope from `COVAR_SAMP` ÷ `VAR_SAMP`
- Rule-based selections compared against a hindsight optimum
- Validation that recomputes the slope from raw sums and checks that deciles do not overlap

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Window revenue = source January–September revenue |
| 02 | Two pair rows per customer |
| 03 | First-year ranks run 1..n in each pair |
| 04 | Decile = ⌈10 × rank ÷ active customers⌉ |
| 05 | Deciles differ in size by at most 1 and do not overlap |
| 06 | Year 2 of the first pair = year 1 of the second pair |
| 07 | **Log slope = a recount from raw sums** |
| 08 | Each rule selects exactly 30 distinct accounts |
| 09 | The hindsight selection captures at least as much as any rule |
| 10 | Rule A = the top 30 by first-year rank |

## 8. Findings

**In both years, the biggest customers grew least.**

| Pair | Top decile growth | Other deciles | All existing customers | Total incl. new customers | Log slope | Correlation |
|---|---:|---:|---:|---:|---:|---:|
| 2024 → 2025 | **−8.8 %** | +18.3 % | +2.3 % | +10.2 % | **0.68** | 0.72 |
| 2025 → 2026 | **+27.6 %** | +37.6 % | +31.8 % | +38.7 % | **0.80** | 0.77 |

| Decile (2025) | Customers | Revenue Jan–Sep 2025 | Revenue Jan–Sep 2026 | Growth | Stopped buying |
|---:|---:|---:|---:|---:|---:|
| 1 | 32 | ₹13.05 crore | ₹16.66 crore | +27.6 % | 0 |
| 2 | 32 | ₹3.87 crore | ₹4.48 crore | +15.8 % | 1 |
| 3 | 32 | ₹2.27 crore | ₹3.52 crore | +54.9 % | 0 |
| 5 | 33 | ₹0.95 crore | ₹1.23 crore | +30.0 % | 1 |
| 8 | 32 | ₹15.6 lakh | ₹33.1 lakh | +112.0 % | 7 |
| 10 | 33 | ₹2.5 lakh | ₹15.1 lakh | +502.8 % | **16** |

- **The pattern is the same in a weak year and a strong year.** When the business was flat (2024 → 2025), the top decile shrank 8.8 %; when it grew strongly, the top decile still grew 10 points less than the rest.
- **This is regression to the mean, not under-performance.** A customer reaches the top partly through a large one-off year; the next year it is usually closer to its normal level. The smallest customers show the mirror image: half of decile 10 stop buying, but the rest multiply their tiny base.

**The top of the list is fairly stable, but a third changes each year.**

| Pair | Top 10 still top 10 | Top 20 still top 20 | Top 30 still top 30 | Top 50 still top 50 | Growth of the top 30 |
|---|---:|---:|---:|---:|---:|
| 2024 → 2025 | 7 | 17 | 21 | 33 | −9.0 % |
| 2025 → 2026 | 6 | 15 | 21 | 31 | +28.5 % |

| Next year's top 30 (2026), by 2025 rank | Customers | 2026 revenue |
|---|---:|---:|
| Already top 30 | 21 | ₹15.24 crore |
| Ranked 31–60 | 4 | ₹1.63 crore |
| Ranked 61–100 | 3 | ₹0.86 crore |
| Not a customer in 2025 | 2 | ₹0.47 crore |

- **No top-30 customer stopped buying in either year.** Those who drop out of the top 30 shrink, they do not leave.
- **Seven of every nine newcomers to the top 30 were already ranked 31–100.** Only two in each year came from outside the customer base.

**Last year's revenue is still the best simple way to choose key accounts.**

| Rule (top 30) | 2026 revenue | Share of all 2026 revenue |
|---|---:|---:|
| **A. 2025 revenue** | **₹16.35 crore** | **52.4 %** |
| D. 2025 revenue, customers who also bought in 2024 | ₹15.35 crore | 49.2 % |
| B. 2024 + 2025 revenue | ₹15.25 crore | 48.9 % |
| C. 2025 order count | ₹14.33 crore | 45.9 % |
| Best possible (hindsight) | ₹18.20 crore | 58.3 % |

Ranking by the latest year captures 90 % of what a perfect list would (52.4 % against 58.3 %). Longer histories and order counts do worse.

**But uniform targets set the key accounts up to miss.**

| Group (2025 → 2026) | Customers | Uniform target | Actual | Actual vs target | Met target |
|---|---:|---:|---:|---:|---:|
| Key accounts (top 30) | 30 | ₹16.78 crore | ₹16.36 crore | **−2.5 %** | 12 (40 %) |
| Other customers | 292 | ₹12.91 crore | ₹13.33 crore | +3.3 % | 114 (39 %) |

Even in a strong year, applying company growth to every account put the key accounts 2.5 % below target and the rest 3.3 % above. In the flat year the gap would have been far larger: the top 30 shrank 9.0 % while existing customers grew 2.3 %.

## 9. Business implications and recommendations

1. **Keep choosing key accounts by last year's revenue.** It beats every alternative tested and captures 90 % of the best possible list.
2. **Set key-account targets below company growth.** In both years the top decile grew less than the rest of the base: 10 points less in the strong year, 27 points less in the flat one. Setting key-account targets at least 10 points below company growth, and the rest correspondingly higher, keeps the total plan unchanged and matches how the base actually moves.
3. **Do not read a key account's slowdown as lost share by default.** Regression to the mean explains much of it; look for real warning signs (fewer orders, fewer categories, as in the [customer health score](../12_customer_health_score/)).
4. **Watch accounts ranked 31–100.** They supplied seven of the nine newcomers to the top 30 in the two years; a "next 70" watch list finds tomorrow's key accounts before they arrive.
5. **Expect a third of the list to change each year** and plan account-manager capacity for it.

## 10. Assumptions and limitations

- **January–September windows** keep the comparison like-for-like with the latest data; full calendar years would include the October–December peak.
- **Two pairs only.** The direction of the effect is the same in both, but its size differs with the year's overall growth.
- **Revenue only.** Margin, payment behaviour and strategic fit also matter when choosing key accounts.
- **Customers as recorded.** Possible duplicate customer records (see [customer master de-duplication](../../04_data_quality_and_reconciliation/03_customer_master_deduplication/)) are not merged.
- **Uniform target** uses the realised growth of existing customers as a stand-in for the planned growth rate.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer window, pair and selection tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
