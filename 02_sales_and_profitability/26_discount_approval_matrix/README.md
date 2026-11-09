# Case Study · A Discount Approval Matrix: Who Should Approve Which Discounts, and How Many Approvals Each Design Creates

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. The study applies a proposed approval matrix by job title to 10,000 orders entered from January 2024 to September 2026. It measures how many approvals the matrix would create and tests what really drives discounts. It then checks a design by customer segment, built on 2024–2025 and tested on 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-11-09 |

---

## 1. Business problem

Salespeople set discounts with no approval. The CFO proposes a delegation-of-authority matrix by job title:

| Title | May approve up to |
|---|---:|
| Sales Executive | 5 % |
| Senior Sales Executive | 7.5 % |
| Key Account Manager, Regional Sales Manager | 10 % |
| Head of Sales | 12.5 % |
| Above 12.5 % | Managing Director |

The Head of Sales says it would bury the MD in approvals for routine distributor orders. Before it goes live, the CFO wants the matrix tested on history.

## 2. Business questions

1. How many orders would the proposed matrix escalate, and to whom?
2. What actually drives the size of a discount today?
3. Is there already a rule in the data that limits by customer segment would capture, and does it hold on orders it was not built on?
4. Which salespeople would the proposed matrix flag, and why?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_orders` | One row per order | Date, customer, salesperson |
| `sales_order_items` | One row per product per order | Gross value, discount % |
| `employees` | One row per employee | Name, job title |
| `customers` | One row per customer | Segment |

## 4. Method and metric definitions

| Term | Definition |
|---|---|
| Orders | Every order entered 1 January 2024 – 30 September 2026, any status (approval applies at entry): 10,000 orders |
| **Order discount** | The highest line discount on the order; a missing discount counts as 0 % |
| Gross value / discount given | Quantity × unit price / gross value × discount % |
| **Approver (title matrix)** | The salesperson, if the order discount is within their limit; otherwise the lowest title whose limit covers it |
| **Discount above limit** | Gross value of each line × MAX(0, line discount − the salesperson's limit) |
| Size band | Gross order value under ₹25,000, ₹25,000 – 1 lakh, ₹1 – 5 lakh, ₹5 lakh and above |
| Variance explained | Between-group sum of squares ÷ total sum of squares of order discounts |
| **Segment cap** | The highest order discount the segment received in 2024–2025; tested on January – September 2026 |

## 5. Analytical approach

1. **Lines** (`sahyadri_b2b.da_lines`), **orders** (`da_orders`) with title, segment, size band and approver, the **title matrix** (`da_title_limits`) and **segment caps** (`da_segment_caps`).
2. **Title matrix**: approvals by level and week, orders above each title's limit, rupees above the limit.
3. **Drivers**: discount by segment and size; share of variance explained by segment, size and title.
4. **Segment caps**: share of orders at the cap, any order above it, and the 2026 test.
5. **Salespeople**: who the title matrix flags, against their customer mix.

## 6. SQL techniques used

- An approval matrix held as a table and joined to orders, so limits can be changed without editing the query
- A one-way analysis of variance in SQL: between-group sum of squares ÷ total, for each candidate driver
- Calibration and test periods in one table (`order_date <= calibration_end`) to check a rule out of sample
- Validation that between + within sums of squares add up to the total

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Lines = items of orders dated in the window; gross value and discount = source |
| 02 | Order gross value, discount, maximum line discount and line count = recount |
| 03 | Every order kept; title limit missing only when no salesperson is recorded |
| 04 | **Approver = own authority, or the lowest title whose limit covers the discount** (recount) |
| 05 | Size bands follow their boundaries |
| 06 | **Segment cap = the highest order discount in 2024–2025** (recount) |
| 07 | Four segments; a line-level recount finds no line above its segment cap |
| 08 | Calibration period = orders dated to 31 December 2025 |
| 09 | Discount above the title limit never exceeds the discount given |
| 10 | Between + within sums of squares = total |

## 8. Findings

**The proposed matrix would escalate one order in four: about 19 a week, 8 of them to the MD.**

| Approver under the title matrix | Orders | Share | Per week |
|---|---:|---:|---:|
| Salesperson's own authority | 6,990 | 69.9 % | 48.8 |
| Senior Sales Executive | 124 | 1.2 % | 0.9 |
| Manager (KAM or RSM) | 397 | 4.0 % | 2.8 |
| Head of Sales | 951 | 9.5 % | 6.6 |
| **Managing Director** | **1,186** | **11.9 %** | **8.3** |
| No salesperson recorded | 352 | 3.5 % | 2.5 |

| Title | People | Limit | Orders | Above own limit | Discount given | Discount above limit |
|---|---:|---:|---:|---:|---:|---:|
| Sales Executive | 4 | 5 % | 1,415 | 31.0 % | ₹93.0 lakh | ₹47.3 lakh |
| Senior Sales Executive | 4 | 7.5 % | 1,623 | 37.1 % | ₹137.7 lakh | ₹40.4 lakh |
| Key Account Manager | 3 | 10 % | 2,534 | 23.2 % | ₹258.3 lakh | ₹39.0 lakh |
| Regional Sales Manager | 4 | 10 % | 3,813 | 26.0 % | ₹358.5 lakh | ₹52.4 lakh |
| Head of Sales | 1 | 12.5 % | 263 | 14.8 % | ₹22.9 lakh | ₹1.8 lakh |

Even the Head of Sales gives more than the proposed 12.5 % limit on one order in seven. In 2026 the load would rise to 23 escalations a week. 352 orders (3.5 %) have no salesperson, so no title-based rule could be applied to them.

**Discounts follow the customer segment, not the person.**

| What explains the order discount | Groups | Variance explained |
|---|---:|---:|
| **Customer segment** | 4 | **56.5 %** |
| Segment × order size | 15 | 57.2 % |
| Order size | 4 | 21.8 % |
| Salesperson's title | 6 | 3.8 % |

| Segment | Average order discount: under ₹25,000 | ₹25,000 – 1 lakh | ₹1 – 5 lakh | ₹5 lakh+ | Orders above 12.5 % |
|---|---:|---:|---:|---:|---:|
| Distributor | 11.5 % | 11.8 % | 12.4 % | 13.0 % | 32–44 % |
| Enterprise | 8.2 % | 9.0 % | 9.7 % | 10.4 % | 10–30 % |
| Mid-Market | 4.3 % | 5.0 % | 5.1 % | 5.9 % | 0 % |
| SMB | 1.5 % | 1.7 % | 2.0 % | – | 0 % |

Within a segment, every title gives almost the same discount. On Distributor orders it ranges from 11.9 % to 12.9 % across all five titles, and on Enterprise orders from 9.0 % to 9.3 %.

**There is already an unwritten rule: a cap per segment, never broken.**

| Segment | Cap (highest in 2024–2025) | Orders | At the cap | Above the cap | Above it in 2026 | Escalated by the title matrix | Sent to the MD |
|---|---:|---:|---:|---:|---:|---:|---:|
| SMB | 5 % | 2,075 | 16.8 % | 0 | 0 | 0 | 0 |
| Mid-Market | 10 % | 2,502 | 12.9 % | 0 | 0 | 197 | 0 |
| Enterprise | 15 % | 3,417 | 14.5 % | 0 | 0 | 1,116 | 478 |
| Distributor | 18 % | 2,006 | 12.0 % | 0 | 0 | 1,345 | 708 |

- Not one order in 33 months went above its segment's cap, in any size band or for any salesperson. The cap held in January – September 2026, after it was set from 2024–2025.
- All 1,186 orders the title matrix would send to the MD are within the cap for their segment. They are distributor and enterprise orders at the normal discount for those customers.

**The title matrix would flag the people who serve distributors, not the people who discount too much.**

| Salesperson | Title | Orders to Distributor or Enterprise | Average order discount | Above title limit | Above segment cap |
|---|---|---:|---:|---:|---:|
| Ritu Mishra | Senior Sales Executive | 54.1 % | 7.76 % | **45.3 %** | 0 |
| Rahul Kapoor | Senior Sales Executive | 42.5 % | 7.15 % | 40.3 % | 0 |
| Anjali Jadhav | Senior Sales Executive | 45.0 % | 6.92 % | 36.8 % | 0 |
| Harish Tiwari | Sales Executive | 35.1 % | 5.53 % | 36.7 % | 0 |
| Ramesh Patil | Senior Sales Executive | 12.4 % | 3.59 % | 12.4 % | 0 |

The title matrix ranks salespeople by the customers they cover: Ritu Mishra's orders are mostly distributor and enterprise accounts, and Ramesh Patil's are not.

## 9. Business implications and recommendations

1. **Do not adopt the title matrix as proposed.** It would create about 19 approvals a week, 8 for the MD. Every one of them is a discount the company already gives every customer in that segment.
2. **Write down the segment caps and enforce them in the order system:** SMB 5 %, Mid-Market 10 %, Enterprise 15 %, Distributor 18 %. They describe current practice exactly, and a hard cap needs no approver.
3. **Use approvals only for exceptions above the cap.** On history that would be no orders at all. Any request above it is a real exception worth the MD's time.
4. **If discounts are too high, change the caps, not the approvers.** About 12–17 % of orders sit at their segment's cap. Lowering the Distributor cap from 18 % to 15 % is a pricing decision to model on volume (see [does discount buy volume?](../../05_advanced_analytics/11_discount_volume_response/)), not a control.
5. **Make the salesperson mandatory on every order.** 352 orders have none, so no title- or person-based control can reach them.

## 10. Assumptions and limitations

- **The proposed limits are the CFO's draft**, used as given; other limits change the counts but not the finding that title explains under 4 % of discounts.
- **The approval level is set by the highest line discount on the order.** An order-average rule would escalate fewer orders.
- **Segment caps are what the data show**, not a documented policy. Someone may already enforce them in the order system; if so, the title matrix would add a second, redundant check.
- **Discount on gross value only.** Free goods, freight absorbed or credit terms are not in the data.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Title limits, lines, orders and segment caps tables, and 5 analysis steps |
| `validation.sql` | 10 pass/fail checks |
