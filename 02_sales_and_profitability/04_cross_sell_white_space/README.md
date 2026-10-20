# Case Study · Cross-Sell White-Space Analysis

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Window: 12 months, October 2025 – September 2026.

| | |
|---|---|
| **Category** | [Sales and Profitability](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-21 |

---

## 1. Business problem

The company sells ten product categories, but many customers buy only a few of them. Selling more categories to existing customers is usually cheaper than winning new ones: the relationship, credit terms and delivery route already exist. The sales head wants to know where the **white space** is. That means categories a customer does not buy although most similar customers do, and roughly what each gap is worth, so account plans can target them.

## 2. Business questions

1. How many categories do customers buy, and how does that relate to their value?
2. Which categories are under-penetrated in each customer segment?
3. Which customers have white-space gaps, in which categories, and what are they indicatively worth?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `sales_order_items` | One row per product per order | Spend |
| `sales_orders` | One row per order | Date, status, customer |
| `products`, `product_categories` | One row per product / category | Category |
| `customers` | One row per customer | Segment and name |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Active customer | At least one order (not Cancelled or Returned) in the 12-month window. 367 customers. |
| Spend | `quantity * unit_price * (1 - IFNULL(discount_percent, 0) / 100)` |
| Categories bought | Number of the 10 categories with spend in the window |
| Penetration | Share of a segment's active customers who bought the category |
| White-space gap | A category the customer did not buy although **at least 60 %** of their segment peers did |
| Indicative gap value | Median 12-month spend on that category among buyers in the same segment |

## 5. Analytical approach

1. **Customer × category grid** (`customer_category_spend`). Every active customer crossed with every category, with zero spend where nothing was bought.
2. **Breadth vs value.** Customers and revenue by number of categories bought.
3. **Penetration** by segment and category.
4. **Gap table** (`cross_sell_gaps`), summarised by segment and by category.
5. **Account plan list.** The top 10 customers by total indicative gap value, with the categories to offer.

## 6. SQL techniques used

- `CROSS JOIN` to build a complete customer × category grid, and `LEFT JOIN` to keep categories not bought
- Conditional averages, `AVG(IF(...))`, to pivot penetration rates by segment
- Window functions (`AVG … OVER`, `PERCENTILE_CONT … OVER`) for segment penetration and peer median spend
- A declared penetration threshold
- `STRING_AGG(… ORDER BY …)` to produce a ready-to-use list of categories to offer

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Grid rows = active customers × 10 categories |
| 02 | One row per customer–category pair |
| 03 | Grid spend = source revenue for the window |
| 04 | The "bought" flag matches positive spend |
| 05 | Every customer in the grid bought at least one category |
| 06 | No gap is recorded where the customer already buys the category |
| 07 | No gap is in a category below the 60 % penetration threshold (penetration recomputed with `GROUP BY`) |
| 08 | No duplicate gaps |
| 09 | Every gap has a positive value |
| 10 | Gap count = independent recount of qualifying cells |

## 8. Findings

**Customers who buy across the range are where the revenue is.**

| Categories bought | Customers | Average 12-month spend | Share of revenue |
|---|---:|---:|---:|
| 1 | 25 | ₹20,300 | 0.1 % |
| 2–5 | 116 | ₹51,700 – ₹1.30 lakh | 2.6 % |
| 6–8 | 89 | ₹2.31 – ₹5.55 lakh | 7.9 % |
| 9 | 44 | ₹8.41 lakh | 9.2 % |
| **10 (all)** | **93** | **₹34.8 lakh** | **80.3 %** |

This does not prove that adding categories causes higher spend, since large customers naturally need more product types. It does show that range breadth is a strong marker of a fully developed account.

**Penetration gaps differ by segment.**

| Category | Enterprise | Distributor | Mid-Market | SMB |
|---|---:|---:|---:|---:|
| Power Transmission | 77 % | 72 % | 53 % | 31 % |
| Electric Motors & Drives | 89 % | 67 % | 55 % | 34 % |
| Pumps | 87 % | 75 % | 65 % | 31 % |
| … | | | | |
| Industrial Safety Equipment | 92 % | 89 % | 86 % | 66 % |

Industrial Safety Equipment and Valves & Fittings are the "entry" categories, bought by most customers in every segment. Power Transmission, Electric Motors and Pumps are the least penetrated, especially among SMB and Mid-Market customers.

**190 customers have 473 white-space gaps, worth an indicative ₹4.18 crore a year.**

| Segment | Customers with gaps | Gaps | Indicative value |
|---|---:|---:|---:|
| Distributor | 41 | 144 | ₹1.96 crore |
| Enterprise | 21 | 74 | ₹1.12 crore |
| Mid-Market | 61 | 166 | ₹0.97 crore |
| SMB | 67 | 89 | ₹0.13 crore |

- **Pumps is the largest single opportunity.** 60 customers do not buy Pumps although most of their peers do, worth an indicative ₹1.33 crore. Electric Motors follows at ₹0.69 crore.
- **The top 10 accounts each have about ₹10–14 lakh of white space**, mostly Enterprise customers and distributors that buy only 1–4 categories today.
- **Two of the top 10 are not currently active buyers.** Customer 1107 is lapsed and customer 1187 is in the "Cannot lose" group of the [RFM segmentation](../../05_advanced_analytics/03_rfm_customer_segmentation/). For them, reactivation comes before cross-selling.

## 9. Business implications and recommendations

1. **Build account plans for the top 10 white-space customers** using the "categories to offer" list from Step 5. Start with Pumps and Electric Motors, where gap values are highest.
2. **Run a Pumps cross-sell campaign for the 60 customers who do not buy it**, using the existing relationship and delivery route. Check supply capacity first: Pumps already drove most of this year's growth (see [Price-volume-mix](../03_price_volume_mix/)).
3. **Use the entry categories as the door-opener for SMB customers.** SMB penetration is low in most categories. Bundling a low-penetration category with Safety or Valves orders is a low-cost way to widen the range.
4. **Track categories per customer as an account-health KPI**, alongside revenue. A customer dropping categories is an early warning sign.
5. **Treat gap values as a ceiling for prioritisation, not a forecast.** Some customers may buy those categories from other suppliers under contract.

## 10. Assumptions and limitations

- **Indicative value.** The gap value assumes the customer would spend like a typical peer, which overstates the near-term opportunity. It is meant for ranking, not for targets.
- **Peer definition.** Peers are defined by segment only. Industry would be a sharper peer group but has missing values for 18 customers.
- **12-month window.** A category bought just before October 2025 counts as not bought.
- **No competitor data.** A gap may mean the customer has no need, or buys elsewhere. Account managers should qualify each gap.
- **Duplicates.** Six probable duplicate customer records exist (see [Customer master de-duplication](../../04_data_quality_and_reconciliation/03_customer_master_deduplication/)). A duplicate can make one customer look like two narrower buyers.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Customer × category grid, gap table and 4 analysis steps |
| `validation.sql` | 10 pass/fail checks |
