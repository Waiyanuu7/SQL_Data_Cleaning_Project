# Customers Table: Data Cleaning Report

**Table:** `raw_customers` → `clean_customers`
**Rows:** 26,600 → **25,035**
**Scripts:** [`sql/customers/`](../sql/customers)

| Step | Script | What it does |
|---|---|---|
| 1 | `01_customers_audit.sql` | Measures every problem before anything is changed |
| 2 | `02_customers_clean.sql` | Builds `clean_customers`: dedupes, trims, standardises, converts types |
| 3 | `03_customers_dedupe.sql` | Merges customers who registered twice under different IDs |
| 4 | `04_customers_validate.sql` | Proves the result is clean |

---

## 1. Audit: what was wrong

| # | Column | Problem | Rows affected |
|---|---|---|---|
| 1 | all | Exact duplicate rows (same ID, same values) | 400 |
| 2 | all | Same person registered under different IDs (same email) | 1,165 extra rows |
| 3 | full_name | Blank | 516 |
| 4 | full_name | Written as "Last, First" | 772 |
| 5 | full_name | Leading or trailing spaces | 1,259 |
| 6 | full_name | Inconsistent case (`JAMES SMITH`, `james smith`) | many |
| 7 | email | Blank | 776 |
| 8 | email | Invalid (missing `@`) | 812 |
| 9 | email | `.con` typo instead of `.com` | 419 |
| 10 | email | Mixed case and extra spaces | many |
| 11 | phone | Blank or `N/A` | 4,911 |
| 12 | phone | ~10 different formats, plus junk values (`123`, `0000000000`) | all |
| 13 | country | **31 spellings** of 6 countries (`UK`, `U.K.`, `England`, `Great Britain`, ` UK `...) | all |
| 14 | city | Case variants (`London` / `LONDON` / `london`, `new york`) | ~5,700 |
| 15 | city | City contradicts country (e.g. Paris + United Kingdom) | ~66% of rows |
| 16 | age | Blank | 1,926 |
| 17 | age | Impossible (-1, 0, 2, 150, 999) | 759 |
| 18 | gender | **12 codes** for 5 meanings (`M`, `m`, `Male`, `male`, `U`, blank...) | all |
| 19 | signup_date | **6 different formats**, including Unix timestamps | ~45% not ISO |
| 20 | signup_date | Unusable: blank (508), text like `N/A`/`unknown` (409), `0000-00-00` (126) | 1,043 |
| 21 | marketing_opt_in | **9 codes** for yes/no (`Y`, `yes`, `1`, `TRUE`, `false`...) and blanks | all |

### Audit findings worth highlighting

- **MySQL hides case variants by default.** Its default collation is case- and accent-insensitive, so `GROUP BY country` silently merges `UK` and `uk`. The audit uses `COLLATE utf8mb4_bin` to reveal the true number of variants.
- **A "valid" format can still hold junk.** `0000-00-00` matches the `YYYY-MM-DD` pattern, so checking format alone isn't enough.
- **Ambiguous dates were resolved with evidence, not assumption.** `03-07-2021` could be 3 July or March 7. A month can never be above 12, so I counted which part ever goes above 12:

| Format | 1st part > 12 | 2nd part > 12 | Conclusion |
|---|---|---|---|
| `NN/NN/YYYY` | 2,505 | 0 | Day first: **DD/MM/YYYY** (UK) |
| `NN-NN-YYYY` | 0 | 1,640 | Month first: **MM-DD-YYYY** (US) |

---

## 2. Cleaning: what I did

| Column | Rule applied |
|---|---|
| all rows | `SELECT DISTINCT` removes the 400 exact copies |
| full_name | Trim → swap "Last, First" → Proper Case → blank = NULL |
| email | Trim + lower case → anything not matching `name@domain.tld`, or ending `.con`, = NULL |
| phone | Strip all non-digits → convert every valid UK mobile to `+447XXXXXXXXX` → junk = NULL |
| country | Trim + lower case → map 31 spellings to 6 countries |
| city | Trim → fix case variants → blank = NULL |
| age | Keep only whole numbers from 16 to 100 → otherwise NULL |
| gender | Map 12 codes to `Male`, `Female`, `Other`, `Prefer not to say`, `Unknown` |
| signup_date | Detect each format with `REGEXP` → convert with the matching `STR_TO_DATE`, or [`uk_from_unix()`](../sql/00_uk_time_function.sql) for Unix timestamps → real `DATE` type |
| marketing_opt_in | Map to `1` / `0` → blank = NULL |
| location_conflict | **New flag column:** 1 = city doesn't belong to the country |
| customer_id | Converted to a number and made the **PRIMARY KEY** (fails if any duplicates remain) |

