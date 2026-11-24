/*
  Grants privileges to the service roles

  Run order: after warehouses, databases, schemas, roles, and tables exist.

  Runs as SECURITYADMIN because it holds MANAGE GRANTS, which is required
  to grant on objects in managed access schemas (GOVERNANCE.LOGS and
  GOVERNANCE.OPERATIONS) and for database-level future grants.

  Role hierarchy grants (roles -> SYSADMIN) are handled in the role
  creation script.
*/


USE ROLE SECURITYADMIN;

-- Operations
GRANT USAGE ON WAREHOUSE WH_SVC TO ROLE SVC_OPERATIONS_ROLE;

GRANT USAGE ON SCHEMA MONITORING.HISTORY TO ROLE SVC_OPERATIONS_ROLE;

GRANT INSERT ON TABLE MONITORING.HISTORY.ORCHESTRATOR_RUN_HISTORY TO ROLE SVC_OPERATIONS_ROLE;
GRANT INSERT ON TABLE MONITORING.HISTORY.PIPELINE_RUN_HISTORY TO ROLE SVC_OPERATIONS_ROLE;

