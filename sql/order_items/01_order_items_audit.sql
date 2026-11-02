-- =============================================================
-- 01_order_items_audit.sql
-- Measures every data quality problem in raw_order_items.
-- Results: docs/order_items_cleaning_report.md
-- Needs: products and orders scripts already run.
-- =============================================================
USE ecommerce;

-- 1. Duplicate rows ---------------------------------------------
SELECT COUNT(*)                                  AS total_rows,
       COUNT(DISTINCT order_item_id)             AS distinct_ids,
       COUNT(*) - COUNT(DISTINCT order_item_id)  AS duplicate_rows
FROM raw_order_items;

-- 2. Quantity: zero, negative and extreme values ----------------
SELECT CAST(quantity AS SIGNED) AS quantity, COUNT(*) AS num_rows
FROM raw_order_items
GROUP BY CAST(quantity AS SIGNED)
ORDER BY quantity;

-- Are negative quantities returns? If they were, they'd be concentrated
-- in Returned orders. They're ~1% in EVERY status -> data entry errors.
SELECT o.status,
       COUNT(*)                                         AS num_lines,
       SUM(CAST(i.quantity AS SIGNED) < 0)              AS negative_lines,
       ROUND(100 * AVG(CAST(i.quantity AS SIGNED) < 0), 2) AS pct_negative
FROM (SELECT DISTINCT * FROM raw_order_items) i
JOIN clean_orders o ON o.order_id = CAST(i.order_id AS UNSIGNED)
GROUP BY o.status
ORDER BY num_lines DESC;

-- 3. Unit price stored as text ----------------------------------
SELECT
  -- note: LOAD DATA turns the unquoted word NULL into a real SQL NULL
  CASE WHEN unit_price IS NULL                      THEN 'NULL'
       WHEN unit_price REGEXP '^[0-9]+\\.[0-9]{2}$' THEN 'Valid number'
       WHEN TRIM(unit_price) = ''                   THEN 'Blank'
       ELSE 'Has £ symbol'
  END AS price_format,
  COUNT(*) AS num_rows
FROM raw_order_items
GROUP BY price_format
ORDER BY num_rows DESC;

-- 4. Discount in 3 different notations (0.1 / 10 / 10%) --------
SELECT discount COLLATE utf8mb4_bin AS discount_value, COUNT(*) AS num_rows
FROM raw_order_items
GROUP BY discount_value
ORDER BY discount_value;

-- 5. Products that don't exist in the catalogue -----------------
SELECT COUNT(*)                     AS lines_unknown_product,
       COUNT(DISTINCT i.product_id) AS unknown_product_ids,
       MIN(CAST(i.product_id AS UNSIGNED)) AS lowest_id,
       MAX(CAST(i.product_id AS UNSIGNED)) AS highest_id
FROM (SELECT DISTINCT * FROM raw_order_items) i
LEFT JOIN clean_products p ON p.product_id = CAST(i.product_id AS UNSIGNED)
WHERE p.product_id IS NULL;

-- 6. Lines whose order doesn't exist (expected 0) ---------------
SELECT COUNT(*) AS lines_without_order
FROM (SELECT DISTINCT * FROM raw_order_items) i
LEFT JOIN clean_orders o ON o.order_id = CAST(i.order_id AS UNSIGNED)
WHERE o.order_id IS NULL;
