# Orders Table: Data Cleaning Report

**Table:** `raw_orders` → `clean_orders`
**Rows:** 153,000 → **150,000**
**Scripts:** [`sql/orders/`](../sql/orders)

| Step | Script | What it does |
|---|---|---|
| 1 | `01_orders_audit.sql` | Measures every problem before anything is changed |
| 2 | `02_orders_clean.sql` | Builds `clean_orders` |
| 3 | `03_orders_validate.sql` | Proves the result is clean |
| 4 | `../order_items/04_order_totals_reconcile.sql` | Recalculates every order total from its line items (after order_items is cleaned) |

---

## 1. Audit: what was wrong

| # | Column | Problem | Rows affected |
|---|---|---|---|
| 1 | all | Exact duplicate rows | 3,000 |
| 2 | order_date | **7 formats**, including Unix timestamps | 68,905 not in the standard format |
| 3 | order_date | Blank / text (`N/A`, `unknown`) / `0000-00-00` | 3,055 / 2,352 / 771 |
| 4 | order_date | Placeholder date in 1970 (before the shop existed) | 243 |
| 5 | order_date | In the future (2027–2029) | 593 |
| 6 | ship_date | Same mix of formats; blank | 18,211 blank |
| 7 | ship_date | **Before the order date** | 2,426 |
| 8 | status | **16 values** for 5 meanings (`Delivered`, `delivered`, ` Delivered `, `Dlvrd`, `complete`, `canceled`...) | all |
| 9 | payment_method | **14 values** (`CC` / `Credit Card` / `credit card`, `Pay Pal` / `paypal`, `applepay`...) | all |
| 10 | channel | **11 values** (`web` / `Web` / `WEB`, `App` / `mobile app` / `iOS` / `android`...) | all |
| 11 | promo_code | Case variants (`summer10`), a hidden trailing space (`welcome `), and `N/A` | 51,194 |
| 12 | customer_id | Blank | 1,509 |
| 13 | customer_id | Customer doesn't exist (orphan, IDs 90000+) | 2,283 |
| 14 | customer_id | Placed under a **duplicate customer account** (found in customers cleaning) | 6,636 |
| 15 | order_total | Blank | 3,019 |
| 16 | order_total | Doesn't match the order's line items | see reconciliation |

### Audit findings worth highlighting

**Day/month order proven, not assumed.** A month can't be above 12:

| Column / format | 1st part > 12 | 2nd part > 12 | Conclusion |
|---|---|---|---|
| order_date `NN/NN/YYYY` | 14,011 | 0 | DD/MM/YYYY (UK) |
| order_date `NN-NN-YYYY` | 0 | 9,265 | MM-DD-YYYY (US) |
| ship_date `NN/NN/YYYY` | 12,349 | 0 | DD/MM/YYYY (UK) |
| ship_date `NN-NN-YYYY` | 0 | 8,474 | MM-DD-YYYY (US) |

**The valid period was found from the data itself.** After parsing, orders appear every month from January 2021 to September 2026 (about 2,000 a month). Then there's a gap, followed by a thin scatter of around 10–25 dates a month across 2027–2029. Those can't have happened yet. A handful of 1970-01-01 dates also appear: that's "Unix time zero", a classic placeholder for a missing date.

**Unix timestamps were converted to UK time, not UTC.** MySQL's `FROM_UNIXTIME()` uses the server's time zone, and named zones like `Europe/London` only work if time-zone tables are installed. I wrote a small function, [`uk_from_unix()`](../sql/00_uk_time_function.sql), that applies the UK daylight-saving rule. I tested it against 4,056 timestamps, including every clock change from 2019 to 2029, with 0 errors. Without it, orders placed just after midnight in summer would land on the previous day.

**Shipping time pattern.** Orders that shipped after being ordered took 0–7 days, spread evenly (about 15,000 orders per day value). That confirms the 7-day window used to validate ship dates.

---

## 2. Cleaning: what I did

