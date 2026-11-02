-- =============================================================
-- 04_order_totals_reconcile.sql
-- Recalculates every order total from its line items and compares
-- it with the total stored in the orders table.
--   calculated total = SUM(quantity x unit_price x (1 - discount)) + shipping
-- Needs: clean_orders and clean_order_items.
-- =============================================================
USE ecommerce;

-- 1. Totals per order from the line items ------------------------
DROP TEMPORARY TABLE IF EXISTS order_calc;
CREATE TEMPORARY TABLE order_calc AS
SELECT order_id,
       COUNT(*)                         AS num_lines,
       SUM(is_valid = 0)                AS invalid_lines,
       SUM(line_issue = 'Missing price') AS lines_missing_price,
       SUM(line_total)                  AS items_total      -- valid lines only
FROM clean_order_items
GROUP BY order_id;
ALTER TABLE order_calc ADD PRIMARY KEY (order_id);

-- 2. Add the results to clean_orders -----------------------------
ALTER TABLE clean_orders
    ADD COLUMN num_lines        INT,
    ADD COLUMN items_total      DECIMAL(12,2),
    ADD COLUMN order_total      DECIMAL(12,2),
    ADD COLUMN total_check      VARCHAR(40);

SET SQL_SAFE_UPDATES = 0;

UPDATE clean_orders o
JOIN order_calc c ON c.order_id = o.order_id
SET o.num_lines   = c.num_lines,
    o.items_total = COALESCE(c.items_total, 0),
    -- The clean total is the CALCULATED one (line items are the detailed record)
    o.order_total = CASE WHEN c.lines_missing_price > 0 THEN NULL
                         ELSE COALESCE(c.items_total, 0) + o.shipping_cost END,
    o.total_check = CASE
        WHEN c.lines_missing_price > 0           THEN 'Cannot calculate (missing price)'
        WHEN o.order_total_reported IS NULL      THEN 'Reported total missing'
        WHEN ABS(o.order_total_reported - (COALESCE(c.items_total, 0) + o.shipping_cost)) <= 0.05
                                                 THEN 'Match'
        WHEN c.invalid_lines > 0                 THEN 'Differs: has invalid line(s)'
        ELSE                                          'Differs: unexplained'
    END;

SET SQL_SAFE_UPDATES = 1;
DROP TEMPORARY TABLE order_calc;

-- 3. Results ------------------------------------------------------
SELECT total_check,
       COUNT(*)                                                AS num_orders,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM clean_orders), 1) AS pct,
       ROUND(SUM(order_total_reported), 2)                     AS reported_total,
       ROUND(SUM(order_total), 2)                              AS calculated_total
FROM clean_orders
GROUP BY total_check
ORDER BY num_orders DESC;

-- Why do orders with invalid lines differ? Check which line issue is involved.
-- (Orders with a 999 line: the reported total counted all 999 units.)
SELECT i.line_issue,
       COUNT(DISTINCT o.order_id)                              AS orders,
       SUM(o.total_check = 'Differs: has invalid line(s)')     AS orders_that_differ
FROM clean_orders o
JOIN clean_order_items i ON i.order_id = o.order_id
WHERE i.line_issue IS NOT NULL
GROUP BY i.line_issue;

-- Every order should have line items (expected 0)
SELECT COUNT(*) AS orders_without_lines FROM clean_orders WHERE num_lines IS NULL;
