# Case Study · Customer Master De-duplication

> **Status: Complete.** Query, validation checks and findings are included. All 10 validation checks pass. Snapshot of the customer master as loaded (500 records).

| | |
|---|---|
| **Category** | [Data Quality and Reconciliation](../) |
| **Dataset** | `sahyadri_b2b` (Google BigQuery) |
| **SQL dialect** | BigQuery Standard SQL (multi-statement script) |
| **Files** | [`analysis.sql`](analysis.sql) · [`validation.sql`](validation.sql) |
| **Last updated** | 2026-10-19 |

---

## 1. Business problem

Sales and finance suspect that some customers were created twice in the customer master, for example once as "Navkar Agencies" and again as "Navkar Agencies Pvt Ltd". When that happens, one customer's sales, receivables and credit exposure are split across two accounts. Customer rankings, credit limits and churn flags are then wrong for exactly the accounts where they matter. The master data team wants a repeatable way to find duplicates, rate them, and propose which record should survive, **without merging anything until a person has reviewed it**.

## 2. Business questions

1. Which customer records are likely duplicates of each other?
2. How confident is each match?
3. For high-confidence pairs, which record should be the master?
4. How would merging change revenue and customer rankings?

## 3. Dataset and relevant tables

| Table | Grain | Used for |
|---|---|---|
| `customers` | One row per customer record | Name, city, state, segment, registration date |
| `sales_orders` | One row per order | Orders per customer |
| `sales_order_items` | One row per product per order | Revenue per customer |

## 4. Metric definitions

**Name normalisation** (the matching key):

| Step | Example |
|---|---|
| Original | `Navkar Agencies Pvt. Ltd.` |
| Lower case | `navkar agencies pvt. ltd.` |
| Remove punctuation | `navkar agencies pvt ltd` |
| Remove legal-form words (pvt, private, ltd, limited, llp, co, company) | `navkar agencies` |
| Collapse spaces | `navkar agencies` |

| Term | Definition |
|---|---|
| Candidate pair | Two customer IDs with the same normalised name |
| Match confidence | **High:** same city and state · **Medium:** same state, different city · **Low:** different state |
| Survivorship rule | The master is the record with more orders. Ties go to the earlier registration date, then the lower customer ID. |
| Revenue | Orders not Cancelled or Returned; NULL discount = 0 % |

## 5. Analytical approach

1. **Name-key table** (`customer_name_keys`). Every customer with its normalised name, orders and revenue.
2. **Candidate pairs** (`customer_duplicate_candidates`). A self-join on the normalised name, with match confidence.
3. **Summary** by confidence level.
4. **Master mapping table** (`customer_master_map`). High-confidence pairs only, each marked *Proposed – pending review*.
5. **Merge impact.** Revenue and revenue rank before and after merging.
6. **Manual review list** for medium and low confidence pairs.

## 6. SQL techniques used

- Text normalisation with nested `REGEXP_REPLACE` (punctuation, `\b` word boundaries for legal-form words, whitespace)
- A self-join with `a.customer_id < b.customer_id`, so each pair appears once and no record matches itself
- Rule-based match confidence with `CASE`
- Survivorship with `ROW_NUMBER() OVER (PARTITION BY … ORDER BY …)`
- Before-and-after ranking with `RANK()` and a `LEFT JOIN` to the mapping table

## 7. Validation and reconciliation

All 10 checks in `validation.sql` return **PASS**.

| # | Check |
|---|---|
| 01 | Every customer record has a name key (500) |
| 02 | One row per customer ID |
| 03 | No empty normalised names |
| 04 | Revenue = in-scope line-item total |
| 05 | No self-matches, and every pair is in ID order |
| 06 | Pair count = independent recount (n × (n − 1) / 2 per name group) |
| 07 | No record is mapped as a duplicate more than once |
| 08 | No master is also mapped as a duplicate |
| 09 | One mapping row per high-confidence pair |
| 10 | Every master has at least as many orders as its duplicate |

## 8. Findings

