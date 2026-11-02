-- =============================================================
-- 00_uk_time_function.sql
-- Helper function: converts a Unix timestamp to UK local time.
--
-- Why: some dates were stored as Unix timestamps (seconds since
-- 1970-01-01 UTC). The shop is in the UK, so the other date columns
-- are in UK time: GMT in winter, BST (GMT+1) in summer.
-- MySQL's FROM_UNIXTIME() depends on the session time zone, and
-- named zones like 'Europe/London' only work if time-zone tables
-- are installed (often not on Mac/Windows). This function applies
-- the UK daylight-saving rule itself, so it works everywhere:
--   BST runs from 01:00 UTC on the last Sunday of March
--   to 01:00 UTC on the last Sunday of October.
-- Run once, after 00_setup_load.sql.
-- =============================================================
USE ecommerce;

DROP FUNCTION IF EXISTS uk_from_unix;

DELIMITER $$
CREATE FUNCTION uk_from_unix(ts BIGINT)
RETURNS DATETIME
DETERMINISTIC NO SQL
BEGIN
    DECLARE utc_dt  DATETIME;
    DECLARE bst_start DATETIME;
    DECLARE bst_end   DATETIME;

    -- Unix time -> UTC, without depending on the session time zone
    SET utc_dt = TIMESTAMPADD(SECOND, ts, '1970-01-01 00:00:00');

    -- Last Sunday of March / October at 01:00 UTC (DAYOFWEEK: Sunday = 1)
    SET bst_start = LAST_DAY(CONCAT(YEAR(utc_dt), '-03-01'));
    SET bst_start = TIMESTAMPADD(HOUR, 1, DATE_SUB(bst_start, INTERVAL DAYOFWEEK(bst_start) - 1 DAY));
    SET bst_end   = LAST_DAY(CONCAT(YEAR(utc_dt), '-10-01'));
    SET bst_end   = TIMESTAMPADD(HOUR, 1, DATE_SUB(bst_end, INTERVAL DAYOFWEEK(bst_end) - 1 DAY));

    IF utc_dt >= bst_start AND utc_dt < bst_end THEN
        RETURN TIMESTAMPADD(HOUR, 1, utc_dt);   -- summer: BST = UTC + 1
    END IF;
    RETURN utc_dt;                              -- winter: GMT = UTC
END$$
DELIMITER ;

-- Quick test: 1 Jul 2021 00:00 BST and 1 Jan 2021 00:00 GMT
SELECT uk_from_unix(1625094000) AS summer_test,   -- expect 2021-07-01 00:00:00
       uk_from_unix(1609459200) AS winter_test;   -- expect 2021-01-01 00:00:00
