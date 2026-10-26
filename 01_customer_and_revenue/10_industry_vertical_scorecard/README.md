# Case Study · Industry Vertical Scorecard

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. 15 industry groups (14 industries and "Not recorded"), compared over two like-for-like 12-month periods.

| | |
|---|---|
| **Category** | [Customer and Revenue](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-26 |

---

## 1. Business problem

Sales coverage is organised by region and customer segment, but customers buy for different reasons in different industries. The commercial head is planning next year's industry focus, such as trade shows, application engineers and industry price lists, and wants one scorecard for every industry the company sells to. The scorecard needs to separate real industry strength from two traps: growth that rests on a single customer, and margins that only reflect the segment mix.

## 2. Business questions

1. How large is each industry, and how fast is it growing?
2. Is the growth broad, or does it rest on one customer?
3. Which industries earn better margins, and is that the industry itself or its customer-segment mix?
4. Which industries keep their customers and pay quickly?
5. Where should the company invest, reprice, harvest or review?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `customers` | One row per customer | Industry, segment |
| `sales_orders` | One row per order | Order date, status, payment status |
| `sales_order_items` | One row per product per order | Revenue |
| `products` | One row per product | Unit cost |
| `shipments`, `payments` | One row per shipment / payment | Delivery and payment dates |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Revenue | Quantity × unit price × (1 − discount %), orders not Cancelled or Returned; NULL discount = 0 % |
| Periods | **Current** 1 Oct 2025 – 30 Sep 2026 · **Prior** 1 Oct 2024 – 30 Sep 2025 |
| Growth | Current ÷ Prior revenue − 1 |
| **Growth without top grower** | Growth after removing the increase of the industry's fastest-growing customer |
| Gross margin % | (Revenue − quantity × unit cost) ÷ revenue, on lines with a known cost |
| **Mix-expected margin** | The margin the industry would earn if each of its segments earned the company-wide margin for that segment |
| **Margin vs mix** | Actual margin % − mix-expected margin %. Positive = the industry earns more than its segment mix explains. |
| Retention | Share of Prior-period customers who also bought in the Current period |
| Payment speed | Median days from final delivery to last payment, for Paid, Delivered orders delivered in the Current period |
| Quadrants | For industries with ₹1 crore or more: growth and margin each compared with the company (32.5 % and 15.5 %). Invest = both higher; Grow but reprice = growth higher; Harvest = margin higher; Review = both lower. |

## 5. Analytical approach

1. **Customer-period table** (`sahyadri_b2b.industry_customer_period`). Revenue, costed revenue, margin and orders per customer and period, tagged with industry and segment.
2. **Scorecard table** (`sahyadri_b2b.industry_scorecard`). Size, growth, growth without the top grower, largest-customer share, margin, mix-expected margin, retention, order value and payment speed.
3. **Margin and segment mix**: each industry's segment mix beside its actual and expected margin.
4. **Portfolio quadrants**, and the customer behind each industry's growth.

## 6. SQL techniques used

- Direct standardisation: expected margin = Σ segment revenue × company segment margin, to separate industry effect from mix
- "Leave one out" growth with `QUALIFY ROW_NUMBER()` to find each industry's top grower
- Conditional aggregation for two periods in one pass
- Validation through an identity: the mix-expected margin of all industries must add up to the actual company margin

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per customer and period |
| 02 | Two-period revenue = source revenue |
| 03 | Current margin = source lines with a known cost |
| 04 | One scorecard row per industry |
| 05 | Active customers add up to the distinct customers in the period |
| 06 | Registered customers add up to the customer master (500) |
| 07 | **Growth = an independent recomputation** from source lines |
| 08 | **Mix-expected margin adds up to the actual company margin** |
| 09 | Retention between 0 and 100 % |
| 10 | Largest-customer share is valid, and each top grower belongs to its industry |

## 8. Findings

**One industry is more than a third of the business, and most of the growth is concentrated in a few customers.**

| Industry | Active / registered | Revenue (Current) | Share | Growth | Growth without top grower | Largest customer | Margin | Retention | Days delivery → paid |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Industrial Distribution | 60 / 77 | ₹14.53 crore | 36.0 % | +27.4 % | +17.0 % | 22.9 % | 13.9 % | 92.6 % | **29** |
| General Engineering | 41 / 54 | ₹4.00 crore | 9.9 % | +10.0 % | +3.2 % | 17.8 % | 17.3 % | 87.2 % | 47 |
| Steel & Metals | 33 / 45 | ₹4.00 crore | 9.9 % | +47.7 % | +25.0 % | 48.6 % | 15.6 % | 87.5 % | 55 |
| Textiles | 28 / 38 | ₹2.53 crore | 6.3 % | +17.4 % | **−7.5 %** | 59.3 % | 14.6 % | 87.0 % | 56 |
| Chemicals | 21 / 28 | ₹2.33 crore | 5.8 % | +22.8 % | +10.7 % | 37.0 % | 16.6 % | 84.2 % | 57 |
| Not recorded | 12 / 18 | ₹2.16 crore | 5.3 % | +139.8 % | +17.6 % | 77.4 % | 14.3 % | 77.8 % | 39 |
| Automotive | 33 / 44 | ₹2.04 crore | 5.0 % | +29.5 % | +24.1 % | 39.9 % | 17.3 % | 90.0 % | 41 |
| Packaging | 19 / 24 | ₹2.02 crore | 5.0 % | +38.1 % | +19.8 % | 33.2 % | 16.0 % | 95.0 % | **60** |
| FMCG | 18 / 23 | ₹1.69 crore | 4.2 % | +129.7 % | +18.2 % | 54.9 % | 16.8 % | 83.3 % | 46 |
| Plastics & Polymers | 18 / 30 | ₹1.30 crore | 3.2 % | +4.4 % | **−14.0 %** | 24.2 % | **18.1 %** | 75.0 % | 35 |
| Construction | 23 / 28 | ₹1.27 crore | 3.1 % | **+94.6 %** | **+73.8 %** | 20.8 % | 15.8 % | 94.4 % | 39 |
| Food Processing | 18 / 21 | ₹90.9 lakh | 2.3 % | −5.4 % | −10.2 % | 30.7 % | 17.6 % | 100.0 % | 47 |
| Electrical Equipment | 21 / 34 | ₹70.4 lakh | 1.7 % | +104.6 % | +38.0 % | 32.5 % | 17.5 % | 78.9 % | 24 |
| Pharmaceuticals | 15 / 20 | ₹52.5 lakh | 1.3 % | −8.0 % | −14.6 % | 25.8 % | 18.3 % | 80.0 % | 34 |
| Agricultural Equipment | 7 / 16 | ₹34.4 lakh | 0.9 % | +73.8 % | −9.8 % | 65.1 % | 17.5 % | 66.7 % | 33 |

Company: revenue grew **32.5 %** in the Current 12 months, at a **15.5 %** gross margin. (The [regional performance](../06_regional_performance/) study's 38.7 % is January–September year to date, a different period.)

- **Headline growth often rests on one customer.** Textiles' growth of 17.4 % turns into a 7.5 % fall without Mahavir Pillai Spinning Mills. Plastics & Polymers falls 14.0 % without Shree Mukherjee Moulders. FMCG's 129.7 % is 18.2 % without Jai Consumer Care India, which supplied 86 % of the increase.
- **Construction is the only industry with broad, fast growth**: +94.6 %, still +73.8 % without its top grower, with 94.4 % retention and no customer above 21 % of revenue.
- **"Not recorded" is a ₹2.16 crore industry.** 18 customers have no industry, mostly distributors, including Banerjee Sales Corporation. Their growth cannot be planned for until the field is filled.

**Industry margins are almost entirely segment mix.**

| Industry | Distributor share | Enterprise share | Actual margin | Mix-expected | Difference |
|---|---:|---:|---:|---:|---:|
| Pharmaceuticals | 0 % | 51.9 % | 18.3 % | 17.4 % | +0.9 |
| Packaging | 0 % | 94.2 % | 16.0 % | 15.2 % | +0.9 |
| Plastics & Polymers | 0 % | 54.5 % | 18.1 % | 17.2 % | +0.9 |
| Industrial Distribution | 100 % | 0 % | 13.9 % | 14.0 % | −0.1 |
| Textiles | 0 % | 80.9 % | 14.6 % | 15.8 % | −1.2 |
| Construction | 0 % | 46.0 % | 15.8 % | 17.4 % | −1.6 |
| Agricultural Equipment | 0 % | 0 % | 17.5 % | 19.5 % | −2.0 |

- Every industry is within 2 points of the margin its segment mix predicts. **Industrial Distribution's low margin is the distributor discount, not the industry.** All of its customers are in the Distributor segment.
- Industry-specific price lists would therefore have little to correct, except for Construction (−1.6 points) and Textiles (−1.2 points), which earn less than their mix should give.

**Portfolio for industries above ₹1 crore.**

| Quadrant | Industries |
|---|---|
| **Invest** (growth and margin above company) | Construction (broad-based); Steel & Metals, Packaging, FMCG (each with growth resting on one customer) |
| **Grow but reprice** | Not recorded (mainly distributors) |
| **Harvest** (margin above, growth below) | General Engineering, Chemicals, Automotive, Plastics & Polymers |
| **Review** (both below) | Industrial Distribution, Textiles |

- **Industrial Distribution sits in Review only because the distributor channel has lower margins.** It is the largest industry, retains 92.6 % of its customers and pays fastest of the large industries (29 days). It should be managed as a channel, not judged against direct industries.
- **Textiles is the real Review case**: below-company growth that turns negative without one customer, a 59.3 % dependence on that customer, a margin 1.2 points below its mix and 56 days to pay.

## 9. Business implications and recommendations

1. **Make Construction the priority growth industry.** It is the only industry growing fast across many customers. Put application support and a targeted campaign behind it; 5 of its 28 registered customers did not buy in the last 12 months.
2. **Treat single-customer growth as account wins, not industry trends.** In Steel & Metals, FMCG, Packaging and Textiles, plan around the key account (Krishna Castings, Jai Consumer Care, Sai Corrugators, Mahavir Pillai Spinning Mills) rather than the industry.
3. **Do not build industry price lists for margin.** Segment mix explains margin within 2 points everywhere. Review discounts in Construction and Textiles only.
4. **Manage Industrial Distribution as a channel.** Measure it against distributor benchmarks (volume, retention, payment speed), where it performs well, not against direct-sale margins.
5. **Fill the industry field for the 18 customers marked "Not recorded"** and make it mandatory at registration. They are ₹2.16 crore of revenue that the industry plan cannot see.

## 10. Assumptions and limitations

- **One industry per customer.** Diversified groups are classified under one industry in the customer master.
- **Small industries.** Agricultural Equipment (7 active customers) and Pharmaceuticals (15) move with single orders; their growth figures are indicative only.
- **Current unit cost.** Margins use today's product cost for all periods, as elsewhere in the repository.
- **Payment speed is not mix-adjusted.** Faster payment in Industrial Distribution may reflect distributor terms rather than the industry.
- **Quadrant thresholds** are the company averages; an industry just below a threshold is not materially different from one just above.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer-period and scorecard tables, and 2 analysis steps |
| `validation.sql` | 10 pass/fail checks |
