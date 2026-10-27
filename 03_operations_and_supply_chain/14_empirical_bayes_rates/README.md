# Case Study · Real Differences or Noise? Empirical Bayes for Operational Rates

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Six "worst ten" style measures — cancellations by customer, salesperson and product, returns by city, late delivery by customer and by city — tested for real variation and shrunk with empirical Bayes.

| | |
|---|---|
| **Category** | [Operations and Supply Chain](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-28 |

---

## 1. Business problem

The operations review ranks customers, salespeople, products and cities on cancellation, return and late-delivery rates, and sends "worst ten" lists to managers every quarter. Many entries are customers with a handful of orders, and the lists change almost completely from one quarter to the next. The [cancellation and return leakage](../06_cancellation_return_leakage/) study already suggested that cancellations are a company-wide level rather than a pocket. The operations head wants a consistent way to decide which lists show real differences and which only show chance.

## 2. Business questions

1. For which rates do customers, products, salespeople or cities really differ, and for which is the variation just chance?
2. What is each member's credible rate once small samples are allowed for?
3. How many of the members flagged on raw rates survive?
4. Which lists are worth sending, and which should stop?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, customer, salesperson, promise date |
| `sales_order_items` | One row per product per order | Product-level cancellations |
| `shipments` | One row per shipment | Returns, delivery dates, destination city |
| `customers` | One row per customer | Names |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Measures | Cancellation by customer and by salesperson (closed orders: Delivered, Cancelled, Returned); cancellation by product (lines of closed orders); return by city (shipments); late delivery by customer and by city (delivered orders with a promise date; city = first shipment's standardised city) |
| Rates | Overall rate p; member rate r = k ÷ n |
| **Heterogeneity Q** | Σ n (r − p)² ÷ (p (1 − p)). If members differ only by chance, Q follows chi-square on (members − 1) degrees of freedom; converted to a z-score (Wilson–Hilferty). z ≥ 3.09 = real differences (0.1 %). |
| **Between-member variance τ²** | DerSimonian–Laird: max(0, (Q − (K − 1)) ÷ (Σw − Σw² ÷ Σw)), w = n ÷ (p (1 − p)). The spread of true rates once sampling noise is removed. |
| **Shrinkage B** | (p (1 − p) ÷ n) ÷ (p (1 − p) ÷ n + τ²): how much a member's rate is pulled towards p. Small members and measures with no real variation are pulled the most. |
| **Credible rate** | B × p + (1 − B) × r (empirical Bayes estimate) |
| **Reliably above average** | Posterior probability of at least 0.95 that the true rate exceeds p (normal approximation, posterior s.d. = √(τ² B)) |
| City-adjusted test | Late delivery by customer compared with what each order's city predicts (observed against Σ city rates) |

## 5. Analytical approach

1. **Count table** (`sahyadri_b2b.eb_counts`): n and k for every member of every measure.
2. **Measure table** (`sahyadri_b2b.eb_measures`): overall rate, Q, heterogeneity z and τ².
3. **Member table** (`sahyadri_b2b.eb_members`): raw rate, raw z, shrinkage, credible rate and the probability of being above average; comparison of raw flags with shrunk results.
4. **What the lists should contain**: the raw cancellation "worst ten", members reliably above average, the most and least reliable destinations, and a city-adjusted test of customer lateness.

## 6. SQL techniques used

- One long count table for six measures at four grains, built with `UNION ALL`
- Heterogeneity statistics and a random-effects variance estimate (DerSimonian–Laird) in SQL
- Empirical Bayes shrinkage and posterior probabilities with a closed-form normal approximation
- Indirect standardisation (observed against city-expected lateness) to separate customer from destination
- Validation that recomputes Q by a second formula and checks every credible rate lies between the raw rate and the overall rate

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Customer and salesperson cancellation counts = closed orders |
| 02 | Product cancellation counts = lines of closed orders |
| 03 | City return counts = all shipments and returned shipments |
| 04 | Late delivery: customer and city views count the same orders |
| 05 | Overall rate = events ÷ records for every measure |
| 06 | **Q = a recount by a second formula** |
| 07 | τ² is zero exactly when Q ≤ degrees of freedom |
| 08 | Shrinkage between 0 and 1; credible rate between the raw rate and the overall rate |
| 09 | With no real variation, every credible rate equals the overall rate |
| 10 | Raw z recomputed |

## 8. Findings

**Only late delivery shows real differences. Cancellations and returns do not.**

| Measure | Members | Overall rate | Q | df | z | Spread of true rates (s.d.) | Verdict |
|---|---:|---:|---:|---:|---:|---:|---|
| Cancellation by customer | 430 | 5.40 % | 418.3 | 429 | −0.35 | **0** | Chance |
| Cancellation by salesperson | 17 | 5.40 % | 13.7 | 16 | −0.32 | **0** | Chance |
| Cancellation by product | 186 | 5.36 % | 207.8 | 185 | 1.17 | 0.65 pts | Chance |
| Return by city | 61 | 0.80 % | 94.1 | 60 | 2.72 | 0.53 pts | Chance (weak signal) |
| **Late delivery by customer** | 425 | 18.32 % | 623.7 | 424 | **6.02** | **5.75 pts** | **Real** |
| **Late delivery by city** | 61 | 18.32 % | 165.5 | 60 | **6.68** | **4.23 pts** | **Real** |

- For customer and salesperson cancellations, the variation between members is *smaller* than pure chance would produce (Q below its degrees of freedom). There is no evidence that any customer or salesperson is a "serial canceller".

**Raw lists flag dozens of members; after shrinkage, only late-delivery members remain.**

| Measure | Raw rate ≥ 1.5 × average | Raw z ≥ 2 | Expected by chance | Reliably above average | Raw range | Credible range |
|---|---:|---:|---:|---:|---|---|
| Cancellation by customer | 94 | 25 | 9.8 | **0** | 0 – 100 % | 5.4 – 5.4 % |
| Cancellation by salesperson | 0 | 0 | 0.4 | **0** | 3.7 – 7.5 % | 5.4 – 5.4 % |
| Cancellation by product | 29 | 6 | 4.2 | **0** | 0 – 16.7 % | 4.6 – 5.9 % |
| Return by city | 17 | 5 | 1.4 | **0** | 0 – 14.3 % | 0.4 – 1.3 % |
| Late delivery by customer | 93 | 46 | 9.7 | **12** | 0 – 100 % | 9.3 – 29.5 % |
| Late delivery by city | 3 | 9 | 1.4 | **7** | 0 – 38.1 % | 10.3 – 24.9 % |

- **The customer cancellation "worst ten" is entirely noise.** Siddhivinayak Tiwari Sales Corporation (5 of 30, 16.7 %), Navkar Agencies (7 of 47) and Banerjee Sales Corporation (9 of 75) all have a credible rate of 5.4 %, the company average. The seven customers flagged in the [leakage study](../06_cancellation_return_leakage/) were consistent with chance, as that study cautioned.

**Late delivery: a short, stable list of destinations.**

| City | Delivered orders | Late | Raw rate | Credible rate | Shrinkage |
|---|---:|---:|---:|---:|---:|
| Dhanbad | 42 | 16 | 38.1 % | 24.9 % | 0.67 |
| Haridwar | 277 | 73 | 26.4 % | 24.5 % | 0.23 |
| New Delhi | 232 | 61 | 26.3 % | 24.2 % | 0.26 |
| Noida | 100 | 28 | 28.0 % | 23.6 % | 0.46 |
| Jaipur | 203 | 51 | 25.1 % | 23.1 % | 0.29 |
| Panipat | 190 | 47 | 24.7 % | 22.8 % | 0.31 |
| Kolkata | 598 | 135 | 22.6 % | 22.1 % | 0.12 |
| … | | | | | |
| Pune | 563 | 68 | 12.1 % | 12.9 % | 0.13 |
| Mumbai | 299 | 24 | 8.0 % | **10.3 %** | 0.22 |

These seven cities are reliably above the 18.3 % average; the northern cluster (New Delhi, Noida, Panipat, Haridwar, Jaipur) stands out.

**Most of the customer differences in lateness are really destination differences.** Allowing for each order's city, customer heterogeneity falls from z = 6.02 to **2.28**, below the threshold. The 12 customers who are reliably above average (led by Universal Alloys, 16 of 37 late, credible 29.5 %, and Ganesh Precision Engineering, 67 of 256, credible 25.0 %) mostly reflect where they are; 28 customers are still above their city's expectation at z ≥ 2, against about 10 expected by chance, so a small customer-specific element may remain.

## 9. Business implications and recommendations

1. **Stop the customer, salesperson and product cancellation lists.** There is no detectable real difference between members; the lists only rotate noise and send managers after the wrong accounts. Track cancellation as one company rate on a control chart (see [statistical process control](../09_statistical_process_control/)).
2. **Keep a destination list for late delivery.** Seven cities, mainly in the north, are reliably worse. Work on carrier and lane performance there, or lengthen promises using the [city promise standards](../05_promise_date_standards/).
3. **Rank customers on credible rates, not raw rates.** Where a customer list is needed, sort by the credible rate: a customer with 7 of 9 orders late (77.8 % raw) is credibly at 28.2 %, below Universal Alloys with 37 orders.
4. **Judge customer lateness against its city.** A customer in a hard-to-serve city is not a service failure; report customer on-time against city expectation.
5. **Run this test before publishing any new ranking.** If Q is not above its degrees of freedom, the ranking should not be published.

## 10. Assumptions and limitations

- **Normal approximation** to the beta-binomial for shrinkage and posterior probabilities; for very small members and rates near 0 % (returns) the exact beta posterior would differ slightly.
- **Rates assumed stable** over the 33 months. A member whose rate changed recently is averaged with its past.
- **City from the first shipment** for late delivery; returns use the shipment's own city.
- **One level at a time.** Customer and city effects are separated only by the indirect standardisation step, not by a joint model.
- **Logistic approximation of the normal CDF** (accurate to about 0.01) keeps the logic portable across SQL engines.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Count, measure and member tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
