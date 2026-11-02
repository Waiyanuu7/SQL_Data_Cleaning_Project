-- =============================================================
-- 01_products_audit.sql
-- Measures every data quality problem in raw_products.
-- Results: docs/products_cleaning_report.md
-- =============================================================
USE ecommerce;

-- 1. Duplicate rows ---------------------------------------------
SELECT COUNT(*)                                          AS total_rows,
       COUNT(DISTINCT product_id)                        AS distinct_ids,
       (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM raw_products) d) AS distinct_rows
FROM raw_products;

-- 2. Inconsistent text values (case-sensitive grouping) ---------
SELECT category COLLATE utf8mb4_bin AS category_value, COUNT(*) AS num_rows
FROM raw_products GROUP BY category_value ORDER BY category_value;

SELECT supplier COLLATE utf8mb4_bin AS supplier_value, COUNT(*) AS num_rows
FROM raw_products GROUP BY supplier_value ORDER BY supplier_value;

SELECT status COLLATE utf8mb4_bin AS status_value, COUNT(*) AS num_rows
FROM raw_products GROUP BY status_value ORDER BY status_value;

-- 3. Price stored as text in many formats -----------------------
SELECT
  CASE
    WHEN TRIM(price) = ''                      THEN 'Blank'
    WHEN price LIKE '-%'                       THEN 'Negative'
    WHEN price LIKE '%GBP%'                    THEN 'Has "GBP" text'
    WHEN price LIKE '%,%'                      THEN 'Comma decimal (12,50)'
    WHEN price REGEXP '^[0-9]+(\\.[0-9]+)?$'   THEN 'Plain number'
    ELSE 'Has £ symbol'
  END AS price_format,
  COUNT(*) AS num_rows,
  MIN(price) AS example
FROM raw_products
GROUP BY price_format
ORDER BY num_rows DESC;

-- 4. SKU and product name formatting ----------------------------
SELECT
  SUM(sku NOT REGEXP '^SKU-[0-9]{5}$')                              AS sku_wrong_format,
  SUM(LENGTH(product_name) <> LENGTH(TRIM(product_name)))           AS name_extra_spaces,
  SUM(BINARY product_name = BINARY UPPER(product_name))             AS name_all_caps
FROM raw_products;

-- 5. Cross-check catalogue prices against what customers paid ---
-- order_items stores the price charged on each sale. If a product was
-- always sold at one price, that price is strong evidence of the true price.
WITH sold AS (
    SELECT product_id,
           COUNT(DISTINCT unit_price) AS prices_seen,
           MAX(unit_price)            AS price_paid
    FROM raw_order_items
    WHERE unit_price REGEXP '^[0-9]+\\.[0-9]{2}$'
    GROUP BY product_id
)
SELECT
  CASE WHEN TRIM(p.price) = '' THEN 'Blank'
       WHEN p.price LIKE '-%'  THEN 'Negative'
       ELSE 'Other' END                                   AS price_group,
  COUNT(*)                                                AS products,
  SUM(s.prices_seen = 1)                                  AS sold_at_one_price,
  SUM(ABS(CAST(NULLIF(REPLACE(REGEXP_REPLACE(p.price, '[^0-9.,]', ''), ',', '.'), '') AS DECIMAL(10,2)))
      = CAST(s.price_paid AS DECIMAL(10,2)))              AS catalogue_matches_paid
FROM (SELECT DISTINCT * FROM raw_products) p
JOIN sold s ON s.product_id = p.product_id
GROUP BY price_group;
