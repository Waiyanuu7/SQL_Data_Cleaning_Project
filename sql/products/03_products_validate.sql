-- =============================================================
-- 03_products_validate.sql
-- Proves clean_products is clean.
-- =============================================================
USE ecommerce;

-- 1. Row count and uniqueness (expected 800 rows, 0 duplicate IDs, 0 duplicate SKUs)
SELECT COUNT(*)                              AS clean_rows,
       COUNT(*) - COUNT(DISTINCT product_id) AS duplicate_ids,
       COUNT(*) - COUNT(DISTINCT sku)        AS duplicate_skus
FROM clean_products;

-- 2. Only the expected values remain
SELECT category, COUNT(*) AS num_products FROM clean_products GROUP BY category ORDER BY num_products DESC;
SELECT supplier, COUNT(*) AS num_products FROM clean_products GROUP BY supplier ORDER BY num_products DESC;
SELECT status,   COUNT(*) AS num_products FROM clean_products GROUP BY status   ORDER BY num_products DESC;

-- 3. Price: numeric, positive, no gaps (expected: min > 0, 0 missing)
SELECT MIN(price) AS min_price, MAX(price) AS max_price,
       SUM(price IS NULL)    AS missing_price,
       SUM(price <= 0)       AS non_positive_price,
       SUM(price_from_sales) AS prices_filled_from_sales
FROM clean_products;

-- 4. Formats (all expected 0)
SELECT SUM(sku NOT REGEXP '^SKU-[0-9]{5}$')                        AS bad_sku,
       SUM(LENGTH(product_name) <> LENGTH(TRIM(product_name)))     AS names_with_spaces,
       SUM(BINARY product_name = BINARY UPPER(product_name))       AS names_all_caps
FROM clean_products;

-- 5. Catalogue price equals the price customers paid (expected 0 mismatches)
SELECT COUNT(*) AS price_mismatches
FROM clean_products p
JOIN (SELECT product_id, MAX(CAST(unit_price AS DECIMAL(10,2))) AS paid
      FROM raw_order_items
      WHERE unit_price REGEXP '^[0-9]+\\.[0-9]{2}$'
      GROUP BY product_id) s ON s.product_id = p.product_id
WHERE p.price <> s.paid;
