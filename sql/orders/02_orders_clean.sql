-- =============================================================
-- 02_orders_clean.sql
-- Builds clean_orders from raw_orders (raw is never modified).
-- Needs: 00_uk_time_function.sql and the customers scripts.
-- =============================================================
USE ecommerce;

-- Valid order period, found in the date audit (03_orders_validate.sql
-- shows the monthly counts): orders run every month from Jan 2021 to
-- Sep 2026, then there is a gap, followed by a thin scatter of dates in
-- 2027-2029 that can't have happened yet.
SET @data_start = '2021-01-01';
SET @data_end   = '2026-09-30';

DROP TABLE IF EXISTS clean_orders;

CREATE TABLE clean_orders AS
WITH
-- Stage 1: remove the 3,000 exact duplicate rows
dedup AS (
    SELECT DISTINCT * FROM raw_orders
),

-- Stage 2: parse dates and tidy text
prepped AS (
    SELECT
        CAST(order_id AS UNSIGNED)                        AS order_id,
        NULLIF(TRIM(customer_id), '')                     AS customer_id_raw,

        -- order_date: 7 formats -> DATE (time is only known for half the rows,
        -- so the clean column is a date)
        CASE
            WHEN order_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}$'
                 THEN DATE(STR_TO_DATE(order_date, '%Y-%m-%d %H:%i:%s'))
            WHEN order_date REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'      THEN STR_TO_DATE(order_date, '%Y/%m/%d')
            WHEN order_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'      THEN STR_TO_DATE(order_date, '%d/%m/%Y')  -- UK style (proven in audit)
            WHEN order_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'      THEN STR_TO_DATE(order_date, '%m-%d-%Y')  -- US style (proven in audit)
            WHEN order_date REGEXP '^[0-9]{1,2} [A-Za-z]{3} [0-9]{4}$' THEN STR_TO_DATE(order_date, '%d %b %Y')
            WHEN order_date REGEXP '^-?[0-9]{1,10}$'                   THEN DATE(uk_from_unix(order_date))
        END                                               AS order_date_parsed,

        CASE
            WHEN ship_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND ship_date <> '0000-00-00'
                                                                      THEN STR_TO_DATE(ship_date, '%Y-%m-%d')
            WHEN ship_date REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'      THEN STR_TO_DATE(ship_date, '%Y/%m/%d')
            WHEN ship_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'      THEN STR_TO_DATE(ship_date, '%d/%m/%Y')
            WHEN ship_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'      THEN STR_TO_DATE(ship_date, '%m-%d-%Y')
            WHEN ship_date REGEXP '^[0-9]{1,2} [A-Za-z]{3} [0-9]{4}$' THEN STR_TO_DATE(ship_date, '%d %b %Y')
            WHEN ship_date REGEXP '^-?[0-9]{1,10}$'                   THEN DATE(uk_from_unix(ship_date))
        END                                               AS ship_date_parsed,

        LOWER(TRIM(status))                               AS status_lc,
        REPLACE(LOWER(TRIM(payment_method)), ' ', '')     AS payment_key,   -- 'Pay Pal' -> 'paypal'
        LOWER(TRIM(channel))                              AS channel_lc,
        UPPER(TRIM(promo_code))                           AS promo_uc,
        CAST(NULLIF(TRIM(shipping_cost), '') AS DECIMAL(10,2)) AS shipping_cost,
        CAST(NULLIF(TRIM(order_total),   '') AS DECIMAL(10,2)) AS order_total_reported
    FROM dedup
)

