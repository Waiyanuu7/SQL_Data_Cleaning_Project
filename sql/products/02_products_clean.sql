-- =============================================================
-- 02_products_clean.sql
-- Builds clean_products from raw_products (raw is never modified).
-- =============================================================
USE ecommerce;

DROP TABLE IF EXISTS clean_products;

CREATE TABLE clean_products AS
WITH
-- Stage 1: remove the 25 exact duplicate rows
dedup AS (
    SELECT DISTINCT * FROM raw_products
),

-- Stage 2: the price customers actually paid for each product
-- (used to fill blank catalogue prices; see audit query 5)
price_paid AS (
    SELECT product_id,
           MAX(CAST(unit_price AS DECIMAL(10,2))) AS price_paid
    FROM raw_order_items
    WHERE unit_price REGEXP '^[0-9]+\\.[0-9]{2}$'
    GROUP BY product_id
    HAVING COUNT(DISTINCT unit_price) = 1          -- only if it was always one price
),

-- Stage 3: tidy text
prepped AS (
    SELECT
        CAST(d.product_id AS UNSIGNED)                         AS product_id,
        UPPER(REPLACE(TRIM(d.sku), '-', ''))                   AS sku_raw,
        TRIM(d.product_name)                                   AS name_t,
        LOWER(TRIM(d.category))                                AS category_lc,
        -- keep only digits, dot and comma, then make comma a decimal point
        NULLIF(REPLACE(REGEXP_REPLACE(d.price, '[^0-9.,]', ''), ',', '.'), '') AS price_num,
        LOWER(TRIM(d.supplier))                                AS supplier_lc,
        LOWER(TRIM(d.status))                                  AS status_lc,
        pp.price_paid
    FROM dedup d
    LEFT JOIN price_paid pp ON pp.product_id = d.product_id
),

-- Stage 4: correctly-cased spelling of every product name that is NOT all caps
-- (e.g. 'Pro Mug Set'), used to fix names typed in ALL CAPS ('PRO MUG SET')
proper_names AS (
    SELECT LOWER(name_t) AS name_key, MIN(name_t) AS proper_name
    FROM prepped
    WHERE BINARY name_t <> BINARY UPPER(name_t)
    GROUP BY LOWER(name_t)
)

-- Stage 5: standardise
SELECT
    product_id,

    -- SKU: 'sku00012' / 'SKU-00012' -> 'SKU-00012'
    CONCAT('SKU-', SUBSTRING(sku_raw, 4))                       AS sku,

    -- Name: trimmed; ALL CAPS names replaced by the normal spelling of the
    -- same name used elsewhere in the catalogue; if none exists, capitalise
    -- the first letter of each of the first two words
    CASE WHEN BINARY name_t <> BINARY UPPER(name_t) THEN name_t
         ELSE COALESCE(pn.proper_name,
              CONCAT(UPPER(LEFT(name_t, 1)),
                     LOWER(SUBSTRING(name_t, 2, LOCATE(' ', name_t) - 1)),
                     UPPER(SUBSTRING(name_t, LOCATE(' ', name_t) + 1, 1)),
                     LOWER(SUBSTRING(name_t, LOCATE(' ', name_t) + 2))))
    END                                                          AS product_name,

    -- Category: 27 spellings -> 6 categories
    CASE
        WHEN category_lc IN ('electronics','electronic','elec.')                   THEN 'Electronics'
        WHEN category_lc IN ('home & kitchen','home and kitchen','home&kitchen',
                             'kitchen')                                            THEN 'Home & Kitchen'
        WHEN category_lc IN ('clothing','clothes','apparel')                       THEN 'Clothing'
        WHEN category_lc IN ('books','book')                                       THEN 'Books'
        WHEN category_lc IN ('sports','sport','sports & outdoors')                 THEN 'Sports'
        WHEN category_lc IN ('beauty','beauty & personal care','cosmetics')        THEN 'Beauty'
        ELSE 'Unknown'
    END                                                          AS category,

    -- Price: text -> DECIMAL. Negative sign dropped (sign error, proven in audit).
    -- Blank -> price customers actually paid, if it was always the same.
    COALESCE(CAST(price_num AS DECIMAL(10,2)), price_paid)       AS price,

    -- Was the price filled in from sales data? (for transparency)
    CASE WHEN price_num IS NULL AND price_paid IS NOT NULL THEN 1 ELSE 0 END
                                                                 AS price_from_sales,

    -- Supplier: 'acme' / 'ACME Ltd' -> 'Acme Ltd'; blank -> NULL
    CASE
        WHEN supplier_lc IN ('acme','acme ltd') THEN 'Acme Ltd'
        WHEN supplier_lc = 'northwind'          THEN 'Northwind'
        WHEN supplier_lc = 'globex'             THEN 'Globex'
        WHEN supplier_lc = 'initech'            THEN 'Initech'
    END                                                          AS supplier,

    -- Status: 6 values -> 4
    CASE
        WHEN status_lc = 'active'       THEN 'Active'
        WHEN status_lc = 'discontinued' THEN 'Discontinued'
        WHEN status_lc = 'inactive'     THEN 'Inactive'
        ELSE 'Unknown'
    END                                                          AS status
FROM prepped p
LEFT JOIN proper_names pn ON pn.name_key = LOWER(p.name_t);

ALTER TABLE clean_products ADD PRIMARY KEY (product_id);