| Column | Rule applied |
|---|---|
| all rows | `SELECT DISTINCT` removes the 3,000 exact copies |
| order_id | Number, **PRIMARY KEY**; indexes added on customer_id and order_date |
| customer_id | Re-pointed through `customer_id_map`: duplicate accounts → the kept account; unknown/blank → NULL |
| customer_note | **New column** explaining any customer problem: `Merged duplicate account`, `Customer not found`, `Missing customer ID` |
| order_date | 7 formats → `DATE`; only kept if between 2021-01-01 and 2026-09-30 |
| order_date_issue | **New column**: `Missing or unreadable`, `Before shop opened (1970 default)`, `Future date` |
| ship_date | Same parsing; kept if within the valid period + 7 days |
| ship_before_order | **New flag**: 1 = shipped before ordered |
| status | 16 values → `Delivered`, `Shipped`, `Cancelled`, `Returned`, `Pending`, `Unknown` |
| payment_method | 14 values → 9 (spaces removed before matching, so `Pay Pal` = `PayPal`) |
| channel | 11 values → `Web`, `Mobile App`, `Phone`, `In-store`, `Unknown` |
| app_platform | **New column**: `iOS` / `Android`, so merging them into Mobile App loses nothing |
| promo_code | Trimmed, upper case; `N/A` and blank → NULL |
| order_total | Reported value kept as `order_total_reported`; a **recalculated** `order_total` is added in reconciliation |

---

## 3. Decisions log

| Decision | Why |
|---|---|
| **Orders with problems are kept, not deleted** | A sale with a missing date or unknown customer still happened. Its revenue is real. Deleting it would understate sales. Flag columns let each analysis choose what to include. |
| Unknown customers → NULL customer_id + note | Keeps every customer_id a valid link to `clean_customers` (0 broken links), while recording what was wrong. |
| Orders from duplicate accounts re-pointed (6,636) | Uses the map built in customers cleaning. Without it, these customers' spending would be split across two IDs, or lost. |
| Order date stored as `DATE`, not `DATETIME` | Only 55% of rows include a time. A time column that's blank for half the rows would mislead hourly analysis. |
| Future and 1970 dates → NULL with a reason | They're impossible. The reason column keeps the raw problem visible. |
| Ship-before-order: **flagged, not fixed** | One of the two dates is wrong, and there's no way to tell which. These orders are excluded from shipping-time analysis only. |
| `complete` and `Dlvrd` → `Delivered` | Both mean the order reached the customer. |
| `Visa` and `Mastercard` kept separate from Credit/Debit Card | They're card brands, so they could be either credit or debit. Merging them would be a guess. |
| `phone` channel = telephone order | It's listed alongside `App`, `iOS` and `android`, so it isn't the mobile app. |
| `iOS` / `Android` → `Mobile App`, with platform kept in `app_platform` | Channel-level reporting gets one clean category, and the platform detail is still there. |

---

## 4. Validation: proof it's clean

| Check | Result |
|---|---|
| Rows | **150,000** |
| Duplicate order IDs | **0** |
| customer_id pointing to a missing customer | **0** |
| Order date range | **2021-01-01 – 2026-09-29**, every month present (1,859–2,211 orders per month) |
| Ship date range | **2021-01-01 – 2026-10-06** |
| Status values | Delivered 92,453 · Shipped 23,357 · Cancelled 14,302 · Returned 8,973 · Pending 7,357 · Unknown 3,558 |
| Channel values | Mobile App 68,141 (Android 27,211 · iOS 13,574 · unspecified 27,356) · Web 41,057 · In-store 13,578 · Phone 13,428 · Unknown 13,796 |
| Promo codes | WELCOME 33,386 · SUMMER10 33,336 · BF2025 16,652 · none 66,626 |

### Issues kept visible

| Flag | Orders |
|---|---|
| `customer_note` = Merged duplicate account | 6,636 |
| `customer_note` = Customer not found | 2,283 |
| `customer_note` = Missing customer ID | 1,509 |
| `order_date_issue` = Missing or unreadable | 6,076 |
| `order_date_issue` = Future date | 593 |
| `order_date_issue` = Before shop opened (1970 default) | 243 |
| `ship_before_order` = 1 | 2,426 |

Order totals: see the [order_items report](order_items_cleaning_report.md#5-order-total-reconciliation).
