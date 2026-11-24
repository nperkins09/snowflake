-- Removes everything setup.sql created.
-- Drop the user first: a policy can't be dropped while it's attached.
USE ROLE ACCOUNTADMIN;
DROP USER IF EXISTS svc_wif_test;
DROP AUTHENTICATION POLICY IF EXISTS wif_test.security.github_wif_only;
DROP DATABASE IF EXISTS wif_test;
DROP WAREHOUSE IF EXISTS wif_test_wh;
DROP ROLE IF EXISTS wif_test_role;
