# Case Study · Price Elasticity from a Natural Experiment: Do Customers Notice ±3 %?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 26,472 order lines whose invoice prices are scattered at random within ±3 % of the list price, used as a natural experiment to measure how units bought respond to price, with balance checks, a repeat-purchase test and the value of billing at list.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-31 |

---

## 1. Business problem

The [price discipline](../12_price_increase_and_price_discipline/) study found that invoice prices are spread evenly within ±3 % of the list price, with no customer, salesperson or product pattern: in effect, every order line gets a random price. The CFO wants to stop billing below list. Sales warns that customers will buy less if their prices rise. Because the deviations are random, they form a natural experiment: lines that happened to be priced above list can be compared with lines that happened to be priced below it.

## 2. Business questions

1. Are the price deviations really random, so they can be used as an experiment?
2. Do customers buy fewer units on lines priced above list, and more below it?
3. Does a high price on a line make the customer less likely to buy that product again?
4. What would billing every line at no less than list be worth, and how much could it cost in volume at worst?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Quantity, invoice price, discount |
| `sales_orders` | One row per order | Customer, date, status |
| `products` | One row per product | Today's list price |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Lines | Order lines on valid orders (not Cancelled or Returned) |
| List in force | Today's list price × the year's price factor (median invoice ÷ list ratio of the year's valid lines) |
| **Price deviation** | Invoice price ÷ list in force − 1 |
| **Elasticity** | Slope of ln(quantity) on ln(1 + deviation), both centred within product × year, so only price variation around the same product's normal level counts. −1 means a 1 % higher price loses 1 % of units. |
| Standard error | From the residuals, allowing one degree of freedom per product-year; 95 % interval = ±1.96 SE |
| Discount comparison | The same model on ln(1 − discount %); discount is set by people and can follow quantity |
| Repeat purchase | Same customer buys the same product again within 180 days (lines to 31 Mar 2026) |
| **Billing at list** | Every below-list line re-priced to list, with units adjusted by (list ÷ price)^elasticity |

## 5. Analytical approach

1. **Lines** (`sahyadri_b2b.pe_lines`) with list in force and deviation, and the **centred table** (`sahyadri_b2b.pe_centred`).
2. **Balance checks**: average deviation by segment, quantity, discount and year.
3. **Elasticity** (`sahyadri_b2b.pe_elasticity`) for price deviation and discount; units by deviation band.
4. **Repeat purchase** by deviation band.
5. **Value of billing at list** under four elasticity scenarios.

## 6. SQL techniques used

- A natural experiment: using random variation already in the data instead of a designed test
- Fixed effects by demeaning within product × year with window averages
- Regression slope, residual standard error and confidence interval from plain aggregates
- Balance tables to check the experiment's randomness, and a counterfactual revenue calculation line by line

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One line per valid order line |
| 02 | One price factor per year, equal to the median invoice ÷ list ratio |
| 03 | Deviation = invoice ÷ list in force − 1, within ±3.1 % |
| 04 | Log columns agree with the raw values |
| 05 | Centred values average zero in every product-year |
| 06 | Centred table has one row per line |
| 07 | **Price elasticity = a direct recount** |
| 08 | Standard errors positive; both drivers estimated on the same lines |
| 09 | Below- and above-list amounts add up to the net difference from list |
| 10 | Only product-years with 2+ lines enter the elasticity |

## 8. Findings

**The deviations behave like a randomised experiment.** On valid orders they run from −3.02 % to +3.04 % (SD 1.74 %): ₹73.6 lakh was billed below list and ₹76.5 lakh above it.

| Group | Average deviation (standard error) |
|---|---|
| Segments | −0.006 % to +0.049 % (SE 0.02–0.03 %) |
| Quantity bands (1–2 units to 51+) | −0.001 % to +0.039 % |
| Discount bands (none to over 10 %) | +0.003 % to +0.023 % |
| Years 2024 / 2025 / 2026 | +0.032 % / +0.009 % / −0.009 % |

The deviation is uncorrelated with quantity (r = −0.005), discount (0.005) and list price (0.002). Every group average is within two standard errors of zero.

**Customers do not buy fewer units when the price is higher.**

| Driver | Elasticity | 95 % interval | t |
|---|---:|---|---:|
| **Price deviation (random)** | **−0.26** | −0.84 to +0.32 | −0.87 |
| Discount (chosen by people) | −5.45 | −5.63 to −5.27 | −59.1 |

| Price vs list | Lines | Units vs the product's normal |
|---|---:|---:|
| 2–3 % below | 4,365 | +1.1 % |
| 1–2 % below | 4,489 | +1.0 % |
| 0–1 % below | 4,382 | −1.1 % |
| 0–1 % above | 4,363 | −0.8 % |
| 1–2 % above | 4,331 | −1.1 % |
| 2–3 % above | 4,542 | +0.8 % |

- Units move by about ±1 % (standard error 1.2 %) with no trend from the cheapest band to the dearest.
- **The discount "elasticity" is not a customer response.** Bigger discounts go with bigger quantities because salespeople give volume discounts (correlation −0.24 between discount factor and quantity). This is why discount data cannot answer the question, and random price deviations can.

**A higher price does not stop customers coming back.** The same product was bought again within 180 days after 34.8 % of lines priced more than 1 % below list, 36.4 % within 1 % of list and 35.4 % more than 1 % above it (standard error 0.6 points each).

**Billing at no less than list would add about ₹20 lakh a year.**

| Scenario | Elasticity | Revenue on the 13,236 below-list lines | Gain (33 months) | Gain a year |
|---|---:|---:|---:|---:|
| Customers ignore price | 0 | ₹4,889 → ₹4,963 lakh | ₹73.6 lakh | ₹26.7 lakh |
| **Estimated elasticity** | **−0.26** | ₹4,889 → ₹4,944 lakh | **₹54.3 lakh** | **₹19.7 lakh** |
| Worst end of the 95 % interval | −0.84 | ₹4,889 → ₹4,901 lakh | ₹11.5 lakh | ₹4.2 lakh |
| Unit-elastic customers | −1 | no change | ₹0 | ₹0 |

Even at the worst plausible elasticity, billing at list does not lose revenue.

## 9. Business implications and recommendations

1. **Invoice at list, with discounts only through the discount field.** Below-list invoice prices cost about ₹20 lakh a year with no measurable volume benefit.
2. **Lock the invoice price field in the ERP** to the list in force, so any reduction has to be a recorded discount with a reason and an approver.
3. **Do not raise prices above list on the strength of this result.** It covers ±3 % around a known list; larger changes, or prices customers can compare openly, may behave differently. Above-list billing should also be stopped as a compliance risk.
4. **Use random variation when it exists.** Before running a pricing pilot, check whether the data already contain an accidental experiment; this one answered the question without any customer seeing a test.
5. **Do not estimate price response from discounts.** Discount follows quantity, so a discount-volume model will always show a strong response that customers did not make.

## 10. Assumptions and limitations

- **Short-run, line-level response.** The experiment measures units on the same line and repeat purchases within 180 days; it cannot see customers moving business to competitors over years.
- **Customers may not see list prices.** If customers do not know the list, a ±3 % deviation is invisible to them; publishing price lists could change behaviour.
- **Valid orders only.** The figures differ slightly from the price discipline study, which included cancelled and returned orders (₹77.9 lakh below list there).
- **Wide interval.** Elasticities between −0.84 and +0.32 are consistent with the data; the recommendation holds across that whole range.
- **Quantity is a whole number** and often small; ln(quantity) treats a change from 1 to 2 units as large.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Line, centred and elasticity tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
