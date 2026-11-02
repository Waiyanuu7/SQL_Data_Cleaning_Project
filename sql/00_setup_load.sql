-- =============================================================
-- 00_setup_load.sql
-- Creates the database and loads the four raw CSVs.
-- Every column is VARCHAR on purpose: messy data must load as-is.
--
-- One-time setup in MySQL Workbench:
--   Edit Connection -> Advanced -> Others: OPT_LOCAL_INFILE=1
--   then run: SET GLOBAL local_infile = 1;
-- Change '/path/to/data/' below to where your CSV files are.
-- =============================================================
CREATE DATABASE IF NOT EXISTS ecommerce CHARACTER SET utf8mb4;
USE ecommerce;

DROP TABLE IF EXISTS raw_customers, raw_products, raw_orders, raw_order_items;

CREATE TABLE raw_customers (
  customer_id VARCHAR(255), full_name VARCHAR(255), email VARCHAR(255),
  phone VARCHAR(255), country VARCHAR(255), city VARCHAR(255),
  age VARCHAR(255), gender VARCHAR(255), signup_date VARCHAR(255),
  marketing_opt_in VARCHAR(255)
);

CREATE TABLE raw_products (
  product_id VARCHAR(255), sku VARCHAR(255), product_name VARCHAR(255),
  category VARCHAR(255), price VARCHAR(255), supplier VARCHAR(255),
  status VARCHAR(255)
);

CREATE TABLE raw_orders (
  order_id VARCHAR(255), customer_id VARCHAR(255), order_date VARCHAR(255),
  status VARCHAR(255), payment_method VARCHAR(255), shipping_cost VARCHAR(255),
  order_total VARCHAR(255), ship_date VARCHAR(255), channel VARCHAR(255),
  promo_code VARCHAR(255)
);

CREATE TABLE raw_order_items (
  order_item_id VARCHAR(255), order_id VARCHAR(255), product_id VARCHAR(255),
  quantity VARCHAR(255), unit_price VARCHAR(255), discount VARCHAR(255)
);

LOAD DATA LOCAL INFILE '/path/to/data/customers.csv' INTO TABLE raw_customers
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE '/path/to/data/products.csv' INTO TABLE raw_products
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE '/path/to/data/orders.csv' INTO TABLE raw_orders
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE '/path/to/data/order_items.csv' INTO TABLE raw_order_items
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;

-- Check: expect 26,600 / 825 / 153,000 / 290,371
SELECT 'customers' AS tbl, COUNT(*) AS num_rows FROM raw_customers
UNION ALL SELECT 'products',    COUNT(*) FROM raw_products
UNION ALL SELECT 'orders',      COUNT(*) FROM raw_orders
UNION ALL SELECT 'order_items', COUNT(*) FROM raw_order_items;
