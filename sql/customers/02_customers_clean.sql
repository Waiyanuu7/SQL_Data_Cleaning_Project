-- =============================================================
-- 02_customers_clean.sql
-- Builds clean_customers from raw_customers (raw is never modified).
-- =============================================================
USE ecommerce;

DROP TABLE IF EXISTS clean_customers;

CREATE TABLE clean_customers AS
WITH
-- Stage 1: remove the 400 exact duplicate rows
dedup AS (
    SELECT DISTINCT * FROM raw_customers
),

-- Stage 2: trim spaces and standardise case so values can be compared
prepped AS (
    SELECT
        CAST(customer_id AS UNSIGNED)                     AS customer_id,
        -- "Smith, James" -> "James Smith"
        CASE WHEN full_name LIKE '%,%'
             THEN CONCAT(TRIM(SUBSTRING_INDEX(full_name, ',', -1)), ' ',
                         TRIM(SUBSTRING_INDEX(full_name, ',', 1)))
             ELSE TRIM(full_name)
        END                                               AS name_fixed,
        LOWER(TRIM(email))                                AS email_lc,
        REGEXP_REPLACE(phone, '[^0-9]', '')               AS phone_digits,
        LOWER(TRIM(country))                              AS country_lc,
        TRIM(city)                                        AS city_t,
        TRIM(age)                                         AS age_t,
        LOWER(TRIM(gender))                               AS gender_lc,
        TRIM(signup_date)                                 AS sd,
        LOWER(TRIM(marketing_opt_in))                     AS opt_lc
    FROM dedup
),

-- Stage 3: map every messy variant to one standard value
standardised AS (
    SELECT
        customer_id,

        -- Name: "james SMITH" -> "James Smith"; blank -> NULL
        CASE WHEN name_fixed = '' THEN NULL
             ELSE CONCAT(
                  UPPER(LEFT(SUBSTRING_INDEX(name_fixed, ' ', 1), 1)),
                  LOWER(SUBSTRING(SUBSTRING_INDEX(name_fixed, ' ', 1), 2)), ' ',
                  UPPER(LEFT(SUBSTRING_INDEX(name_fixed, ' ', -1), 1)),
                  LOWER(SUBSTRING(SUBSTRING_INDEX(name_fixed, ' ', -1), 2)))
        END                                               AS full_name,

        -- Email: lower case; invalid (no @, or .con typo) -> NULL
        CASE WHEN email_lc REGEXP '^[^@ ]+@[^@ ]+\\.[a-z]{2,}$'
              AND email_lc NOT LIKE '%.con'
             THEN email_lc
        END                                               AS email,

        -- Phone: every valid UK mobile -> +447XXXXXXXXX; junk -> NULL
        CASE WHEN phone_digits REGEXP '^447[0-9]{9}$' THEN CONCAT('+', phone_digits)
             WHEN phone_digits REGEXP '^07[0-9]{9}$'  THEN CONCAT('+44', SUBSTRING(phone_digits, 2))
             WHEN phone_digits REGEXP '^7[0-9]{9}$'   THEN CONCAT('+44', phone_digits)
        END                                               AS phone,

        -- Country: 31 spellings -> 6 countries
        CASE
            WHEN country_lc IN ('united kingdom','uk','u.k.','england','great britain') THEN 'United Kingdom'
            WHEN country_lc IN ('united states','usa','us','u.s.a.','america',
                                'united states of america')                           THEN 'United States'
            WHEN country_lc IN ('germany','de','deutschland')                         THEN 'Germany'
            WHEN country_lc IN ('france','fr')                                        THEN 'France'
            WHEN country_lc IN ('ireland','ie','eire')                                THEN 'Ireland'
            WHEN country_lc IN ('spain','es','españa','espana')                       THEN 'Spain'
            ELSE 'Unknown'
        END                                               AS country,

        -- City: fix casing variants found in the audit; blank -> NULL
        CASE WHEN city_t = ''                  THEN NULL
             WHEN LOWER(city_t) = 'london'     THEN 'London'
             WHEN LOWER(city_t) = 'new york'   THEN 'New York'
             ELSE city_t
        END                                               AS city,

        -- Age: keep only realistic ages (16-100); anything else -> NULL
        CASE WHEN age_t REGEXP '^[0-9]+$'
              AND CAST(age_t AS UNSIGNED) BETWEEN 16 AND 100
             THEN CAST(age_t AS UNSIGNED)
        END                                               AS age,

        -- Gender: 12 codes -> 5 categories
        CASE WHEN gender_lc IN ('m','male')           THEN 'Male'
             WHEN gender_lc IN ('f','female')         THEN 'Female'
             WHEN gender_lc = 'other'                 THEN 'Other'
             WHEN gender_lc = 'prefer not to say'     THEN 'Prefer not to say'
             ELSE 'Unknown'
        END                                               AS gender,

        -- Signup date: 6 formats -> a real DATE; junk -> NULL
        CASE
            WHEN sd REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND sd <> '0000-00-00'
                                                          THEN STR_TO_DATE(sd, '%Y-%m-%d')
            WHEN sd REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$' THEN STR_TO_DATE(sd, '%Y/%m/%d')
            WHEN sd REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN STR_TO_DATE(sd, '%d/%m/%Y')  -- UK style (proven in audit)
            WHEN sd REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' THEN STR_TO_DATE(sd, '%m-%d-%Y')  -- US style (proven in audit)
            WHEN sd REGEXP '^[0-9]{1,2} [A-Za-z]{3} [0-9]{4}$' THEN STR_TO_DATE(sd, '%d %b %Y')
            WHEN sd REGEXP '^[0-9]{9,10}$'                THEN DATE(uk_from_unix(sd))  -- see 00_uk_time_function.sql
        END                                               AS signup_date,

        -- Marketing opt-in: 9 codes -> 1 / 0; blank -> NULL (unknown)
        CASE WHEN opt_lc IN ('y','yes','1','true')  THEN 1
             WHEN opt_lc IN ('n','no','0','false')  THEN 0
        END                                               AS marketing_opt_in
    FROM prepped
)

-- Stage 4: flag rows where city and country contradict each other
-- (e.g. Paris + United Kingdom). We can't know which is right, so flag, don't guess.
SELECT
    s.*,
    CASE
        WHEN city IS NULL THEN NULL
        WHEN country = CASE
                WHEN city IN ('London','Manchester','Bristol','Leeds','Bath','Bradford-on-Avon') THEN 'United Kingdom'
                WHEN city = 'New York' THEN 'United States'
                WHEN city = 'Berlin'   THEN 'Germany'
                WHEN city = 'Paris'    THEN 'France'
                WHEN city = 'Dublin'   THEN 'Ireland'
                WHEN city = 'Madrid'   THEN 'Spain'
             END THEN 0
        ELSE 1
    END AS location_conflict
FROM standardised s;

-- customer_id must now be unique: this fails if any duplicate IDs are left
ALTER TABLE clean_customers ADD PRIMARY KEY (customer_id);
