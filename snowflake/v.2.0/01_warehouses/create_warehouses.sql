/*
  Creates the Warehouse layer via SYSADMIN

  Notes:
    - Multi-cluster settings (MIN/MAX_CLUSTER_COUNT, SCALING_POLICY)
      require Enterprise Edition or higher. On Standard Edition,
      remove those lines or the statements will fail.
    - IF NOT EXISTS skips a warehouse that already exists, even if its
      settings differ. Use ALTER WAREHOUSE to change existing settings.
*/

USE ROLE SYSADMIN;

-- Orchestrator, pipelines, transformations, and PROD deployments
CREATE WAREHOUSE IF NOT EXISTS WH_SVC
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 3600   -- cancel queries running over 1 hour
  MIN_CLUSTER_COUNT = 1                 -- multi-cluster (Enterprise Edition)
  MAX_CLUSTER_COUNT = 3
  SCALING_POLICY = 'STANDARD'
  COMMENT = 'Service workloads: orchestration, pipelines, transformations, PROD deployments';

-- Monitoring dashboard and ad hoc queries
CREATE WAREHOUSE IF NOT EXISTS WH_REPORTING
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 3600
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 3
  SCALING_POLICY = 'STANDARD'
  COMMENT = 'Monitoring dashboards and ad hoc reporting queries';

  ALTER WAREHOUSE COMPUTE_WH SET
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  STATEMENT_TIMEOUT_IN_SECONDS = 3600
  COMMENT = 'Used for Development Purposes';
