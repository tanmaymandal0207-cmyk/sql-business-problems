# Case Study · Early-Payment Discount: Would "2/10 Net 60" Pay for Itself?

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study takes 3,331 orders delivered between October 2024 and September 2025, each followed for a year of payments. For three discount levels (0.5 %, 1 % and 2 % for payment within 10 days) it weighs the windfall to customers who already pay fast against the financing saved when slower payers switch. It reports results for the whole company and by segment, with break-even uptake.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-05 |

---

## 1. Business problem

The working-capital review proposes a 2 % discount for invoices paid within 10 days of delivery ("2/10 net 60"). The CFO likes the idea of cash arriving sooner. She worries, though, about paying 2 % to customers who already pay quickly, and about whether 2 % is more than the company's own cost of money. Before the offer goes into the new terms, she wants the economics worked out on real payment behaviour.

## 2. Business questions

1. How much would the discount cost on orders that are already paid within 10 days?
2. For a slower order that switches to 10-day payment, when does the financing saved outweigh the discount?
3. What share of slower orders must switch for the offer to break even, by segment?
4. Would a smaller discount, or one aimed at particular segments, work better?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Status, customer |
| `sales_order_items` | One row per product per order | Order value |
| `shipments` | One row per shipment | Final delivery date |
| `payments` | One row per payment | Days to pay |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Orders | Valid, fully delivered orders delivered 1 Oct 2024 – 30 Sep 2025, followed to 30 Sep 2026 (at least a year) |
| **Days to pay** | Delivery to the day payments reach 99 % of value (paid before delivery = 0) |
| Not settled | Not paid to 99 % within the follow-up; treated as bad debt the discount would not recover |
| Cost of money | 12 % a year (as in the cost-to-serve studies) |
| **Windfall** | Discount × value of orders already paid within 10 days |
| **Switch** | A slower order paid at day 10 instead of its actual day d: financing saved = value × (d − 10) × 12 % ÷ 365; net gain = saved − discount |
| **Break-even day** | A switch pays only if d > 10 + discount × 365 ÷ 12 %: day 25 for 0.5 %, 40 for 1 %, 71 for 2 % |
| **Break-even uptake** | Share of slower settled orders that must switch (at random) for net gains to cover the windfall |
| Receivable released | Value × days saved ÷ 365 if every slower order switched: the fall in the average balance owed |

## 5. Analytical approach

1. **Orders** (`sahyadri_b2b.ep_orders`) with days to pay, and how fast each segment pays.
2. **Terms** (`sahyadri_b2b.ep_terms`): windfall, financing saved and discount for each order under each discount level.
3. **Summary** (`sahyadri_b2b.ep_summary`): totals, break-even uptake and receivable released, for the company and by segment.
4. **Who the discount reaches**, and the interest rate each discount implies for a typical customer.

## 6. SQL techniques used

- Settlement dates from running sums of payments (`SUM() OVER (PARTITION BY order ORDER BY date)`), as in the Kaplan–Meier study
- A scenario cross join (orders × discount levels), so every term is evaluated on the same orders
- `GROUP BY ROLLUP(segment)` for segment rows and a company total in one pass
- A closed-form break-even (day and uptake) checked order by order in validation

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | One row per valid, fully delivered order delivered in the window |
| 02 | **Settled on the first day payments reach 99 %, and never otherwise** |
| 03 | Days to pay = settlement − delivery (0 if before); none when not settled |
| 04 | Three discount levels for every order |
| 05 | Windfall only on early payers; switch values only on later payers |
| 06 | Financing saved = value × (days − 10) × 12 % ÷ 365 |
| 07 | **A switch gains exactly when days to pay exceed the break-even day** |
| 08 | Segments add up to the company totals |
| 09 | Receivable released recounted |
| 10 | Payment-speed bands add up to all orders |

## 8. Findings

**Few orders are paid within 10 days, so the windfall is small. The problem is the size of the discount.**

| Segment | Orders | Value | Paid within 10 days | Paid later | Not settled | Median days to pay |
|---|---:|---:|---:|---:|---:|---:|
| Distributor | 675 | ₹12.14 crore | 7.6 % | 85.2 % | 7.2 % | 30 |
| Enterprise | 1,124 | ₹12.28 crore | 0.0 % | 88.6 % | 11.4 % | 65 |
| Mid-Market | 835 | ₹4.20 crore | 0.0 % | 89.6 % | 10.4 % | 42 |
| SMB | 697 | ₹1.75 crore | **39.1 %** | 47.9 % | 13.0 % | **10** |
| **All** | 3,331 | ₹30.37 crore | 5.3 % | 85.1 % | 9.7 % | 45 |

**2 % costs more than it saves for almost every order.** At a 12 % cost of money, a 2 % discount for paying 50 days early is an annual rate of about 15 %. A switch pays only if the customer would otherwise have paid after day 71. Only 18.4 % of order value is paid that late.

