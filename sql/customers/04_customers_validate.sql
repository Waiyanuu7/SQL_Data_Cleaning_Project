-- =============================================================
-- 04_customers_validate.sql
-- Proves clean_customers is clean. Expected results are in
-- docs/customers_cleaning_report.md
-- =============================================================
USE ecommerce;

-- 1. Final row count (expected 25,035)
SELECT COUNT(*) AS clean_rows FROM clean_customers;

-- 2. No duplicate IDs or emails left (both expected 0)
SELECT COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_ids FROM clean_customers;
SELECT COUNT(*) AS duplicate_emails FROM (
    SELECT email FROM clean_customers
    WHERE email IS NOT NULL GROUP BY email HAVING COUNT(*) > 1
) x;

-- 3. Standardised columns contain only the expected values
SELECT country, COUNT(*) AS num_rows FROM clean_customers GROUP BY country ORDER BY num_rows DESC;
SELECT gender,  COUNT(*) AS num_rows FROM clean_customers GROUP BY gender  ORDER BY num_rows DESC;
SELECT marketing_opt_in, COUNT(*) AS num_rows FROM clean_customers GROUP BY marketing_opt_in;

-- 4. Values are in sensible ranges and formats
SELECT MIN(age) AS min_age, MAX(age) AS max_age,
       MIN(signup_date) AS first_signup, MAX(signup_date) AS last_signup,
       SUM(phone IS NOT NULL AND phone NOT REGEXP '^\\+447[0-9]{9}$') AS bad_phones,
       SUM(email IS NOT NULL AND email <> LOWER(email))              AS non_lowercase_emails
FROM clean_customers;

-- 5. Remaining unknowns (kept as NULL on purpose, not guessed)
SELECT
  SUM(full_name   IS NULL)      AS null_name,
  SUM(email       IS NULL)      AS null_email,
  SUM(phone       IS NULL)      AS null_phone,
  SUM(age         IS NULL)      AS null_age,
  SUM(signup_date IS NULL)      AS null_signup_date,
  SUM(marketing_opt_in IS NULL) AS null_opt_in,
  SUM(location_conflict = 1)    AS city_country_conflicts
FROM clean_customers;

-- 6. Every old customer_id maps to a customer that still exists (expected 0)
SELECT COUNT(*) AS broken_mappings
FROM customer_id_map m
LEFT JOIN clean_customers c ON c.customer_id = m.master_id
WHERE c.customer_id IS NULL;
