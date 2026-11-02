# E-commerce Data Cleaning & Analysis with SQL (MySQL)

End-to-end cleaning of a messy, four-table e-commerce dataset (**~470,000 rows**) in MySQL, followed by business analysis on the clean data. Every table goes through the same process: **audit → clean → validate → document**.

> **Headline result:** the raw `order_total` column would have reported **£113.8M** in revenue. After cleaning and recalculating totals from line items, the true figure is **£32.3M**. A handful of orders with a placeholder quantity of 999 had inflated revenue about 3.5×.

## The dataset

A fictional UK online shop, January 2021 – September 2026. It's a synthetic practice dataset containing realistic data quality problems. The raw CSV files are in [`data/`](data).

| Table | Raw rows | Clean rows | Report |
|---|---|---|---|
| customers | 26,600 | 25,035 | [Customers report](docs/customers_cleaning_report.md) |
| products | 825 | 800 | [Products report](docs/products_cleaning_report.md) |
| orders | 153,000 | 150,000 | [Orders report](docs/orders_cleaning_report.md) |
| order_items | 290,371 | 286,371 | [Order items report](docs/order_items_cleaning_report.md) |
| **Analysis** | | | [**Business findings**](docs/analysis_findings.md) |

```
customers.customer_id ──< orders.customer_id
orders.order_id       ──< order_items.order_id
products.product_id   ──< order_items.product_id
```

## Approach

1. **Load raw data as text.** Every column was imported as `VARCHAR` with `LOAD DATA LOCAL INFILE`, so nothing was rejected or silently converted.
2. **Never modify raw tables.** All fixes create new `clean_` tables, so every change can be traced back to the original.
3. **Audit before cleaning.** Each problem is measured with a query and recorded with its row count.
4. **Decide with evidence.** Ambiguous cases are settled with a query wherever possible, not an assumption.
5. **Flag, don't delete.** Rows with problems are kept with a flag or reason column, so revenue isn't silently lost and each analysis can choose what to include.
6. **Validate** every clean table with queries that prove it meets its rules.
7. **Document** every judgement call in a decisions log.

## Key findings from the cleaning

| Finding | How it was handled |
|---|---|
| Reported order totals overstated revenue **3.5×** (orders with quantity 999) | Totals recalculated from valid line items; originals kept for comparison |
| **1,165 customers registered twice** under different IDs | Merged by email, missing details rescued, and **6,636 orders re-pointed** through an ID mapping table |
| Dates in **7 formats**, including ambiguous `03/07/2021` | **Proved** DD/MM vs MM/DD by checking which part ever exceeds 12 |
| Unix timestamps | Converted to **UK local time** with a custom function that handles daylight saving (tested on 4,056 timestamps, 0 errors) |
| City contradicts country for **61% of customers** | Flagged; country chosen as the source of truth based on its distribution |
| Negative product prices and blank prices | Sales data proved negatives were sign errors (100% match) and supplied the missing prices |
| Negative quantities: returns or errors? | ~1% in every order status (returns too), so **entry errors** |
| 593 orders dated in the **future**, 243 in **1970** | Valid period found from the monthly order counts; impossible dates set to NULL with a reason |
| 31 spellings of country, 27 of category, 16 of order status | Standardised with `CASE` mappings |

## Business insights (from the clean data)

- **£32.3M** revenue from 115,786 completed orders; average order value **£279**.
- Revenue has been **flat for five years**. 2026 is **down 2.3%** like-for-like (Jan–Sep). The raw full-year figure wrongly suggests -27%.
- **Electronics = 38.7% of revenue** and all of the top 10 products, despite selling the same number of units as other categories.
- **The UK brings in 49% of revenue**; the **mobile app is the biggest channel (45%)**.
- **56% of orders use a promo code**, but promo orders aren't any larger than orders without one.

Full results: [docs/analysis_findings.md](docs/analysis_findings.md)

## SQL techniques used

- CTEs (`WITH`) for step-by-step transformations
- `CASE` mappings
- `REGEXP`, `REGEXP_REPLACE`, `STR_TO_DATE`, `SUBSTRING_INDEX`, `COALESCE`, `NULLIF`
- Window functions: `MIN() OVER (PARTITION BY)`, `LAG()`, `RANK()`, moving averages, `SUM() OVER ()`
- A stored function (`uk_from_unix`)
- `UPDATE ... JOIN`, temporary tables, views
- Primary keys and indexes, also used as validation
- `COLLATE utf8mb4_bin` to reveal case variants that MySQL normally hides

## How to reproduce

Requires **MySQL 8**. In MySQL Workbench, add `OPT_LOCAL_INFILE=1` under *Edit Connection → Advanced → Others*, then run `SET GLOBAL local_infile = 1;`.

1. Download the four CSV files from the `data/` folder.
2. Run the scripts **in this order**:

| # | Script |
|---|---|
| 1 | `sql/00_setup_load.sql` (edit the file paths first) |
| 2 | `sql/00_uk_time_function.sql` |
| 3 | `sql/customers/01` → `02` → `03` → `04` |
| 4 | `sql/products/01` → `02` → `03` |
| 5 | `sql/orders/01` → `02` → `03` |
| 6 | `sql/order_items/01` → `02` → `03` → `04` |
| 7 | `sql/analysis/01_business_analysis.sql` |

The whole pipeline has been run end to end on an empty database in strict SQL mode, with no errors or warnings.

## Repository structure

```
├── README.md
├── data/
│   ├── customers.csv                      # raw data (messy)
│   ├── products.csv
│   ├── orders.csv
│   └── order_items.csv
├── docs/
│   ├── customers_cleaning_report.md
│   ├── products_cleaning_report.md
│   ├── orders_cleaning_report.md
│   ├── order_items_cleaning_report.md
│   └── analysis_findings.md
└── sql/
    ├── 00_setup_load.sql                  # create raw tables, load CSVs
    ├── 00_uk_time_function.sql            # Unix timestamp -> UK local time
    ├── customers/
    │   ├── 01_customers_audit.sql
    │   ├── 02_customers_clean.sql
    │   ├── 03_customers_dedupe.sql
    │   └── 04_customers_validate.sql
    ├── products/
    │   ├── 01_products_audit.sql
    │   ├── 02_products_clean.sql
    │   └── 03_products_validate.sql
    ├── orders/
    │   ├── 01_orders_audit.sql
    │   ├── 02_orders_clean.sql
    │   └── 03_orders_validate.sql
    ├── order_items/
    │   ├── 01_order_items_audit.sql
    │   ├── 02_order_items_clean.sql
    │   ├── 03_order_items_validate.sql
    │   └── 04_order_totals_reconcile.sql
    └── analysis/
        └── 01_business_analysis.sql
```
