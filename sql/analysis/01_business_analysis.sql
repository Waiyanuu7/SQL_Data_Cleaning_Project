-- =============================================================
-- 01_business_analysis.sql
-- Business questions answered with the CLEAN tables.
--
-- Revenue definition used throughout:
--   * orders with status Delivered or Shipped (Cancelled, Returned,
--     Pending and Unknown are excluded)
--   * order_total = total RECALCULATED from valid line items + shipping
--     (see 04_order_totals_reconcile.sql)
--   * product/category revenue = line_total of valid lines (excludes shipping)
-- =============================================================
USE ecommerce;

-- Reusable view of completed orders
CREATE OR REPLACE VIEW completed_orders AS
SELECT *
FROM clean_orders
WHERE status IN ('Delivered', 'Shipped')
  AND order_total IS NOT NULL;

-- Q0. Why the cleaning mattered: revenue from raw vs clean totals --
SELECT ROUND(SUM(order_total_reported) / 1e6, 2) AS revenue_m_using_reported_totals,
       ROUND(SUM(order_total) / 1e6, 2)          AS revenue_m_using_clean_totals
FROM completed_orders;

-- Q1. Headline KPIs -----------------------------------------------
SELECT COUNT(*)                              AS completed_orders,
       COUNT(DISTINCT customer_id)           AS customers,
       ROUND(SUM(order_total), 2)            AS revenue,
       ROUND(AVG(order_total), 2)            AS avg_order_value
FROM completed_orders;

-- Q2. Revenue by year, with year-on-year growth ---------------------
-- 2026 only has January-September, so it is also compared like-for-like
WITH yearly AS (
    SELECT YEAR(order_date)                               AS yr,
           SUM(order_total)                               AS revenue,
           SUM(CASE WHEN MONTH(order_date) <= 9 THEN order_total END) AS revenue_jan_sep
    FROM completed_orders
    WHERE order_date IS NOT NULL
    GROUP BY YEAR(order_date)
)
SELECT yr,
       ROUND(revenue, 0)                                                    AS revenue,
       ROUND(100 * (revenue / LAG(revenue) OVER (ORDER BY yr) - 1), 1)      AS yoy_growth_pct,
       ROUND(revenue_jan_sep, 0)                                            AS revenue_jan_sep,
       ROUND(100 * (revenue_jan_sep / LAG(revenue_jan_sep) OVER (ORDER BY yr) - 1), 1) AS yoy_growth_jan_sep_pct
FROM yearly
ORDER BY yr;

-- Q3. Monthly revenue trend with 3-month moving average ---------------
WITH monthly AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m') AS month,
           COUNT(*)                         AS orders,
           SUM(order_total)                 AS revenue
    FROM completed_orders
    WHERE order_date IS NOT NULL
    GROUP BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT month,
       orders,
       ROUND(revenue, 0)                                                   AS revenue,
       ROUND(AVG(revenue) OVER (ORDER BY month
                                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS revenue_3m_avg
FROM monthly
ORDER BY month;

-- Q4. Revenue by product category --------------------------------
SELECT COALESCE(p.category, 'Not in catalogue')               AS category,
       SUM(i.quantity)                                         AS units_sold,
       ROUND(SUM(i.line_total), 0)                             AS revenue,
       ROUND(100 * SUM(i.line_total) / SUM(SUM(i.line_total)) OVER (), 1) AS pct_of_revenue
FROM clean_order_items i
JOIN completed_orders o   ON o.order_id = i.order_id
LEFT JOIN clean_products p ON p.product_id = i.product_id
WHERE i.is_valid = 1
GROUP BY COALESCE(p.category, 'Not in catalogue')
ORDER BY revenue DESC;

-- Q5. Top 10 products by revenue ----------------------------------
SELECT p.product_id, p.sku, p.product_name, p.category,
       SUM(i.quantity)            AS units_sold,
       ROUND(SUM(i.line_total), 0) AS revenue,
       RANK() OVER (ORDER BY SUM(i.line_total) DESC) AS revenue_rank
FROM clean_order_items i
JOIN completed_orders o ON o.order_id = i.order_id
JOIN clean_products p   ON p.product_id = i.product_id
WHERE i.is_valid = 1
GROUP BY p.product_id, p.sku, p.product_name, p.category
ORDER BY revenue DESC
LIMIT 10;

-- Q6. Revenue by customer country ---------------------------------
-- (country, not city: city contradicts country for most customers)
SELECT COALESCE(c.country, 'Unknown customer')                 AS country,
       COUNT(*)                                                AS orders,
       ROUND(SUM(o.order_total), 0)                            AS revenue,
       ROUND(AVG(o.order_total), 2)                            AS avg_order_value
FROM completed_orders o
LEFT JOIN clean_customers c ON c.customer_id = o.customer_id
GROUP BY COALESCE(c.country, 'Unknown customer')
ORDER BY revenue DESC;

-- Q7. Revenue by sales channel --------------------------------------
SELECT channel,
       COUNT(*)                     AS orders,
       ROUND(SUM(order_total), 0)   AS revenue,
       ROUND(AVG(order_total), 2)   AS avg_order_value
FROM completed_orders
GROUP BY channel
ORDER BY revenue DESC;

-- Q8. Repeat customers ---------------------------------------------
WITH per_customer AS (
    SELECT customer_id, COUNT(*) AS orders, SUM(order_total) AS spend
    FROM completed_orders
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
)
SELECT COUNT(*)                                          AS buying_customers,
       SUM(orders >= 2)                                  AS repeat_customers,
       ROUND(100 * AVG(orders >= 2), 1)                  AS repeat_rate_pct,
       ROUND(AVG(orders), 2)                             AS avg_orders_per_customer,
       ROUND(AVG(spend), 2)                              AS avg_lifetime_spend
FROM per_customer;

-- Q9. Return and cancellation rate by category ----------------------
-- Based on all orders with a final outcome (Delivered/Shipped/Returned/Cancelled)
SELECT COALESCE(p.category, 'Not in catalogue')                           AS category,
       COUNT(DISTINCT o.order_id)                                         AS orders,
       ROUND(100 * COUNT(DISTINCT CASE WHEN o.status = 'Returned'  THEN o.order_id END)
                 / COUNT(DISTINCT o.order_id), 1)                         AS return_rate_pct,
       ROUND(100 * COUNT(DISTINCT CASE WHEN o.status = 'Cancelled' THEN o.order_id END)
                 / COUNT(DISTINCT o.order_id), 1)                         AS cancel_rate_pct
FROM clean_orders o
JOIN clean_order_items i   ON i.order_id = o.order_id AND i.is_valid = 1
LEFT JOIN clean_products p ON p.product_id = i.product_id
WHERE o.status IN ('Delivered','Shipped','Returned','Cancelled')
GROUP BY COALESCE(p.category, 'Not in catalogue')
ORDER BY return_rate_pct DESC;

-- Q10. Promo codes: usage and average order value ------------------
SELECT COALESCE(promo_code, 'No promo')  AS promo_code,
       COUNT(*)                          AS orders,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders,
       ROUND(AVG(order_total), 2)        AS avg_order_value
FROM completed_orders
GROUP BY COALESCE(promo_code, 'No promo')
ORDER BY orders DESC;

-- Q11. Average days from order to shipping, by channel ---------------
SELECT channel,
       ROUND(AVG(DATEDIFF(ship_date, order_date)), 2) AS avg_days_to_ship
FROM clean_orders
WHERE ship_before_order = 0
GROUP BY channel
ORDER BY avg_days_to_ship;
