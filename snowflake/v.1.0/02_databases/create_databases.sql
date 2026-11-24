/*
  Creates the Governance database via SYSADMIN

  DATABASES
  - GOVERNANCE
  - MONITORING
  - BRONZE
  - SILVER
  - GOLD
*/

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS MONITORING
  COMMENT = 'Monitoring layer: logs and runtime metric data';

CREATE DATABASE IF NOT EXISTS BRONZE
  COMMENT = 'Bronze layer: Landing point for raw data collected by pipelines';

CREATE DATABASE IF NOT EXISTS SILVER
  COMMENT = 'Silver layer: Transformation and standardization layer for Bronze layer raw data';

CREATE DATABASE IF NOT EXISTS GOLD
  COMMENT = 'Gold layer: Data products created via merging of Silver layer data';