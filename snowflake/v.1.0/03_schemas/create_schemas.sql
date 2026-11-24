/*
Create Schemas
*/

USE ROLE SYSADMIN;

CREATE SCHEMA IF NOT EXISTS MONITORING.HISTORY
  WITH MANAGED ACCESS
  COMMENT = 'Logging and runtime metrics data';
