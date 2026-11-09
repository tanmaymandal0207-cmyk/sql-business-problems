# Case Study · Gratuity Liability Under the New Labour Codes: A Projected Unit Credit Valuation in SQL, and What the 50 % Wage Rule Adds

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study values the gratuity obligation for the 46 employees in service on 31 March 2026 who have a salary recorded. It computes what the company would owe if everyone left that day, the Ind AS 19 projected unit credit obligation, the service cost and next year's expected payout. Each figure is shown on today's pay structure and under the labour codes' 50 % wage rule, with sensitivities.

| | |
|---|---|
| **Category** | [Advanced Analytics](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-09 |

---

## 1. Business problem

The company has never provided for gratuity: it pays it from cash when someone leaves after five years. The auditor wants a provision at 31 March 2026 measured the Ind AS 19 way. The labour codes in force since 21 November 2025 also change the wage on which gratuity is calculated: allowances above half of total remuneration now count as wages. The CFO wants the size of the provision, what the new rule adds, and the cash to set aside.

## 2. Business questions

1. What would the company owe if everyone left on 31 March 2026, on today's pay structure and under the 50 % wage rule?
2. What is the actuarial obligation and the cost of one more year of service, and how sensitive are they to the assumptions?
3. Which departments and length-of-service groups carry it?
4. How much cash should be set aside for gratuity paid next year?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `employees` | One row per employee | Hire date, salary (annual CTC), title |
| `departments` | One row per department | Department name |

## 4. Method and metric definitions

**Rules applied** (as summarised by labour-law practitioners; see the sources at the end):

| Rule | Value |
|---|---|
| Formula | **15 ÷ 26 × last drawn monthly wages × completed years of service**; a final part-year over six months counts as a year |
| Eligibility | After **five years** of continuous service (one year for fixed-term employees; the company has none) |
| Ceiling | **₹20 lakh** per employee |
| Wages under the labour codes (from 21 November 2025) | Excluded allowances may not exceed 50 % of total remuneration; the excess counts as wages |

**Method and assumptions:**

| Term | Definition |
|---|---|
| Employees valued | In service on 31 March 2026 with a salary recorded (46); 2 long-serving employees have no salary and are listed separately |
| Wages for gratuity | **40 % of CTC** on the current pay structure (assumed); **50 % of CTC** under the labour codes |
| **Accrued if all left** | Gratuity payable if every employee left on 31 March 2026 |
| Actuarial assumptions (illustrative) | Discount rate 7.0 %; salary growth 8.0 % a year; attrition 10 % a year; joined at 25, retire at 60; mortality ignored |
| Exits | Mid-year; service at an exit in year t = service today + t − 0.5; wages = today's × 1.08^(t − 1) |
| **Defined benefit obligation (DBO)** | Σ over future years of P(exit) × discount factor × projected benefit (if vested) × service today ÷ service at exit |
| **Current service cost** | The same, with 1 ÷ service at exit: the benefit earned by one more year of service |
| Expected payout next year | Σ P(exit in 2026-27) × benefit, for employees vested at exit |

## 5. Analytical approach

1. **Employees** (`sahyadri_b2b.gr_employees`), **accrued gratuity** (`gr_accrued`), and a **projection grid** (`gr_projection`): one row per employee and future year of possible exit, with probability, service, vesting and discount factor.
2. **If everyone left**, on both wage bases.
3. **Projected unit credit**: DBO, service cost and next year's payout on both bases; sensitivity to the discount rate and salary growth.
4. **Who carries it**: departments and length of service.

## 6. SQL techniques used

- An actuarial projection as a grid: employees × `GENERATE_ARRAY(1, 35)` future years, with exit probabilities (1 − q)^(t − 1) × q and a retirement year that takes the rest
- Projected unit credit attribution (service today ÷ service at exit) in one aggregate expression
- Scenario tables crossed with the grid for wage basis and sensitivities
- Validation that exit probabilities add up to 1 for every employee

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Employees = in service on 31 March 2026; missing salaries flagged |
| 02 | Gratuity years: completed years, plus one for a part-year over six months |
| 03 | **Accrued = 15/26 × monthly wages × years from five years' service**, never above ₹20 lakh |
| 04 | **Exit probabilities add up to 1 for every employee** |
| 05 | One exit year per future year up to retirement |
| 06 | Attrition probabilities = 0.9^(t − 1) × 0.1; retirement takes the rest |
| 07 | Service at exit and discount factors = recount |
| 08 | Vesting and rounding at exit = recount |
| 09 | With no one at the cap, accrued at 50 % wages = 1.25 × at 40 % |
| 10 | Every valued employee is projected, and only they are |

## 8. Findings

**If everyone had left on 31 March 2026, the company would have owed ₹45.5 lakh under the labour codes, 25 % more than on today's pay structure.**

| | Value |
|---|---:|
| Employees valued | 46 (25 with five years' service) |
| Annual CTC | ₹423.5 lakh |
| Accrued, wages 40 % of CTC | ₹36.42 lakh |
| **Accrued, wages 50 % of CTC (labour codes)** | **₹45.53 lakh** (+25.0 %) |
| Employees at the ₹20 lakh ceiling | 0 |

Two employees with seven to nine years' service have no salary recorded (a Dispatch Executive and an IT Support Executive). Both are eligible, so the figures above understate the liability by their gratuity.

**The Ind AS 19 provision is about ₹53 lakh, and grows by about ₹8.6 lakh a year of service.**

| Wage basis | Obligation (DBO) | Current service cost | Expected payout 2026-27 |
|---|---:|---:|---:|
| Current structure (wages 40 % of CTC) | ₹43.62 lakh | ₹7.07 lakh | ₹4.01 lakh |
| **Labour codes (wages 50 % of CTC)** | **₹52.82 lakh** | **₹8.58 lakh** | **₹5.02 lakh** |

| Sensitivity (labour-code wages) | Obligation | Change |
|---|---:|---:|
| Base | ₹52.82 lakh | – |
| Discount rate − 1 point (6.0 %) | ₹57.02 lakh | +8.0 % |
| Discount rate + 1 point (8.0 %) | ₹49.16 lakh | −6.9 % |
| Salary growth − 1 point (7.0 %) | ₹50.46 lakh | −4.5 % |
| Salary growth + 1 point (9.0 %) | ₹55.17 lakh | +4.4 % |

- The obligation is about 16 % above the walk-away figure: salary growth raises future benefits, and attrition and discounting take them down.
- Employees not yet eligible still carry obligation. Those with 3–5 years' service account for ₹10.1 lakh, because most of them are expected to reach five years.

**Sales carries half the obligation; long-serving staff carry most of it.**

| Department | Employees | With five years | Accrued if all left | Obligation | Share |
|---|---:|---:|---:|---:|---:|
| **Sales** | 16 | 9 | ₹27.91 lakh | **₹26.24 lakh** | **49.7 %** |
| Finance & Accounts | 6 | 4 | ₹4.39 lakh | ₹5.93 lakh | 11.2 % |
| Supply Chain & Logistics | 5 | 3 | ₹2.40 lakh | ₹3.94 lakh | 7.5 % |
| Production | 5 | 1 | ₹0.65 lakh | ₹3.90 lakh | 7.4 % |
| Marketing | 4 | 2 | ₹3.61 lakh | ₹3.54 lakh | 6.7 % |
| Operations | 5 | 3 | ₹2.25 lakh | ₹3.48 lakh | 6.6 % |
| Human Resources | 3 | 2 | ₹1.91 lakh | ₹3.17 lakh | 6.0 % |
| Information Technology | 2 | 1 | ₹2.41 lakh | ₹2.63 lakh | 5.0 % |

| Service on 31 March 2026 | Employees | Accrued if all left | Obligation |
|---|---:|---:|---:|
| Under 3 years | 9 | – | ₹1.94 lakh |
| 3 – 5 years (not yet eligible) | 12 | – | ₹10.13 lakh |
| 5 – 8 years | 13 | ₹18.09 lakh | ₹16.59 lakh |
| 8 years and more | 12 | ₹27.44 lakh | ₹24.17 lakh |

## 9. Business implications and recommendations

1. **Book a gratuity provision of about ₹53 lakh at 31 March 2026**, on labour-code wages, subject to an actuary's report. The walk-away figure (₹45.5 lakh) is a floor the auditor can check directly.
2. **Budget about ₹8.6 lakh a year of service cost**, plus interest on the obligation, as an employee expense, and keep about ₹5 lakh liquid for payouts in 2026-27.
3. **Record the two missing salaries.** Both employees are eligible for gratuity, and the payroll master is the auditor's first test of the valuation data.
4. **Model the pay-structure response before restructuring CTCs.** The 25 % rise comes from moving wages from 40 % to 50 % of CTC. If the current basic is already near 50 %, the impact is smaller. Run the valuation on actual payslip components.
5. **Consider funding the obligation through an approved gratuity fund** managed by an insurer. Ask the tax adviser about the deduction for contributions; the cash also stops being available for operations, which is the point.

## 10. Assumptions and limitations

- **Not actuarial or legal advice.** The discount rate, salary growth and attrition are illustrative. An actuary sets them from bond yields and the company's own history, and Ind AS 19 requires an actuarial valuation.
- **The 40 % wage share is assumed.** The data has only CTC, not salary components.
- **No dates of birth.** Everyone is assumed to have joined at 25 and to retire at 60; mortality and disability exits are ignored.
- **Attrition is one rate for all.** Sales and junior staff usually leave more often, which would lower their obligation.
- **The tax-exemption limit is not the payment ceiling.** The study applies the ₹20 lakh statutory cap; a contract may promise more.

**Sources for the rules:** [Fisher Phillips: India's new labour codes expand gratuity rules](https://www.fisherphillips.com/en/insights/insights/indias-new-labor-codes-expand-gratuity-payment-rules) · [Patron Accounting: gratuity calculation 2026](https://www.patronaccounting.com/blog/gratuity-calculation-2026-one-year-rule-fixed-term-employees) · [King Stubb & Kasiva: the 50 % wage rule under the labour codes](https://ksandk.com/labour-employment/50-wage-rule-labour-codes-salary-pf-gratuity/)

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Employee, accrued and projection tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
