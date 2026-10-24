# Case Study · Benford's Law Forensic Test

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 10,568 payments, 10,000 orders and 28,201 order lines.

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-24 |

---

## 1. Business problem

Internal audit wants a quick, data-wide screen for invented or manipulated amounts before the year-end audit. Naturally occurring financial amounts follow **Benford's law**: about 30 % start with the digit 1 and fewer than 5 % with 9. Made-up numbers, systematic rounding or amounts keyed to stay under an approval limit usually break that pattern. The test cannot prove fraud. It shows auditors **where to look first**, and where the data behaves as genuine data should.

## 2. Business questions

1. Do payment amounts, order values and order line values conform to Benford's law, overall and by payment method?
2. Which leading digits or digit pairs are over-represented?
3. Are there unusual round amounts, and can normal business behaviour explain them?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `payments` | One row per payment | Amount, payment method |
| `sales_order_items` | One row per product per order | Order and line values |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Expected share, first digit d | log₁₀(1 + 1/d): 30.1 % for 1, falling to 4.6 % for 9 |
| Expected share, first two digits dd | log₁₀(1 + 1/dd), for 10–99 |
| Digit z-statistic | (\|p_obs − p_exp\| − 1/(2n)) ÷ √(p_exp (1 − p_exp) ÷ n), with continuity correction |
| **MAD** | Mean absolute deviation of observed from expected shares, the main conformity measure |
| Conformity (Nigrini) | First digit: ≤ 0.006 close, ≤ 0.012 acceptable, ≤ 0.015 marginal, else non-conforming. First two digits: ≤ 0.0012, ≤ 0.0018, ≤ 0.0022 |
| Chi-square | Reported for information. With thousands of records it flags trivial deviations, which is why MAD is preferred. |
| Round amount | An exact multiple of ₹1,000 |

Amounts under ₹10 are excluded, so every amount has two leading digits. Leading digits are read from the amount as text, which avoids floating-point errors in logarithms.

## 5. Analytical approach

1. **Value table** (`sahyadri_b2b.benford_values`). Every amount in the three populations with its first digit and first two digits.
2. **First-digit test** (`sahyadri_b2b.benford_first_digit`). Observed against expected shares, z-statistics, MAD and conformity.
3. **First-two-digit test** (`sahyadri_b2b.benford_first_two`). MAD, conformity and the over-represented pairs.
4. **Round-amount test** on payments, explained against the order's payment pattern.
5. **Subgroup test** by payment method, and a **payment-rail limit** check.

## 6. SQL techniques used

- Leading-digit extraction with `SUBSTR(CAST(… AS STRING), 1, 2)`
- Expected distributions generated with `UNNEST(GENERATE_ARRAY(1, 9))` and `LOG10`
- z-statistics with continuity correction, MAD and chi-square computed in SQL
- Subgroup analysis to find where a population-level pattern breaks down
- Validation that re-derives digits with a different (logarithmic) method and checks that two-digit counts roll up to one-digit counts

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Payment records = source payments of ₹10 or more |
| 02 | Order-line records = source lines of ₹10 or more |
| 03 | Every first digit is 1–9 and every first-two pair 10–99 |
| 04 | The first digit is the first digit of the first-two pair |
| 05 | **First digits recomputed** with a LOG10 scaling method |
| 06 | Expected first-digit shares sum to 1 |
| 07 | Expected first-two-digit shares sum to 1 |
| 08 | Observed first-digit counts sum to the record count |
| 09 | First-two-digit counts roll up exactly to first-digit counts |
| 10 | Each population has 9 first-digit rows and 90 first-two-digit rows |

## 8. Findings

**All three populations conform closely to Benford's law.**

| Population | Records | First-digit MAD | First-two MAD | Conformity | Starts with 1 | Starts with 9 |
|---|---:|---:|---:|---|---:|---:|
| Payments | 10,568 | 0.0033 | 0.00083 | Close | 30.2 % | 4.7 % |
| Order values | 10,000 | 0.0043 | 0.00088 | Close | 31.3 % | 5.0 % |
| Order lines | 28,201 | 0.0026 | 0.00078 | Close | 30.1 % | 5.1 % |