### Merging duplicate customers

1,124 email addresses were used by more than one customer ID, which meant 1,165 extra registrations.

1. Built **`customer_id_map`** (`old_id` → `master_id`), keeping the lowest ID, which is the first registration.
2. **Rescued details:** if the kept record was missing a phone, name, age, signup date or opt-in value that a duplicate had, it was copied across with `COALESCE`.
3. Deleted the duplicate rows.

The map table is kept on purpose. Orders placed under a duplicate ID are re-pointed to the master ID when the orders table is cleaned, so **no sales are lost**.

---

## 3. Decisions log

| Decision | Why |
|---|---|
| Invalid values set to **NULL**, not guessed or deleted | An unknown value is honest; a guessed value is false data. Deleting the row would also lose the customer's other valid fields. |
| Impossible ages (outside 16–100) → NULL | Ages like 999 are entry errors. |
| `England` mapped to `United Kingdom` | England is part of the UK; the analysis is at country level. |
| `U` and blank gender → `Unknown`; `Prefer not to say` kept separate | "Prefer not to say" is a real choice the customer made; "unknown" means the data is missing. |
| Blank marketing opt-in → NULL, not 0 | Kept as unknown in the data. **Any marketing use must treat NULL as "not opted in"** (GDPR). |
| `.con` emails → NULL instead of auto-fixing to `.com` | The real domain can't be confirmed, so it isn't safe to email that address. |
| City/country conflicts **flagged, not fixed** | 66% of rows conflict, far too many to be typos. Country has a realistic spread (about 50% UK for a UK shop); city is suspiciously even (~1,850 per city). **Country is treated as the source of truth** for geographic analysis. In a real company I'd raise this with the team that owns the sign-up form. |
| Duplicate customers matched on **email only** | Email is unique per person. Matching on name would wrongly merge different people called "James Smith". Customers with no valid email can't be matched and were left alone. |
| Kept the **lowest ID** when merging | The lowest ID is the first registration, so it's the customer's original account. |

---

## 4. Validation: proof it's clean

| Check | Result |
|---|---|
| Final row count | **25,035** |
| Duplicate customer IDs | **0** |
| Emails used by more than one customer | **0** |
| Distinct countries | **6** |
| Distinct gender values | **5** |
| Age range | **18 – 80** |
| Signup date range | **2019-01-01 – 2025-12-30** |
| Phones not in `+447XXXXXXXXX` format | **0** |
| Emails not lower case | **0** |
| Mappings pointing to a deleted customer | **0** |

**Final country split:** United Kingdom 12,480 · United States 5,077 · Germany 2,481 · France 1,980 · Ireland 1,707 · Spain 1,310

### Remaining unknowns (kept as NULL on purpose)

| Column | NULL rows | % of 25,035 |
|---|---|---|
| full_name | 487 | 1.9% |
| email | 1,980 | 7.9% |
| phone | 9,089 | 36.3% |
| age | 2,535 | 10.1% |
| signup_date | 981 | 3.9% |
| marketing_opt_in | 2,847 | 11.4% |
| city/country conflict flagged | 15,382 | 61.4% |

---

## 5. Limitations and next steps

- **Phone has 36% missing.** It isn't reliable for analysis or contact campaigns.
- **City should not be used for analysis** until the source of the conflicts is fixed.
- Proper Case doesn't handle names like `O'Brien` (becomes `O'brien`). A lookup table of name exceptions would fix this.
- Customers without an email may still contain duplicates. A fuzzy match on name + phone could find some of them.
- `customer_id_map` is used in the [orders cleaning](orders_cleaning_report.md) to re-point 6,636 orders from duplicate accounts.
