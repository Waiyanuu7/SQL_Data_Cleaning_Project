-- =============================================================
-- 03_orders_validate.sql
-- Proves clean_orders is clean.
-- =============================================================
USE ecommerce;

-- 1. Row count and uniqueness (expected 150,000 and 0)
SELECT COUNT(*) AS clean_rows,
       COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_ids
FROM clean_orders;

-- 2. Every customer_id points to a real customer (expected 0)
SELECT COUNT(*) AS broken_customer_links
FROM clean_orders o
LEFT JOIN clean_customers c ON c.customer_id = o.customer_id
WHERE o.customer_id IS NOT NULL AND c.customer_id IS NULL;

-- 3. Only standard values remain
SELECT status,         COUNT(*) AS num_orders FROM clean_orders GROUP BY status         ORDER BY num_orders DESC;
SELECT payment_method, COUNT(*) AS num_orders FROM clean_orders GROUP BY payment_method ORDER BY num_orders DESC;
SELECT channel, app_platform, COUNT(*) AS num_orders FROM clean_orders GROUP BY channel, app_platform ORDER BY num_orders DESC;
SELECT promo_code,     COUNT(*) AS num_orders FROM clean_orders GROUP BY promo_code     ORDER BY num_orders DESC;

-- 4. Dates inside the valid period
SELECT MIN(order_date) AS first_order, MAX(order_date) AS last_order,
       MIN(ship_date)  AS first_ship,  MAX(ship_date)  AS last_ship
FROM clean_orders;

-- Evidence for the valid period: orders per month, every month present
SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, COUNT(*) AS num_orders
FROM clean_orders
WHERE order_date IS NOT NULL
GROUP BY month
ORDER BY month;

-- 5. Issues kept visible, not hidden
SELECT customer_note,    COUNT(*) AS num_orders FROM clean_orders GROUP BY customer_note;
SELECT order_date_issue, COUNT(*) AS num_orders FROM clean_orders GROUP BY order_date_issue;
SELECT ship_before_order, COUNT(*) AS num_orders FROM clean_orders GROUP BY ship_before_order;

-- 6. Days from order to shipping (normal orders should take 0-7 days)
SELECT DATEDIFF(ship_date, order_date) AS days_to_ship, COUNT(*) AS num_orders
FROM clean_orders
WHERE ship_before_order = 0
GROUP BY days_to_ship
ORDER BY days_to_ship;
