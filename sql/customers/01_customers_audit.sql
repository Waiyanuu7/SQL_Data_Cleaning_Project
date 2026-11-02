-- =============================================================
-- 01_customers_audit.sql
-- Measures every data quality problem in raw_customers
-- BEFORE anything is changed. Results: docs/customers_cleaning_report.md
-- =============================================================
USE ecommerce;

-- 1. Exact duplicate rows ---------------------------------------
SELECT COUNT(*)                               AS total_rows,
       COUNT(DISTINCT customer_id)            AS distinct_ids,
       COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_rows
FROM raw_customers;

-- 2. Inconsistent category values -------------------------------
-- COLLATE utf8mb4_bin makes grouping case- and accent-sensitive.
-- Without it MySQL treats 'UK' and 'uk' as equal and hides variants.
SELECT country COLLATE utf8mb4_bin AS country_value, COUNT(*) AS num_rows
FROM raw_customers GROUP BY country_value ORDER BY num_rows DESC;

SELECT city COLLATE utf8mb4_bin AS city_value, COUNT(*) AS num_rows
FROM raw_customers GROUP BY city_value ORDER BY num_rows DESC;

SELECT gender COLLATE utf8mb4_bin AS gender_value, COUNT(*) AS num_rows
FROM raw_customers GROUP BY gender_value ORDER BY num_rows DESC;

SELECT marketing_opt_in COLLATE utf8mb4_bin AS opt_in_value, COUNT(*) AS num_rows
FROM raw_customers GROUP BY opt_in_value ORDER BY num_rows DESC;

-- 3. Missing and invalid values ---------------------------------
SELECT
  SUM(TRIM(full_name) = '')                                 AS blank_name,
  SUM(full_name LIKE '%,%')                                 AS name_last_first,
  SUM(full_name <> TRIM(full_name))                         AS name_extra_spaces,
  SUM(TRIM(email) = '')                                     AS blank_email,
  SUM(TRIM(email) <> '' AND email NOT LIKE '%_@_%._%')      AS invalid_email,
  SUM(email LIKE '%.con')                                   AS email_con_typo,
  SUM(TRIM(phone) IN ('', 'N/A'))                           AS blank_phone,
  SUM(TRIM(age) = '')                                       AS blank_age,
  SUM(TRIM(age) <> '' AND (CAST(age AS SIGNED) < 16
                        OR CAST(age AS SIGNED) > 100))      AS impossible_age
FROM raw_customers;

-- 4. Date formats in signup_date --------------------------------
SELECT
  CASE
    WHEN signup_date = '0000-00-00'                             THEN 'Zero date (junk)'
    WHEN signup_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'      THEN 'YYYY-MM-DD'
    WHEN signup_date REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'      THEN 'YYYY/MM/DD'
    WHEN signup_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'      THEN 'NN/NN/YYYY (slashes)'
    WHEN signup_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'      THEN 'NN-NN-YYYY (dashes)'
    WHEN signup_date REGEXP '^[0-9]{1,2} [A-Za-z]{3} [0-9]{4}$' THEN 'DD Mon YYYY'
    WHEN signup_date REGEXP '^[0-9]{9,10}$'                     THEN 'Unix timestamp'
    WHEN TRIM(signup_date) = ''                                 THEN 'Blank'
    ELSE 'Other text (N/A, unknown, null)'
  END AS date_format,
  COUNT(*) AS num_rows
FROM raw_customers
GROUP BY date_format
ORDER BY num_rows DESC;

-- 5. Proof of day/month order: a month can never be > 12 -------
-- Result 2505 / 0 / 0 / 1640 -> slashes are DD/MM, dashes are MM-DD
SELECT
  SUM(signup_date REGEXP '^[0-9]{2}/' AND LEFT(signup_date,2) > 12)                 AS slash_1st_over_12,
  SUM(signup_date REGEXP '^[0-9]{2}/' AND SUBSTRING(signup_date,4,2) > 12)          AS slash_2nd_over_12,
  SUM(signup_date REGEXP '^[0-9]{2}-[0-9]{2}-' AND LEFT(signup_date,2) > 12)        AS dash_1st_over_12,
  SUM(signup_date REGEXP '^[0-9]{2}-[0-9]{2}-' AND SUBSTRING(signup_date,4,2) > 12) AS dash_2nd_over_12
FROM raw_customers;

-- 6. Hidden duplicates: same email, different customer_id -------
SELECT COUNT(*) AS emails_used_by_several_ids
FROM (
    SELECT LOWER(TRIM(email)) AS email_clean
    FROM (SELECT DISTINCT * FROM raw_customers) d
    WHERE TRIM(email) <> ''
    GROUP BY email_clean
    HAVING COUNT(DISTINCT customer_id) > 1
) x;
