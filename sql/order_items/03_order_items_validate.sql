-- =============================================================
-- 03_order_items_validate.sql
-- Proves clean_order_items is clean.
-- =============================================================
USE ecommerce;

-- 1. Row count and uniqueness (expected 286,371 and 0)
SELECT COUNT(*) AS clean_rows,
       COUNT(*) - COUNT(DISTINCT order_item_id) AS duplicate_ids
FROM clean_order_items;

-- 2. Every line belongs to a real order (expected 0)
SELECT COUNT(*) AS lines_without_order
FROM clean_order_items i
LEFT JOIN clean_orders o ON o.order_id = i.order_id
WHERE o.order_id IS NULL;

-- 3. Discount is a fraction from 0 to 0.20
SELECT discount, COUNT(*) AS num_lines FROM clean_order_items GROUP BY discount ORDER BY discount;

-- 4. Valid lines only have sensible values (all expected 0)
SELECT SUM(quantity NOT BETWEEN 1 AND 10)   AS bad_quantity,
       SUM(unit_price IS NULL OR unit_price <= 0) AS bad_price,
       SUM(line_total IS NULL OR line_total <= 0) AS bad_line_total
FROM clean_order_items
WHERE is_valid = 1;

-- 5. Issues kept visible
SELECT COALESCE(line_issue, 'Valid') AS line_status, COUNT(*) AS num_lines
FROM clean_order_items GROUP BY line_status ORDER BY num_lines DESC;

SELECT SUM(price_from_catalogue) AS prices_filled_from_catalogue,
       SUM(unknown_product)      AS lines_with_unknown_product
FROM clean_order_items;
