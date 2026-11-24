/*
  Creates the service roles via USERADMIN

Roles

- SVC_OPERATIONS_ROLE

Future: Add more roles as needed for other service accounts

- Split SVC_OPERATIONS_ROLE into more narrowly scoped roles for each service account
- Add a monitoring role to read the run history logging tables and views
- Add a transformation role to read the Bronze tables and write to Silver tables
*/

USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS SVC_OPERATIONS_ROLE
  COMMENT = 'Automated ingestion into Bronze and run history logging';
  -- NOTE: This role should be more narrowly scoped in the future.

-- Attach to the hierarchy so SYSADMIN can manage objects these roles use
GRANT ROLE SVC_OPERATIONS_ROLE TO ROLE SYSADMIN;