- **There is no sign of invented amounts at population level.** Only three digit pairs stand out (z > 3): line values starting 18 and 49, and order values starting 93. They are 14–49 % above expectation, a normal amount of variation when 90 digit pairs are tested in each population.

**Round amounts are explained by instalment payments, with 35 exceptions.**

| Payment type | Payments | Share | Amount |
|---|---:|---:|---:|
| Not a round amount | 9,178 | 86.9 % | ₹70.73 crore |
| Round instalment (the order has several payments) | 1,355 | 12.8 % | ₹8.38 crore |
| Round single payment that does not settle the order | **35** | 0.3 % | ₹20.5 lakh |

Customers commonly pay a round sum on account, then the balance. The 35 single round payments that leave a balance (largest ₹1.68 lakh) are all on Delivered orders marked Partially Paid. Their balances should be in the [receivables ageing](../01_order_to_cash_reconciliation/) and followed up.

**By payment method, the pattern breaks down. The cause is a mislabelled payment method, not invented amounts.**

| Payment method | Payments | First-digit MAD | Conformity |
|---|---:|---:|---|
| NEFT | 4,787 | 0.0091 | Acceptable |
| Cheque | 2,281 | 0.0127 | Marginal |
| Demand Draft | 408 | 0.0164 | Non-conforming |
| UPI | 1,758 | 0.0208 | Non-conforming |
| Not recorded | 190 | 0.0274 | Non-conforming |
| RTGS | 1,144 | **0.0369** | Non-conforming |

- **Payment rails have limits that legitimately change the digit pattern.** RTGS is for amounts of ₹2 lakh and above, so genuine RTGS amounts start disproportionately with 2. UPI has a general limit of ₹1 lakh per transaction, and the data's largest UPI payment is exactly ₹1,00,000.
- **But 543 RTGS payments (47 % of them, ₹3.71 crore) are below the ₹2 lakh RTGS minimum.** Either they were made by NEFT and recorded as RTGS, or the method field is unreliable. Either way, the bank reconciliation by payment channel will not match the ledger.
- The 190 payments with no method recorded cannot be matched to a bank channel at all.

## 9. Business implications and recommendations

1. **Record Benford conformity as audit evidence.** Close conformity across almost 49,000 amounts supports the integrity of transaction amounts at year-end.
2. **Correct the payment-method field.** Reclassify the 543 sub-₹2 lakh "RTGS" receipts after checking bank statements, and make payment method mandatory. This directly affects bank reconciliation by channel.
3. **Follow up the 35 round single part-payments** (₹20.5 lakh received, balances outstanding). Confirm whether the remaining balance is disputed or simply unpaid.
4. **Run the test by salesperson and by month** as a routine control. A subgroup that drifts away from Benford while the whole population conforms is the classic sign of a local problem.
5. **Do not treat Benford alone as proof.** Use it to choose samples for detailed audit testing, together with the [order anomaly screen](../06_order_anomaly_screen/) and the [order-to-cash reconciliation](../01_order_to_cash_reconciliation/).

## 10. Assumptions and limitations

- **Benford applies to amounts spanning several orders of magnitude** and not capped by rules. Subgroups with limits (UPI, RTGS) are expected to deviate, and are interpreted accordingly.
- **Payment-rail rules** are those generally applied by the Reserve Bank of India and NPCI (RTGS minimum ₹2 lakh; UPI general per-transaction limit ₹1 lakh). Some UPI categories allow higher limits, which does not affect this data.
- **Conformity thresholds** are empirical guidelines (Nigrini), not statistical tests.
- **Conformity is necessary, not sufficient.** Manipulated amounts that follow a natural pattern, such as copied genuine invoices, would pass the test.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Value and digit-test tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
