-- =============================================================
-- 03_customers_dedupe.sql
-- Merges customers who registered more than once with the same
-- email under different IDs. Run after 02_customers_clean.sql.
-- =============================================================
USE ecommerce;

-- 1. Size of the problem (same email, different IDs) ------------
SELECT COUNT(*)                AS emails_with_duplicates,
       SUM(num_ids)            AS customer_rows_involved,
       SUM(num_ids) - COUNT(*) AS rows_to_remove
FROM (
    SELECT email, COUNT(*) AS num_ids
    FROM clean_customers
    WHERE email IS NOT NULL          -- NULL = unknown, not a match
    GROUP BY email
    HAVING COUNT(*) > 1
) AS dupes;

-- 2. Map every customer_id to the ID we keep --------------------
-- Keep the lowest ID (= first registration). Orders are re-pointed
-- through this map later, so no order loses its customer.
DROP TABLE IF EXISTS customer_id_map;
CREATE TABLE customer_id_map AS
SELECT customer_id AS old_id,
       CASE WHEN email IS NULL THEN customer_id
            ELSE MIN(customer_id) OVER (PARTITION BY email)
       END AS master_id
FROM clean_customers;

ALTER TABLE customer_id_map ADD PRIMARY KEY (old_id);

-- 3. Rescue details before deleting -----------------------------
-- If the kept record is missing a value (e.g. phone) but a duplicate
-- has it, copy it across so no information is lost.
DROP TEMPORARY TABLE IF EXISTS dup_details;
CREATE TEMPORARY TABLE dup_details AS
SELECT m.master_id,
       MAX(c.full_name)        AS full_name,
       MAX(c.phone)            AS phone,
       MAX(c.age)              AS age,
       MIN(c.signup_date)      AS signup_date,
       MAX(c.marketing_opt_in) AS marketing_opt_in
FROM customer_id_map m
JOIN clean_customers c ON c.customer_id = m.old_id
WHERE m.old_id <> m.master_id
GROUP BY m.master_id;

SET SQL_SAFE_UPDATES = 0;   -- Workbench blocks bulk UPDATE/DELETE by default

UPDATE clean_customers k
JOIN dup_details d ON d.master_id = k.customer_id
SET k.full_name        = COALESCE(k.full_name,        d.full_name),
    k.phone            = COALESCE(k.phone,            d.phone),
    k.age              = COALESCE(k.age,              d.age),
    k.signup_date      = COALESCE(k.signup_date,      d.signup_date),
    k.marketing_opt_in = COALESCE(k.marketing_opt_in, d.marketing_opt_in);

-- 4. Remove the duplicate registrations -------------------------
DELETE FROM clean_customers
WHERE customer_id IN (SELECT old_id FROM customer_id_map WHERE old_id <> master_id);

SET SQL_SAFE_UPDATES = 1;
DROP TEMPORARY TABLE dup_details;