| Days to pay | Orders | Value | Share |
|---|---:|---:|---:|
| 0–10 | 376 | ₹160.4 lakh | 5.3 % |
| 11–30 | 524 | ₹538.3 lakh | 17.7 % |
| 31–60 | 1,155 | ₹1,142.5 lakh | 37.6 % |
| 61–71 | 353 | ₹345.2 lakh | 11.4 % |
| 72+ | 571 | ₹557.5 lakh | 18.4 % |
| Not settled after a year | 352 | ₹293.6 lakh | 9.7 % |

**Company-wide results for the year, by discount level**

| Terms | Switch pays after day | Windfall | Result if every slower order switches | Break-even uptake | Result if only slow payers switch |
|---|---:|---:|---:|---:|---:|
| 0.5/10 | 25 | ₹0.8 lakh | **+₹24.4 lakh** | **3.2 %** | +₹24.8 lakh |
| 1/10 | 40 | ₹1.6 lakh | +₹10.6 lakh | 13.1 % | +₹14.2 lakh |
| 2/10 | 71 | ₹3.2 lakh | **−₹16.8 lakh** | never | +₹1.4 lakh |

- With 2 %, the offer loses money if every customer takes it. It gains (₹1.4 lakh) only in the unlikely case that the sole takers are the customers who pay after day 71; customers who pay in one to two months anyway are the likeliest takers, and each of them costs money.
- If every slower order switched, the average balance owed would fall by **₹3.17 crore**. That cash release is the same for any discount level; a smaller discount buys it more cheaply.
- Bad debts are 9.7 % of value. A discount would not recover them, because customers who never pay will not pay early for 2 %.

**By segment, the offer suits Enterprise and does not suit SMB.**

| Segment | 0.5/10: result if all switch | 1/10: result if all switch | 2/10: result if all switch | Receivable released |
|---|---:|---:|---:|---:|
| Enterprise | +₹16.6 lakh | **+₹11.2 lakh** | +₹0.3 lakh | ₹183.7 lakh |
| Distributor | +₹4.9 lakh | −₹0.7 lakh | −₹12.0 lakh | ₹88.0 lakh |
| Mid-Market | +₹3.0 lakh | +₹1.1 lakh | −₹2.7 lakh | ₹40.4 lakh |
| SMB | −₹0.1 lakh | −₹0.9 lakh | −₹2.4 lakh | ₹5.2 lakh |

| Segment | Median days to pay | Annual rate the customer earns: 1 % discount | 2 % discount |
|---|---:|---:|---:|
| Enterprise | 65 | 6.7 % | 13.5 % |
| Mid-Market | 42 | 11.5 % | 23.3 % |
| Distributor | 30 | 18.4 % | 37.2 % |
| SMB | 10 | (already at day 10) | |

- **SMB customers already pay at day 10.** For them the discount is a pure price cut.
- **Enterprise is the only segment where a 1 % discount clearly pays**, because Enterprise customers take 65 days and nobody pays early today. For a typical Enterprise customer the 1 % offer is worth 6.7 % a year, so it may not tempt treasurers whose money costs more than that.

## 9. Business implications and recommendations

1. **Do not introduce "2/10 net 60".** It costs more than the money is worth to the company (about 15 % a year against a 12 % cost of money) and loses up to ₹17 lakh a year.
2. **If an early-payment incentive is wanted, offer 1/10, and only to Enterprise and Mid-Market accounts.** Nobody in those segments pays within 10 days today, so there is no windfall, and every switch by an order otherwise paid after day 40 gains. Company-wide, 1/10 would break even at 13 % uptake.
3. **Keep SMB and Distributor terms as they are.** SMB customers already pay at day 10, and for Distributors even 1 % is roughly break-even.
4. **Use collections, not discounts, for the slowest payers and bad debts.** Orders paid after 72 days or never are a credit-control problem (see [expected credit loss](../../05_advanced_analytics/19_expected_credit_loss_provision/) and [time to cash](../../05_advanced_analytics/26_time_to_cash_kaplan_meier/)).
5. **Test before committing.** Offer 1/10 to a random half of Enterprise accounts for two quarters and measure uptake and the days saved against the other half (see [pilot design](../../05_advanced_analytics/23_pilot_design_power_cuped/)).

## 10. Assumptions and limitations

- **Uptake is unknown.** The study gives break-even uptake rather than a forecast of who would switch.
- **Cost of money 12 %.** At a higher cost of capital the offers look better; the break-even day falls in proportion.
- **Switchers are assumed to pay on day 10 exactly,** and customers who already pay early are assumed to take the discount.
- **One year of deliveries.** Payment behaviour has been stable by segment (see [payment behaviour](../../05_advanced_analytics/02_customer_payment_behaviour/)), so the year is representative.
- **No administration costs** (credit notes, disputes over the 10-day cut-off) are included.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Order, term and summary tables, and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
