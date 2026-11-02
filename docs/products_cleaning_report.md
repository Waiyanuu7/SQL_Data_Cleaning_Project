# Products Table: Data Cleaning Report

**Table:** `raw_products` → `clean_products`
**Rows:** 825 → **800**
**Scripts:** [`sql/products/`](../sql/products)

| Step | Script | What it does |
|---|---|---|
| 1 | `01_products_audit.sql` | Measures every problem before anything is changed |
| 2 | `02_products_clean.sql` | Builds `clean_products` |
| 3 | `03_products_validate.sql` | Proves the result is clean |

---

## 1. Audit: what was wrong

| # | Column | Problem | Rows affected |
|---|---|---|---|
| 1 | all | Exact duplicate rows | 25 |
| 2 | price | Stored as text in **6 formats** (see below) | 299 not plain numbers |
| 3 | price | Negative (e.g. `-100.29`) | 19 |
| 4 | price | Blank | 40 |
| 5 | category | **27 spellings** of 6 categories (`Electronics`, `Elec.`, `ELECTRONICS`, `Kitchen`, `Cosmetics`...) | all |
| 6 | sku | Wrong format (`sku00012` instead of `SKU-00012`) | 96 |
| 7 | product_name | Trailing spaces | 39 |
| 8 | product_name | Typed in ALL CAPS | 76 |
| 9 | supplier | Same supplier spelt differently: Acme 3 ways (`Acme`, `acme`, `ACME Ltd`), Northwind 2 ways | 463 |
| 10 | supplier | Blank | 174 |
| 11 | status | Case variants (`Active` / `active`, `DISCONTINUED` / `discontinued`) and blanks | all |

**Price formats found:**

| Format | Rows | Example |
|---|---|---|
| Plain number | 526 | `10.22` |
| With £ symbol | 123 | `£10.62` |
| European comma decimal | 65 | `10,52` |
| With "GBP" text | 52 | `10.72 GBP` |
| Blank | 40 | |
| Negative | 19 | `-100.29` |

### Key finding: the sales data proves the true price

`order_items` records the price charged on every sale. I checked every catalogue price against it:

| Catalogue price | Products | Always sold at one price | Catalogue matches price paid |
|---|---|---|---|
| Normal (all formats) | 741 | 741 | **741 (100%)** |
| Negative | 19 | 19 | **19 (100%)** once the minus sign is removed |
| Blank | 40 | 40 | (nothing to compare) |

This turned two guesses into evidence-based decisions:
1. Negative prices are **sign errors**. Without the minus sign they match what customers paid exactly.
2. Blank prices can be **filled from sales data**, because each product was always sold at a single price.

---

## 2. Cleaning: what I did

| Column | Rule applied |
|---|---|
| all rows | `SELECT DISTINCT` removes the 25 exact copies |
| product_id | Converted to a number and made the **PRIMARY KEY** |
| sku | Upper case, dash removed then re-added → always `SKU-00000` |
| product_name | Trimmed. ALL-CAPS names replaced with the normal spelling of the same name used elsewhere in the catalogue (`PRO MUG SET` → `Pro Mug Set`) |
| category | Map 27 spellings to 6 categories |
| price | `REGEXP_REPLACE` strips everything except digits, `.` and `,` → comma becomes a decimal point → `DECIMAL(10,2)`. This removes `£`, `GBP` and the minus sign in one step |
| price (blank) | Filled with the price customers actually paid; new column `price_from_sales = 1` marks these 40 rows |
| supplier | `acme` / `Acme` / `ACME Ltd` → `Acme Ltd`, `northwind` → `Northwind`; blank → NULL |
| status | `Active`, `Discontinued`, `Inactive`; blank → `Unknown` |

---

## 3. Decisions log

| Decision | Why |
|---|---|
| Negative prices made positive | A price can't be negative, and the positive value matches the sales data for all 19 products. |
| Blank prices filled from sales data, and flagged | Each of the 40 products was always sold at exactly one price, so it's a recorded fact, not a guess. The `price_from_sales` flag keeps the change transparent. |
| `Kitchen` → `Home & Kitchen`, `Cosmetics` → `Beauty`, `Apparel` → `Clothing` | Each is a sub-type or synonym of a main category. Keeping them separate would split one category's sales across several labels. |
| `Inactive` kept separate from `Discontinued` | They may mean different things (temporarily off sale vs permanently removed). Merging them would lose information. |
| Blank supplier → NULL, not guessed | There's no reliable way to know the supplier. |
| ALL-CAPS names fixed with a lookup, not a formula | A simple formula turns `T-SHIRT` into `T-shirt`. Re-using the existing spelling keeps names consistent (340 distinct names, 0 case variants). |

---

## 4. Validation: proof it's clean

| Check | Result |
|---|---|
| Rows | **800** |
| Duplicate product IDs / SKUs | **0 / 0** |
| Categories | **6**: Clothing 142 · Home & Kitchen 138 · Sports 137 · Electronics 129 · Beauty 128 · Books 126 |
| Price range | **£3.15 – £399.74** |
| Missing or non-positive prices | **0** |
| Prices filled from sales data | **40** |
| SKUs in wrong format / names with extra spaces / ALL-CAPS names | **0 / 0 / 0** |
| Catalogue price ≠ price customers paid | **0** |

**Remaining unknowns:** supplier is NULL for 168 products (21%), and status is `Unknown` for 122 (15%).

---

## 5. Limitations

- Supplier and status gaps can't be filled from the data. They'd need the purchasing team.
- **100 product IDs (900–999) appear in orders but not in the catalogue.** These are handled in the order_items cleaning.
