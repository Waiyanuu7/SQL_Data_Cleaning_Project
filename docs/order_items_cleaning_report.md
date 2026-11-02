# Order Items Table: Data Cleaning Report

**Table:** `raw_order_items` → `clean_order_items`
**Rows:** 290,371 → **286,371**
**Scripts:** [`sql/order_items/`](../sql/order_items)

| Step | Script | What it does |
|---|---|---|
| 1 | `01_order_items_audit.sql` | Measures every problem before anything is changed |
| 2 | `02_order_items_clean.sql` | Builds `clean_order_items` |
| 3 | `03_order_items_validate.sql` | Proves the result is clean |
| 4 | `04_order_totals_reconcile.sql` | Recalculates every order total and compares it with the reported one |

---

## 1. Audit: what was wrong

| # | Column | Problem | Rows affected |
|---|---|---|---|
| 1 | all | Exact duplicate rows | 4,000 |
| 2 | quantity | Zero | 2,886 |
| 3 | quantity | Negative (-1 to -10) | 2,943 |
| 4 | quantity | **999**: normal orders are 1–10, so this is ~100× the next largest value | 1,450 |
| 5 | unit_price | NULL | 2,941 |
| 6 | unit_price | Blank | 2,840 |
| 7 | unit_price | Has a `£` symbol (`£18.2`) | 2,852 |
| 8 | discount | **3 notations** for the same value: `0.1`, `10`, `10%`; zero written 4 ways (`0`, `0.0`, `0%`, blank) | all |
| 9 | product_id | Product not in the catalogue (IDs 900–999, 100 products) | 1,415 lines |
| 10 | order_id | Order doesn't exist | **0** ✅ |

### Are negative quantities returns?

If negative quantities recorded returns, they'd be concentrated in Returned orders. They aren't. They make up about 1% of lines in **every** status:

| Order status | Lines | Negative | % |
|---|---|---|---|
| Delivered | 176,437 | 1,843 | 1.04% |
| Shipped | 44,666 | 441 | 0.99% |
| Cancelled | 27,353 | 262 | 0.96% |
| Returned | 17,158 | 163 | **0.95%** |
| Pending | 14,016 | 134 | 0.96% |

**Conclusion:** negative quantities are data entry errors, not returns. Returns are tracked by order status instead.

> MySQL gotcha found during the audit: `LOAD DATA` turns the unquoted word `NULL` in a CSV into a real SQL `NULL`. So a check like `unit_price = 'NULL'` finds nothing; you need `unit_price IS NULL`.

---

## 2. Cleaning: what I did

| Column | Rule applied |
|---|---|
| all rows | `SELECT DISTINCT` removes the 4,000 exact copies |
| order_item_id | Number, **PRIMARY KEY**; indexes on order_id and product_id |
| unit_price | Strip everything except digits and `.` → `DECIMAL`; missing → **catalogue price** (flag `price_from_catalogue`) |
| discount | Strip `%` → numbers above 1 divided by 100 → always a fraction (`0.10`); blank → 0 |
| unknown_product | **New flag**: 1 = product not in the catalogue |
| line_issue | **New column**: why a line can't count as a sale: `Zero quantity`, `Negative quantity`, `Quantity 999 (placeholder/outlier)`, `Missing price` |
| is_valid | **New flag**: 1 = no line issue |
| line_total | **New column**: `quantity × unit_price × (1 − discount)`, only for valid lines |

---

## 3. Decisions log

| Decision | Why |
|---|---|
| Invalid lines **flagged, not deleted** | Keeps a full record. Analysis filters with `is_valid = 1`. |
| Zero, negative and 999 quantities excluded from revenue | Zero sells nothing. Negatives are entry errors (see audit). 999 is an implausible outlier: a single order of 999 headphones in a consumer shop. |
| Missing unit_price → catalogue price | The products audit proved catalogue price = price paid for 100% of products. |
| Blank discount → 0 | Blank appears at the same rate as the other "zero" spellings (`0`, `0.0`, `0%`, about 43,500 each), so it's another way of writing "no discount". |
| Unknown products **kept** | The sale happened and the line has its own price. They're reported as "Not in catalogue" (0.2% of revenue). |

---

## 4. Validation: proof it's clean

| Check | Result |
|---|---|
| Rows | **286,371** |
| Duplicate line IDs | **0** |
| Lines whose order doesn't exist | **0** |
| Discount values | only **0, 0.05, 0.10, 0.15, 0.20** |
| Valid lines with quantity outside 1–10, missing price or line total ≤ 0 | **0** |

| Line status | Lines |
|---|---|
| Valid | **279,147** (97.5%) |
| Negative quantity | 2,907 |
| Zero quantity | 2,851 |
| Quantity 999 | 1,434 |
| Missing price (unknown product with no price) | 32 |

Prices filled from catalogue: **5,670 lines**. Lines with an unknown product: **1,415**.

---

## 5. Order total reconciliation

Every order total was recalculated from its line items and compared with the total stored in `orders`:

```
calculated total = SUM(quantity × unit_price × (1 − discount)) for valid lines + shipping_cost
```

| Result | Orders | % | Reported total (£) | Calculated total (£) |
|---|---|---|---|---|
| Match (within 5p) | 138,045 | 92.0% | 38,522,777 | 38,522,810 |
| Differs: unexplained | 7,253 | 4.8% | 2,066,421 | 2,072,598 |
| Reported total missing | 3,019 | 2.0% | — | 826,519 |
| **Differs: has invalid line(s)** | 1,651 | 1.1% | **107,164,234** | **384,377** |
| Cannot calculate (missing price) | 32 | 0.0% | 50,064 | — |

### The biggest finding of the project

1,651 orders (just 1.1%) carry **£107 million** of reported revenue, while their real line items add up to **£0.38 million**. Almost all of them (1,406) contain a **quantity 999** line, and the reported order total counted all 999 units at full price.

**If revenue were taken straight from the raw `order_total` column, completed-order revenue would be £113.8M instead of £32.3M: overstated about 3.5×.**

### Decisions

| Decision | Why |
|---|---|
| The **calculated** total is the clean `order_total`; the original is kept as `order_total_reported` | Line items are the detailed record and can be checked line by line. The reported total is missing for 2% of orders and wrong for another 5.9%. |
| Orders whose total can't be calculated → `order_total` NULL | Only 32 orders (0.02%). Using the reported total for them would mix two different methods. |
| `total_check` column kept on every order | Anyone can see exactly which orders were affected and why. |

**Check:** every order has at least one line item (0 orders without lines).
