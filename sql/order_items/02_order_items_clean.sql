-- =============================================================
-- 02_order_items_clean.sql
-- Builds clean_order_items from raw_order_items (raw is never modified).
-- Needs: clean_products.
-- =============================================================
USE ecommerce;

DROP TABLE IF EXISTS clean_order_items;

CREATE TABLE clean_order_items AS
WITH
-- Stage 1: remove the 4,000 exact duplicate rows
dedup AS (
    SELECT DISTINCT * FROM raw_order_items
),

-- Stage 2: convert text to numbers
prepped AS (
    SELECT
        CAST(d.order_item_id AS UNSIGNED)                 AS order_item_id,
        CAST(d.order_id      AS UNSIGNED)                 AS order_id,
        CAST(d.product_id    AS UNSIGNED)                 AS product_id,
        CAST(d.quantity      AS SIGNED)                   AS quantity,
        -- '£18.2' -> 18.20; blank / 'NULL' -> NULL
        CAST(NULLIF(REGEXP_REPLACE(d.unit_price, '[^0-9.]', ''), '') AS DECIMAL(10,2)) AS unit_price_num,
        -- '10%' / '10' / '0.1' -> 0.10; blank -> 0 (no discount recorded)
        CAST(COALESCE(NULLIF(REPLACE(TRIM(d.discount), '%', ''), ''), '0') AS DECIMAL(6,2)) AS discount_num,
        p.product_id                                      AS catalogue_product_id,
        p.price                                           AS catalogue_price
    FROM dedup d
    LEFT JOIN clean_products p ON p.product_id = CAST(d.product_id AS UNSIGNED)
),

-- Stage 3: standardise and flag
standardised AS (
    SELECT
        order_item_id,
        order_id,
        product_id,
        quantity,

        -- Missing price -> catalogue price (catalogue = price paid, proven in products audit)
        COALESCE(unit_price_num, catalogue_price)              AS unit_price,
        CASE WHEN unit_price_num IS NULL AND catalogue_price IS NOT NULL
             THEN 1 ELSE 0 END                                 AS price_from_catalogue,

        -- Whole numbers above 1 are percentages: 10 -> 0.10
        CASE WHEN discount_num > 1 THEN discount_num / 100
             ELSE discount_num END                             AS discount,

        CASE WHEN catalogue_product_id IS NULL THEN 1 ELSE 0 END AS unknown_product,

        -- Why a line can't be counted as a sale (NULL = valid line)
        CASE
            WHEN quantity = 0    THEN 'Zero quantity'
            WHEN quantity < 0    THEN 'Negative quantity'
            WHEN quantity = 999  THEN 'Quantity 999 (placeholder/outlier)'
            WHEN COALESCE(unit_price_num, catalogue_price) IS NULL THEN 'Missing price'
        END                                                    AS line_issue
    FROM prepped
)

SELECT
    s.*,
    CASE WHEN line_issue IS NULL THEN 1 ELSE 0 END             AS is_valid,
    -- Revenue for the line: only for valid lines
    CASE WHEN line_issue IS NULL
         THEN ROUND(quantity * unit_price * (1 - discount), 2)
    END                                                        AS line_total
FROM standardised s;

ALTER TABLE clean_order_items
    MODIFY discount DECIMAL(4,2),
    ADD PRIMARY KEY (order_item_id),
    ADD INDEX idx_items_order (order_id),
    ADD INDEX idx_items_product (product_id);
