-- =============================================================
-- 01_orders_audit.sql
-- Measures every data quality problem in raw_orders.
-- Results: docs/orders_cleaning_report.md
-- Needs: customers scripts already run (uses customer_id_map).
-- =============================================================
USE ecommerce;

-- 1. Duplicate rows ---------------------------------------------
SELECT COUNT(*)                                        AS total_rows,
       COUNT(DISTINCT order_id)                        AS distinct_order_ids,
       COUNT(*) - COUNT(DISTINCT order_id)             AS duplicate_rows
FROM raw_orders;

-- 2. Inconsistent text values (case-sensitive grouping) ---------
SELECT status COLLATE utf8mb4_bin AS status_value, COUNT(*) AS num_rows
FROM raw_orders GROUP BY status_value ORDER BY num_rows DESC;

SELECT payment_method COLLATE utf8mb4_bin AS payment_value, COUNT(*) AS num_rows
FROM raw_orders GROUP BY payment_value ORDER BY num_rows DESC;

SELECT channel COLLATE utf8mb4_bin AS channel_value, COUNT(*) AS num_rows
FROM raw_orders GROUP BY channel_value ORDER BY num_rows DESC;

SELECT promo_code COLLATE utf8mb4_bin AS promo_value,
       LENGTH(promo_code) AS characters,          -- reveals 'welcome ' with a trailing space
       COUNT(*) AS num_rows
FROM raw_orders GROUP BY promo_value, characters ORDER BY num_rows DESC;

-- 3. Date formats -----------------------------------------------
SELECT
  CASE
    WHEN order_date = '0000-00-00'                                   THEN 'Zero date (junk)'
    WHEN order_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}$'  THEN 'YYYY-MM-DD HH:MM:SS'
    WHEN order_date REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'            THEN 'YYYY/MM/DD'
    WHEN order_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'            THEN 'NN/NN/YYYY (slashes)'
    WHEN order_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'            THEN 'NN-NN-YYYY (dashes)'
    WHEN order_date REGEXP '^[0-9]{1,2} [A-Za-z]{3} [0-9]{4}$'       THEN 'DD Mon YYYY'
    WHEN order_date REGEXP '^-?[0-9]{1,10}$'                         THEN 'Unix timestamp'
    WHEN TRIM(order_date) = ''                                       THEN 'Blank'
    ELSE 'Other text (N/A, unknown, null)'
  END AS order_date_format,
  COUNT(*) AS num_rows
FROM raw_orders
GROUP BY order_date_format
ORDER BY num_rows DESC;

-- Proof of day/month order (a month can never be > 12)
-- Result: slashes = DD/MM, dashes = MM-DD, in BOTH date columns
SELECT
  SUM(order_date REGEXP '^[0-9]{2}/' AND LEFT(order_date,2) > 12)                 AS order_slash_1st_over_12,
  SUM(order_date REGEXP '^[0-9]{2}/' AND SUBSTRING(order_date,4,2) > 12)          AS order_slash_2nd_over_12,
  SUM(order_date REGEXP '^[0-9]{2}-[0-9]{2}-' AND LEFT(order_date,2) > 12)        AS order_dash_1st_over_12,
  SUM(order_date REGEXP '^[0-9]{2}-[0-9]{2}-' AND SUBSTRING(order_date,4,2) > 12) AS order_dash_2nd_over_12,
  SUM(ship_date  REGEXP '^[0-9]{2}/' AND LEFT(ship_date,2) > 12)                  AS ship_slash_1st_over_12,
  SUM(ship_date  REGEXP '^[0-9]{2}/' AND SUBSTRING(ship_date,4,2) > 12)           AS ship_slash_2nd_over_12,
  SUM(ship_date  REGEXP '^[0-9]{2}-[0-9]{2}-' AND LEFT(ship_date,2) > 12)         AS ship_dash_1st_over_12,
  SUM(ship_date  REGEXP '^[0-9]{2}-[0-9]{2}-' AND SUBSTRING(ship_date,4,2) > 12)  AS ship_dash_2nd_over_12
FROM raw_orders;

-- 4. Missing values ---------------------------------------------
SELECT
  SUM(TRIM(customer_id) = '')      AS blank_customer_id,
  SUM(TRIM(order_total) = '')      AS blank_order_total,
  SUM(TRIM(ship_date) = '')        AS blank_ship_date,
  SUM(TRIM(status) = '')           AS blank_status,
  SUM(TRIM(payment_method) = '')   AS blank_payment,
  SUM(TRIM(channel) = '')          AS blank_channel
FROM raw_orders;

-- 5. Orders whose customer doesn't exist (orphans) --------------
SELECT COUNT(*) AS orders_with_unknown_customer
FROM (SELECT DISTINCT order_id, customer_id FROM raw_orders) o
LEFT JOIN customer_id_map m ON m.old_id = CAST(NULLIF(TRIM(o.customer_id), '') AS UNSIGNED)
WHERE TRIM(o.customer_id) <> '' AND m.old_id IS NULL;

-- Orders placed under a duplicate customer account (to be re-pointed)
SELECT COUNT(*) AS orders_from_duplicate_accounts
FROM (SELECT DISTINCT order_id, customer_id FROM raw_orders) o
JOIN customer_id_map m ON m.old_id = CAST(NULLIF(TRIM(o.customer_id), '') AS UNSIGNED)
WHERE m.old_id <> m.master_id;
