-- ============================================================
-- Snowflake setup for the snowflake-wif-test repo
-- Run in a Snowsight worksheet AFTER your first workflow run,
-- once you've copied the 'sub' value it printed.
--
-- Your GitHub is GitHub Enterprise Cloud with data residency (GHE.com),
-- so tokens are issued by https://token.actions.flyontario-emu.ghe.com,
-- NOT https://token.actions.githubusercontent.com (that's for github.com).
-- The issuer appears twice below: on the user and in the auth policy.
-- ============================================================

-- 1. A tiny warehouse and a place to keep the auth policy
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS wif_test_wh
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
CREATE DATABASE IF NOT EXISTS wif_test;
CREATE SCHEMA IF NOT EXISTS wif_test.security;

-- 2. A role with exactly one key: it may use the warehouse
USE ROLE SECURITYADMIN;
CREATE ROLE IF NOT EXISTS wif_test_role;
GRANT ROLE wif_test_role TO ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE wif_test_wh TO ROLE wif_test_role;

-- 3. The service user that trusts this repo's GitHub tokens
CREATE USER IF NOT EXISTS svc_wif_test
  TYPE = SERVICE
  DEFAULT_ROLE = wif_test_role
  DEFAULT_WAREHOUSE = wif_test_wh
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = 'https://token.actions.flyontario-emu.ghe.com'   -- must match 'iss' from the first run
    SUBJECT = '<PASTE THE sub VALUE FROM THE FIRST RUN>'
    -- e.g. 'repo:flyontario@1934096/snowflake-wif-test@3921521:ref:refs/heads/main'
    OIDC_AUDIENCE_LIST = ('<SAME VALUE AS YOUR SNOWFLAKE_AUDIENCE VARIABLE>')
  );
GRANT ROLE wif_test_role TO USER svc_wif_test;

-- 4. Only allow GitHub OIDC logins for this user
--    (if this statement is rejected, check the parameter names against
--     Snowflake's current CREATE AUTHENTICATION POLICY docs)
USE ROLE ACCOUNTADMIN;
CREATE AUTHENTICATION POLICY IF NOT EXISTS wif_test.security.github_wif_only
  AUTHENTICATION_METHODS = ('WORKLOAD_IDENTITY')
  WORKLOAD_IDENTITY_POLICY = (
    ALLOWED_PROVIDERS = (OIDC)
    ALLOWED_OIDC_ISSUERS = ('https://token.actions.flyontario-emu.ghe.com')
  );
ALTER USER svc_wif_test SET AUTHENTICATION POLICY wif_test.security.github_wif_only;

-- 5. Check your work
SHOW USER WORKLOAD IDENTITY AUTHENTICATION METHODS FOR USER svc_wif_test;