-- Stage 3: standardise, re-point customers, flag problems
SELECT
    p.order_id,

    -- Customer: duplicate accounts -> the kept account; unknown -> NULL
    m.master_id                                           AS customer_id,
    CASE WHEN p.customer_id_raw IS NULL THEN 'Missing customer ID'
         WHEN m.old_id IS NULL          THEN 'Customer not found'
         WHEN m.old_id <> m.master_id   THEN 'Merged duplicate account'
    END                                                   AS customer_note,

    -- Order date: only dates inside the valid period are kept
    CASE WHEN p.order_date_parsed BETWEEN @data_start AND @data_end
         THEN p.order_date_parsed END                     AS order_date,
    CASE WHEN p.order_date_parsed IS NULL        THEN 'Missing or unreadable'
         WHEN p.order_date_parsed < @data_start  THEN 'Before shop opened (1970 default)'
         WHEN p.order_date_parsed > @data_end    THEN 'Future date'
    END                                                   AS order_date_issue,

    -- Ship date: valid period plus up to 7 days of shipping time
    CASE WHEN p.ship_date_parsed BETWEEN @data_start AND DATE_ADD(@data_end, INTERVAL 7 DAY)
         THEN p.ship_date_parsed END                      AS ship_date,

    -- Status: 16 values -> 6
    CASE
        WHEN p.status_lc IN ('delivered','dlvrd','complete') THEN 'Delivered'
        WHEN p.status_lc = 'shipped'                         THEN 'Shipped'
        WHEN p.status_lc IN ('cancelled','canceled')         THEN 'Cancelled'
        WHEN p.status_lc = 'returned'                        THEN 'Returned'
        WHEN p.status_lc = 'pending'                         THEN 'Pending'
        ELSE 'Unknown'
    END                                                   AS status,

    -- Payment: 14 values -> 9
    CASE
        WHEN p.payment_key IN ('creditcard','cc') THEN 'Credit Card'
        WHEN p.payment_key = 'debitcard'          THEN 'Debit Card'
        WHEN p.payment_key = 'visa'               THEN 'Visa'
        WHEN p.payment_key = 'mastercard'         THEN 'Mastercard'
        WHEN p.payment_key = 'paypal'             THEN 'PayPal'
        WHEN p.payment_key = 'applepay'           THEN 'Apple Pay'
        WHEN p.payment_key = 'klarna'             THEN 'Klarna'
        WHEN p.payment_key = 'cash'               THEN 'Cash'
        ELSE 'Unknown'
    END                                                   AS payment_method,

    -- Channel: 11 values -> 5, keeping the app platform in its own column
    CASE
        WHEN p.channel_lc = 'web'                                   THEN 'Web'
        WHEN p.channel_lc IN ('app','mobile app','ios','android')   THEN 'Mobile App'
        WHEN p.channel_lc = 'phone'                                 THEN 'Phone'
        WHEN p.channel_lc = 'in-store'                              THEN 'In-store'
        ELSE 'Unknown'
    END                                                   AS channel,
    CASE WHEN p.channel_lc = 'ios'     THEN 'iOS'
         WHEN p.channel_lc = 'android' THEN 'Android'
    END                                                   AS app_platform,

    -- Promo code: upper case; 'N/A' and blank -> NULL
    CASE WHEN p.promo_uc IN ('', 'N/A') THEN NULL ELSE p.promo_uc END AS promo_code,

    p.shipping_cost,
    p.order_total_reported
FROM prepped p
LEFT JOIN customer_id_map m ON m.old_id = CAST(p.customer_id_raw AS UNSIGNED);

-- Flag orders that shipped before they were ordered (can't be true;
-- one of the two dates is wrong, and we can't tell which)
ALTER TABLE clean_orders ADD COLUMN ship_before_order TINYINT;

SET SQL_SAFE_UPDATES = 0;
UPDATE clean_orders
SET ship_before_order = CASE WHEN order_date IS NULL OR ship_date IS NULL THEN NULL
                             WHEN ship_date < order_date THEN 1 ELSE 0 END;
SET SQL_SAFE_UPDATES = 1;

ALTER TABLE clean_orders
    ADD PRIMARY KEY (order_id),
    ADD INDEX idx_orders_customer (customer_id),
    ADD INDEX idx_orders_date (order_date);