**12 candidate pairs were found. Six are high-confidence duplicates; the other six are probably different companies.** The existing [Data quality scorecard](../02_data_quality_scorecard/) rule U02, which only ignores case and spacing, found 2 of them. Removing legal-form words finds 10 more.

| Confidence | Pairs | Same segment | Orders involved | Revenue involved |
|---|---:|---:|---:|---:|
| High (same city) | 6 | 6 | 513 | ₹6.78 crore |
| Medium (same state) | 0 | – | – | – |
| Low (different state) | 6 | 1 | 234 | ₹1.77 crore |

**Proposed merges (high confidence):**

| Duplicate | Master | Duplicate's orders | Duplicate's revenue |
|---|---|---:|---:|
| 1034 Navkar Agencies | 1131 Navkar Agencies Pvt Ltd | 40 | ₹55.8 lakh |
| 1183 Mahavir Pillai Spinning Mills Pvt. Ltd. | 1025 Mahavir Pillai Spinning Mills Pvt Ltd | 8 | ₹9.9 lakh |
| 1339 GARG AUTOPARTS PVT LTD | 1202 Garg Autoparts Pvt Ltd | 4 | ₹3.6 lakh |
| 1289 JAIN PACKAGING PVT LTD | 1245 Jain Packaging Pvt Ltd | 2 | ₹0.4 lakh |
| 1282 Indus Industries Pvt. Ltd. | 1219 Indus Industries Pvt Ltd | 1 | ₹0.2 lakh |
| 1425 Supreme Chettiar Consumer Care Pvt. Ltd. | 1362 Supreme Chettiar Consumer Care Pvt Ltd | 0 | – |

- **₹69.9 lakh of revenue and 55 orders sit on duplicate records.**
- **Navkar Agencies is the largest case.** 40 orders (₹55.8 lakh) were booked to a second account. Merged, the customer is worth ₹2.97 crore and moves from 6th to 5th largest. Its credit exposure and payment history are currently split across two records.
- **Mahavir Pillai Spinning Mills** (a top-5 customer) and **Garg Autoparts** also have activity on both records. Garg moves from 82nd to 73rd largest once merged.
- **The six low-confidence pairs are in different states, and five of the six are in different segments** (for example Om Agro Foods Ltd, an Enterprise account in Lucknow, and Om Agro Foods Pvt Ltd, an SMB in Hyderabad). They are most likely different businesses with common names and should not be merged without confirmation, such as matching GST numbers.

## 9. Business implications and recommendations

1. **Review and approve the six proposed merges.** Repoint the duplicates' orders, payments and open balances to the master, then mark the duplicate records inactive rather than deleting them, so the audit trail is kept.
2. **Recalculate credit limits and customer rankings for the merged accounts**, starting with Navkar Agencies, where 19 % of the customer's revenue sits on a second record.
3. **Confirm the six low-confidence pairs with a unique identifier.** GST or PAN numbers are the standard key for Indian businesses. Add such an identifier to the customer master so future checks do not rely on names.
4. **Block new duplicates at entry.** When a new customer is created, check its normalised name against existing records and show possible matches before saving.
5. **Run this check monthly** alongside the data quality scorecard, and keep `customer_master_map` as the permanent record of approved merges.

## 10. Assumptions and limitations

- **Name-based matching only.** Duplicates with misspellings or abbreviations (for example "Navkar Agncies" or "NA Pvt Ltd") are not found by exact matching on the normalised name. Fuzzy matching (for example edit distance) would be the next step.
- **Legal-form words.** Removing words such as "co" and "company" can occasionally merge genuinely different firms. That is why every merge is proposed for review rather than applied.
- **Confidence rules.** City and state are reasonable but imperfect signals. One company can have branches in different cities, and two firms can share a name in one city.
- **No merges are applied.** The analysis proposes a mapping. Revenue and rank impacts show what would change if the mapping were approved.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | Case study documentation (this file) |
| `analysis.sql` | Name keys, candidate pairs, master mapping and 3 analysis steps |
| `validation.sql` | 10 pass/fail checks |
